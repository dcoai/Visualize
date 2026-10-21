defmodule Visualize.Chart.Template do
  @moduledoc false
  # The first two steps of application (spec/14 §7.3, D-65): `resolve/2` replaces every
  # variable in a chart by its value, walking the map by the schema so that a text part
  # is known to be one; `bind/2` binds each slot to a source of the pool and checks the
  # slot's declared fields against the bound rows. Both report every fault by path.
  # `walk/2` is the walk itself, over variables and schema facts alike, with which the
  # schema step (`Visualize.Chart.Facts`, §7.4) resolves facts; `entry/3` is binding's
  # lookup, which that step reads a slot's feed and delivery with.

  alias Visualize.Chart
  alias Visualize.Chart.{Fact, Names, Schema, Text, Validator, Var}
  alias Visualize.Data.{Delivery, Table}

  @doc false
  # The chart with every variable resolved from the given values or the declared
  # defaults, `vars` emptied; or the unresolved uses and the undeclared names by path.
  @spec resolve(Chart.t(), %{atom() => term()}) ::
          {:ok, Chart.t()} | {:error, [Validator.error(), ...]}
  def resolve(%Chart{vars: declared} = chart, given) do
    undeclared =
      for {name, _} <- given, not Map.has_key?(declared, name) do
        {[:vars, name], {:undeclared, :var, name}}
      end

    values = Map.merge(defaults(declared), given)
    map = chart |> Chart.to_map() |> Map.put(:vars, %{})
    {resolved, unresolved} = walk(map, &variable(&1, &2, values))

    case Enum.sort_by(undeclared ++ unresolved, &elem(&1, 0)) do
      [] -> {:ok, struct(Chart, resolved)}
      errors -> {:error, errors}
    end
  end

  # A declared default of `nil` is no default: the variable MUST be supplied (§2.4).
  defp defaults(declared) do
    for {name, %{default: default}} <- declared, default != nil, into: %{}, do: {name, default}
  end

  # Resolution is single level (spec/14 §7.1): a value that is itself a variable is
  # reported at every path the variable stood at, never substituted. A fact is left for
  # the schema step (§7.4).
  defp variable(%Var{name: name}, path, values) do
    case Map.fetch(values, name) do
      {:ok, %Var{}} -> {%Var{name: name}, [{path, {:var_binding, name}}]}
      {:ok, v} -> {v, []}
      :error -> {%Var{name: name}, [{path, {:unresolved, :var, name}}]}
    end
  end

  defp variable(other, _path, _values), do: {other, []}

  # -- the walk, by node kind -----------------------------------------------------------

  @doc false
  # The design map with every variable and every fact it reaches replaced by what
  # `substitute` answers for it at its path — `{value, errors}` — and every error. The
  # walk follows the schema, so a text part is known to be one: a hole stands at the
  # text's key, and a number or an atom put into a text is written as a string (§7.3).
  @spec walk(map(), (Var.t() | Fact.t(), Validator.path() -> {term(), [Validator.error()]})) ::
          {map(), [Validator.error()]}
  def walk(map, substitute) when is_map(map), do: node(:design, map, [], substitute)

  defp node(kind, map, path, sub) do
    Enum.reduce(map, {%{}, []}, fn {k, v}, {acc, errors} ->
      type = if spec = Schema.key(kind, k), do: spec.type, else: :term
      {v, e} = value(type, v, path ++ [k], sub)
      {Map.put(acc, k, v), errors ++ e}
    end)
  end

  defp value(_type, %Var{} = var, path, sub), do: sub.(var, path)
  defp value(_type, %Fact{} = fact, path, sub), do: sub.(fact, path)

  defp value({:node, kind}, v, path, sub) when is_map(v) and not is_struct(v) do
    node(kind, v, path, sub)
  end

  defp value({:list, t}, v, path, sub) when is_list(v), do: each(t, v, path, sub)
  # An extent's member may be a variable or a fact: a threshold at a feed's target (§4.3).
  defp value(type, v, path, sub) when type in [:extent, :range] and is_list(v),
    do: each(:term, v, path, sub)

  defp value({:map, t}, v, path, sub) when is_map(v) and not is_struct(v) do
    Enum.reduce(v, {%{}, []}, fn {k, e}, {acc, errors} ->
      {e, errs} = value(t, e, path ++ [k], sub)
      {Map.put(acc, k, e), errors ++ errs}
    end)
  end

  defp value({:one_of, types}, v, path, sub) do
    case Schema.select(types, v) do
      nil -> {v, []}
      type -> value(type, v, path, sub)
    end
  end

  defp value(:text, parts, path, sub) when is_list(parts) do
    {resolved, errors} = each(:term, parts, path, sub)
    {Enum.map(resolved, &part/1), errors}
  end

  # The string form (§7.1): its holes take their values in place; a field stays for the
  # datum. The result is written back as the string it is.
  defp value(:text, string, path, sub) when is_binary(string) do
    case Text.parse(string) do
      {:ok, parts} ->
        {resolved, errors} =
          Enum.reduce(parts, {[], []}, fn
            part, {acc, errors} when is_struct(part, Var) or is_struct(part, Fact) ->
              {v, e} = sub.(part, path)
              {[part(v) | acc], errors ++ e}

            other, {acc, errors} ->
              {[other | acc], errors}
          end)

        {resolved |> Enum.reverse() |> Text.unparse(), errors}

      {:error, _} ->
        {string, []}
    end
  end

  defp value(_type, v, _path, _sub), do: {v, []}

  defp each(type, list, path, sub) do
    list
    |> Enum.with_index()
    |> Enum.reduce({[], []}, fn {e, i}, {acc, errors} ->
      {e, errs} = value(type, e, path ++ [i], sub)
      {[e | acc], errors ++ errs}
    end)
    |> then(fn {acc, errors} -> {Enum.reverse(acc), errors} end)
  end

  # A number or an atom put into a text is written as a string (§7.3).
  defp part(v) when is_number(v) or (is_atom(v) and not is_struct(v)), do: to_string(v)
  defp part(v), do: v

  # -- binding --------------------------------------------------------------------------

  @doc false
  # The bound sources by slot name — each slot's pool entry under its own name, else its
  # default — or the unbound slots and the missing fields by path (spec/14 §7.3).
  @spec bind(Chart.t(), %{atom() => term()}) ::
          {:ok, %{atom() => term()}} | {:error, [Validator.error(), ...]}
  def bind(%Chart{sources: slots}, pool) when is_map(slots) do
    {bound, errors} =
      Enum.reduce(slots, {%{}, []}, fn {name, slot}, {bound, errors} ->
        case entry(pool, name, slot) do
          {:ok, _feed, source} ->
            # A delivery binds as the source it carries (spec/08 §10.4), and a tensor as
            # its columns named by the slot's fields (D-214).
            case read(slot, Delivery.source(source)) do
              {:ok, source} ->
                {Map.put(bound, name, source), errors ++ missing_fields(slot, source, name)}

              {:error, reason} ->
                {bound, [{[:sources, name], reason} | errors]}
            end

          :error ->
            {bound, [{[:sources, name], {:unbound, :source, name}} | errors]}
        end
      end)

    case Enum.sort_by(errors, &elem(&1, 0)) do
      [] -> {:ok, bound}
      errors -> {:error, errors}
    end
  end

  # A slot that is not a map is left for the validator to report; it binds nothing.
  def bind(%Chart{}, _pool), do: {:ok, %{}}

  @doc false
  # A bound source as a design reads it (spec/14 §7.3, D-214): a tensor's rows are tuples,
  # which have no names, so its columns take the slot's declared fields in order; a slot
  # that declares none refuses it. Any other source is as given.
  @spec read(term(), term()) :: {:ok, term()} | {:error, Validator.reason()}
  def read(slot, %{__struct__: Nx.Tensor} = tensor) do
    case slot do
      %{fields: [_ | _] = fields} -> Table.named(tensor, fields)
      _none -> {:error, {:type, :named_rows}}
    end
  end

  def read(_slot, source), do: {:ok, source}

  @doc false
  # A slot's pool entry — under its own name, else its default — with the name it was
  # found under, which is the slot's feed (spec/14 §7.4).
  @spec entry(map(), atom(), map()) :: {:ok, term(), term()} | :error
  # The pool is the host's, keyed as it keyed it: a slot's name or its default finds its
  # entry by spelling (D-195), and the feed is the host's own key.
  def entry(pool, name, slot) do
    case Names.key(pool, name) do
      {:ok, feed} ->
        {:ok, feed, Map.fetch!(pool, feed)}

      :error ->
        with feed when feed != nil <- default(slot),
             {:ok, feed} <- Names.key(pool, feed) do
          {:ok, feed, Map.fetch!(pool, feed)}
        else
          _none -> :error
        end
    end
  end

  defp default(%{default: default}) when is_binary(default), do: default
  defp default(_slot), do: nil

  # Every declared field is a key of some row, in either spelling (D-52); a source with
  # no rows binds without a check, as does a slot whose fields the validator will fault.
  defp missing_fields(%{fields: fields}, source, name) when is_list(fields) do
    case source |> Table.rows() |> Enum.filter(&is_map/1) do
      [] ->
        []

      rows ->
        for field <- fields,
            is_binary(field),
            not Enum.any?(rows, &has_field?(&1, field)),
            do: {[:sources, name], {:missing_field, field}}
    end
  end

  defp missing_fields(_slot, _source, _name), do: []

  defp has_field?(row, field), do: Visualize.Data.Table.key(row, field) != nil
end
