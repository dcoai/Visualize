defmodule Visualize.Layout.HierarchyTest do
  @moduledoc """
  `stratify/2` and `path/2` against d3-hierarchy's contracts (spec/06 §1.2, §1.4, D-41).
  """
  use ExUnit.Case, async: true

  alias Visualize.Layout.Hierarchy

  defp names(nodes), do: Enum.map(nodes, & &1.data.name)

  describe "stratify/2" do
    test "the moduledoc example attaches a grandchild listed after its parent" do
      root =
        Hierarchy.stratify([
          %{id: "root", parent: nil},
          %{id: "child1", parent: "root"},
          %{id: "child2", parent: "root"},
          %{id: "grandchild", parent: "child2"}
        ])

      assert length(Hierarchy.descendants(root)) == 4
      assert root.height == 2
      assert Enum.map(Hierarchy.leaves(root), & &1.data.id) == ["child1", "grandchild"]
    end

    test "the tree is the same whatever the input order" do
      rows = [
        %{id: "gc", parent: "c2"},
        %{id: "c2", parent: "root"},
        %{id: "ggc", parent: "gc"},
        %{id: "root", parent: nil},
        %{id: "c1", parent: "root"}
      ]

      shape = fn root ->
        root |> Hierarchy.descendants() |> Enum.map(&{&1.data.id, &1.depth}) |> Enum.sort()
      end

      forward = Hierarchy.stratify(rows)
      assert forward.height == 3
      assert shape.(forward) == shape.(Hierarchy.stratify(Enum.reverse(rows)))
      assert shape.(forward) == shape.(Hierarchy.stratify(Enum.sort_by(rows, & &1.id)))
    end

    test "children keep input order under their parent; unknown parents are dropped" do
      root =
        Hierarchy.stratify([
          %{id: "b", parent: "root"},
          %{id: "root", parent: ""},
          %{id: "a", parent: "root"},
          %{id: "orphan", parent: "nobody"}
        ])

      assert Enum.map(root.children, & &1.data.id) == ["b", "a"]
      assert length(Hierarchy.descendants(root)) == 3
    end

    test "no root raises" do
      assert_raise ArgumentError, fn -> Hierarchy.stratify([%{id: "a", parent: "b"}]) end
    end
  end

  describe "path/2" do
    setup do
      root =
        Hierarchy.new(%{
          name: "root",
          children: [
            %{name: "A", children: [%{name: "A1"}, %{name: "A2"}]},
            %{name: "B", children: [%{name: "B1"}, %{name: "B2"}]}
          ]
        })

      [a, b] = root.children
      [a1, a2] = a.children
      [_b1, b2] = b.children
      %{root: root, a: a, a1: a1, a2: a2, b2: b2}
    end

    test "cousins go up to the root and down again", ctx do
      assert names(Hierarchy.path(ctx.a1, ctx.b2)) == ["A1", "A", "root", "B", "B2"]
      assert names(Hierarchy.path(ctx.b2, ctx.a1)) == ["B2", "B", "root", "A", "A1"]
    end

    test "siblings meet at their parent", ctx do
      assert names(Hierarchy.path(ctx.a1, ctx.a2)) == ["A1", "A", "A2"]
    end

    test "an ancestor or descendant is a straight chain, each endpoint once", ctx do
      assert names(Hierarchy.path(ctx.a, ctx.a1)) == ["A", "A1"]
      assert names(Hierarchy.path(ctx.a1, ctx.a)) == ["A1", "A"]
      assert names(Hierarchy.path(ctx.root, ctx.b2)) == ["root", "B", "B2"]
    end

    test "a node to itself is the node alone", ctx do
      assert names(Hierarchy.path(ctx.a1, ctx.a1)) == ["A1"]
    end
  end
end
