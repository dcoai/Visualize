defmodule Visualize.SignalsTest do
  @moduledoc "Generated sources over a sliding window and a tick (spec/08 §8)."
  use ExUnit.Case, async: true

  alias Visualize.Signals

  doctest Signals

  test "a sine starts at the midpoint, swings between min and max, and the columns are shifted" do
    sine = Signals.new(:sine, [:t, :a, :b], window: 5, period: 4, min: 10, max: 20)
    [r0, r1, r2, r3, r4] = Signals.rows(sine, 4)
    assert Enum.map([r0, r1, r2, r3, r4], & &1.t) == [0, 1, 2, 3, 4]
    assert_in_delta r0.a, 15.0, 1.0e-9
    assert_in_delta r1.a, 20.0, 1.0e-9
    assert_in_delta r3.a, 10.0, 1.0e-9
    assert_in_delta r4.a, 15.0, 1.0e-9
    # The second column is half a cycle on.
    assert_in_delta r1.b, 10.0, 1.0e-9
  end

  test "a square alternates each half period; a random replays under its seed; a discrete counts and wraps" do
    square = Signals.new(:square, [:t, :on], window: 4, period: 4, min: 0, max: 1)
    assert Enum.map(Signals.rows(square, 3), & &1.on) == [1, 1, 0, 0]

    random = Signals.new(:random, [:t, :r], window: 3, seed: 7)
    rows = Signals.rows(random, 9)
    assert rows == Signals.rows(random, 9)
    assert Enum.all?(rows, &(&1.r >= 0 and &1.r < 100))
    assert rows != Signals.rows(%{random | seed: 8}, 9)
    # A tick's value does not depend on the window it is seen through.
    assert List.last(rows) == List.last(Signals.rows(%{random | window: 1}, 9))

    counter = Signals.new(:discrete, [:t, :n, :m], window: 4, min: 0, max: 2)
    assert Enum.map(Signals.rows(counter, 3), &{&1.n, &1.m}) == [{0, 1}, {1, 2}, {2, 0}, {0, 1}]
  end

  test "the window slides by one per tick and fills over its first ticks" do
    sine = Signals.new(:sine, [:t, :v], window: 24)
    assert Enum.map(Signals.rows(sine, 25), & &1.t) == Enum.to_list(2..25)
    assert Enum.map(Signals.rows(sine, 26), & &1.t) == Enum.to_list(3..26)
    assert Enum.map(Signals.rows(sine, 3), & &1.t) == [0, 1, 2, 3]
  end

  test "a pool of signals binds a design and draws" do
    signals = %{feed: Signals.new(:sine, [:hour, :value], window: 24)}

    design = %{
      version: 1,
      sources: %{feed: %{fields: [:hour, :value]}},
      frame: %{kind: :cartesian, scales: %{x: %{kind: :linear}, y: %{kind: :linear}}},
      marks: [%{type: :line, data: :feed, channels: %{x: :hour, y: :value}}]
    }

    {:ok, applied} = Visualize.Chart.apply(design, sources: Signals.pool(signals, 30))
    assert Visualize.Chart.render(applied) =~ ~s(class="mark mark-line")
  end
end
