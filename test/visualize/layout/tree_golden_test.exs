defmodule Visualize.Layout.TreeGoldenTest do
  @moduledoc """
  Layout golden for the tidy tree (spec/06 §2.2, D-41).

  `test/support/tree_golden.txt` records `Tree.generate/2` — raw, with `size` and with
  `node_size` — over two fixed trees: the seven-node cousin case from spec/06 and an
  unbalanced tree whose contours exercise the threads. Regenerate only when the layout
  changes on purpose:

      mix run -e 'ExUnit.start(autorun: false); Code.require_file("test/visualize/layout/tree_golden_test.exs"); Visualize.Layout.TreeGoldenTest.write!()'
  """
  use ExUnit.Case, async: true

  alias Visualize.Layout.{Hierarchy, Tree}

  @golden "test/support/tree_golden.txt"

  def trees do
    [
      cousins: %{
        name: "root",
        children: [
          %{name: "A", children: [%{name: "A1"}, %{name: "A2"}]},
          %{name: "B", children: [%{name: "B1"}, %{name: "B2"}]}
        ]
      },
      unbalanced: %{
        name: "r",
        children: [
          %{name: "A", children: [%{name: "A1", children: [%{name: "A1a"}, %{name: "A1b"}]}]},
          %{name: "B"},
          %{name: "C", children: [%{name: "C1"}, %{name: "C2"}, %{name: "C3"}]}
        ]
      }
    ]
  end

  def layouts do
    [
      raw: Tree.new(),
      size: Tree.new() |> Tree.size([400, 200]),
      node_size: Tree.new() |> Tree.node_size([10, 20])
    ]
  end

  def render do
    for {tree_name, data} <- trees(), {layout_name, layout} <- layouts() do
      root = Tree.generate(layout, Hierarchy.new(data))

      root
      |> Hierarchy.descendants()
      |> Enum.map(&"#{tree_name} #{layout_name} #{&1.data.name} #{fmt(&1.x)} #{fmt(&1.y)}")
    end
    |> List.flatten()
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  def write!, do: File.write!(@golden, render())

  defp fmt(x) when is_float(x), do: :erlang.float_to_binary(x + 0.0, decimals: 9)
  defp fmt(x) when is_integer(x), do: fmt(x * 1.0)

  test "every tree and layout mode positions exactly as recorded" do
    assert File.read!(@golden) == render()
  end

  test "cousin subtrees do not overlap: leaves are distinct, siblings 1 apart, cousins 2" do
    root = Tree.generate(Tree.new(), Hierarchy.new(trees()[:cousins]))
    [a1, a2, b1, b2] = root |> Hierarchy.leaves() |> Enum.map(& &1.x)

    assert_in_delta a2 - a1, 1, 1.0e-9
    assert_in_delta b1 - a2, 2, 1.0e-9
    assert_in_delta b2 - b1, 1, 1.0e-9
  end

  test "every parent is centered over its children and the root sits at 0" do
    root = Tree.generate(Tree.new(), Hierarchy.new(trees()[:unbalanced]))
    assert root.x == 0

    Hierarchy.each(root, fn node ->
      if node.children do
        assert_in_delta node.x, (hd(node.children).x + List.last(node.children).x) / 2, 1.0e-9
      end
    end)
  end

  test "nodes at one depth are separated by at least the separation function" do
    sep = fn a, b -> if a.parent == b.parent, do: 1.5, else: 3 end
    tree = Tree.new() |> Tree.separation(sep)
    root = Tree.generate(tree, Hierarchy.new(trees()[:unbalanced]))

    root
    |> Hierarchy.descendants()
    |> Enum.group_by(& &1.depth)
    |> Enum.each(fn {_depth, nodes} ->
      nodes
      |> Enum.sort_by(& &1.x)
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.each(fn [l, r] -> assert r.x - l.x >= sep.(r, l) - 1.0e-9 end)
    end)
  end

  test "size normalizes the extent to the box; node_size multiplies the raw units" do
    sized = Tree.generate(Tree.new() |> Tree.size([400, 200]), Hierarchy.new(trees()[:cousins]))
    xs = sized |> Hierarchy.descendants() |> Enum.map(& &1.x)
    ys = sized |> Hierarchy.descendants() |> Enum.map(& &1.y)
    assert {Enum.min(xs), Enum.max(xs)} == {0.0, 400.0}
    assert {Enum.min(ys), Enum.max(ys)} == {0.0, 200.0}

    fixed =
      Tree.generate(Tree.new() |> Tree.node_size([10, 20]), Hierarchy.new(trees()[:cousins]))

    assert Enum.map(Hierarchy.leaves(fixed), & &1.x) == [-20.0, -10.0, 10.0, 20.0]
    assert Enum.map(Hierarchy.leaves(fixed), & &1.y) == [40, 40, 40, 40]
  end
end
