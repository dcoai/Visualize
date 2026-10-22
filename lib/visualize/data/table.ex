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
  - A keyword list whose values are equal-length columns is a list of columns; the rows are
    maps keyed by the keys. (`table` reads a list the same way, columns before rows.) A
    column is a list or a rank-1 `Nx.Tensor` (D-214).
  - A map whose values are equal-length columns is a map of columns, rows keyed likewise.
    Any other plain map raises `ArgumentError`.
  - An `Nx.Tensor` of rank 2 yields one tuple per row, in column order — the shape the
    default `Visualize.Shape.Line` accessors read; rank 1 yields its values. Any other rank
    raises `ArgumentError`. A tuple has no names: `named/2` gives a tensor's columns some.
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
  A tensor's columns, or tuple rows' elements, under `names`, in order (spec/08 §6.4,
  D-214, D-232).

  Column `i` of a rank-2 tensor is `Enum.at(names, i)`, and a rank-1 tensor is one column:
  the column map `rows/1` reads. A tensor whose width is not `length(names)` is
  `{:error, {:width, length(names), width}}`, one of another rank `{:error, {:rank, rank}}`.

  Tuple rows — a list `rows/1` reads as rows whose first row is a tuple — are named row by
  row: element `i` of each tuple under `Enum.at(names, i)`, and a row that is not a tuple
  kept as it is. A tuple of another size is `{:error, {:width, length(names), size}}`, the
  first such row's. A keyword list of columns is columns, and passes through.

  Nothing raises. Any other source is `{:ok, source}`, the same term, so every source can
  pass through.

      iex> Visualize.Data.Table.named([{1, 4.0}, {2, 5.0}], ["x", "y"])
      {:ok, [%{"x" => 1, "y" => 4.0}, %{"x" => 2, "y" => 5.0}]}
      iex> Visualize.Data.Table.named([{1, 4.0, 7}], ["x", "y"])
      {:error, {:width, 2, 3}}
      iex> Visualize.Data.Table.named([%{x: 1}], ["x"])
      {:ok, [%{x: 1}]}
  """
  @spec named(source(), [name()]) ::
          {:ok, source()}
          | {:error, {:width, non_neg_integer(), non_neg_integer()} | {:rank, non_neg_integer()}}
  def named(%{__struct__: Nx.Tensor} = tensor, names) when is_list(names) do
    case {Nx.rank(tensor), length(names)} do
      {1, 1} -> {:ok, %{hd(names) => Nx.to_list(tensor)}}
      {1, n} -> {:error, {:width, n, 1}}
      {2, n} -> named_columns(tensor, names, Nx.axis_size(tensor, 1), n)
      {rank, _n} -> {:error, {:rank, rank}}
    end
  end

  def named([first | _] = rows, names) when is_tuple(first) and is_list(names) do
    if columns?(rows, first), do: {:ok, rows}, else: named_rows(rows, names, length(names))
  end

  def named(source, names) when is_list(names), do: {:ok, source}

  @doc false
  # Whether a source's rows have no names a design can read (spec/14 §7.3, D-214, D-232):
  # a tensor, whose rows are tuples, or a list of tuple rows — not a keyword list of
  # columns, which is named by its keys.
  @spec unnamed?(term()) :: boolean()
  def unnamed?(%{__struct__: Nx.Tensor}), do: true
  def unnamed?([first | _] = rows) when is_tuple(first), do: not columns?(rows, first)
  def unnamed?(_source), do: false

  # Each tuple row a map of its elements under the names; any other row as it is.
  defp named_rows(rows, names, n) do
    rows
    |> Enum.reduce_while([], fn
      row, acc when is_tuple(row) and tuple_size(row) == n ->
        {:cont, [names |> Enum.zip(Tuple.to_list(row)) |> Map.new() | acc]}

      row, _acc when is_tuple(row) ->
        {:halt, {:error, {:width, n, tuple_size(row)}}}

      row, acc ->
        {:cont, [row | acc]}
    end)
    |> case do
      {:error, _width} = error -> error
      named -> {:ok, Enum.reverse(named)}
    end
  end

  defp named_columns(tensor, names, n, n),
    do: {:ok, names |> Enum.zip(tensor |> Nx.transpose() |> Nx.to_list()) |> Map.new()}

  defp named_columns(_tensor, _names, width, n), do: {:error, {:width, n, width}}

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

      # The atom key this name spelled last time, read at once (#813): every channel of
      # every item of a chart reads a field by its name.
      _ ->
        case Process.get({__MODULE__, name}) do
          key when is_map_key(row, key) ->
            :erlang.map_get(key, row)

          _other ->
            case scan(row, name) do
              nil -> nil
              key -> Map.fetch!(row, key)
            end
        end
    end
  end

  @doc """
  The key of `row` that spells `name`: `name` itself when it is a key, else the key of the
  other spelling, `nil` when neither is.

  A design names a field by its string (spec/14 §1.4, D-195) and a host's rows are often
  keyed by atoms: the atom key a string finds is remembered for the calling process, so a
  frame that reads the same field from every row scans one row's keys, not all of them. No
  atom is ever created or looked up by name — the remembered key is one a row held.

      iex> Visualize.Data.Table.key(%{cpu: 1}, "cpu")
      :cpu
      iex> Visualize.Data.Table.key(%{"cpu" => 1}, :cpu)
      "cpu"
      iex> Visualize.Data.Table.key(%{cpu: 1}, "mem")
      nil
  """
  @spec key(map(), name()) :: name() | nil
  def key(row, name) when is_map_key(row, name), do: name

  def key(row, name) when is_atom(name),
    do: if(is_map_key(row, Atom.to_string(name)), do: Atom.to_string(name))

  def key(row, name) when is_binary(name) do
    case Process.get({__MODULE__, name}) do
      key when is_map_key(row, key) -> key
      _other -> scan(row, name)
    end
  end

  defp scan(row, name) do
    found = Enum.find(Map.keys(row), &(is_atom(&1) and Atom.to_string(&1) == name))
    if found, do: Process.put({__MODULE__, name}, found)
    found
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
  booleans `:category`, all typed colors (tuples `Visualize.Color.value?/1` holds) `:color`
  (D-233); a mixed or empty column is left out. A suggestion for a tool, never something
  the layer reads at render.

      iex> rows = [%{t: ~U[2024-01-01 00:00:00Z], v: 1, k: :a, s: "x", m: 1, c: {:color, :good}},
      ...>         %{t: ~U[2024-01-02 00:00:00Z], v: 2.5, k: :b, s: "y", m: "two",
      ...>           c: {:alpha, {:color, :bad}, 0.5}}]
      iex> Visualize.Data.Table.column_types(rows)
      %{t: :time, v: :number, k: :category, s: :text, c: :color}
      iex> Visualize.Data.Table.column_types([])
      %{}
  """
  @spec column_types(source()) :: %{name() => :time | :number | :category | :text | :color}
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
      Enum.all?(values, &(is_tuple(&1) and Visualize.Color.value?(&1))) -> :color
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

  # A list is columns when every element names an equal-length column.
  defp columns?(list, {name, values}) when is_atom(name) or is_binary(name) do
    n = column_length(values)

    n != nil and
      Enum.all?(list, fn
        {k, v} when is_atom(k) or is_binary(k) -> column_length(v) == n
        _other -> false
      end)
  end

  defp columns?(_list, _first), do: false

  # A column's length: a list's, or a rank-1 tensor's (D-214); `nil` for anything else.
  defp column_length(values) when is_list(values), do: length(values)

  defp column_length(%{__struct__: Nx.Tensor} = tensor) do
    if Nx.rank(tensor) == 1, do: Nx.axis_size(tensor, 0)
  end

  defp column_length(_values), do: nil

  # A rank-1 tensor column as its list of values; anything else as given.
  defp column(%{__struct__: Nx.Tensor} = tensor) do
    if Nx.rank(tensor) == 1, do: Nx.to_list(tensor), else: tensor
  end

  defp column(values), do: values

  # Column pairs to rows: one map per index, keyed by every column name. Callers pass a
  # non-empty list.
  defp column_rows(pairs) do
    columns = Enum.map(pairs, fn {name, values} -> {name, column(values)} end)
    [{_, first} | _] = columns
    # A first column that is no list is reported by the check below, by its name.
    n = if is_list(first), do: length(first), else: 0

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
