defmodule Visualize.Data.TableTest do
  @moduledoc "`Visualize.Data.Table` (spec/08 §6): every source shape to the same rows."
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Explorer.DataFrame
  alias Visualize.Data.Table

  doctest Table

  @rows [%{t: 1, v: 10.0}, %{t: 2, v: 20.0}, %{t: 3, v: 30.0}]

  # Rows to a column map: the inverse `rows/1` is tested against.
  defp columns(rows) do
    names = rows |> Enum.flat_map(&Map.keys/1) |> Enum.uniq()
    Map.new(names, fn name -> {name, Enum.map(rows, &Map.fetch!(&1, name))} end)
  end

  defp row_gen do
    gen all(t <- integer(), v <- float(), s <- string(:alphanumeric)) do
      %{t: t, v: v, s: s}
    end
  end

  describe "rows/1 over lists" do
    property "a list of rows is itself, zero-copy" do
      check all(rows <- list_of(row_gen())) do
        assert Table.rows(rows) === rows
      end
    end

    property "rows(columns(rows)) == rows for a column map and a keyword list" do
      check all(rows <- list_of(row_gen(), min_length: 1)) do
        assert Table.rows(columns(rows)) == rows
        assert Table.rows(Map.to_list(columns(rows))) == rows
      end
    end

    test "tuple rows pass through" do
      assert Table.rows([{1, 2}, {3, 4}]) === [{1, 2}, {3, 4}]
    end

    test "the empty list, map and keyword list are []" do
      assert Table.rows([]) == []
      assert Table.rows(%{}) == []
    end

    test "string column names stay strings" do
      assert Table.rows(%{"t" => [1, 2], "v" => [3, 4]}) == [
               %{"t" => 1, "v" => 3},
               %{"t" => 2, "v" => 4}
             ]
    end

    test "a keyword list of columns is columns, not rows, as table reads it" do
      assert Table.rows(t: [1, 2], v: [3, 4]) == [%{t: 1, v: 3}, %{t: 2, v: 4}]
    end

    test "a keyword list of unequal columns is rows" do
      assert Table.rows([{:a, [1]}, {:b, [1, 2]}]) == [{:a, [1]}, {:b, [1, 2]}]
    end

    test "a map whose values are not equal-length lists is a caller error" do
      assert_raise ArgumentError, ~r/expected every column/, fn ->
        Table.rows(%{t: [1, 2], v: [3]})
      end

      assert_raise ArgumentError, fn -> Table.rows(%{t: 1}) end
    end
  end

  describe "rows/1 over Explorer and Nx" do
    test "an Explorer frame yields rows keyed by its string column names" do
      df = DataFrame.new(t: [1, 2, 3], v: [10.0, 20.0, 30.0])

      assert Table.rows(df) == [
               %{"t" => 1, "v" => 10.0},
               %{"t" => 2, "v" => 20.0},
               %{"t" => 3, "v" => 30.0}
             ]
    end

    test "an Explorer frame round-trips through rows/1" do
      df = DataFrame.new(columns(@rows))

      assert Table.rows(df) |> Enum.map(&Map.new(&1, fn {k, v} -> {String.to_atom(k), v} end)) ==
               @rows
    end

    test "a rank-2 tensor yields one tuple per row" do
      assert Table.rows(Nx.tensor([[1, 10], [2, 20], [3, 30]])) == [{1, 10}, {2, 20}, {3, 30}]
    end

    test "a rank-1 tensor yields its values" do
      assert Table.rows(Nx.tensor([1.5, 2.5])) == [1.5, 2.5]
    end

    test "a struct with no Table.Reader impl is the protocol's error" do
      assert_raise Protocol.UndefinedError, fn -> Table.rows(~D[2024-01-01]) end
    end

    test "any other rank is a caller error" do
      assert_raise ArgumentError, ~r/rank 1 or 2/, fn -> Table.rows(Nx.tensor([[[1]]])) end
    end

    test "a Table.Reader source read by columns yields the same rows as by rows" do
      # `table` reads a plain map by columns and Explorer by rows; both come out identical.
      columns = columns(@rows)
      assert Table.rows(columns) == Table.rows(DataFrame.new(columns)) |> Enum.map(&atomise/1)
    end
  end

  describe "get/2 and accessor/1" do
    test "an atom name reads an atom key, then the string spelling" do
      assert Table.get(%{v: 1}, :v) == 1
      assert Table.get(%{"v" => 2}, :v) == 2
      assert Table.get(%{:v => 1, "v" => 2}, :v) == 1
      assert Table.get(%{w: 1}, :v) == nil
    end

    test "a string name reads a string key, then the atom spelling" do
      assert Table.get(%{"v" => 2}, "v") == 2
      assert Table.get(%{v: 1}, "v") == 1
      assert Table.get(%{:v => 1, "v" => 2}, "v") == 2
      assert Table.get(%{w: 1}, "v") == nil
    end

    test "a nil value is a value, not a miss" do
      assert Table.get(%{:v => nil, "v" => 2}, :v) == nil
    end

    test "accessor/1 wraps a name and passes a function through" do
      fun = fn d -> d.v * 2 end
      assert Table.accessor(fun) == fun
      assert Table.accessor(:v).(%{"v" => 3}) == 3
      assert Table.accessor("v").(%{v: 4}) == 4
    end

    test "atom accessors reach an Explorer frame's string columns" do
      [first | _] = Table.rows(DataFrame.new(t: [1], v: [10.0]))
      assert Table.accessor(:v).(first) == 10.0
    end

    test "a tuple row has no names" do
      assert_raise BadMapError, fn -> Table.get({1, 2}, :v) end
    end
  end

  describe "column_types/1 (spec/08 §6.3, #369)" do
    test "types a column by its whole, leaves a mixed or empty one out" do
      rows = [
        %{
          t: ~U[2024-01-01 00:00:00Z],
          d: "2024-01-01",
          n: 1,
          f: 1.5,
          s: "a",
          k: :x,
          b: true,
          m: 1,
          e: nil
        },
        %{
          t: ~U[2024-01-02 00:00:00Z],
          d: "2024-01-02",
          n: 2,
          f: nil,
          s: "b",
          k: :y,
          b: false,
          m: "x",
          e: nil
        }
      ]

      assert Table.column_types(rows) == %{
               t: :time,
               d: :time,
               n: :number,
               f: :number,
               s: :text,
               k: :category,
               b: :category
             }
    end

    test "a column that stops being temporal is text, a column map and a tuple table" do
      assert Table.column_types([%{d: "2024-01-01"}, %{d: "later"}]) == %{d: :text}
      assert Table.column_types(%{t: [1, 2], s: ["a", "b"]}) == %{t: :number, s: :text}
      assert Table.column_types([{1, 2}, {3, 4}]) == %{}
      assert Table.column_types([]) == %{}
    end
  end

  describe "time_columns/1 and temporal?/1" do
    test "each temporal type is detected, over the whole column" do
      source = %{
        dt: [~U[2024-01-01 00:00:00Z], ~U[2024-01-02 00:00:00Z]],
        d: [~D[2024-01-01], ~D[2024-01-02]],
        ndt: [~N[2024-01-01 00:00:00], ~N[2024-01-02 00:00:00]],
        iso: ["2024-01-01T00:00:00Z", "2024-01-02"],
        v: [1, 2],
        mixed: [~D[2024-01-01], 2],
        strings: ["2024-01-01", "tomorrow"]
      }

      assert Table.time_columns(source) == [:d, :dt, :iso, :ndt]
    end

    test "nil is a gap, not a value; an all-nil column is not temporal" do
      assert Table.time_columns(%{t: [nil, ~D[2024-01-01]], u: [nil, nil]}) == [:t]
    end

    test "a first-row check would pass what the whole column fails" do
      assert Table.time_columns([%{t: ~D[2024-01-01]}, %{t: "later"}]) == []
    end

    test "names are the union of every row's keys, sorted; a row missing a key is a gap" do
      rows = [%{b: ~D[2024-01-01]}, %{a: ~D[2024-01-02], b: ~D[2024-01-02]}]
      assert Table.time_columns(rows) == [:a, :b]
    end

    test "tuple rows have no columns" do
      assert Table.time_columns([{~D[2024-01-01], 1}]) == []
    end

    test "an Explorer frame's date column is detected by its string name" do
      df = DataFrame.new(t: [~D[2024-01-01], ~D[2024-01-02]], v: [1, 2])
      assert Table.time_columns(df) == ["t"]
    end

    test "temporal?/1 accepts the three structs and ISO 8601 strings only" do
      assert Table.temporal?(~U[2024-01-01 00:00:00Z])
      assert Table.temporal?(~D[2024-01-01])
      assert Table.temporal?(~N[2024-01-01 00:00:00])
      assert Table.temporal?("2024-01-01T00:00:00+01:00")
      assert Table.temporal?("2024-01-01T00:00:00")
      assert Table.temporal?("2024-01-01")
      refute Table.temporal?("2024")
      refute Table.temporal?("01/02/2024")
      refute Table.temporal?(1_704_067_200)
      refute Table.temporal?(nil)
    end
  end

  defp atomise(row), do: Map.new(row, fn {k, v} -> {String.to_atom(k), v} end)
end
