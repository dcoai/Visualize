defmodule Visualize.Board.BindingTest do
  @moduledoc """
  The connector's binding (spec/15 §4.2–4.4, D-141): a separate value from the board,
  checked for every unbound slot, every contract a bound schema cannot meet and every
  binding to nothing, and turned into one pool per cell.
  """
  use ExUnit.Case, async: true

  alias Visualize.Board.Binding
  alias Visualize.Data.Schema

  doctest Visualize.Board.Binding

  @required %{
    {:latency, :primary} => %{
      fields: [:t, :v, :state],
      types: %{t: :time, v: :number, state: :category},
      requires: %{v: [:unit, :label], state: [:order]}
    },
    {:eu, :primary} => %{fields: [:t, :v], types: %{v: :number}, requires: %{v: [:unit]}},
    {:gauge, :reading} => %{fields: [:v], types: %{}, requires: %{}}
  }

  defp full do
    Schema.new!(%{
      t: %{type: :time},
      v: %{type: :number, unit: "ms", label: "Request time"},
      state: %{type: :category, order: ["ok", "fail"]}
    })
  end

  test "new/1 and put/4 take pairs of atoms, and nothing else" do
    assert Binding.new([{{:a, :s}, :feed}]) == Binding.new() |> Binding.put(:a, :s, :feed)
    assert Binding.fetch(Binding.new(), :a, :s) == :error

    assert_raise ArgumentError, ~r/two atoms/, fn -> Binding.new(%{{"a", :s} => :feed}) end
    assert_raise ArgumentError, ~r/pair/, fn -> Binding.new([:a]) end
  end

  test "a complete binding whose schemas meet every contract is :ok" do
    binding =
      Binding.new(%{
        {:latency, :primary} => :us,
        {:eu, :primary} => :us,
        {:gauge, :reading} => :cpu
      })

    assert Binding.check(binding, @required, %{us: full()}) == :ok
  end

  test "every unbound slot, every unmet contract and every binding to nothing" do
    thin = Schema.new!(%{v: %{type: :category, label: "Latency"}, state: %{type: :category}})

    binding =
      Binding.new(%{
        {:latency, :primary} => :thin,
        {:eu, :primary} => :nowhere,
        {:removed, :primary} => :thin
      })

    assert Binding.check(binding, @required, %{thin: thin}) ==
             {:error,
              [
                {[:cells, :eu, :sources, :primary], {:undescribed, :nowhere}},
                {[:cells, :gauge, :sources, :reading], {:unbound, :binding, :reading}},
                {[:cells, :latency, :sources, :primary, :requires, :state],
                 {:missing_attribute, :primary, :state, :order}},
                {[:cells, :latency, :sources, :primary, :requires, :v],
                 {:missing_attribute, :primary, :v, :unit}},
                {[:cells, :latency, :sources, :primary, :types, :v],
                 {:schema_type, :v, :number, :category}},
                {[:cells, :removed, :sources, :primary], :not_required}
              ]}
  end

  test "a slot with an empty contract is not looked up" do
    binding = Binding.new(%{{:gauge, :reading} => :cpu})
    required = Map.take(@required, [{:gauge, :reading}])

    assert Binding.check(binding, required, fn _feed -> flunk("described") end) == :ok
  end

  test "a describe function is asked once per feed, and its errors are reported" do
    binding =
      Binding.new(%{
        {:latency, :primary} => :us,
        {:eu, :primary} => :us,
        {:gauge, :reading} => :cpu
      })

    test = self()

    describe = fn feed ->
      send(test, {:described, feed})
      {:ok, full()}
    end

    assert Binding.check(binding, @required, describe) == :ok
    assert_received {:described, :us}
    refute_received {:described, :us}

    assert Binding.check(binding, @required, fn feed -> {:error, {:down, feed}} end) ==
             {:error,
              [
                {[:cells, :eu, :sources, :primary], {:describe, :us, {:down, :us}}},
                {[:cells, :latency, :sources, :primary], {:describe, :us, {:down, :us}}}
              ]}
  end

  test "the faults read in the words apply/2 uses" do
    assert Visualize.Board.format_error(
             {[:cells, :gauge, :sources, :reading], {:unbound, :binding, :reading}}
           ) ==
             "cells.gauge.sources.reading: slot :reading is bound to no feed: the binding names none for it"

    assert Visualize.Board.format_error({[:cells, :x, :sources, :s], :not_required}) ==
             "cells.x.sources.s: binds a slot that no cell's component declares"
  end

  test "pools: one per cell, by the slot's own name, a feed with no source left out" do
    binding = Binding.new(%{{:a, :primary} => :cpu, {:a, :extra} => :mem, {:b, :primary} => :cpu})

    assert Binding.pools(binding, %{cpu: [%{v: 1}]}) == %{
             a: %{primary: [%{v: 1}]},
             b: %{primary: [%{v: 1}]}
           }
  end
end
