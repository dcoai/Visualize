defmodule Visualize.VirtualSource.Sandbox.Names do
  @moduledoc false
  # A stored function's names, read without an atom made (spec/08 §10.5.1, spec/14 §9.4,
  # D-195). The source is parsed with a static atoms encoder that hands every name back as
  # `{:__sandbox_name__, string}`; this pass gives each its meaning by where it stands:
  #
  #   * a name the library or Elixir already has — a module, a function or a special form the
  #     checker knows, a binary segment's type, a word an allowed function takes (`:desc`,
  #     `:ok`) — is that atom, from tables built when the library compiles;
  #   * a variable is one of a fixed pool of the library's own atoms, its name kept in its
  #     meta for the checker's words, so a function of any names compiles without one made;
  #   * a map read's field (`row.cpu`) is its string, read by spelling when the function runs;
  #   * any other name — a map key, a keyword key, an atom literal — is its string, so a
  #     category value is a string, as a row's is (D-195);
  #   * a call's name the checker does not know is a sentinel the checker refuses, its string
  #     kept in the call's meta for the fault.
  #
  # Nothing here makes an atom: every atom this pass returns is one of its own tables.

  alias Visualize.VirtualSource.Sandbox.Allowlist

  @tag :__sandbox_name__
  @unknown :__sandbox_unknown__

  # The variables a function may bind: the library's own atoms, one per distinct name. The
  # pools are made when the library compiles, a fixed number (class (d), D-195).
  @pool_size 256
  @pool for n <- 1..@pool_size, do: :"sandbox_v#{n}"
  @under for n <- 1..@pool_size, do: :"_sandbox_v#{n}"

  @modules [Enum, Map, Keyword, String, Integer, Float, :math, Access, Kernel, Visualize.Data]
  @alias_parts [
    :Enum,
    :Map,
    :Keyword,
    :String,
    :Integer,
    :Float,
    :Access,
    :Kernel,
    :Visualize,
    :Data
  ]

  # Words an allowed function takes, the tuples and control words a function writes, and the
  # names the checker refuses by name: atoms Elixir has, kept as atoms.
  @words ~w(ok error cont halt suspend done asc desc trim parts global second millisecond
            microsecond nanosecond minute hour day week year infinity up down half_up
            half_even half_down ceiling floor leading trailing all first last discard keep
            default ascii greek turkic nfc nfd nfkc nfkd do else after into uniq reduce when
            math size unit binary bits bitstring bytes integer float utf8 utf16 utf32 signed
            unsigned big little native __struct__ __MODULE__ __ENV__ __CALLER__ __DIR__
            __STACKTRACE__ erlang os code ets file io init rpc net_kernel application
            persistent_term atomics counters prim_file erl_eval)a

  @calls Enum.uniq(
           Enum.map(Allowlist.kernel(), &elem(&1, 0)) ++
             Enum.flat_map(@modules, fn module ->
               Enum.map(Allowlist.allowed(module), &elem(&1, 0)) ++
                 Enum.map(Allowlist.excluded(module), &(&1 |> elem(0) |> elem(0)))
             end) ++
             Enum.map(Kernel.__info__(:functions) ++ Kernel.__info__(:macros), &elem(&1, 0)) ++
             Enum.map(Kernel.SpecialForms.__info__(:macros), &elem(&1, 0))
         )

  @known Map.new(@calls ++ @words ++ @alias_parts, &{Atom.to_string(&1), &1})
  # A literal, a map key and a keyword key are words only: `%{sum: rows}` keys a string,
  # though `sum` names a function.
  @literals Map.new(@words, &{Atom.to_string(&1), &1})
  @specials ~w(__MODULE__ __ENV__ __CALLER__ __DIR__ __STACKTRACE__)

  @doc false
  # The encoder a source is parsed with: every name comes back as its string, tagged.
  @spec encoder() :: (String.t(), keyword() -> {:ok, {atom(), String.t()}})
  def encoder, do: fn name, _meta -> {:ok, {@tag, name}} end

  @doc false
  # The sentinel a call the checker does not know is named by.
  @spec unknown() :: atom()
  def unknown, do: @unknown

  @doc false
  # The name a node was written with: the string kept in its meta, else its own name.
  @spec written(Macro.t()) :: atom() | String.t()
  def written({name, meta, _args}) when is_list(meta), do: Keyword.get(meta, :sandbox, name)
  def written(other), do: other

  @doc false
  # The parsed source with every name read, or `{:error, {:too_many_variables, max}}`.
  @spec read(Macro.t()) :: {:ok, Macro.t()} | {:error, {:too_many_variables, pos_integer()}}
  def read(quoted) do
    {read, vars} = node(quoted, %{})

    if map_size(vars) > @pool_size,
      do: {:error, {:too_many_variables, @pool_size}},
      else: {:ok, read}
  end

  # A remote call or a map read: the receiver decides what the name after the dot is.
  defp node({{:., dot_meta, [receiver, {@tag, original}]}, meta, args}, vars)
       when is_list(args) do
    {receiver, vars} = node(receiver, vars)
    {args, vars} = nodes(args, vars)

    name =
      case receiver do
        {:__aliases__, _m, _parts} -> call_name(original)
        atom when is_atom(atom) -> call_name(original)
        _value when args == [] -> if(meta[:no_parens], do: original, else: call_name(original))
        _value -> call_name(original)
      end

    {{{:., dot_meta, [receiver, name]}, Keyword.put(meta, :sandbox, original), args}, vars}
  end

  defp node({:__aliases__, meta, parts}, vars),
    do: {{:__aliases__, meta, Enum.map(parts, &alias_part/1)}, vars}

  # A capture of a named function, `&name/arity`: the name is a call's, not a variable's.
  defp node({:&, meta, [{:/, slash_meta, [{{@tag, name}, m, context}, arity]}]}, vars)
       when is_atom(context) and is_integer(arity) do
    {{:&, meta,
      [{:/, slash_meta, [{call_name(name), Keyword.put(m, :sandbox, name), context}, arity]}]},
     vars}
  end

  # A special form's variable (`__MODULE__`): the checker refuses it by its own atom.
  defp node({{@tag, name}, meta, context}, vars) when is_atom(context) and name in @specials,
    do: {{Map.fetch!(@known, name), meta, context}, vars}

  # A variable: a name with a context.
  defp node({{@tag, name}, meta, context}, vars) when is_atom(context) do
    {atom, vars} = variable(name, vars)
    {{atom, Keyword.put(meta, :sandbox, name), context}, vars}
  end

  # A local call or a form.
  defp node({{@tag, name}, meta, args}, vars) when is_list(args) do
    {args, vars} = nodes(args, vars)
    {{call_name(name), Keyword.put(meta, :sandbox, name), args}, vars}
  end

  # A keyword or a map key, and any other two-element tuple.
  defp node({{@tag, key}, value}, vars) do
    {value, vars} = node(value, vars)
    {{word(key), value}, vars}
  end

  defp node({@tag, name}, vars), do: {word(name), vars}

  defp node({form, meta, args}, vars) when is_list(args) do
    {form, vars} = node(form, vars)
    {args, vars} = nodes(args, vars)
    {{form, meta, args}, vars}
  end

  defp node({left, right}, vars) do
    {left, vars} = node(left, vars)
    {right, vars} = node(right, vars)
    {{left, right}, vars}
  end

  defp node(list, vars) when is_list(list), do: nodes(list, vars)
  defp node(other, vars), do: {other, vars}

  defp nodes(list, vars), do: Enum.map_reduce(list, vars, &node/2)

  defp variable("_", vars), do: {:_, vars}

  defp variable(name, vars) do
    case Map.fetch(vars, name) do
      {:ok, atom} ->
        {atom, vars}

      :error ->
        pool = if String.starts_with?(name, "_"), do: @under, else: @pool
        atom = Enum.at(pool, map_size(vars), @unknown)
        {atom, Map.put(vars, name, atom)}
    end
  end

  # A call's name: the atom the checker knows it by, else the sentinel the checker refuses.
  defp call_name(name) do
    case Map.fetch(@known, name) do
      {:ok, atom} -> atom
      :error -> @unknown
    end
  end

  defp alias_part({@tag, name}) do
    case Map.fetch(@known, name) do
      {:ok, atom} -> atom
      :error -> name
    end
  end

  defp alias_part(other), do: other

  @doc false
  # A name or a category value as a stored function sees it (spec/08 §10.5.6, D-195): the
  # atom of a word its allowed functions take (`:ok`, `:desc`, `:second`), else its string —
  # the rule its own literals are read by, so a row's `:ok` is the function's `:ok` and a
  # row's `day` field the key its `%{day: d}` matches.
  @spec spelling(term()) :: term()
  def spelling(name) when is_binary(name), do: word(name)

  def spelling(name) when is_atom(name) and name not in [nil, true, false],
    do: name |> Atom.to_string() |> word()

  def spelling(other), do: other

  # A literal word: Elixir's or the library's atom, else its string.
  defp word(name) do
    case Map.fetch(@literals, name) do
      {:ok, atom} -> atom
      :error -> name
    end
  end
end
