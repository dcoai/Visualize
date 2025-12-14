defmodule VisualizeTest do
  use ExUnit.Case

  describe "SVG" do
    alias Visualize.SVG
    alias Visualize.SVG.{Element, Path, Renderer}

    test "creates SVG elements" do
      svg = SVG.new(width: 400, height: 300)
      assert svg.tag == :svg
      assert svg.attrs.width == 400
      assert svg.attrs.height == 300
    end

    test "renders elements to string" do
      rect = Element.rect(%{x: 10, y: 20, width: 100, height: 50})
      result = Renderer.render_to_string(rect)
      assert result =~ ~r/<rect.*x="10".*\/>/
    end

    test "builds path commands" do
      path = Path.new()
        |> Path.move_to(10, 20)
        |> Path.line_to(100, 200)
        |> Path.close()

      assert Path.to_string(path) == "M10,20L100,200Z"
    end

    test "appends children" do
      svg = SVG.new()
        |> SVG.append(:rect, x: 0, y: 0, width: 50, height: 50)
        |> SVG.append(:circle, cx: 100, cy: 100, r: 25)

      assert length(svg.children) == 2
    end
  end

  describe "Scale.Linear" do
    alias Visualize.Scale

    test "maps domain to range" do
      scale = Scale.linear()
        |> Scale.domain([0, 100])
        |> Scale.range([0, 500])

      assert Scale.apply(scale, 0) == 0.0
      assert Scale.apply(scale, 50) == 250.0
      assert Scale.apply(scale, 100) == 500.0
    end

    test "inverts range to domain" do
      scale = Scale.linear()
        |> Scale.domain([0, 100])
        |> Scale.range([0, 500])

      assert Scale.invert(scale, 250) == 50.0
    end

    test "generates nice ticks" do
      scale = Scale.linear()
        |> Scale.domain([0, 97])
        |> Scale.range([0, 500])

      ticks = Scale.ticks(scale, 5)
      assert is_list(ticks)
      assert length(ticks) > 0
    end

    test "extends domain to nice values" do
      scale = Scale.linear()
        |> Scale.domain([0.5, 97.3])
        |> Scale.nice()

      [d0, d1] = scale.domain
      assert d0 == 0.0
      assert d1 == 100.0
    end
  end

  describe "Scale.Band" do
    alias Visualize.Scale

    test "maps categories to positions" do
      scale = Scale.band()
        |> Scale.domain(["A", "B", "C"])
        |> Scale.range([0, 300])

      assert Scale.apply(scale, "A") == 0
      assert Scale.apply(scale, "B") == 100
      assert Scale.apply(scale, "C") == 200
    end

    test "calculates bandwidth" do
      scale = Scale.band()
        |> Scale.domain(["A", "B", "C"])
        |> Scale.range([0, 300])

      assert Scale.bandwidth(scale) == 100
    end

    test "respects padding" do
      scale = Scale.band()
        |> Scale.domain(["A", "B"])
        |> Scale.range([0, 200])
        |> Scale.padding(0.5)

      bandwidth = Scale.bandwidth(scale)
      assert bandwidth < 100
    end
  end

  describe "Shape.Line" do
    alias Visualize.Shape

    test "generates path from data" do
      data = [{0, 0}, {10, 10}, {20, 5}]

      line = Shape.line()
      path = Shape.generate(line, data)

      assert path =~ "M0,0"
      assert path =~ "L10,10"
      assert path =~ "L20,5"
    end

    test "uses custom accessors" do
      data = [
        %{x: 0, y: 100},
        %{x: 50, y: 50},
        %{x: 100, y: 75}
      ]

      line = Shape.line()
        |> Shape.x(fn d -> d.x end)
        |> Shape.y(fn d -> d.y end)

      path = Shape.generate(line, data)

      assert path =~ "M0,100"
    end
  end

  describe "Shape.Pie" do
    alias Visualize.Shape

    test "computes angles from data" do
      data = [10, 20, 30]

      pie = Shape.pie()
      arcs = Shape.generate(pie, data)

      assert length(arcs) == 3
      assert Enum.all?(arcs, &Map.has_key?(&1, :start_angle))
      assert Enum.all?(arcs, &Map.has_key?(&1, :end_angle))
    end

    test "preserves original data" do
      data = [%{name: "A", value: 10}, %{name: "B", value: 20}]

      pie = Shape.pie()
        |> Shape.value(fn d -> d.value end)

      arcs = Shape.generate(pie, data)

      assert Enum.at(arcs, 0).data.name == "A"
    end
  end

  describe "Axis" do
    alias Visualize.{Scale, Axis}

    test "generates axis elements" do
      scale = Scale.linear()
        |> Scale.domain([0, 100])
        |> Scale.range([0, 500])

      axis = Axis.bottom(scale)
        |> Axis.ticks(5)

      element = Axis.generate(axis)

      assert element.tag == :g
      assert length(element.children) > 1  # domain + ticks
    end
  end

  describe "Data" do
    alias Visualize.Data

    test "calculates extent" do
      assert Data.extent([3, 1, 4, 1, 5, 9]) == {1, 9}
    end

    test "calculates extent with accessor" do
      data = [%{v: 3}, %{v: 1}, %{v: 4}]
      assert Data.extent(data, & &1.v) == {1, 4}
    end

    test "calculates mean" do
      assert Data.mean([1, 2, 3, 4, 5]) == 3.0
    end

    test "groups data" do
      data = [
        %{cat: "A", val: 1},
        %{cat: "A", val: 2},
        %{cat: "B", val: 3}
      ]

      grouped = Data.group(data, & &1.cat)

      assert length(grouped["A"]) == 2
      assert length(grouped["B"]) == 1
    end

    test "rolls up data" do
      data = [
        %{cat: "A", val: 1},
        %{cat: "A", val: 2},
        %{cat: "B", val: 3}
      ]

      rolled = Data.rollup(data, & &1.cat, &length/1)

      assert rolled["A"] == 2
      assert rolled["B"] == 1
    end

    test "creates bins" do
      data = Enum.to_list(1..100)
      bins = Data.bin(data, thresholds: 10)

      assert length(bins) == 10
      assert Enum.all?(bins, &Map.has_key?(&1, :x0))
    end
  end

  describe "Format" do
    alias Visualize.Format

    test "formats numbers with separators" do
      assert Format.number(1234567) =~ "1,234,567"
    end

    test "formats SI prefixes" do
      assert Format.si(1_500_000) =~ "M"
      assert Format.si(1500) =~ "k"
    end

    test "formats percentages" do
      assert Format.percent(0.1234) =~ "12"
      assert Format.percent(0.1234) =~ "%"
    end

    test "creates formatter functions" do
      formatter = Format.formatter(".2s")
      result = formatter.(1_234_567)
      assert result =~ "M"
    end
  end

  describe "Force Layout" do
    alias Visualize.Layout.Force

    test "runs simulation synchronously" do
      nodes = [
        %{id: "a"},
        %{id: "b"},
        %{id: "c"}
      ]

      links = [
        %{source: "a", target: "b"},
        %{source: "b", target: "c"}
      ]

      result = Force.run(
        nodes: nodes,
        links: links,
        iterations: 50
      )

      assert length(result.nodes) == 3
      assert Enum.all?(result.nodes, &Map.has_key?(&1, :x))
      assert Enum.all?(result.nodes, &Map.has_key?(&1, :y))
    end
  end
end
