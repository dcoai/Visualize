defmodule Visualize.Layout.TreemapGoldenTest do
  @moduledoc """
  Layout golden for the treemap and the partition (spec/06 §4.2, §5.2, D-41).

  `test/support/treemap_golden.txt` records every tiling algorithm and the partition over
  one six-node hierarchy that carries a zero-valued child. Regenerate only when the
  layouts change on purpose:

      mix run -e 'ExUnit.start(autorun: false); Code.require_file("test/visualize/layout/treemap_golden_test.exs"); Visualize.Layout.TreemapGoldenTest.write!()'
  """
  use ExUnit.Case, async: true

  alias Visualize.Layout.{Hierarchy, Partition, Treemap}

  @golden "test/support/treemap_golden.txt"
  @tiles [:squarify, :binary, :slice, :dice, :slice_dice]

  def root do
    %{
      name: "root",
      children: [
        %{name: "A", value: 100},
        %{name: "B", value: 0},
        %{name: "C", children: [%{name: "C1", value: 50}, %{name: "C2", value: 75}]}
      ]
    }
    |> Hierarchy.new()
    |> Hierarchy.sum(fn d -> d[:value] || 0 end)
  end

  def render do
    treemaps =
      for tile <- @tiles do
        layout =
          Treemap.new()
          |> Treemap.size([400, 300])
          |> Treemap.tile(tile)
          |> Treemap.padding(2)
          |> Treemap.padding_inner(1)

        rows("treemap #{tile}", Treemap.generate(layout, root()))
      end

    partition =
      Partition.new()
      |> Partition.size([400, 300])
      |> Partition.padding(2)
      |> Partition.generate(root())

    (treemaps ++ [rows("partition", partition)])
    |> List.flatten()
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  defp rows(prefix, root) do
    root
    |> Hierarchy.descendants()
    |> Enum.map(fn n ->
      "#{prefix} #{n.data.name} #{fmt(n.x0)} #{fmt(n.y0)} #{fmt(n.x1)} #{fmt(n.y1)}"
    end)
  end

  def write!, do: File.write!(@golden, render())

  defp fmt(x) when is_float(x), do: :erlang.float_to_binary(x + 0.0, decimals: 9)
  defp fmt(x) when is_integer(x), do: fmt(x * 1.0)

  test "every tiling algorithm and the partition lay out exactly as recorded" do
    assert File.read!(@golden) == render()
  end

  defp by_name(root), do: root |> Hierarchy.descendants() |> Map.new(&{&1.data.name, &1})

  test "a zero-valued child stays in the treemap with a zero-area rectangle" do
    for tile <- @tiles do
      layout = Treemap.new() |> Treemap.size([400, 300]) |> Treemap.tile(tile)
      nodes = by_name(Treemap.generate(layout, root()))

      assert Map.has_key?(nodes, "B"), "#{tile} dropped B"
      b = nodes["B"]
      assert (b.x1 - b.x0) * (b.y1 - b.y0) == 0
      assert b.x0 >= 0 and b.x1 <= 400 and b.y0 >= 0 and b.y1 <= 300
      a = nodes["A"]
      assert_in_delta (a.x1 - a.x0) * (a.y1 - a.y0), 400 * 300 * 100 / 225, 1.0e-6
    end
  end

  test "a nil-valued subtree is retained with zero-area rectangles at every depth" do
    root =
      Hierarchy.new(%{
        name: "r",
        children: [%{name: "a", value: 3}, %{name: "z", children: [%{name: "z1"}]}]
      })
      |> Hierarchy.sum(fn d -> d[:value] || 0 end)

    nodes = by_name(Treemap.generate(Treemap.new() |> Treemap.size([10, 10]), root))
    assert Map.keys(nodes) |> Enum.sort() == ["a", "r", "z", "z1"]
    assert (nodes["z"].x1 - nodes["z"].x0) * (nodes["z"].y1 - nodes["z"].y0) == 0
    assert nodes["z1"].x0 == nodes["z1"].x1 and nodes["z1"].y0 == nodes["z1"].y1
  end

  test "a padding wider than a tile collapses it to a point instead of inverting it" do
    root =
      Hierarchy.new(%{name: "r", children: [%{name: "a", value: 1}, %{name: "b", value: 1000}]})
      |> Hierarchy.sum(fn d -> d[:value] || 0 end)

    layout =
      Treemap.new() |> Treemap.size([100, 100]) |> Treemap.tile(:dice) |> Treemap.padding_inner(4)

    a = by_name(Treemap.generate(layout, root))["a"]
    assert a.x0 == a.x1
    assert a.y0 < a.y1
  end

  test "the partition keeps a zero-valued child at its slot with zero width" do
    layout = Partition.new() |> Partition.size([400, 300]) |> Partition.padding(2)
    nodes = by_name(Partition.generate(layout, root()))

    assert nodes["B"].x0 == nodes["B"].x1
    assert nodes["B"].x0 == nodes["A"].x1 + 2
    assert nodes["C"].x0 == nodes["B"].x1 + 2
    assert nodes["C"].x1 == 400.0
  end

  test "a partition node whose children have no weight still positions them" do
    root = Hierarchy.new(%{name: "r", children: [%{name: "a"}, %{name: "b"}]})
    nodes = by_name(Partition.generate(Partition.new() |> Partition.size([10, 10]), root))
    assert {nodes["a"].x0, nodes["a"].x1, nodes["b"].x0, nodes["b"].x1} == {0, 0, 0, 0}
    assert nodes["a"].y0 == 5.0 and nodes["a"].y1 == 10.0
  end
end
