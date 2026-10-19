defmodule Visualize.VirtualSources do
  @moduledoc """
  A host's virtual-source functions (spec/08 §10.5.8, D-194), written as Elixir in the
  host's own module and tested with ExUnit, as generators are (spec/14 §3.13, D-177):

      defmodule MyApp.Sources do
        use Visualize.VirtualSources

        defsource health(rows) do
          cpu = Enum.map(rows, & &1.cpu)
          %{state: if(List.last(cpu) > 90, do: :error, else: :ok)}
        end
      end

  `use Visualize.VirtualSources` imports `defsource/2` and compiles
  `__virtual_sources__/0`, each function's name and its source text, `[{name, source}]` in
  definition order. The text is captured when the module compiles, since a release strips
  the debug information a later reading would need; the builder shows it.

  A host's function is trusted — the sandbox's checker does not read it — but it runs
  through the same bounded runner as a stored one (`Visualize.VirtualSource.Sandbox.run/3`),
  so a runaway ends as a fault, not as the board's crash. A virtual source names it with
  `function: :health`; the host registers the module with `config :visualize,
  virtual_sources: [MyApp.Sources]` or the board's `virtual_sources:` option.

  ## Examples

      iex> defmodule Doc.Sources do
      ...>   use Visualize.VirtualSources
      ...>   defsource doubled(rows), do: Enum.map(rows, &(&1 * 2))
      ...> end
      iex> Doc.Sources.doubled([1, 2])
      [2, 4]
      iex> Doc.Sources.__virtual_sources__()
      [doubled: "fn rows -> Enum.map(rows, &(&1 * 2)) end"]
      iex> Visualize.VirtualSources.registry([Doc.Sources])
      %{doubled: Doc.Sources}

  """

  @typedoc "Each host function's name by the module that defines it."
  @type registry :: %{atom() => module()}

  @doc false
  defmacro __using__(_opts) do
    quote do
      import Visualize.VirtualSources, only: [defsource: 2]
      Module.register_attribute(__MODULE__, :visualize_virtual_sources, accumulate: true)
      @before_compile Visualize.VirtualSources
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    clauses =
      env.module
      |> Module.get_attribute(:visualize_virtual_sources)
      |> Enum.reverse()

    sources =
      clauses
      |> Enum.map(&elem(&1, 0))
      |> Enum.uniq()
      |> Enum.map(fn name ->
        fns = for {^name, clause} <- clauses, do: clause
        {name, Macro.to_string({:fn, [], fns})}
      end)

    quote do
      @doc false
      def __virtual_sources__, do: unquote(sources)
    end
  end

  @doc """
  A host's virtual-source function: `defsource name(arg) do … end` is a public `def` of one
  argument, recorded with its source text under the module's `__virtual_sources__/0`. A
  function of several clauses is defined clause by clause, as any function is, and listed
  once with every clause.
  """
  defmacro defsource(head, body) do
    {name, args, guard} = head!(head, __CALLER__)
    block = body!(body, __CALLER__)
    patterns = if guard, do: [{:when, [], args ++ [guard]}], else: args
    clause = Macro.escape({:->, [], [patterns, block]})

    quote do
      @visualize_virtual_sources {unquote(name), unquote(clause)}
      def unquote(head), unquote(body)
    end
  end

  defp head!({:when, _meta, [head, guard]}, caller) do
    {name, args, nil} = head!(head, caller)
    {name, args, guard}
  end

  defp head!({name, _meta, [_arg] = args}, _caller) when is_atom(name), do: {name, args, nil}

  defp head!(head, caller) do
    raise CompileError,
      file: caller.file,
      line: caller.line,
      description:
        "defsource needs a head of one argument, `name(rows)`, as a stored function " <>
          "takes; got #{Macro.to_string(head)}"
  end

  defp body!([do: block], _caller), do: block

  defp body!(body, caller) do
    raise CompileError,
      file: caller.file,
      line: caller.line,
      description: "defsource takes a do block alone; got #{Macro.to_string(body)}"
  end

  @doc "As `registry/1` with no modules: the configuration's alone."
  @spec registry() :: registry()
  def registry, do: registry([])

  @doc """
  The registry of `modules` then `config :visualize, virtual_sources:` (spec/08 §10.5.8):
  each function's name by the module that defines it. Raises `ArgumentError` for a module
  without `__virtual_sources__/0` and for a name two modules define.
  """
  @spec registry([module()]) :: registry()
  def registry(modules) when is_list(modules) do
    configured = Application.get_env(:visualize, :virtual_sources, [])

    (modules ++ configured)
    |> Enum.uniq()
    |> Enum.reduce(%{}, fn module, registry ->
      module |> sources!() |> Enum.reduce(registry, &register(&2, elem(&1, 0), module))
    end)
  end

  defp sources!(module) do
    if is_atom(module) and Code.ensure_loaded?(module) and
         function_exported?(module, :__virtual_sources__, 0) do
      module.__virtual_sources__()
    else
      raise ArgumentError,
            "#{inspect(module)} is not a virtual-source module: `use Visualize.VirtualSources` " <>
              "defines __virtual_sources__/0 (spec/08 §10.5.8)"
    end
  end

  defp register(registry, name, module) do
    case Map.fetch(registry, name) do
      :error ->
        Map.put(registry, name, module)

      {:ok, other} ->
        raise ArgumentError,
              "virtual-source function #{name} is defined by both #{inspect(other)} and " <>
                "#{inspect(module)}: a virtual source names one function (spec/08 §10.5.8)"
    end
  end
end
