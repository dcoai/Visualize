defmodule Visualize.Shape.ArcStackTest do
  @moduledoc "Regressions for the `Arc`, `Stack` and facade defects of #14 (#26)."
  use ExUnit.Case, async: true

  alias Visualize.IR.Path
  alias Visualize.Shape
  alias Visualize.Shape.{Arc, Pie, Stack}

  doctest Stack

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
      # tangent point is on the outer ring; the corner circle's center is r1 − rc from the origin.
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

    # A fixed order (spec/04 §8.4, #492): bottom first as listed, whatever the sums.
    test "{:keys, list} stacks in exactly the listed order" do
      data = [%{a: 5, b: 1, c: 3}, %{a: 1, b: 9, c: 2}]
      stack = Stack.new() |> Stack.keys([:a, :b, :c]) |> Stack.order({:keys, [:b, :c, :a]})
      series = Stack.generate(stack, data)

      assert Enum.map(series, &{&1.key, &1.index}) == [a: 2, b: 0, c: 1]
      [a, b, c] = Enum.map(series, &Enum.map(&1.points, fn p -> {p.y0, p.y1} end))
      assert b == [{0, 1}, {0, 9}]
      assert c == [{1, 4}, {9, 11}]
      assert a == [{4, 9}, {11, 12}]

      # The same keys over other data keep the same places: no value is read.
      other = Stack.generate(stack, [%{a: 100, b: 0, c: 50}])
      assert Enum.map(other, & &1.index) == [2, 0, 1]
    end

    test "{:keys, list} puts unlisted keys above in key order and ignores unknown ones" do
      data = [%{a: 1, b: 2, c: 3, d: 4}]
      stack = Stack.new() |> Stack.keys([:a, :b, :c, :d])

      by = fn order ->
        stack |> Stack.order(order) |> Stack.generate(data) |> Enum.map(&{&1.key, &1.index})
      end

      # c, then the unlisted a, b, d in key order; :x is not a key and is ignored.
      assert by.({:keys, [:x, :c]}) == [a: 1, b: 2, c: 0, d: 3]
      # A key named twice is placed at its first mention.
      assert by.({:keys, [:d, :a, :d]}) == [a: 1, b: 2, c: 3, d: 0]
      # Nothing listed that the stack has is key order, as :none.
      assert by.({:keys, [:x]}) == by.(:none)
      assert by.({:keys, []}) == by.(:none)
    end
  end

  # d3-shape 3.2.0 `src/order/insideOut.js`, lines 15-26:
  #
  #     for (i = 0; i < n; ++i) {
  #       j = order[i];                         // order = appearance(series)
  #       if (top < bottom) { top += sums[j]; tops.push(j); }
  #       else { bottom += sums[j]; bottoms.push(j); }
  #     }
  #     return bottoms.reverse().concat(tops);
  #
  # with `appearance` (`src/order/appearance.js`, lines 3-6) a sort of the key indexes by
  # `peak`, the index of the first greatest value (lines 8-11, `>` keeps the first), and
  # `sum` (`src/order/ascending.js`, lines 8-11) the signed sum. Each expected order below is
  # that loop run by hand, and was confirmed with `stack().order(stackOrderInsideOut)` under
  # d3-shape 3.2.0. `{key, index}`: index 0 is the bottom of the stack.
  describe "Stack :insideout is d3's stackOrderInsideOut (spec/04 §8.4, D-125)" do
    defp inside_out(columns) do
      keys = Enum.map(columns, &elem(&1, 0))
      n = columns |> hd() |> elem(1) |> length()
      data = for j <- 0..(n - 1), do: Map.new(columns, fn {k, vs} -> {k, Enum.at(vs, j)} end)

      Stack.new()
      |> Stack.keys(keys)
      |> Stack.order(:insideout)
      |> Stack.generate(data)
      |> Enum.map(&{&1.key, &1.index})
    end

    test "the earliest peak sits in the middle, later peaks outward on the lighter side" do
      # Peaks: b 0, d 1, e 2, a 3, c 4; sums a 13, b 10, c 8, d 11, e 9.
      # b → bottom (0 < 0 is false; bottom 10), d → top (0 < 10; top 11),
      # e → bottom (11 < 10 is false; bottom 19), a → top (11 < 19; top 24),
      # c → bottom (24 < 19 is false). bottoms b e c reversed, then tops d a: c e b d a.
      assert inside_out(
               a: [1, 1, 1, 9, 1],
               b: [6, 1, 1, 1, 1],
               c: [1, 1, 1, 1, 4],
               d: [1, 7, 1, 1, 1],
               e: [1, 1, 5, 1, 1]
             ) == [a: 4, b: 2, c: 0, d: 3, e: 1]
    end

    test "one datum: every peak is at 0, so appearance is key order and sums decide the side" do
      # The case the #26 test pinned as a d b c (the heaviest, a, at the bottom).
      # a → bottom (5), b → top (1 < 5), c → top (4 < 5), d → top (6): a, then b c d.
      assert inside_out(a: [5], b: [1], c: [3], d: [2]) == [a: 0, b: 1, c: 2, d: 3]
    end

    test "a tied peak keeps the first index, and tied peaks keep key order" do
      # a's peak is index 0 (2 at 0 and 1), c's is 0 (1 at 0 and 2), b's is 1 (3 at 1 and 2).
      # Appearance (stable): a c b. a → bottom (4), c → top (2 < 4), b → top (2 < 4): a c b.
      assert inside_out(a: [2, 2, 0], b: [0, 3, 3], c: [1, 0, 1]) == [a: 0, b: 2, c: 1]
    end

    test "sums are signed: a negative series lowers its side's total" do
      # Peaks: a 0, d 0, b 1 (-1 > -3), c 1; appearance a d b c; sums a 4, b -4, c 2, d 1.
      # a → bottom (4), d → top (1 < 4; top 1), b → top (1 < 4; top -3), c → top (-3 < 4).
      # Summing magnitudes would send c to the bottom (5 < 4 is false): c a d b.
      assert inside_out(a: [4, 0], b: [-3, -1], c: [0, 2], d: [1, 0]) ==
               [a: 0, b: 2, c: 3, d: 1]
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
