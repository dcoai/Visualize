defmodule Visualize.Layout.SankeyGoldenTest do
  @moduledoc """
  Layout golden for the Sankey diagram (spec/06 §7.3, D-42).

  `test/support/sankey_golden.txt` records `Sankey.compute/3` over one five-node graph
  under every alignment: for each node its depth, height, column and rectangle, and for
  each link its width and its top offsets. Regenerate only when the layout changes on
  purpose:

      mix run -e 'ExUnit.start(autorun: false); Code.require_file("test/visualize/layout/sankey_golden_test.exs"); Visualize.Layout.SankeyGoldenTest.write!()'
  """
  use ExUnit.Case, async: true

  alias Visualize.Layout.Sankey

  @golden "test/support/sankey_golden.txt"
  @aligns [:left, :right, :center, :justify]

  # a feeds c and the sink g; c feeds d; f is a second source feeding only d. So g is a
  # sink short of the last column and f a source that could sit later: the four
  # alignments give four different column assignments.
  def nodes, do: [%{id: "a"}, %{id: "c"}, %{id: "d"}, %{id: "f"}, %{id: "g"}]

  def links do
    [
      %{source: "a", target: "c", value: 10},
      %{source: "a", target: "g", value: 4},
      %{source: "c", target: "d", value: 15},
      %{source: "f", target: "d", value: 3}
    ]
  end

  def layout(align) do
    Sankey.new()
    |> Sankey.size(400, 300)
    |> Sankey.node_width(20)
    |> Sankey.node_padding(10)
    |> Sankey.node_align(align)
    |> Sankey.compute(nodes(), links())
  end

  def render do
    for align <- @aligns, sankey = layout(align) do
      node_rows =
        Enum.map(sankey.nodes, fn n ->
          "#{align} node #{n.id} d#{n.depth} h#{n.height} L#{n.layer} " <>
            "#{fmt(n.x0)} #{fmt(n.x1)} #{fmt(n.y0)} #{fmt(n.y1)}"
        end)

      link_rows =
        Enum.map(sankey.links, fn l ->
          "#{align} link #{l.source}->#{l.target} #{fmt(l.width)} #{fmt(l.y0)} #{fmt(l.y1)}"
        end)

      node_rows ++ link_rows
    end
    |> List.flatten()
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  def write!, do: File.write!(@golden, render())

  defp fmt(x) when is_float(x), do: :erlang.float_to_binary(x + 0.0, decimals: 9)
  defp fmt(x) when is_integer(x), do: fmt(x * 1.0)

  defp columns(sankey), do: Map.new(sankey.nodes, &{&1.id, &1.layer})

  test "every alignment lays out exactly as recorded" do
    assert File.read!(@golden) == render()
  end

  test "the four alignments place the loose source f and the early sink g differently" do
    assert columns(layout(:left)) == %{"a" => 0, "c" => 1, "d" => 2, "f" => 0, "g" => 1}
    assert columns(layout(:right)) == %{"a" => 0, "c" => 1, "d" => 2, "f" => 1, "g" => 2}
    assert columns(layout(:center)) == %{"a" => 0, "c" => 1, "d" => 2, "f" => 1, "g" => 1}
    assert columns(layout(:justify)) == %{"a" => 0, "c" => 1, "d" => 2, "f" => 0, "g" => 2}
  end

  test "columns are spread across the width, never stacked in one" do
    for align <- @aligns do
      xs = layout(align).nodes |> Enum.map(& &1.x0) |> Enum.uniq() |> Enum.sort()
      assert xs == [0.0, 190.0, 380.0], "#{align}: #{inspect(xs)}"
    end
  end

  test "one scale: a link's width is its value share of both endpoints' heights" do
    sankey = layout(:justify)
    ky = Enum.find(sankey.links, &(&1.source == "c")).width / 15

    for link <- sankey.links do
      assert_in_delta link.width, link.value * ky, 1.0e-9
    end

    for node <- sankey.nodes do
      assert_in_delta node.y1 - node.y0, node.value * ky, 1.0e-9
    end

    # Links leaving a node tile it exactly, top to bottom, in the settled order.
    a = Enum.find(sankey.nodes, &(&1.id == "a"))

    [first, second] =
      Enum.map(a.source_links, fn raw -> Enum.find(sankey.links, &(&1.target == raw.target)) end)

    assert_in_delta first.y0, a.y0, 1.0e-9
    assert_in_delta second.y0, a.y0 + first.width, 1.0e-9
    assert_in_delta second.y0 + second.width, a.y1, 1.0e-9
  end

  test "link_sort orders the links of every node and is otherwise the neighbour order" do
    by_value = Sankey.new() |> Sankey.link_sort(fn x, y -> x.value < y.value end)
    sorted = Sankey.compute(by_value, nodes(), links())
    a = Enum.find(sorted.nodes, &(&1.id == "a"))
    assert Enum.map(a.source_links, & &1.target) == ["g", "c"]

    default = layout(:justify)
    a = Enum.find(default.nodes, &(&1.id == "a"))
    assert Enum.map(a.source_links, & &1.target) == ["c", "g"]
  end

  test "depth is the longest path from a source, whatever the input order" do
    nodes = [%{id: 3}, %{id: 1}, %{id: 2}]

    links = [
      %{source: 1, target: 3, value: 1},
      %{source: 1, target: 2, value: 1},
      %{source: 2, target: 3, value: 1}
    ]

    sankey = Sankey.compute(Sankey.new(), nodes, links)
    assert Map.new(sankey.nodes, &{&1.id, &1.depth}) == %{1 => 0, 2 => 1, 3 => 2}
    assert Map.new(sankey.nodes, &{&1.id, &1.height}) == %{1 => 2, 2 => 1, 3 => 0}
  end

  test "links naming an unknown node keep width 0 and no path; empty input is empty" do
    sankey = Sankey.compute(Sankey.new(), [%{id: 1}], [%{source: 1, target: 2, value: 5}])
    assert [%{width: 0, path: nil}] = sankey.links
    assert %{nodes: [], links: []} = Sankey.compute(Sankey.new(), [], [])
  end

  test "a cycle terminates with every node in the last column" do
    sankey =
      Sankey.compute(Sankey.new(), [%{id: 1}, %{id: 2}], [
        %{source: 1, target: 2, value: 1},
        %{source: 2, target: 1, value: 1}
      ])

    assert Enum.map(sankey.nodes, & &1.layer) == [2, 2]
  end
end
