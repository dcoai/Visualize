defmodule Visualize.Chart.Template do
  @moduledoc false
  # The first two steps of application (spec/14 §7.3, D-65): `resolve/2` replaces every
  # variable in a chart by its value, walking the map by the schema so that a text part
  # is known to be one; `bind/2` binds each slot to a source of the pool and checks the
  # slot's declared fields against the bound rows. Both report every fault by path.

  alias Visualize.Chart
  alias Visualize.Chart.{Schema, Validator, Var}
  alias Visualize.Data.Table

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
    {resolved, unresolved} = node(:design, map, [], values)

    case Enum.sort_by(undeclared ++ unresolved, &elem(&1, 0)) do
      [] -> {:ok, struct(Chart, resolved)}
      errors -> {:error, errors}
    end
  end

  # A declared default of `nil` is no default: the variable MUST be supplied (§2.4).
  defp defaults(declared) do
    for {name, %{default: default}} <- declared, default != nil, into: %{}, do: {name, default}
  end

  # -- the walk, by node kind -----------------------------------------------------------

  defp node(kind, map, path, values) do
    Enum.reduce(map, {%{}, []}, fn {k, v}, {acc, errors} ->
      type = if spec = Schema.key(kind, k), do: spec.type, else: :term
      {v, e} = value(type, v, path ++ [k], values)
      {Map.put(acc, k, v), errors ++ e}
    end)
  end

  # Resolution is single level (spec/14 §7.1): a value that is itself a variable is
  # reported at every path the variable stood at, never substituted.
  defp value(_type, %Var{name: name}, path, values) do
    case Map.fetch(values, name) do
      {:ok, %Var{}} -> {%Var{name: name}, [{path, {:var_binding, name}}]}
      {:ok, v} -> {v, []}
      :error -> {%Var{name: name}, [{path, {:unresolved, :var, name}}]}
    end
  end

  defp value({:node, kind}, v, path, values) when is_map(v) and not is_struct(v) do
    node(kind, v, path, values)
  end

  defp value({:list, t}, v, path, values) when is_list(v), do: each(t, v, path, values)

  defp value({:map, t}, v, path, values) when is_map(v) and not is_struct(v) do
    Enum.reduce(v, {%{}, []}, fn {k, e}, {acc, errors} ->
      {e, errs} = value(t, e, path ++ [k], values)
      {Map.put(acc, k, e), errors ++ errs}
    end)
  end

  defp value({:one_of, types}, v, path, values) do
    case Schema.select(types, v) do
      nil -> {v, []}
      type -> value(type, v, path, values)
    end
  end

  defp value(:text, parts, path, values) when is_list(parts) do
    {resolved, errors} = each(:term, parts, path, values)
    {Enum.map(resolved, &part/1), errors}
  end

  defp value(_type, v, _path, _values), do: {v, []}

  defp each(type, list, path, values) do
    list
    |> Enum.with_index()
    |> Enum.reduce({[], []}, fn {e, i}, {acc, errors} ->
      {e, errs} = value(type, e, path ++ [i], values)
      {[e | acc], errors ++ errs}
    end)
    |> then(fn {acc, errors} -> {Enum.reverse(acc), errors} end)
  end

  # A number or an atom a variable put into a text is written as a string (§7.3).
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
        case lookup(pool, name, slot) do
          {:ok, source} ->
            {Map.put(bound, name, source), errors ++ missing_fields(slot, source, name)}

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

  defp lookup(pool, name, slot) do
    case Map.fetch(pool, name) do
      {:ok, source} -> {:ok, source}
      :error -> Map.fetch(pool, default(slot))
    end
  end

  defp default(%{default: default}) when is_atom(default) and default != nil, do: default
  defp default(_slot), do: nil

  # Every declared field is a key of some row, in either spelling (D-52); a source with
  # no rows binds without a check, as does a slot whose fields the validator will fault.
  defp missing_fields(%{fields: fields}, source, name) when is_list(fields) do
    case source |> Table.rows() |> Enum.filter(&is_map/1) do
      [] ->
        []

      rows ->
        for field <- fields,
            is_atom(field),
            not Enum.any?(rows, &has_field?(&1, field)),
            do: {[:sources, name], {:missing_field, field}}
    end
  end

  defp missing_fields(_slot, _source, _name), do: []

  defp has_field?(row, field) do
    Map.has_key?(row, field) or Map.has_key?(row, Atom.to_string(field))
  end
end
