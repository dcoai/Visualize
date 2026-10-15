defmodule Visualize.Data.Table do
  @moduledoc """
  Tabular data as the row list the generators consume.

  Every generator takes a list of rows. `rows/1` turns the other shapes data arrives in —
  a column-oriented map, a keyword list of columns, an `Nx.Tensor`, an Explorer DataFrame
  or anything else implementing the `Table.Reader` protocol — into that list, and passes a
  list of rows through untouched (spec/08 §6).

      Visualize.Data.Table.rows(%{t: [1, 2, 3], v: [10, 20, 30]})
      # => [%{t: 1, v: 10}, %{t: 2, v: 20}, %{t: 3, v: 30}]

  Sources that name their columns with strings (Explorer does) yield rows keyed by
  strings; `accessor/1` reads a column by either spelling, so `:v` reaches `"v"` and the
  other way round. `time_columns/1` names the columns whose every value is temporal, for a
  time scale to be inferred from.

  The `table` package is optional, like Nx: without it lists, column maps and tensors still
  work, and a struct source raises `UndefinedFunctionError` at `Table.to_rows/1` (D-52).
  """

  # `table` and Nx are optional: the calls stay direct (a missing package raises
  # UndefinedFunctionError at the call) and the compiler is told not to warn about them in a
  # consumer that never fetched either (D-50). The struct branch goes through `Table.to_rows/1`
  # rather than `Table.Reader.init/1`: the protocol is consolidated over whichever impls the
  # host has, and the type checker flags a direct protocol call on an arbitrary struct
  # wherever that set is only List and Map.
  @compile {:no_warn_undefined, [Table, Nx]}

  @typedoc "A column name, as the source spells it."
  @type name :: atom() | String.t()

  @typedoc "A row: a map keyed by column name, or a tuple in column order."
  @type row :: map() | tuple()

  @typedoc """
  Anything `rows/1` accepts: a list of rows, a keyword list or map of equal-length columns,
  an `Nx.Tensor` of rank 1 or 2, a `Visualize.Data.Delivery`, or a struct implementing
  `Table.Reader`.
  """
  @type source :: [row()] | %{name() => [term()]} | [{name(), [term()]}] | struct()

  @doc """
  The rows of a tabular source, as a list.

  - A list of rows is returned as-is: no copy, no traversal.
  - A keyword list whose values are equal-length lists is a list of columns; the rows are
    maps keyed by the keys. (`table` reads a list the same way, columns before rows.)
  - A map whose values are equal-length lists is a map of columns, rows keyed likewise.
    Any other plain map raises `ArgumentError`.
  - An `Nx.Tensor` of rank 2 yields one tuple per row, in column order — the shape the
    default `Visualize.Shape.Line` accessors read; rank 1 yields its values. Any other rank
    raises `ArgumentError`.
  - A `Visualize.Data.Delivery` is the rows of the source it carries (spec/08 §10.4).
  - Any other struct is read through `Table.to_rows/1`: rows keyed by the reader's column
    names as it spells them. A struct with no `Table.Reader` impl raises
    `Protocol.UndefinedError`; a reader answering `:none` raises `ArgumentError`.

  The empty list, an empty map and an empty keyword list all yield `[]`.
  """
  @spec rows(source()) :: [row()]
  def rows([]), do: []
  # A map pattern, not `%Nx.Tensor{}`: a struct pattern needs the struct defined at compile
  # time, and a consumer without Nx has none.
  def rows(%{__struct__: Nx.Tensor} = tensor), do: tensor_rows(tensor, Nx.rank(tensor))
  # A feed's answer is the rows of the source it carries (spec/08 §10.4).
  def rows(%Visualize.Data.Delivery{rows: rows}), do: rows(rows)
  def rows(%_{} = struct), do: struct |> Table.to_rows() |> Enum.to_list()
  def rows(map) when map_size(map) == 0, do: []
  def rows(map) when is_map(map), do: column_rows(Map.to_list(map))

  def rows([first | _] = list) do
    if columns?(list, first), do: column_rows(list), else: list
  end

  @doc """
  The value of column `name` in `row`, by either spelling of the name.

  `Map.get(row, name)` when the key is present; otherwise an atom name is tried as its
  string and a string name as the atom key spelled the same. `nil` when neither is a key.
  No atom is ever created. A tuple row has no names and raises `BadMapError`.
  """
  @spec get(map(), name()) :: term()
  def get(row, name) when is_atom(name) do
    case row do
      %{^name => value} -> value
      _ -> Map.get(row, Atom.to_string(name))
    end
  end

  def get(row, name) when is_binary(name) do
    case row do
      %{^name => value} ->
        value

      _ ->
        Enum.find_value(Map.keys(row), fn key ->
          if is_atom(key) and Atom.to_string(key) == name, do: Map.fetch!(row, key)
        end)
    end
  end

  @doc """
  The accessor `fn row -> get(row, name) end`, for a shape's `x`/`y` setters.

  A function is returned unchanged, so a generator can normalize any accessor form
  through this one call.
  """
  @spec accessor(name() | (row() -> term())) :: (row() -> term())
  def accessor(fun) when is_function(fun, 1), do: fun
  def accessor(name) when is_atom(name) or is_binary(name), do: &get(&1, name)

  @doc """
  The names of the columns whose values are all temporal.

  The candidate names are every key of every map row, sorted by term order (a map's own key
  order is unspecified); a row without the key contributes `nil`. A column is temporal
  when it has at least one value that is not `nil` and every value is `nil` or satisfies
  `temporal?/1`. Detection reads the **whole column**, not a first row: every row of every
  column is visited and every string is parsed, so the cost is the size of the table. A
  source whose rows are tuples has no names and yields `[]`.
  """
  @spec time_columns(source()) :: [name()]
  def time_columns(source) do
    rows = rows(source)

    rows
    |> column_names()
    |> Enum.filter(fn name -> temporal_column?(Enum.map(rows, &Map.get(&1, name))) end)
  end

  @doc """
  Every named column's type, read whole (spec/08 §6.3, spec/14 §2.3, #369): all non-`nil`
  values temporal is `:time`, all numbers `:number`, all strings `:text`, all atoms or
  booleans `:category`; a mixed or empty column is left out. A suggestion for a tool, never
  something the layer reads at render.

      iex> rows = [%{t: ~U[2024-01-01 00:00:00Z], v: 1, k: :a, s: "x", m: 1},
      ...>         %{t: ~U[2024-01-02 00:00:00Z], v: 2.5, k: :b, s: "y", m: "two"}]
      iex> Visualize.Data.Table.column_types(rows)
      %{t: :time, v: :number, k: :category, s: :text}
      iex> Visualize.Data.Table.column_types([])
      %{}
  """
  @spec column_types(source()) :: %{name() => :time | :number | :category | :text}
  def column_types(source) do
    rows = rows(source)

    for name <- column_names(rows),
        type = column_type(Enum.reject(Enum.map(rows, &Map.get(&1, name)), &is_nil/1)),
        type != nil,
        into: %{},
        do: {name, type}
  end

  defp column_type([]), do: nil

  defp column_type(values) do
    cond do
      Enum.all?(values, &temporal?/1) -> :time
      Enum.all?(values, &is_number/1) -> :number
      Enum.all?(values, &is_binary/1) -> :text
      Enum.all?(values, &(is_atom(&1) and not is_nil(&1))) -> :category
      true -> nil
    end
  end

  @doc """
  Whether a value is a point in time: a `DateTime`, `Date` or `NaiveDateTime`, or a string
  in ISO 8601 form that one of those parses (`DateTime.from_iso8601/1` first, then
  `NaiveDateTime.from_iso8601/1`, then `Date.from_iso8601/1`).
  """
  @spec temporal?(term()) :: boolean()
  def temporal?(%DateTime{}), do: true
  def temporal?(%Date{}), do: true
  def temporal?(%NaiveDateTime{}), do: true

  def temporal?(string) when is_binary(string) do
    match?({:ok, _, _}, DateTime.from_iso8601(string)) or
      match?({:ok, _}, NaiveDateTime.from_iso8601(string)) or
      match?({:ok, _}, Date.from_iso8601(string))
  end

  def temporal?(_), do: false

  # A list is columns when every element names an equal-length list.
  defp columns?(list, {name, values})
       when (is_atom(name) or is_binary(name)) and is_list(values) do
    n = length(values)

    Enum.all?(
      list,
      &match?({k, v} when (is_atom(k) or is_binary(k)) and is_list(v) and length(v) == n, &1)
    )
  end

  defp columns?(_list, _first), do: false

  # Column pairs to rows: one map per index, keyed by every column name. Callers pass a
  # non-empty list.
  defp column_rows([{_, first} | _] = columns) do
    n = length(first)

    Enum.each(columns, fn {name, values} ->
      unless is_list(values) and length(values) == n do
        raise ArgumentError,
              "expected every column to be a list of #{n} values, got #{inspect(name)}: " <>
                inspect(values)
      end
    end)

    names = Enum.map(columns, &elem(&1, 0))

    columns
    |> Enum.map(&elem(&1, 1))
    |> Enum.zip_with(fn values -> names |> Enum.zip(values) |> Map.new() end)
  end

  defp tensor_rows(tensor, 1), do: Nx.to_list(tensor)
  defp tensor_rows(tensor, 2), do: tensor |> Nx.to_list() |> Enum.map(&List.to_tuple/1)

  defp tensor_rows(tensor, rank) do
    raise ArgumentError,
          "expected a tensor of rank 1 or 2, got rank #{rank}: #{inspect(tensor)}"
  end

  # Every map key of every row, sorted; tuple rows have none.
  defp column_names(rows) do
    rows
    |> Enum.flat_map(fn
      row when is_map(row) -> Map.keys(row)
      _ -> []
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp temporal_column?(values) do
    Enum.any?(values, &(not is_nil(&1))) and Enum.all?(values, &(is_nil(&1) or temporal?(&1)))
  end
end
