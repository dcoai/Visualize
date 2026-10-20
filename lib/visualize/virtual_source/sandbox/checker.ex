defmodule Visualize.VirtualSource.Sandbox.Checker do
  @moduledoc false
  # The checker of a stored virtual-source function (spec/08 §10.5.1, D-194): the source
  # parsed with `existing_atoms_only`, required to be one `fn` of the arity, and walked
  # before macros expand in three contexts — an expression, a pattern, a guard — every
  # form held to `Visualize.VirtualSource.Sandbox.Allowlist`. It evaluates nothing.
  #
  # The walk threads one state: the faults found, the variables bound in the scope being
  # walked, the fields a map read may name and the line last seen. A construct that opens
  # a scope (a clause, a comprehension) walks inside it and restores the outer variables.

  alias Visualize.VirtualSource.Sandbox.{Allowlist, Names}

  @special_vars [:__MODULE__, :__ENV__, :__CALLER__, :__DIR__, :__STACKTRACE__]

  @segment_types ~w(binary bits bitstring bytes integer float utf8 utf16 utf32 signed
                    unsigned big little native)a

  # The aliases a remote call may name, by their parts. The parts are atoms in this
  # module's code, so they exist once it is loaded, before any source is parsed with
  # `existing_atoms_only`: `Keyword.get(…)` parses on a node that never wrote `Keyword`.
  @aliases %{
    [:Enum] => Enum,
    [:Map] => Map,
    [:Keyword] => Keyword,
    [:String] => String,
    [:Integer] => Integer,
    [:Float] => Float,
    [:Access] => Access,
    [:Kernel] => Kernel,
    [:Visualize, :Data] => Visualize.Data
  }

  @doc false
  def check(source, opts) do
    max = Keyword.fetch!(opts, :max_source)
    arity = Keyword.fetch!(opts, :arity)

    fields =
      case Keyword.fetch!(opts, :fields) do
        nil -> nil
        fields -> MapSet.new(fields, &to_string/1)
      end

    if byte_size(source) > max do
      {:error, [{nil, {:too_long, max, byte_size(source)}}]}
    else
      # Every name is read without an atom made (D-195): `Sandbox.Names` gives each its
      # meaning, and an interpolated atom is still held to existing atoms.
      case Code.string_to_quoted(source,
             static_atoms_encoder: Names.encoder(),
             existing_atoms_only: true
           ) do
        {:ok, quoted} -> read(quoted, arity, fields)
        {:error, {meta, message, token}} -> {:error, [parse_fault(meta, message, token)]}
      end
    end
  end

  defp read(quoted, arity, fields) do
    case Names.read(quoted) do
      {:ok, read} -> function(read, arity, fields)
      {:error, reason} -> {:error, [{nil, reason}]}
    end
  end

  defp parse_fault(meta, message, token) do
    line = Keyword.get(List.wrap(meta), :line)
    text = message_text(message)

    if String.starts_with?(text, "unsafe atom does not exist"),
      do: {line, {:unknown_atom, token}},
      else: {line, {:syntax, String.trim(text <> token)}}
  end

  defp message_text({prefix, suffix}), do: message_text(prefix) <> message_text(suffix)
  defp message_text(text) when is_binary(text), do: text
  defp message_text(other), do: inspect(other)

  # One `fn`, every clause of `arity` arguments; then the walk.
  defp function({:fn, meta, clauses} = quoted, arity, fields) when is_list(clauses) do
    state = %{faults: [], vars: MapSet.new(), fields: fields, line: meta[:line]}

    state =
      if Enum.all?(clauses, &(clause_arity(&1) == arity)),
        do: expr(quoted, state),
        else: fault(state, {:not_a_function, arity})

    case state.faults do
      [] -> {:ok, quoted}
      faults -> {:error, faults |> Enum.reverse() |> Enum.uniq() |> Enum.sort_by(&line_key/1)}
    end
  end

  defp function(quoted, arity, _fields) do
    {:error, [{line_of(quoted), {:not_a_function, arity}}]}
  end

  defp line_key({nil, _reason}), do: 0
  defp line_key({line, _reason}), do: line

  defp line_of({_name, meta, _args}) when is_list(meta), do: meta[:line]
  defp line_of(_quoted), do: nil

  defp clause_arity({:->, _meta, [args, _body]}) when is_list(args), do: length(heads(args))
  defp clause_arity(_other), do: nil

  # A clause's patterns, without its guard.
  defp heads([{:when, _meta, args}]), do: Enum.drop(args, -1)
  defp heads(args), do: args

  # -- state -------------------------------------------------------------------------------

  defp fault(state, reason), do: %{state | faults: [{state.line, reason} | state.faults]}

  defp at(state, meta) when is_list(meta) do
    case meta[:line] do
      nil -> state
      line -> %{state | line: line}
    end
  end

  defp at(state, _meta), do: state

  # Walks `fun` in a scope of its own: the variables it binds do not leak.
  defp scoped(state, fun) do
    %{fun.(state) | vars: state.vars}
  end

  defp exprs(list, state), do: Enum.reduce(list, state, &expr/2)

  # -- expressions -------------------------------------------------------------------------

  defp expr(number, state) when is_number(number), do: state
  defp expr(binary, state) when is_binary(binary), do: state
  defp expr(atom, state) when is_atom(atom), do: atom(atom, state)
  defp expr(list, state) when is_list(list), do: exprs(list, state)
  defp expr({left, right}, state), do: exprs([left, right], state)

  defp expr({name, meta, context} = var, state) when is_atom(name) and is_atom(context) do
    state = at(state, meta)

    cond do
      name in @special_vars -> fault(state, {:restricted, {name, 0}})
      MapSet.member?(state.vars, name) -> state
      true -> fault(state, {:undefined_variable, var_name(var)})
    end
  end

  defp expr({:__block__, meta, body}, state) when is_list(body),
    do: exprs(body, at(state, meta))

  defp expr({:=, meta, [left, right]}, state) do
    state = expr(right, at(state, meta))
    pattern(left, state, state.vars)
  end

  defp expr({:fn, meta, clauses}, state) when is_list(clauses) do
    state = at(state, meta)

    state =
      case clauses |> Enum.map(&clause_arity/1) |> Enum.uniq() do
        [_one] -> state
        arities -> fault(state, {:fn_arity, arities})
      end

    Enum.reduce(clauses, state, &clause/2)
  end

  defp expr({:case, meta, [subject, [do: clauses]]}, state) when is_list(clauses) do
    state = expr(subject, at(state, meta))
    Enum.reduce(clauses, state, &clause/2)
  end

  defp expr({:cond, meta, [[do: clauses]]}, state) when is_list(clauses) do
    Enum.reduce(clauses, at(state, meta), fn
      {:->, m, [[condition], body]}, acc ->
        scoped(at(acc, m), &expr(body, expr(condition, &1)))

      other, acc ->
        malformed(acc, :cond, other)
    end)
  end

  defp expr({branch, meta, [condition, blocks]}, state)
       when branch in [:if, :unless] and is_list(blocks) do
    state = expr(condition, at(state, meta))

    Enum.reduce(blocks, state, fn
      {key, body}, acc when key in [:do, :else] -> scoped(acc, &expr(body, &1))
      other, acc -> malformed(acc, branch, other)
    end)
  end

  defp expr({:with, meta, args}, state) when is_list(args) and args != [],
    do: with_(args, at(state, meta))

  defp expr({:for, meta, args}, state) when is_list(args) and args != [],
    do: for_(args, at(state, meta))

  defp expr({:&, meta, [arg]}, state), do: capture(arg, at(state, meta))

  defp expr({:|>, meta, [left, right]}, state) do
    state = at(state, meta)

    case right do
      {callee, call_meta, args} when is_list(args) and callee != :fn ->
        expr({callee, call_meta, [left | args]}, state)

      _not_a_call ->
        fault(expr(left, state), {:syntax, "a pipe into something that is not a call"})
    end
  end

  defp expr({:%, meta, _args}, state), do: fault(at(state, meta), {:restricted, :struct})

  defp expr({:%{}, meta, entries}, state) when is_list(entries) do
    Enum.reduce(entries, at(state, meta), fn
      {:|, _m, [map, pairs]}, acc -> expr(pairs, expr(map, acc))
      entry, acc -> expr(entry, acc)
    end)
  end

  defp expr({:{}, meta, elements}, state) when is_list(elements),
    do: exprs(elements, at(state, meta))

  defp expr({:<<>>, meta, segments}, state) when is_list(segments),
    do: Enum.reduce(segments, at(state, meta), &segment(&1, &2, :expr))

  defp expr({:|, meta, [head, tail]}, state), do: exprs([head, tail], at(state, meta))

  defp expr({:__aliases__, meta, parts}, state),
    do: fault(at(state, meta), {:restricted_atom, alias_name(parts)})

  defp expr({:^, meta, [_var]}, state), do: fault(at(state, meta), {:pattern, :^})

  defp expr({{:., meta, [receiver, name]}, call_meta, args}, state)
       when (is_atom(name) or is_binary(name)) and is_list(args),
       do: remote(receiver, name, call_meta, args, at(at(state, meta), call_meta))

  defp expr({{:., meta, [fun]}, _call_meta, args}, state) when is_list(args),
    do: exprs(args, expr(fun, at(state, meta)))

  defp expr({name, meta, args}, state) when is_atom(name) and is_list(args) do
    state = at(state, meta)

    # A refused form's arguments are not walked: `receive`'s clauses, `quote`'s body.
    if Allowlist.local?(name, length(args)),
      do: exprs(args, state),
      else: fault(state, {:restricted, {shown(name, meta), length(args)}})
  end

  defp expr(other, state), do: malformed(state, :expression, other)

  defp malformed(state, form, _quoted), do: fault(state, {:syntax, "malformed #{form}"})

  defp var_name(var), do: Names.written(var)

  # A name as the source wrote it: a call the checker does not know keeps its string.
  defp shown(name, meta) do
    if name == Names.unknown(), do: Keyword.get(meta, :sandbox, name), else: name
  end

  defp atom(atom, state) when atom in [nil, true, false], do: state
  defp atom(:__struct__, state), do: fault(state, {:restricted_atom, :__struct__})

  defp atom(atom, state) do
    if String.starts_with?(Atom.to_string(atom), "Elixir."),
      do: fault(state, {:restricted_atom, atom}),
      else: state
  end

  defp alias_name(parts) do
    if Enum.all?(parts, &(is_atom(&1) or is_binary(&1))) do
      parts |> Enum.reject(&(&1 == Elixir)) |> Enum.map_join(".", &to_string/1)
    else
      "__MODULE__"
    end
  end

  # -- calls -------------------------------------------------------------------------------

  # A remote call, a map read or a dynamic call, by the receiver (spec/08 §10.5.1).
  defp remote(receiver, name, meta, args, state) do
    case module(receiver) do
      {:module, module} ->
        arity = length(args)

        state =
          cond do
            not Allowlist.remote?(module, name, arity) ->
              fault(state, {:restricted, {module, shown(name, meta), arity}})

            module == Enum and name == :into and not literal_target?(Enum.at(args, 1)) ->
              fault(state, {:into, :literal})

            true ->
              state
          end

        exprs(args, state)

      {:unknown, written} ->
        exprs(args, fault(state, {:restricted, {written, shown(name, meta), length(args)}}))

      :value when args == [] ->
        if meta[:no_parens],
          do: expr(receiver, field(name, state)),
          else: expr(receiver, fault(state, {:dynamic_call, shown(name, meta)}))

      :value ->
        exprs(args, expr(receiver, fault(state, {:dynamic_call, shown(name, meta)})))
    end
  end

  defp module({:__aliases__, _meta, parts}) do
    case Map.fetch(@aliases, Enum.reject(parts, &(&1 == Elixir))) do
      {:ok, module} -> {:module, module}
      :error -> {:unknown, alias_name(parts)}
    end
  end

  defp module(atom) when is_atom(atom) do
    if Allowlist.module_name?(atom), do: {:module, atom}, else: {:unknown, atom}
  end

  defp module(_value), do: :value

  defp field(name, %{fields: nil} = state) when is_binary(name), do: state
  defp field(name, %{fields: nil} = state), do: atom(name, state)

  defp field(name, state) do
    if MapSet.member?(state.fields, to_string(name)),
      do: state,
      else: fault(state, {:unknown_field, name})
  end

  defp literal_target?({:%{}, _meta, []}), do: true
  defp literal_target?([]), do: true
  defp literal_target?(""), do: true
  defp literal_target?(_other), do: false

  # `&Mod.fun/n`, `&fun/n`, or `&(expression)` over `&1`, `&2`, ….
  defp capture(n, state) when is_integer(n), do: state

  defp capture({:/, _meta, [{{:., _m, [receiver, name]}, cm, []}, arity]}, state)
       when is_atom(name) and is_integer(arity) do
    name = shown(name, cm)

    case module(receiver) do
      {:module, Enum} when name == :into ->
        fault(state, {:into, :literal})

      {:module, module} ->
        if Allowlist.remote?(module, name, arity),
          do: state,
          else: fault(state, {:restricted, {module, name, arity}})

      {:unknown, written} ->
        fault(state, {:restricted, {written, name, arity}})

      :value ->
        fault(state, {:dynamic_call, name})
    end
  end

  defp capture({:/, _meta, [{name, m, context}, arity]}, state)
       when is_atom(name) and is_atom(context) and is_integer(arity) do
    if Allowlist.local?(name, arity),
      do: state,
      else: fault(state, {:restricted, {shown(name, m), arity}})
  end

  defp capture(body, state), do: expr(body, state)

  # -- clauses -----------------------------------------------------------------------------

  # A clause of `fn`, `case` or `with`'s `else`: its patterns bind in a scope of its own,
  # its guard reads them, its body runs in it.
  defp clause({:->, meta, [args, body]}, state) when is_list(args) do
    state = at(state, meta)

    scoped(state, fn state ->
      {patterns, guard} = split_guard(args)
      outer = state.vars
      state = Enum.reduce(patterns, state, &pattern(&1, &2, outer))
      state = if guard, do: guard(guard, state), else: state
      expr(body, state)
    end)
  end

  defp clause(other, state), do: malformed(state, :clause, other)

  defp split_guard([{:when, _meta, args}]), do: {Enum.drop(args, -1), List.last(args)}
  defp split_guard(args), do: {args, nil}

  # `with`: each `<-` binds for what follows; `else` clauses run in the outer scope.
  defp with_(args, state) do
    {clauses, blocks} = split_blocks(args)

    scoped(state, fn inner ->
      inner = Enum.reduce(clauses, inner, &generator/2)

      Enum.reduce(blocks, inner, fn
        {:do, body}, acc ->
          scoped(acc, &expr(body, &1))

        {:else, else_clauses}, acc when is_list(else_clauses) ->
          scoped(
            %{acc | vars: state.vars},
            &Enum.reduce(else_clauses, &1, fn c, a -> clause(c, a) end)
          )

        other, acc ->
          malformed(acc, :with, other)
      end)
    end)
  end

  # `for`: generators bind in order; `into:` and `uniq:` are literals; `reduce:` makes the
  # body a list of clauses over the accumulator.
  defp for_(args, state) do
    {generators, blocks} = split_blocks(args)

    scoped(state, fn inner ->
      inner = Enum.reduce(generators, inner, &generator/2)
      reduce? = Keyword.has_key?(blocks, :reduce)

      Enum.reduce(blocks, inner, fn
        {:into, target}, acc ->
          if literal_target?(target), do: acc, else: fault(acc, {:into, :literal})

        {:uniq, value}, acc when is_boolean(value) ->
          acc

        {:uniq, _value}, acc ->
          fault(acc, {:uniq, :literal})

        {:reduce, initial}, acc ->
          expr(initial, %{acc | vars: state.vars}) |> Map.put(:vars, acc.vars)

        {:do, clauses}, acc when reduce? and is_list(clauses) ->
          Enum.reduce(clauses, acc, &clause/2)

        {:do, body}, acc ->
          scoped(acc, &expr(body, &1))

        other, acc ->
          malformed(acc, :for, other)
      end)
    end)
  end

  # The trailing keyword lists: a `do` block written as one is its own argument after the
  # options (`for x <- xs, reduce: 0 do … end`).
  defp split_blocks(args) do
    {blocks, rest} =
      args
      |> Enum.reverse()
      |> Enum.split_while(&(is_list(&1) and &1 != [] and Keyword.keyword?(&1)))

    blocks = blocks |> Enum.reverse() |> Enum.concat()

    if Keyword.has_key?(blocks, :do),
      do: {Enum.reverse(rest), blocks},
      else: {args, []}
  end

  # A generator or a `with` clause: the right side read in the scope so far, then the
  # pattern (and its guard) bound; a bitstring generator likewise; anything else is a
  # filter or a bare expression.
  defp generator({:<-, meta, [left, right]}, state) do
    state = expr(right, at(state, meta))
    {patterns, guard} = split_guard([left])
    outer = state.vars
    state = Enum.reduce(patterns, state, &pattern(&1, &2, outer))
    if guard, do: guard(guard, state), else: state
  end

  defp generator({:<<>>, meta, [{:<-, _m, [left, right]}]}, state) do
    state = expr(right, at(state, meta))
    pattern({:<<>>, meta, left_segments(left)}, state, state.vars)
  end

  defp generator(filter, state), do: expr(filter, state)

  defp left_segments({:<<>>, _meta, segments}), do: segments
  defp left_segments(segment), do: [segment]

  # -- patterns ----------------------------------------------------------------------------

  # `outer` is the scope before the pattern, which a pin reads.
  defp pattern(number, state, _outer) when is_number(number), do: state
  defp pattern(binary, state, _outer) when is_binary(binary), do: state
  defp pattern(atom, state, _outer) when is_atom(atom), do: atom(atom, state)

  defp pattern(list, state, outer) when is_list(list),
    do: Enum.reduce(list, state, &pattern(&1, &2, outer))

  defp pattern({left, right}, state, outer),
    do: pattern(right, pattern(left, state, outer), outer)

  defp pattern({name, meta, context}, state, _outer) when is_atom(name) and is_atom(context) do
    state = at(state, meta)

    cond do
      name in @special_vars -> fault(state, {:restricted, {name, 0}})
      name == :_ -> state
      true -> %{state | vars: MapSet.put(state.vars, name)}
    end
  end

  defp pattern({:^, meta, [{name, _m, context} = var]}, state, outer)
       when is_atom(name) and is_atom(context) do
    state = at(state, meta)

    if MapSet.member?(outer, name),
      do: state,
      else: fault(state, {:undefined_variable, var_name(var)})
  end

  defp pattern({:=, meta, [left, right]}, state, outer),
    do: pattern(right, pattern(left, at(state, meta), outer), outer)

  defp pattern({:|, meta, [head, tail]}, state, outer),
    do: pattern(tail, pattern(head, at(state, meta), outer), outer)

  defp pattern({:{}, meta, elements}, state, outer) when is_list(elements),
    do: Enum.reduce(elements, at(state, meta), &pattern(&1, &2, outer))

  defp pattern({:%{}, meta, entries}, state, outer) when is_list(entries) do
    Enum.reduce(entries, at(state, meta), fn
      {key, value}, acc -> pattern(value, map_key(key, acc, outer), outer)
      other, acc -> fault(acc, {:pattern, form(other)})
    end)
  end

  defp pattern({:%, meta, _args}, state, _outer),
    do: fault(at(state, meta), {:restricted, :struct})

  defp pattern({:<>, meta, [prefix, rest]}, state, outer) do
    state = at(state, meta)

    state =
      case prefix do
        binary when is_binary(binary) -> state
        {:<<>>, _m, _segments} -> pattern(prefix, state, outer)
        other -> fault(state, {:pattern, form(other)})
      end

    pattern(rest, state, outer)
  end

  defp pattern({:<<>>, meta, segments}, state, _outer) when is_list(segments),
    do: Enum.reduce(segments, at(state, meta), &segment(&1, &2, :pattern))

  defp pattern({:-, _meta, [number]}, state, _outer) when is_number(number), do: state

  defp pattern(other, state, _outer), do: fault(state, {:pattern, form(other)})

  defp map_key(key, state, _outer) when is_atom(key), do: atom(key, state)
  defp map_key(key, state, _outer) when is_binary(key) or is_number(key), do: state
  defp map_key({:^, _meta, _args} = pin, state, outer), do: pattern(pin, state, outer)
  defp map_key(other, state, _outer), do: fault(state, {:pattern, form(other)})

  defp form({name, _meta, _args}) when is_atom(name), do: name
  defp form({{:., _meta, _args}, _call_meta, _call_args}), do: :.
  defp form(_other), do: :expression

  # -- binaries ----------------------------------------------------------------------------

  # A segment's value is an expression or a pattern; its type is a fixed vocabulary, whose
  # `size/1` reads a bound variable or a number.
  defp segment({:"::", meta, [value, type]}, state, context) do
    state = at(state, meta)

    state =
      case context do
        :expr -> expr(value, state)
        :pattern -> pattern(value, state, state.vars)
      end

    segment_type(type, state)
  end

  defp segment(value, state, :expr), do: expr(value, state)
  defp segment(value, state, :pattern), do: pattern(value, state, state.vars)

  defp segment_type({name, _meta, context}, state)
       when name in @segment_types and is_atom(context),
       do: state

  defp segment_type({:-, _meta, [left, right]}, state),
    do: segment_type(right, segment_type(left, state))

  defp segment_type({:*, _meta, [size, unit]}, state) when is_integer(unit),
    do: segment_type(size, state)

  defp segment_type({sizer, _meta, [size]}, state) when sizer in [:size, :unit],
    do: expr(size, state)

  defp segment_type(size, state) when is_integer(size), do: state

  defp segment_type({name, _meta, args}, state) when is_atom(name),
    do: fault(state, {:restricted, {name, if(is_list(args), do: length(args), else: 0)}})

  defp segment_type(_other, state), do: fault(state, {:syntax, "malformed binary segment"})

  # -- guards ------------------------------------------------------------------------------

  defp guard(number, state) when is_number(number), do: state
  defp guard(binary, state) when is_binary(binary), do: state
  defp guard(atom, state) when is_atom(atom), do: atom(atom, state)
  defp guard(list, state) when is_list(list), do: Enum.reduce(list, state, &guard/2)
  defp guard({left, right}, state), do: guard(right, guard(left, state))

  defp guard({name, _meta, context} = var, state) when is_atom(name) and is_atom(context),
    do: expr(var, state)

  defp guard({:when, meta, [left, right]}, state), do: guard(right, guard(left, at(state, meta)))

  defp guard({:{}, meta, elements}, state) when is_list(elements),
    do: Enum.reduce(elements, at(state, meta), &guard/2)

  defp guard({:%{}, meta, entries}, state) when is_list(entries),
    do: Enum.reduce(entries, at(state, meta), &guard/2)

  defp guard({{:., meta, [receiver, name]}, call_meta, args} = call, state)
       when (is_atom(name) or is_binary(name)) and is_list(args) do
    state = at(at(state, meta), call_meta)

    case module(receiver) do
      {:module, Integer} when name in [:is_even, :is_odd] and length(args) == 1 ->
        Enum.reduce(args, state, &guard/2)

      :value when args == [] ->
        if call_meta[:no_parens], do: guard(receiver, field(name, state)), else: expr(call, state)

      _other ->
        case expr(call, state) do
          %{faults: faults} = checked when faults != state.faults -> checked
          checked -> fault(checked, {:guard, {module_label(receiver), name, length(args)}})
        end
    end
  end

  defp guard({name, meta, args}, state) when is_atom(name) and is_list(args) do
    state = at(state, meta)
    arity = length(args)

    cond do
      Allowlist.guard?(name, arity) -> Enum.reduce(args, state, &guard/2)
      Allowlist.local?(name, arity) -> fault(state, {:guard, {name, arity}})
      true -> fault(state, {:restricted, {shown(name, meta), arity}})
    end
  end

  defp guard(other, state), do: malformed(state, :guard, other)

  defp module_label(receiver) do
    case module(receiver) do
      {:module, module} -> module
      {:unknown, written} -> written
      :value -> :value
    end
  end
end
