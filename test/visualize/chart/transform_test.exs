defmodule Visualize.Chart.TransformTest do
  @moduledoc """
  The data pipeline of spec/14 §5.4 and D-62: every op yields the rows its module
  computes for the same input, the layouts carry their shapes as `IR.Path`s in plot
  pixels, and a step that cannot run raises naming the op and the key.
  """
  use ExUnit.Case, async: true

  alias Visualize.Chart.Transform
  alias Visualize.{Contour, Data}
  alias Visualize.Contour.Density
  alias Visualize.Geo.{Delaunay, Projection, Voronoi}
  alias Visualize.IR.Path
  alias Visualize.Layout.{Chord, Force, Hierarchy, Pack, Sankey, Tree, Treemap}
  alias Visualize.Shape.Stack

  doctest Transform

  @size [200, 100]
  @rows for i <- 0..5, do: %{t: i, v: rem(i * 7, 5), a: i, b: 5 - i, c: 1, k: "k#{rem(i, 2)}"}

  defp run(step, rows, opts \\ []) do
    Transform.apply([step], rows, Keyword.put_new(opts, :size, @size))
  end

  describe "data steps" do
    test ":bin is Data.bin/2 with y0, the count and the values per bin" do
      rows = run(%{op: :bin, field: :v, thresholds: 2, as: :n}, @rows)
      bins = Data.bin(Enum.map(@rows, & &1.v), thresholds: 2)

      assert rows ==
               Enum.map(
                 bins,
                 &%{x0: &1.x0, x1: &1.x1, y0: 0, n: length(&1.values), values: &1.values}
               )

      assert run(%{op: :bin, field: :v}, [%{v: nil}]) == []
    end

    test ":stack is Shape.Stack per series in key order, each row its datum plus the stack" do
      rows = run(%{op: :stack, fields: [:a, :b, :c], offset: :expand}, @rows)

      series =
        Stack.new()
        |> Stack.keys([:a, :b, :c])
        |> Stack.offset(:expand)
        |> Stack.generate(@rows)

      expected =
        for s <- series, p <- s.points do
          Map.merge(p.data, %{key: s.key, series: s.index, value: p.value, y0: p.y0, y1: p.y1})
        end

      assert rows == expected
      assert Enum.map(rows, & &1.key) |> Enum.uniq() == [:a, :b, :c]
    end

    test ":stack maps :inside_out and :appearance onto the stacking order" do
      inside = run(%{op: :stack, fields: [:a, :b, :c], order: :inside_out}, @rows)

      direct =
        Stack.new()
        |> Stack.keys([:a, :b, :c])
        |> Stack.order(:insideout)
        |> Stack.generate(@rows)

      assert Enum.map(inside, & &1.series) |> Enum.uniq() == Enum.map(direct, & &1.index)

      # Peaks: a at the last row, b at the first, c at the first; b and c precede a.
      appearance = run(%{op: :stack, fields: [:a, :b, :c], order: :appearance}, @rows)
      by_key = appearance |> Enum.map(&{&1.key, &1.series}) |> Enum.uniq() |> Map.new()
      assert by_key == %{b: 0, c: 1, a: 2}
    end

    test ":sum groups by first appearance and :sort is stable" do
      assert run(%{op: :sum, field: :a, by: :k}, @rows) == [
               %{k: "k0", sum: 6},
               %{k: "k1", sum: 9}
             ]

      assert run(%{op: :sum, field: :a, as: :total}, @rows) == [%{total: 15}]

      sorted = run(%{op: :sort, field: :v, order: :descending}, @rows)
      assert Enum.map(sorted, & &1.v) == [4, 3, 2, 1, 0, 0]
      assert Enum.map(sorted, & &1.t) == [2, 4, 1, 3, 0, 5]
    end

    test ":fold turns wide columns into long rows, skipping listed columns the rows lack (spec/14 §5.4.1)" do
      wide = [%{hour: 0, cpu: 1, mem: 2}, %{hour: 1, cpu: 3}, %{hour: 2, mem: nil, cpu: 5}]

      assert run(%{op: :fold, fields: [:cpu, :mem, :disk]}, wide) == [
               %{hour: 0, key: :cpu, value: 1},
               %{hour: 0, key: :mem, value: 2},
               %{hour: 1, key: :cpu, value: 3},
               %{hour: 2, key: :cpu, value: 5}
             ]

      # The order within a row is the author's; `as` names the two columns.
      assert run(%{op: :fold, fields: [:mem, :cpu], as: [:series, :v]}, Enum.take(wide, 1)) == [
               %{hour: 0, series: :mem, v: 2},
               %{hour: 0, series: :cpu, v: 1}
             ]

      # A line over the fold draws one path per folded column, and a variable chooses the set.
      design = %{
        version: 1,
        # The source declares the columns every row has; the fold lists the ones a row may.
        sources: %{wide: %{fields: [:hour]}},
        vars: %{metrics: %{default: [:cpu, :mem, :disk]}},
        frame: %{
          kind: :cartesian,
          scales: %{x: %{kind: :linear}, y: %{kind: :linear}, color: %{kind: :ordinal}}
        },
        marks: [
          %{
            type: :line,
            data: %{
              source: :wide,
              transforms: [%{op: :fold, fields: Visualize.Chart.var(:metrics)}]
            },
            channels: %{x: :hour, y: :value, series: :key}
          }
        ]
      }

      assert Visualize.Chart.Validator.validate(design) == :ok
      {:ok, applied} = Visualize.Chart.apply(design, sources: %{wide: wide})
      svg = Visualize.Chart.render(applied)
      assert length(Regex.scan(~r/data-series="(cpu|mem)"/, svg)) == 2
      refute svg =~ ~s(data-series="disk")

      {:ok, two} = Visualize.Chart.apply(design, sources: %{wide: wide}, vars: %{metrics: [:cpu]})
      assert length(Regex.scan(~r/data-series=/, Visualize.Chart.render(two))) == 1

      # `as` is a pair for a fold and one name for a sum; the validator holds each to its shape.
      bad =
        put_in(design, [:marks, Access.at(0), :data, :transforms], [
          %{op: :fold, fields: [:cpu], as: :key}
        ])

      assert {:error, [{[:marks, 0, :data, :transforms, 0, :as], {:type, {:list, :name}}}]} =
               Visualize.Chart.Validator.validate(bad)

      bad =
        put_in(design, [:marks, Access.at(0), :data, :transforms], [
          %{op: :sum, field: :cpu, as: [:a, :b]}
        ])

      assert {:error, [{[:marks, 0, :data, :transforms, 0, :as], {:type, :name}}]} =
               Visualize.Chart.Validator.validate(bad)
    end

    test ":filter keeps the rows whose reading passes the test, a missing field reading nil" do
      # `v` is 0 2 4 1 3 0 over `t` 0..5; the last row lacks `v` altogether.
      rows = Enum.take(@rows, 5) ++ [%{t: 5}]
      kept = fn node -> node |> run(rows) |> Enum.map(& &1.t) end

      assert kept.(%{op: :filter, field: :v}) == [0, 1, 2, 3, 4]
      assert kept.(%{op: :filter, field: :v, test: :present}) == [0, 1, 2, 3, 4]
      assert kept.(%{op: :filter, field: :v, test: :absent}) == [5]
      assert kept.(%{op: :filter, field: :v, test: :eq, value: 0}) == [0]
      assert kept.(%{op: :filter, field: :v, test: :ne, value: 0}) == [1, 2, 3, 4, 5]
      assert kept.(%{op: :filter, field: :v, test: :lt, value: 2}) == [0, 3]
      assert kept.(%{op: :filter, field: :v, test: :lte, value: 2}) == [0, 1, 3]
      assert kept.(%{op: :filter, field: :v, test: :gt, value: 2}) == [2, 4]
      assert kept.(%{op: :filter, field: :v, test: :gte, value: 2}) == [1, 2, 4]

      # A field the rows never carry: everything under `:absent`, nothing otherwise.
      assert kept.(%{op: :filter, field: :nope, test: :absent}) == [0, 1, 2, 3, 4, 5]
      assert kept.(%{op: :filter, field: :nope}) == []
      assert kept.(%{op: :filter, field: :nope, test: :gte, value: 0}) == []

      # The step is a pure row step: a kept row is the row, and order is kept.
      assert run(%{op: :filter, field: :k, test: :eq, value: "k1"}, @rows) ==
               Enum.filter(@rows, &(&1.k == "k1"))

      # A leaves-only hierarchy and a rootless one (spec/14 §5.4.1).
      nodes = [%{id: "r", parent: nil}, %{id: "a", parent: "r"}, %{id: "b", parent: "r"}]

      assert [%{id: "a"}, %{id: "b"}] =
               Transform.apply(
                 [%{op: :treemap}, %{op: :filter, field: :height, test: :eq, value: 0}],
                 nodes
               )

      assert [%{id: "a"}, %{id: "b"}] =
               Transform.apply(
                 [%{op: :treemap}, %{op: :filter, field: :depth, test: :gt, value: 0}],
                 nodes
               )
    end
  end

  describe "hierarchies" do
    @tree [
      %{id: "root", parent: nil, w: 1},
      %{id: "a", parent: "root", w: 2},
      %{id: "b", parent: "root", w: 3},
      %{id: "a1", parent: "a", w: 4}
    ]

    test ":tree nodes are the laid-out hierarchy's descendants with the datum's columns" do
      rows = run(%{op: :tree, field: :w}, @tree)

      laid =
        @tree
        |> Hierarchy.stratify()
        |> Hierarchy.sum(& &1.w)
        |> then(&Tree.generate(Tree.size(Tree.new(), @size), &1))

      assert rows ==
               Enum.map(Hierarchy.descendants(laid), fn n ->
                 Map.merge(n.data, %{
                   depth: n.depth,
                   height: n.height,
                   value: n.value,
                   x: n.x,
                   y: n.y
                 })
               end)

      assert hd(rows).id == "root" and hd(rows).value == 10
    end

    test ":tree links carry the link of their orientation, positions unchanged (D-70)" do
      [link | _] = run(%{op: :tree, output: :links}, @tree)
      %{x0: x0, y0: y0, x1: x1, y1: y1} = link
      ym = (y0 + y1) / 2
      assert link.path.commands == [{:M, x0, y0}, {:C, x0, ym, x1, ym, x1, y1}]

      [swapped | _] = run(%{op: :tree, output: :links, orientation: :horizontal}, @tree)
      keys = [:source, :target, :x0, :y0, :x1, :y1]
      assert Map.take(swapped, keys) == Map.take(link, keys)
      assert swapped.path.commands == [{:M, y0, x0}, {:C, ym, x0, ym, x1, y1, x1}]

      assert run(%{op: :tree, output: :links, orientation: :vertical}, @tree) ==
               run(%{op: :tree, output: :links}, @tree)

      assert run(%{op: :tree, orientation: :horizontal}, @tree) == run(%{op: :tree}, @tree)

      [cluster | _] = run(%{op: :cluster, output: :links, orientation: :horizontal}, @tree)
      assert [{:M, cy0, cx0}, {:C, _, _, _, _, _, _}] = cluster.path.commands
      assert {cx0, cy0} == {cluster.x0, cluster.y0}
    end

    test ":tree and :cluster links take the elbow or the line of `link` (#127)" do
      [link | _] = run(%{op: :tree, output: :links}, @tree)
      %{x0: x0, y0: y0, x1: x1, y1: y1} = link

      [elbow | _] = run(%{op: :cluster, output: :links, link: :elbow}, @tree)
      assert elbow.path.commands == [{:M, x0, y0}, {:H, x1}, {:V, y1}]

      [swapped | _] =
        run(%{op: :cluster, output: :links, link: :elbow, orientation: :horizontal}, @tree)

      assert swapped.path.commands == [{:M, y0, x0}, {:V, x1}, {:H, y1}]

      [line | _] = run(%{op: :tree, output: :links, link: :line}, @tree)
      assert line.path.commands == [{:M, x0, y0}, {:L, x1, y1}]

      assert run(%{op: :tree, output: :links, link: :curve}, @tree) ==
               run(%{op: :tree, output: :links}, @tree)
    end

    test ":tree links carry the vertical link and :pack links the straight line" do
      [link | _] = run(%{op: :tree, output: :links}, @tree)

      assert %{
               source: "root",
               target: "a",
               path: %Path{commands: [{:M, _, _}, {:C, _, _, _, _, _, _}]}
             } = link

      [link | _] = run(%{op: :pack, output: :links}, @tree)
      assert %{path: %Path{commands: [{:M, _, _}, {:L, _, _}]}} = link
    end

    test ":treemap, :pack and :partition carry their module's fields, and count leaves without a field" do
      rows = run(%{op: :treemap, tile: :slice, padding: 2}, @tree)

      laid =
        @tree
        |> Hierarchy.stratify()
        |> Hierarchy.count()
        |> then(
          &Treemap.generate(
            Treemap.new() |> Treemap.size(@size) |> Treemap.tile(:slice) |> Treemap.padding(2),
            &1
          )
        )

      assert Enum.map(rows, &Map.take(&1, [:x0, :y0, :x1, :y1])) ==
               Enum.map(Hierarchy.descendants(laid), &Map.take(&1, [:x0, :y0, :x1, :y1]))

      packed = run(%{op: :pack, field: :w}, @tree)
      laid = @tree |> Hierarchy.stratify() |> Hierarchy.sum(& &1.w)
      laid = Pack.generate(Pack.size(Pack.new(), @size), laid)
      assert Enum.map(packed, & &1.r) == Enum.map(Hierarchy.descendants(laid), & &1.r)

      assert [%{x0: 0, y0: 0} | _] = run(%{op: :partition}, @tree)
    end

    test "a :size on the node beats the plot and :links is refused where it means nothing" do
      [root | _] = run(%{op: :treemap, size: [10, 10]}, @tree)
      assert root.x1 == 10

      assert_raise ArgumentError, ~r/:treemap yields no :links/, fn ->
        run(%{op: :treemap, output: :links}, @tree)
      end
    end
  end

  describe "graphs" do
    @flows [
      %{from: "a", to: "b", n: 5},
      %{from: "a", to: "c", n: 3},
      %{from: "b", to: "c", n: 2}
    ]

    test ":chord groups and chords are Layout.Chord over the flow matrix, about the centre" do
      groups = run(%{op: :chord, fields: [:from, :to], field: :n, padding: 0.1}, @flows)
      matrix = [[0, 5, 3], [0, 0, 2], [0, 0, 0]]

      %{groups: expected, chords: chords} =
        Chord.new() |> Chord.pad_angle(0.1) |> Chord.generate(matrix)

      assert Enum.map(groups, &{&1.id, &1.start_angle, &1.end_angle, &1.value}) ==
               Enum.map(
                 expected,
                 &{Enum.at(["a", "b", "c"], &1.index), &1.start_angle, &1.end_angle, &1.value}
               )

      assert [%Path{commands: [{:M, x, _} | _]} | _] = Enum.map(groups, & &1.path)
      assert_in_delta x, 100, 50

      ribbons = run(%{op: :chord, fields: [:from, :to], field: :n, output: :chords}, @flows)
      assert length(ribbons) == length(chords)
      assert Enum.map(ribbons, &{&1.source, &1.target}) == [{"a", "b"}, {"a", "c"}, {"b", "c"}]

      assert %{
               path: %Path{
                 commands: [{:M, _, _}, {:A, _, _, _, _, _, _, _}, {:Q, 100.0, 50.0, _, _} | _]
               }
             } = hd(ribbons)
    end

    test ":sankey nodes and links are Layout.Sankey over the derived nodes" do
      nodes = run(%{op: :sankey, fields: [:from, :to], field: :n}, @flows)

      expected =
        Sankey.new()
        |> Sankey.size(200, 100)
        |> Sankey.compute(
          [%{id: "a"}, %{id: "b"}, %{id: "c"}],
          Enum.map(@flows, &%{source: &1.from, target: &1.to, value: &1.n})
        )

      assert Enum.map(nodes, &{&1.id, &1.x0, &1.y0, &1.x1, &1.y1}) ==
               Enum.map(expected.nodes, &{&1.id, &1.x0, &1.y0, &1.x1, &1.y1})

      links = run(%{op: :sankey, fields: [:from, :to], field: :n, output: :links}, @flows)

      assert Enum.map(links, &{&1.source, &1.target, &1.width, &1.y0, &1.y1}) ==
               Enum.map(expected.links, &{&1.source, &1.target, &1.width, &1.y0, &1.y1})

      assert Enum.map(links, &Path.to_string(&1.path)) ==
               Enum.map(expected.links, &Sankey.generate_link_path/1)
    end

    test ":force is the synchronous run with the centre force at the plot centre" do
      nodes = run(%{op: :force, fields: [:from, :to]}, @flows)

      expected =
        Force.run(
          nodes: [%{id: "a"}, %{id: "b"}, %{id: "c"}],
          links: Enum.map(@flows, &%{source: &1.from, target: &1.to}),
          forces: [
            {:center, x: 100.0, y: 50.0},
            {:many_body, strength: -30},
            {:link, distance: 30}
          ]
        )

      assert nodes == Enum.map(expected.nodes, &Map.take(&1, [:id, :x, :y]))
      assert nodes == run(%{op: :force, fields: [:from, :to]}, @flows)

      [link | _] = run(%{op: :force, fields: [:from, :to], output: :links}, @flows)
      assert {link.x0, link.y0} == {hd(nodes).x, hd(nodes).y}
    end
  end

  describe "geo" do
    @points [%{x: 10, y: 10}, %{x: 90, y: 10}, %{x: 50, y: 60}, %{x: 20, y: 80}, %{x: nil, y: 1}]

    test ":projection adds x and y through the projection and drops clipped points" do
      projection = Projection.new(:orthographic) |> Projection.translate(100, 50)
      rows = [%{lon: 10, lat: 20, name: "in"}, %{lon: 170, lat: 0, name: "behind"}]
      [row] = run(%{op: :projection, fields: [:lon, :lat]}, rows, projection: projection)
      assert row.name == "in"
      assert {row.x, row.y} == Projection.project(projection, 10, 20)

      assert_raise ArgumentError, ~r/needs a projection/, fn ->
        run(%{op: :projection, fields: [:lon, :lat]}, rows)
      end
    end

    test ":delaunay triangles and hull are Geo.Delaunay over the placed points" do
      points = [{10, 10}, {90, 10}, {50, 60}, {20, 80}]
      delaunay = Delaunay.new(points)
      triangles = run(%{op: :delaunay, fields: [:x, :y]}, @points)
      assert Enum.map(triangles, & &1.vertices) == Delaunay.triangles(delaunay)
      assert Enum.map(triangles, & &1.index) == [0, 1]

      [%{path: %Path{commands: commands}}] =
        run(%{op: :delaunay, fields: [:x, :y], output: :hull}, @points)

      assert length(commands) == length(Delaunay.hull(delaunay)) + 1
      assert List.last(commands) == :Z
    end

    test ":voronoi cells keep the datum and are clipped to the plot; edges are segments" do
      cells = run(%{op: :voronoi, fields: [:x, :y]}, @points)

      voronoi =
        [{10, 10}, {90, 10}, {50, 60}, {20, 80}]
        |> Voronoi.new()
        |> Voronoi.bounds([0, 0, 200, 100])

      assert Enum.map(cells, & &1.index) == [0, 1, 2, 3]
      assert hd(cells).x == 10

      assert Enum.map(cells, fn c -> for {:L, x, y} <- c.path.commands, do: {x, y} end) ==
               Enum.map(0..3, fn i -> voronoi |> Voronoi.cell(i) |> tl() end)

      edges = run(%{op: :voronoi, fields: [:x, :y], output: :edges}, @points)
      assert Enum.map(edges, &{{&1.x0, &1.y0}, {&1.x1, &1.y1}}) == Voronoi.edges(voronoi)
    end

    test ":contour rings are Contour.compute/2 stretched over the plot" do
      grid = for y <- 0..3, x <- 0..3, do: %{z: if(x in 1..2 and y in 1..2, do: 5, else: 0)}
      rows = run(%{op: :contour, field: :z, size: [4, 4], thresholds: [2.5]}, grid)

      [%{value: 2.5, coordinates: [[ring]]}] =
        Contour.new()
        |> Contour.size(4, 4)
        |> Contour.thresholds([2.5])
        |> Contour.compute(Enum.map(grid, & &1.z))

      [%{value: 2.5, path: path}] = rows
      [{:M, mx, my} | _] = path.commands
      [[x, y] | _] = ring
      assert {mx, my} == {x * 200 / 3, y * 100 / 3}
      assert List.last(path.commands) == :Z
    end

    test ":density is Contour.Density over the placed points on the plot" do
      node = %{op: :density, fields: [:x, :y], field: :w, bandwidth: 5, thresholds: 3}
      points = [%{x: 20, y: 20, w: 2}, %{x: 60, y: 60, w: 1}]
      rows = run(node, points, size: [80, 80])

      expected =
        Density.new()
        |> Density.x(& &1.x)
        |> Density.y(& &1.y)
        |> Density.weight(& &1.w)
        |> Density.size(80, 80)
        |> Density.bandwidth(5)
        |> Density.thresholds(3)
        |> Density.compute(points)

      assert Enum.map(rows, & &1.value) ==
               for(%{value: v, coordinates: polygons} <- expected, _ <- polygons, do: v)

      assert Enum.all?(rows, &(List.last(&1.path.commands) == :Z))
    end
  end

  describe "errors" do
    test "a missing required key, an unknown op and a step without an op raise by name" do
      assert_raise ArgumentError, ~r/transform :bin needs :field/, fn ->
        run(%{op: :bin}, @rows)
      end

      assert_raise ArgumentError, ~r/:nope is not a transform op/, fn ->
        run(%{op: :nope}, @rows)
      end

      assert_raise ArgumentError, ~r/needs an op/, fn -> run(%{field: :v}, @rows) end
    end

    test "apply/2 defaults to the unit size and step/3 is one step" do
      assert Transform.apply([], @rows) == @rows

      assert Transform.step(%{op: :sort, field: :v}, @rows, []) ==
               run(%{op: :sort, field: :v}, @rows)

      assert [%{x1: 1}] = Transform.apply([%{op: :treemap}], [%{id: "r", parent: nil}])
    end
  end
end
