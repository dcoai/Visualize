defmodule Visualize.Shape.ArcStackTest do
  @moduledoc "Regressions for the `Arc`, `Stack` and facade defects of #14 (#26)."
  use ExUnit.Case, async: true

  alias Visualize.IR.Path
  alias Visualize.Shape
  alias Visualize.Shape.{Arc, Pie, Stack}

  @pi :math.pi()
  @quarter %{start_angle: 0, end_angle: @pi / 2}

  defp ring, do: Arc.new() |> Arc.inner_radius(50) |> Arc.outer_radius(100)

  defp arcs(%Path{commands: commands}, radius),
    do: Enum.filter(commands, &match?({:A, ^radius, ^radius, _, _, _, _, _}, &1))

  defp norm({x, y}), do: :math.sqrt(x * x + y * y)

  describe "Arc plain geometry is unchanged (spec/04 §6.2)" do
    test "annular sector" do
      assert Arc.generate(ring(), @quarter) ==
               "M0,-100A100,100,0,0,1,100,0L50,0A50,50,0,0,0,0,-50Z"
    end

    test "circular sector" do
      assert Arc.generate(Arc.new(), @quarter) == "M0,-100A100,100,0,0,1,100,0L0,0Z"
    end

    test "a full ring closes with Z" do
      %Path{commands: commands} = Arc.generate_path(ring(), %{start_angle: 0, end_angle: 2 * @pi})

      assert [
               {:M, _, _},
               {:A, 100, _, _, 1, 1, _, _},
               {:A, 100, _, _, 1, 1, _, _},
               {:M, _, _} | rest
             ] = commands

      assert [{:A, 50, _, _, 1, 0, _, _}, {:A, 50, _, _, 1, 0, _, _}, :Z] = rest
    end

    test "swapped radii draw the same sector" do
      swapped = Arc.new() |> Arc.inner_radius(100) |> Arc.outer_radius(50)
      assert Arc.generate(swapped, @quarter) == Arc.generate(ring(), @quarter)
    end

    test "no extent or no outer radius is empty" do
      assert Arc.generate_path(ring(), %{start_angle: 1, end_angle: 1}) == Path.new()
      assert Arc.generate_path(Arc.new() |> Arc.outer_radius(0), @quarter) == Path.new()
    end
  end

  describe "Arc.pad_angle/2 (spec/04 §6.2, D-21)" do
    test "each ring's ends move inward by asin(rp / r · sin(ap)) at the default pad radius" do
      %Path{commands: [{:M, x, y}, {:A, 100, _, _, _, _, x1, y1}, {:L, lx, ly} | _]} =
        ring() |> Arc.pad_angle(0.1) |> Arc.generate_path(@quarter)

      rp = :math.sqrt(50 * 50 + 100 * 100)
      p1 = :math.asin(rp / 100 * :math.sin(0.05))
      p0 = :math.asin(rp / 50 * :math.sin(0.05))
      assert_in_delta x, 100 * :math.sin(p1), 1.0e-9
      assert_in_delta y, -100 * :math.cos(p1), 1.0e-9
      assert_in_delta x1, 100 * :math.cos(p1), 1.0e-9
      assert_in_delta y1, -100 * :math.sin(p1), 1.0e-9
      # The inner end sits at the same linear gap, so the same x, on the inner ring.
      assert_in_delta lx, 50 * :math.cos(p0), 1.0e-9
      assert_in_delta ly, -50 * :math.sin(p0), 1.0e-9
    end

    test "pad_radius sets where the pad angle is measured" do
      %Path{commands: [{:M, x, _} | _]} =
        ring() |> Arc.pad_angle(0.1) |> Arc.pad_radius(100) |> Arc.generate_path(@quarter)

      # At rp = r1 the outer shift is exactly half the pad angle.
      assert_in_delta x, 100 * :math.sin(0.05), 1.0e-9
    end

    test "a pad wider than the sector collapses it to a line at the mid-angle" do
      assert Arc.generate(Arc.pad_angle(ring(), 3), @quarter) ==
               "M70.7107,-70.7107L35.3553,-35.3553Z"
    end

    test "zero pad is the plain sector" do
      assert Arc.generate(Arc.pad_angle(ring(), 0), @quarter) == Arc.generate(ring(), @quarter)
    end
  end

  describe "Arc.corner_radius/2 (spec/04 §6.2, D-21)" do
    test "rounds the four corners with tangent arcs of the corner radius" do
      path = ring() |> Arc.corner_radius(10) |> Arc.generate_path(@quarter)
      assert length(arcs(path, 10)) == 4
      assert length(arcs(path, 100)) == 1
      assert length(arcs(path, 50)) == 1

      # The first corner: its edge tangent point is on the start edge (x = 0), and its ring
      # tangent point is on the outer ring; the corner circle's centre is r1 − rc from the origin.
      %Path{commands: [{:M, mx, my}, {:A, 10, 10, _, _, _, tx, ty} | _]} = path
      assert_in_delta mx, 0, 1.0e-9
      assert_in_delta norm({tx, ty}), 100, 1.0e-9
      assert_in_delta norm({10, my}), 90, 1.0e-9
    end

    test "is the exact d3 path" do
      assert Arc.generate(Arc.corner_radius(ring(), 10), @quarter) ==
               "M0,-89.4427A10,10,0,0,1,11.1111,-99.3808A100,100,0,0,1,99.3808,-11.1111A10,10,0,0,1,89.4427,0" <>
                 "L59.1608,0A10,10,0,0,1,49.3007,-8.3333A50,50,0,0,0,8.3333,-49.3007A10,10,0,0,1,0,-59.1608Z"
    end

    test "is limited to half the ring thickness" do
      path = ring() |> Arc.corner_radius(100) |> Arc.generate_path(@quarter)
      assert arcs(path, 100.0) == [] or length(arcs(path, 100)) == 1
      assert length(arcs(path, 25.0)) == 4
    end

    test "a thin sector merges each pair of corners into one arc" do
      path =
        ring() |> Arc.corner_radius(10) |> Arc.generate_path(%{start_angle: 0, end_angle: 0.05})

      corner_arcs = Enum.filter(path.commands, &match?({:A, r, r, _, _, _, _, _} when r < 10, &1))
      assert length(corner_arcs) == 2
      assert arcs(path, 100) == []
    end

    test "a circular sector rounds only the outer corners" do
      path = Arc.new() |> Arc.corner_radius(10) |> Arc.generate_path(@quarter)
      assert length(arcs(path, 10)) == 2
      assert List.last(path.commands) == :Z
      assert Enum.at(path.commands, -2) == {:L, 0, 0}
    end

    test "counter-clockwise sectors flip every sweep" do
      cw = ring() |> Arc.corner_radius(10) |> Arc.generate_path(@quarter)

      ccw =
        ring()
        |> Arc.corner_radius(10)
        |> Arc.generate_path(%{start_angle: @pi / 2, end_angle: 0})

      sweeps = fn path -> for {:A, _, _, _, _, s, _, _} <- path.commands, do: s end
      assert sweeps.(cw) == Enum.map(sweeps.(ccw), &(1 - &1))
    end

    test "the centroid ignores padding and corners" do
      plain = Arc.centroid(ring(), @quarter)
      fancy = ring() |> Arc.corner_radius(10) |> Arc.pad_angle(0.1) |> Arc.centroid(@quarter)
      assert plain == fancy
    end
  end

  describe "Stack offsets (spec/04 §8.5, D-22)" do
    defp layout(stack, data) do
      stack
      |> Stack.generate(data)
      |> Enum.map(fn s -> {s.key, s.index, Enum.map(s.points, &{&1.y0, &1.y1})} end)
    end

    test ":diverging stacks positives up and negatives down from zero, independently" do
      data = [%{a: 1, b: -2, c: 3}, %{a: -1, b: 2, c: -3}, %{a: 0, b: 1, c: -1}]
      stack = Stack.new() |> Stack.keys([:a, :b, :c]) |> Stack.offset(:diverging)

      assert layout(stack, data) == [
               {:a, 0, [{0, 1}, {-1, 0}, {0, 0}]},
               {:b, 1, [{-2, 0}, {0, 2}, {0, 1}]},
               {:c, 2, [{1, 4}, {-4, -1}, {-1, 0}]}
             ]
    end

    test ":wiggle is the streamgraph baseline" do
      # Hand-computed from d3's stackOffsetWiggle: baselines 0, −1.125, −0.925.
      data = [%{a: 1, b: 2}, %{a: 3, b: 1}, %{a: 2, b: 3}]
      stack = Stack.new() |> Stack.keys([:a, :b]) |> Stack.offset(:wiggle)

      assert layout(stack, data) == [
               {:a, 0, [{0, 1}, {-1.125, 1.875}, {-0.925, 1.075}]},
               {:b, 1, [{1, 3}, {1.875, 2.875}, {1.075, 4.075}]}
             ]
    end

    test ":wiggle with one datum is a zero baseline" do
      stack = Stack.new() |> Stack.keys([:a, :b]) |> Stack.offset(:wiggle)
      assert layout(stack, [%{a: 1, b: 2}]) == [{:a, 0, [{0, 1}]}, {:b, 1, [{1, 3}]}]
    end

    test ":wiggle differs from :silhouette" do
      data = [%{a: 1, b: 2}, %{a: 3, b: 1}, %{a: 2, b: 3}]
      base = Stack.new() |> Stack.keys([:a, :b])

      refute layout(Stack.offset(base, :wiggle), data) ==
               layout(Stack.offset(base, :silhouette), data)
    end

    test ":silhouette and :expand are unchanged" do
      data = [%{a: 1, b: 2}, %{a: 3, b: 1}]
      base = Stack.new() |> Stack.keys([:a, :b])

      assert layout(Stack.offset(base, :silhouette), data) ==
               [{:a, 0, [{-1.5, -0.5}, {-2.0, 1.0}]}, {:b, 1, [{-0.5, 1.5}, {1.0, 2.0}]}]

      assert layout(Stack.offset(base, :expand), data) ==
               [{:a, 0, [{0, 1 / 3}, {0, 0.75}]}, {:b, 1, [{1 / 3, 1.0}, {0.75, 1.0}]}]
    end
  end

  describe "Stack series order (spec/04 §8.3, D-22)" do
    test "series come back in key order with index the stacking position" do
      data = [%{a: 1, b: 2}, %{a: 3, b: 1}]
      stack = Stack.new() |> Stack.keys([:a, :b]) |> Stack.order(:reverse)
      series = Stack.generate(stack, data)
      assert Enum.map(series, & &1.key) == [:a, :b]
      assert Enum.map(series, & &1.index) == [1, 0]
      # b is at the bottom; a sits on top of it.
      assert Enum.map(hd(series).points, & &1.y0) == Enum.map(List.last(series).points, & &1.y1)
    end

    test ":insideout keeps its interleaving" do
      data = [%{a: 5, b: 1, c: 3, d: 2}]
      stack = Stack.new() |> Stack.keys([:a, :b, :c, :d]) |> Stack.order(:insideout)
      # Descending by sum: a c d b; interleaved (pairs to top and bottom): a d b c.
      assert Enum.map(Stack.generate(stack, data), &{&1.key, &1.index}) == [
               a: 0,
               b: 2,
               c: 3,
               d: 1
             ]
    end
  end

  describe "Shape facade (spec/04 §2)" do
    test "corner_radius/2 and pad_radius/2 dispatch to Arc" do
      arc = Shape.arc() |> Shape.corner_radius(10) |> Shape.pad_radius(100)
      assert %Arc{} = arc
      assert Shape.generate(arc, @quarter) == Arc.generate(arc, @quarter)
      assert arc.pad_radius.(nil) == 100
    end

    test "sort/2 and sort_values/2 dispatch to Pie" do
      cmp = fn a, b -> a >= b end
      assert %Pie{sort_values: ^cmp, sort: nil} = Shape.pie() |> Shape.sort_values(cmp)
      assert %Pie{sort: ^cmp, sort_values: nil} = Shape.pie() |> Shape.sort(cmp)
    end

    test "a generator without the setting fails to match" do
      assert_raise FunctionClauseError, fn -> Shape.corner_radius(Shape.line(), 1) end
      assert_raise FunctionClauseError, fn -> Shape.sort(Shape.stack(), nil) end
    end
  end
end
