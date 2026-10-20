defmodule Visualize.VirtualSource.Sandbox do
  @moduledoc """
  The sandbox a virtual source's function runs in (spec/08 §10.5, D-194).

  A virtual source is a source computed from other sources by an Elixir function, rows in
  and rows out (#643). A function stored in a design as source text is untrusted, so it is
  **checked** against an allowlist before anything runs (`check/2`), **compiled once** into
  a closure (`compile/2`, cached by `Visualize.VirtualSource.Sandbox.Cache`), and **called
  in a bounded process** (`run/3`) — as is a host's own trusted function.

      iex> alias Visualize.VirtualSource.Sandbox
      iex> {:ok, compiled} = Sandbox.compile("fn rows -> Enum.map(rows, & &1.v * 2) end")
      iex> Sandbox.run(compiled, [[%{v: 1}, %{v: 2}]])
      {:ok, [2, 4]}
      iex> {:error, [{1, reason}]} = Sandbox.check("fn _ -> File.read(\\"/etc/passwd\\") end")
      iex> reason
      {:restricted, {"File", "read", 1}}

  Nothing is rescued: a raise, a heap overrun and a timeout are read from the process the
  call ran in, through its monitor.
  """

  alias Visualize.VirtualSource.Sandbox.{Checker, Compiled}

  @check_opts [arity: 1, fields: nil, max_source: 10_000]
  @run_opts [timeout: 1_000, max_heap: 10_000_000]

  @typedoc "A checker fault: the source line, or `nil`, and the reason (spec/08 §10.5.1)."
  @type fault :: {pos_integer() | nil, term()}

  @typedoc "What a call can end in besides a value (spec/08 §10.5.4)."
  @type kind :: :timeout | :memory | :raised

  @doc "As `check/2` with no options."
  @spec check(String.t()) :: {:ok, Macro.t()} | {:error, [fault(), ...]}
  def check(source), do: check(source, [])

  @doc """
  A stored function checked against the allowlist (spec/08 §10.5.1): `{:ok, quoted}`, or
  `{:error, faults}` with every fault, each `{line, reason}`, ordered by line. Nothing is
  evaluated.

  Options: `arity:` (`1`), `fields:` (the names a `row.field` may read; `nil` reads any)
  and `max_source:` (bytes, `10_000`).
  """
  @spec check(String.t(), keyword()) :: {:ok, Macro.t()} | {:error, [fault(), ...]}
  def check(source, opts) when is_binary(source) and is_list(opts) do
    Checker.check(source, Keyword.validate!(opts, @check_opts))
  end

  @doc "As `compile/2` with no options."
  @spec compile(String.t()) :: {:ok, Compiled.t()} | {:error, [fault(), ...]}
  def compile(source), do: compile(source, [])

  @doc """
  A stored function checked, then compiled once into a closure (spec/08 §10.5.3):
  `{:ok, %Compiled{}}`, or `{:error, faults}` — the checker's, or `{nil, {:compile,
  message}}` for a checked source the compiler refuses. The compilation runs in the
  bounded runner. Options: the checker's and the runner's.
  """
  @spec compile(String.t(), keyword()) :: {:ok, Compiled.t()} | {:error, [fault(), ...]}
  def compile(source, opts) when is_binary(source) and is_list(opts) do
    opts = Keyword.validate!(opts, @check_opts ++ @run_opts)

    with {:ok, quoted} <- Checker.check(source, Keyword.take(opts, Keyword.keys(@check_opts))) do
      evaluate(source, quoted, opts)
    end
  end

  # Map reads become `Sandbox.Runtime.get/2`, by spelling, so an atom receiver never calls a
  # function and a field written as a string reaches an atom key (D-195); the
  # `fn` is evaluated once, under `require Integer`, with its warnings kept, not printed.
  defp evaluate(source, quoted, opts) do
    code =
      quote do
        require Integer
        unquote(rewrite(quoted))
      end

    compile = fn ->
      Code.with_diagnostics(fn -> Code.eval_quoted(code, [], file: "virtual_source") end)
    end

    case bounded(compile, opts) do
      {:ok, {{fun, _binding}, diagnostics}} ->
        {:ok,
         %Compiled{
           hash: hash(source),
           fun: fun,
           arity: opts[:arity],
           warnings: for(%{severity: :warning} = d <- diagnostics, do: warning(d))
         }}

      {:error, :raised, _name, reason} ->
        {:error, [{nil, {:compile, compile_message(reason)}}]}

      {:error, kind, detail, _reason} ->
        {:error, [{nil, {:compile, {kind, detail}}}]}
    end
  end

  defp rewrite(quoted) do
    Macro.prewalk(quoted, fn
      # A guard calls nothing: its map reads stay `:erlang.map_get/2` of the field as its
      # inputs spell it, a word's atom or the string (spec/08 §10.5.6, D-195).
      {:->, meta, [[{:when, when_meta, args}], body]} ->
        {heads, [guard]} = Enum.split(args, -1)
        {:->, meta, [[{:when, when_meta, heads ++ [guarded(guard)]}], body]}

      {{:., dot_meta, [receiver, name]}, meta, []} = node when is_atom(name) or is_binary(name) ->
        if meta[:no_parens] && value_receiver?(receiver),
          do:
            {{:., dot_meta, [Visualize.VirtualSource.Sandbox.Runtime, :get]},
             Keyword.delete(meta, :no_parens), [receiver, name]},
          else: node

      node ->
        node
    end)
  end

  defp guarded(guard) do
    Macro.prewalk(guard, fn
      {{:., dot_meta, [receiver, name]}, meta, []} = node when is_atom(name) or is_binary(name) ->
        if meta[:no_parens] && value_receiver?(receiver),
          do:
            {{:., dot_meta, [:erlang, :map_get]}, Keyword.delete(meta, :no_parens),
             [Visualize.VirtualSource.Sandbox.Names.spelling(name), receiver]},
          else: node

      node ->
        node
    end)
  end

  defp value_receiver?({:__aliases__, _meta, _parts}), do: false
  defp value_receiver?(atom) when is_atom(atom), do: false
  defp value_receiver?(_value), do: true

  defp warning(%{position: {line, _column}, message: message}), do: {line, message}
  defp warning(%{position: line, message: message}) when is_integer(line), do: {line, message}
  defp warning(%{message: message}), do: {nil, message}

  defp compile_message({exception, stack}) when is_list(stack) do
    :error |> Exception.normalize(exception, stack) |> Exception.message()
  end

  defp compile_message(_reason), do: "the source does not compile"

  @doc "As `run/3` with no options."
  @spec run(Compiled.t() | function(), list()) ::
          {:ok, term()} | {:error, kind(), term()}
  def run(function, args), do: run(function, args, [])

  @doc """
  A function called with `args` in a process of its own (spec/08 §10.5.4): `{:ok, value}`,
  or `{:error, kind, detail}` — `{:error, :timeout, ms}` when it did not answer within
  `timeout:` (`1_000` ms), `{:error, :memory, words}` when its heap passed `max_heap:`
  (`10_000_000` words) and the VM killed it, `{:error, :raised, module}` with the
  exception's module when it raised. The process is spawned with its heap limit set and
  monitored; a killed process is waited for before the call returns.
  """
  @spec run(Compiled.t() | function(), list(), keyword()) ::
          {:ok, term()} | {:error, kind(), term()}
  def run(function, args, opts) when is_list(args) and is_list(opts) do
    opts = Keyword.validate!(opts, @run_opts)

    fun =
      case function do
        %Compiled{fun: fun} -> fun
        fun when is_function(fun) -> fun
      end

    case bounded(fn -> apply(fun, args) end, opts) do
      {:ok, value} -> {:ok, value}
      {:error, kind, detail, _reason} -> {:error, kind, detail}
    end
  end

  # The bounded runner: a monitored process with its heap limit set at the spawn, killed
  # when the timeout passes; the outcome read from its result or its `:DOWN`.
  defp bounded(thunk, opts) do
    timeout = Keyword.fetch!(opts, :timeout)
    max_heap = Keyword.fetch!(opts, :max_heap)
    parent = self()
    tag = make_ref()

    limit = %{size: max_heap, kill: true, error_logger: false, include_shared_binaries: true}

    {pid, monitor} =
      :erlang.spawn_opt(fn -> send(parent, {tag, thunk.()}) end, [
        :monitor,
        {:max_heap_size, limit}
      ])

    receive do
      {^tag, value} ->
        Process.demonitor(monitor, [:flush])
        {:ok, value}

      {:DOWN, ^monitor, :process, ^pid, :killed} ->
        {:error, :memory, max_heap, :killed}

      {:DOWN, ^monitor, :process, ^pid, reason} ->
        {:error, :raised, raised(reason), reason}
    after
      timeout ->
        Process.exit(pid, :kill)

        receive do
          {:DOWN, ^monitor, :process, ^pid, _reason} -> :ok
        end

        # A result sent as the timer fired is dropped with the call.
        receive do
          {^tag, _value} -> :ok
        after
          0 -> :ok
        end

        {:error, :timeout, timeout, :timeout}
    end
  end

  # The exception's module, never its message, which may quote the rows.
  defp raised({value, stack}) when is_list(stack),
    do: Exception.normalize(:error, value, stack).__struct__

  defp raised(_reason), do: :exit

  @doc """
  A source's SHA-256 as 64 lowercase hexadecimal digits: its key in the cache (spec/08
  §10.5.3).

      iex> Visualize.VirtualSource.Sandbox.hash("fn rows -> rows end")
      "a07f4aab6263d19d009830e7ad7b37931d654ff286700db61a32f064ea6d98d8"
  """
  @spec hash(String.t()) :: String.t()
  def hash(source) when is_binary(source),
    do: :sha256 |> :crypto.hash(source) |> Base.encode16(case: :lower)

  @doc """
  One checker fault as a line a person reads (spec/08 §10.5.1).

      iex> Visualize.VirtualSource.Sandbox.format_error({3, {:restricted, {"Process", :send, 3}}})
      "line 3: Process.send/3 is not allowed in a virtual source"
  """
  @spec format_error(fault()) :: String.t()
  def format_error({nil, reason}), do: words(reason)
  def format_error({line, reason}), do: "line #{line}: " <> words(reason)

  defp words({:too_long, max, size}),
    do: "the source is #{size} bytes; a virtual source's function may have #{max}"

  defp words({:unknown_atom, name}),
    do: "#{name} is a name this node has never seen; use a schema's field or value, or rename it"

  defp words({:syntax, message}), do: "does not parse: #{message}"

  defp words({:not_a_function, arity}),
    do: "the source must be one fn taking #{arity} argument#{if arity == 1, do: "", else: "s"}"

  defp words({:restricted, :struct}), do: "a struct is not allowed in a virtual source"

  defp words({:restricted, {module, name, arity}}),
    do: "#{module_text(module)}.#{name}/#{arity} is not allowed in a virtual source"

  defp words({:restricted, {name, arity}}),
    do: "#{name}/#{arity} is not allowed in a virtual source"

  defp words({:restricted_atom, atom}),
    do: "#{inspect(atom)} names a module, which a virtual source may not do"

  defp words({:dynamic_call, name}),
    do: "#{name}(…) is called on a value: a virtual source calls only the allowed modules"

  defp words({:unknown_field, name}),
    do: "#{name} is not a field of the virtual source's inputs or its schema"

  defp words({:into, :literal}),
    do: "into: takes a literal empty %{}, [] or \"\" in a virtual source"

  defp words({:uniq, :literal}), do: "uniq: takes true or false"
  defp words({:undefined_variable, name}), do: "the variable #{name} is not bound here"

  defp words({:guard, {module, name, arity}}),
    do: "#{module_text(module)}.#{name}/#{arity} cannot be used in a guard"

  defp words({:guard, {name, arity}}), do: "#{name}/#{arity} cannot be used in a guard"
  defp words({:pattern, form}), do: "#{form} cannot be used in a pattern"

  defp words({:fn_arity, arities}),
    do: "the clauses of one fn take #{Enum.map_join(arities, " and ", &to_string/1)} arguments"

  defp words({:compile, {kind, _detail}}), do: "the compiler did not finish (#{kind})"
  defp words({:compile, message}), do: "does not compile: #{message}"

  defp module_text(module) when is_binary(module), do: module
  defp module_text(module), do: inspect(module)
end
