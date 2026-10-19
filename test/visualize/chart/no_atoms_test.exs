defmodule Visualize.Chart.NoAtomsTest do
  @moduledoc """
  No atom from a key or a closed vocabulary a document names (spec/14 §9.4, #779, D-195):
  a key the schema does not know stays a string and nothing under it is decoded, and a
  string where a library vocabulary goes is looked up, never made an atom, so a refused
  document leaves the node's atom table as it found it whatever its size.
  """
  # The atom table is the node's: nothing else may run while it is counted.
  use ExUnit.Case, async: false

  alias Visualize.{Board, Chart, Vocabulary}
  alias Visualize.Board.Snapshot
  alias Visualize.Chart.Builder.Editor
  alias Visualize.Chart.Fragment
  alias Visualize.VirtualSource.Codec, as: VirtualSourceCodec

  @base %{"version" => 3, "frames" => %{"main" => %{"kind" => "cartesian"}}}

  # A string no atom has been made of: unique to this run, and never seen by the table.
  defp fresh, do: "zz#{System.unique_integer([:positive])}q#{:rand.uniform(1_000_000_000)}"

  # The atoms `fun` makes, after one warm-up call of `fun` loads every module it reaches.
  defp atoms_made(fun) do
    fun.()
    before = :erlang.system_info(:atom_count)
    result = fun.()
    {:erlang.system_info(:atom_count) - before, result}
  end

  defp unknown_keys(n, value), do: Map.new(1..n//1, fn _ -> {fresh(), value} end)

  defp from_json(term), do: term |> Jason.encode!() |> Chart.from_json()

  describe "a refused document makes no atom from its keys" do
    test "N unknown top-level keys, for N from 1 to 2,000" do
      for n <- [1, 10, 100, 2_000] do
        {made, result} =
          atoms_made(fn -> from_json(Map.merge(@base, unknown_keys(n, %{fresh() => 1}))) end)

        assert made == 0, "#{n} unknown keys made #{made} atoms"
        assert {:error, errors} = result
        assert length(errors) == n
        assert Enum.all?(errors, &match?({[key], :unknown_key} when is_binary(key), &1))
      end
    end

    test "unknown keys in a node deep in the design, reported at their own spelling" do
      {made, result} =
        atoms_made(fn ->
          from_json(put_in(@base, ["frames", "main", "wdth"], %{fresh() => [%{fresh() => 1}]}))
        end)

      assert made == 0
      assert {:error, [{[:frames, :main, "wdth"], :unknown_key}]} = result

      assert Chart.Validator.format({[:frames, :main, "wdth"], :unknown_key}) ==
               "frames.main.wdth: is not a key of this node"
    end

    test "a key of another node kind holds nothing that is decoded" do
      # `size` is a schema key, but not the design's: its value is left as parsed.
      {made, result} =
        atoms_made(fn -> from_json(Map.put(@base, "size", unknown_keys(500, 1))) end)

      assert made == 0
      assert {:error, [{[:size], :unknown_key}]} = result
    end

    test "the deep dive's 5.4 MB design: three maps of 99,999 keys under an unknown key" do
      inner = fn -> unknown_keys(99_999, 1) end

      json =
        Jason.encode!(
          Map.put(@base, fresh(), %{"a" => inner.(), "b" => inner.(), "c" => inner.()})
        )

      assert byte_size(json) > 5_000_000

      Chart.from_json(Jason.encode!(Map.put(@base, fresh(), 1)))
      before = :erlang.system_info(:atom_count)
      assert {:error, [{[key], :unknown_key}]} = Chart.from_json(json)
      assert is_binary(key)
      assert :erlang.system_info(:atom_count) - before == 0
    end

    test "a fragment, a board, a snapshot and a virtual source keep an unknown key a string" do
      fragment = fn ->
        Jason.encode!(%{"$version" => 3, "frames" => %{"main" => unknown_keys(100, 1)}})
      end

      board = fn ->
        Jason.encode!(%{"$version" => 3, "meta" => unknown_keys(100, %{fresh() => 1})})
      end

      snapshot = fn ->
        Jason.encode!(%{"$version" => 3, "cells" => %{}, fresh() => unknown_keys(100, 1)})
      end

      assert {0, {:ok, _fragment}} = atoms_made(fn -> Fragment.from_json(fragment.()) end)
      assert {0, {:error, _}} = atoms_made(fn -> Board.from_json(board.()) end)
      assert {0, {:error, _}} = atoms_made(fn -> Snapshot.from_json(snapshot.()) end)

      assert {0, source} = atoms_made(fn -> VirtualSourceCodec.decode(unknown_keys(100, 1)) end)
      assert source |> Map.keys() |> Enum.all?(&is_binary/1)
    end
  end

  describe "each closed vocabulary refuses a string it lacks" do
    # A document with one string where a vocabulary member goes: refused, and no atom made.
    defp refused(at, value) do
      {made, result} = atoms_made(fn -> from_json(put_in(@base, at, value.())) end)
      assert made == 0, "#{inspect(at)} made #{made} atoms"
      assert {:error, [_ | _]} = result
      result
    end

    defp label(anchor),
      do: %{
        "version" => 3,
        "frames" => @base["frames"],
        "labels" => [%{"text" => "t", "anchor" => anchor}]
      }

    test "an enumeration's member" do
      assert {:error, [{[:frames, :main, :kind], {:enum, _}}]} =
               refused(["frames", "main", "kind"], &fresh/0)
    end

    test "a slot, where a size may name one" do
      assert {:error, [{[:styles, :s, :stroke, :width], {:type, :size}}]} =
               refused(["styles"], fn -> %{"s" => %{"stroke" => %{"width" => fresh()}}} end)
    end

    test "a series slot past the bound" do
      assert {:error, [{[:styles, :s, :stroke, :width], {:type, :size}}]} =
               refused(["styles"], fn ->
                 %{
                   "s" => %{
                     "stroke" => %{"width" => "series_#{100_001 + :rand.uniform(10 ** 9)}"}
                   }
                 }
               end)
    end

    test "a text anchor and a frame point" do
      for anchor <- [fn -> fresh() end, fn -> %{"$frame" => fresh()} end] do
        {made, result} = atoms_made(fn -> from_json(label(anchor.())) end)
        assert made == 0
        assert {:error, [{[:labels, 0, :anchor], {:type, :anchor}}]} = result
      end
    end

    test "a unit, a ramp and an id's kind" do
      cases = [
        {["styles"], fn -> %{"s" => %{"stroke" => %{"width" => %{"$unit" => [1, fresh()]}}}} end},
        {["styles"], fn -> %{"s" => %{"fill" => %{"color" => %{"$ramp" => [fresh(), 0.5]}}}} end},
        {["frames", "main", "scales"], fn -> %{"x" => %{"$id" => [fresh(), 1]}} end}
      ]

      for {at, value} <- cases, do: refused(at, value)
    end

    test "a fact's attribute and a channel's scale end, read as terms" do
      Chart.Codec.decode_term(%{"$fact" => ["s", "f", "unit"]})

      for term <- [fn -> %{"$fact" => ["s", "f", fresh()]} end, fn -> %{"$scale" => fresh()} end] do
        {made, _read} = atoms_made(fn -> Chart.Codec.decode_term(term.()) end)
        assert made == 0
      end
    end

    test "the lookup reads a member and nothing else" do
      table = Vocabulary.table([:top, :bottom])
      assert Vocabulary.fetch(table, "top") == {:ok, :top}
      assert Vocabulary.fetch(table, fresh()) == :error
      assert Vocabulary.fetch([:top], "top") == {:ok, :top}
      assert Vocabulary.fetch([:top], fresh()) == :error
      assert Vocabulary.read(table, "middle") == "middle"
      assert Vocabulary.fetch(table, :top) == :error
    end
  end

  describe "the builder's literal reader" do
    test "a literal naming an atom the node lacks is a fault, never a new atom" do
      {made, result} = atoms_made(fn -> Editor.parse(:term, ":#{fresh()}") end)
      assert made == 0
      assert result == :error

      {made, result} = atoms_made(fn -> Editor.parse(:term, "[#{fresh()}: 1]") end)
      assert made == 0
      assert result == :error
    end

    test "a literal of atoms that exist still reads" do
      assert Editor.parse(:term, ":top") == {:ok, :top}
      assert Editor.parse(:term, "[1, :auto]") == {:ok, [1, :auto]}
    end
  end
end
