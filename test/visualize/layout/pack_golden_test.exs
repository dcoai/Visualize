defmodule Visualize.Layout.PackGoldenTest do
  @moduledoc """
  Layout golden for circle packing (spec/06 §3.2, D-42).

  `test/support/pack_golden.txt` records `Pack.generate/2` over a fixed hierarchy with
  five leaves. Regenerate only when the packing changes on purpose:

      mix run -e 'ExUnit.start(autorun: false); Code.require_file("test/visualize/layout/pack_golden_test.exs"); Visualize.Layout.PackGoldenTest.write!()'
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Visualize.Layout.{Hierarchy, Pack}

  @golden "test/support/pack_golden.txt"

  def root do
    %{
      name: "root",
      children: [
        %{name: "A", value: 100},
        %{name: "B", value: 400},
        %{name: "C", children: [%{name: "C1", value: 50}, %{name: "C2", value: 150}]},
        %{name: "D", value: 64}
      ]
    }
    |> Hierarchy.new()
    |> Hierarchy.sum(fn d -> d[:value] || 0 end)
  end

  def render do
    for {label, pack} <- [
          plain: Pack.new() |> Pack.size([400, 400]),
          padded: Pack.new() |> Pack.size([400, 400]) |> Pack.padding(3)
        ] do
      pack
      |> Pack.generate(root())
      |> Hierarchy.descendants()
      |> Enum.map(&"#{label} #{&1.data.name} #{fmt(&1.x)} #{fmt(&1.y)} #{fmt(&1.r)}")
    end
    |> List.flatten()
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  def write!, do: File.write!(@golden, render())

  defp fmt(x) when is_float(x), do: :erlang.float_to_binary(x + 0.0, decimals: 9)
  defp fmt(x) when is_integer(x), do: fmt(x * 1.0)

  test "the five-leaf hierarchy packs exactly as recorded" do
    assert File.read!(@golden) == render()
  end

  defp distance(a, b), do: :math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y))

  defp assert_packed(root) do
    Hierarchy.each(root, fn node ->
      if node.children do
        for a <- node.children, b <- node.children, a.data.name < b.data.name do
          assert distance(a, b) >= a.r + b.r - 1.0e-6,
                 "#{a.data.name} and #{b.data.name} overlap"
        end

        for c <- node.children do
          assert distance(c, node) + c.r <= node.r + 1.0e-6,
                 "#{c.data.name} leaves #{node.data.name}"
        end
      end
    end)
  end

  test "siblings never overlap, children stay inside their parent, the root fills the box" do
    root = Pack.generate(Pack.new() |> Pack.size([400, 300]) |> Pack.padding(3), root())
    assert_packed(root)
    assert {root.x, root.y, root.r} == {200.0, 150.0, 150.0}
  end

  test "the sibling gap is the padding scaled by the unpadded over padded root radius" do
    unpadded = Pack.generate(Pack.new() |> Pack.size([400, 400]), root())
    padded = Pack.generate(Pack.new() |> Pack.size([400, 400]) |> Pack.padding(3), root())
    [a, b | _] = padded.children

    # Both roots fill the box, so the ratio of layout-unit radii is read from the leaves.
    ratio = hd(unpadded.children).r / hd(padded.children).r
    assert_in_delta distance(a, b) - a.r - b.r, 3 / ratio, 1.0e-6
  end

  test "the enclosing circle is minimal: it touches at least two children" do
    root = Pack.generate(Pack.new() |> Pack.size([400, 400]), root())
    touching = Enum.count(root.children, &(abs(distance(&1, root) + &1.r - root.r) < 1.0e-6))
    assert touching >= 2
  end

  property "random sibling sets pack without overlap, inside the parent, deterministically" do
    check all(radii <- list_of(float(min: 0.5, max: 20.0), min_length: 1, max_length: 30)) do
      data = %{
        name: "r",
        children: Enum.with_index(radii, fn r, i -> %{name: "n#{i}", value: r * r} end)
      }

      root = Hierarchy.new(data) |> Hierarchy.sum(fn d -> d[:value] || 0 end)
      pack = Pack.new() |> Pack.size([200, 200]) |> Pack.padding(1)
      first = Pack.generate(pack, root)
      assert_packed(first)
      assert first == Pack.generate(pack, root)
    end
  end

  test "a lone root and a weightless tree are returned without scaling" do
    solo = Pack.generate(Pack.new(), Hierarchy.new(%{name: "s"}) |> Hierarchy.sum(fn _ -> 4 end))
    assert {solo.x, solo.y, solo.r} == {0.5, 0.5, 0.5}

    zero = Hierarchy.new(%{name: "z", children: [%{name: "a"}]}) |> Hierarchy.sum(fn _ -> 0 end)
    assert %{x: 0, y: 0, r: 0} = Pack.generate(Pack.new(), zero)
  end

  test "a radius function sizes the leaves" do
    pack = Pack.new() |> Pack.size([100, 100]) |> Pack.radius(fn _ -> 5 end)

    root =
      Pack.generate(pack, Hierarchy.new(%{name: "r", children: [%{name: "a"}, %{name: "b"}]}))

    assert Enum.map(root.children, & &1.r) == [25.0, 25.0]
  end
end
