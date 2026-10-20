defmodule Examples.StreamgraphTest do
  @moduledoc """
  The streamgraph's layers keep their places while it animates (#492): `order: :inside_out`
  re-sorted the series from each tick's rows, so a layer jumped to another place whenever
  the order moved. The order is now fixed once, inside-out by each series' total over the run.
  """
  use ExUnit.Case, async: true

  alias Examples.Charts.Streamgraph
  alias Visualize.Chart.Transform
  alias Visualize.Shape.Stack

  @keys [:rock, :pop, :jazz, :classical, :electronic, :hiphop]

  # The layer keys bottom to top, as the page's frame at `tick` stacks them: the design
  # and rows the page asks for (`Examples.Frames.frame/4` calls `design/1` the same way),
  # run through the mark's own data pipeline.
  defp layers(tick) do
    {design, %{months: rows}} = Streamgraph.design(animation_tick: tick)
    [%{data: %{transforms: transforms}}] = design.marks

    transforms
    |> Transform.apply(rows, size: [600, 400])
    |> Enum.map(&{&1.series, &1.key})
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(&elem(&1, 1))
  end

  test "the layer order is the same on every one of 200 ticks of a run" do
    orders = Enum.map(0..199, &layers/1)

    assert Enum.uniq(orders) == [Enum.map(Streamgraph.order(), &to_string/1)]
    assert Enum.sort(Streamgraph.order()) == Enum.sort(@keys)
  end

  test "the still chart stacks in the run's order" do
    {design, %{months: rows}} = Streamgraph.design([])
    [%{data: %{transforms: transforms}}] = design.marks

    still =
      transforms
      |> Transform.apply(rows, size: [600, 400])
      |> Enum.map(&{&1.series, &1.key})
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.map(&elem(&1, 1))

    assert still == Enum.map(Streamgraph.order(), &to_string/1)
  end

  test "the fixed order is inside-out by each series' total over one turn of the run" do
    # The totals the module computed at compile time, read back from the rows the run
    # draws, so the attribute and the waves cannot drift apart.
    totals =
      for tick <- 0..62, row <- months(tick), key <- @keys, reduce: %{} do
        acc -> Map.update(acc, key, row[key], &(&1 + row[key]))
      end

    heaviest_first = Enum.sort_by(@keys, &Map.fetch!(totals, &1), :desc)
    order = Streamgraph.order()

    # The heaviest in the middle, each lighter one outward on alternating sides.
    middle = div(length(order), 2)
    assert Enum.at(order, middle) == hd(heaviest_first)

    for {key, rank} <- Enum.with_index(heaviest_first) do
      distance = abs(Enum.find_index(order, &(&1 == key)) - middle)
      assert distance == div(rank + 1, 2), "#{key} (rank #{rank}) sits #{distance} out"
    end
  end

  # The defect the fixed order removes: the per-tick inside-out order moves during a run.
  test "an order computed per tick would have moved the layers in the same run" do
    bottoms =
      for tick <- 0..199 do
        Stack.new()
        |> Stack.keys(@keys)
        |> Stack.order(:insideout)
        |> Stack.generate(months(tick))
        |> Enum.find(&(&1.index == 0))
        |> Map.fetch!(:key)
      end

    assert length(Enum.uniq(bottoms)) > 1
  end

  defp months(tick) do
    {_design, %{months: rows}} = Streamgraph.design(animation_tick: tick)
    rows
  end
end
