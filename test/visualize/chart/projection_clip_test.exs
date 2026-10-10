defmodule Visualize.Chart.ProjectionClipTest do
  @moduledoc """
  #522, D-130: a `:projection` step's clip hides a row, it does not drop it (spec/14
  §5.4.4). The row stays with `nil` positions, so domain inference sees it whatever the
  view (§4.3), and every mark draws nothing for it on every backend (§5.2): a clipped row
  draws exactly what its absence draws, with no empty `<path d="">` left behind.
  """
  use ExUnit.Case, async: true

  alias Visualize.Backend.Canvas
  alias Visualize.Backend.CanvasBinary.Decoder
  alias Visualize.Chart
  alias Visualize.Chart.{Compiled, Transform}
  alias Visualize.Geo.{Delaunay, Projection}
  alias Visualize.IR.{Element, Path}

  # The orthographic shows the hemisphere about (0°, 0°): longitude 170 is behind it.
  @frame %{kind: :geo, projection: %{type: :orthographic, scale: 80}}
  @near %{"type" => "Polygon", "coordinates" => [[[0, 0], [10, 10], [10, 0], [0, 0]]]}
  @behind %{"type" => "Polygon", "coordinates" => [[[170, 0], [175, 5], [175, 0], [170, 0]]]}

  @points [
    %{lon: 0, lat: 0, name: "a", g: "front"},
    %{lon: 170, lat: 0, name: "behind", g: "front"},
    %{lon: 10, lat: 10, name: "c", g: "front"},
    %{lon: 20, lat: -10, name: "d", g: "front"},
    %{lon: 175, lat: 5, name: "far", g: "back"},
    %{lon: 160, lat: -5, name: "farther", g: "back"}
  ]

  @shapes [%{name: "near", shape: @near}, %{name: "behind", shape: @behind}]

  defp clipped?(%{lon: lon}), do: lon > 90
  defp clipped?(%{shape: shape}), do: shape == @behind

  defp visible(rows), do: Enum.reject(rows, &clipped?/1)

  # Every mark that draws rows over the two projected sources, each with a constant paint
  # so the drawing reads no domain, and the tooltip's datum attributes on the circles.
  defp design(render \\ :auto) do
    points = %{source: :points, transforms: [%{op: :projection, fields: [:lon, :lat]}]}
    shapes = %{source: :shapes, transforms: [%{op: :projection, field: :shape}]}

    %{
      version: 2,
      sources: %{points: %{fields: [:lon, :lat, :name, :g]}, shapes: %{fields: [:name, :shape]}},
      styles: %{
        land: %{fill: "#88aa66", stroke: "#000000"},
        dot: %{fill: "#3366cc"},
        route: %{stroke: "#cc3333"}
      },
      frames: %{main: @frame},
      marks: [
        %{type: :path, data: shapes, channels: %{path: :path}, style: :land, render: render},
        %{
          type: :circle,
          data: points,
          channels: %{x: :x, y: :y},
          style: :dot,
          label: %{text: [{:field, :name}]},
          tooltip: %{fields: [:name]},
          render: render
        },
        %{type: :symbol, data: points, channels: %{x: :x, y: :y}, style: :dot, render: render},
        %{type: :text, data: points, channels: %{x: :x, y: :y, value: :name}},
        %{
          type: :line,
          data: points,
          channels: %{x: :x, y: :y, series: :g},
          style: :route,
          render: render
        }
      ]
    }
  end

  defp applied(points, shapes) do
    {:ok, applied} =
      Chart.apply(Chart.from_map!(design()),
        sources: %{points: points, shapes: shapes},
        size: {400, 300}
      )

    applied
  end

  # The front series without its clipped point, so its line has nothing to break at: the
  # comparisons below are about what a clipped row adds, which must be nothing.
  defp unbroken(rows), do: Enum.reject(rows, &(&1.name == "behind"))

  describe "the rows" do
    test "a clipped point and a clipped geometry keep their rows with nil channels" do
      projection = Projection.new(:orthographic)
      opts = [projection: projection, size: [400, 300]]

      points = Transform.apply([%{op: :projection, fields: [:lon, :lat]}], @points, opts)
      assert Enum.map(points, & &1.name) == Enum.map(@points, & &1.name)

      for row <- points do
        if clipped?(row),
          do: assert({row.x, row.y} == {nil, nil}),
          else: assert({row.x, row.y} == Projection.project(projection, row.lon, row.lat))
      end

      [near, behind] = Transform.apply([%{op: :projection, field: :shape}], @shapes, opts)
      assert %Path{commands: [_ | _]} = near.path
      assert %{name: "behind", path: nil, x: nil, y: nil} = behind
    end

    test "a missing or non-numeric coordinate, and a geometry that is not a map, are dropped" do
      opts = [projection: Projection.new(:orthographic), size: [400, 300]]
      bad = [%{lon: nil, lat: 0}, %{lon: 0, lat: "0"}, %{lat: 0}]
      assert Transform.apply([%{op: :projection, fields: [:lon, :lat]}], bad, opts) == []

      shapes = [%{shape: nil}, %{shape: "Polygon"}, %{}]
      assert Transform.apply([%{op: :projection, field: :shape}], shapes, opts) == []
    end
  end

  describe "every backend draws nothing for a clipped row" do
    test "SVG: no element, label, tooltip attribute or empty path for it" do
      svg = Chart.render(applied(unbroken(@points), @shapes), resolve: :literal)

      refute svg =~ ~s(d="")
      refute svg =~ "behind"
      refute svg =~ "far"
      refute svg =~ ~s(data-series="back")
      assert length(Regex.scan(~r/<circle /, svg)) == 3
      assert length(Regex.scan(~r/data-datum-name=/, svg)) == 3

      assert svg ==
               Chart.render(applied(visible(@points), visible(@shapes)), resolve: :literal)
    end

    test "Canvas: the commands are those of the visible rows alone" do
      draw = fn applied ->
        applied |> Chart.generate(resolve: :literal) |> Canvas.render_element(format: :commands)
      end

      commands = draw.(applied(unbroken(@points), @shapes))
      assert commands == draw.(applied(visible(@points), visible(@shapes)))
      refute empty_canvas_path?(commands)
    end

    test "CanvasBinary: the records are those of the visible rows alone, with no empty path" do
      draw = fn applied ->
        applied |> Chart.render(backend: :canvas, format: :binary) |> Decoder.decode()
      end

      records = draw.(applied(unbroken(@points), @shapes))
      assert records == draw.(applied(visible(@points), visible(@shapes)))
      refute Enum.any?(records, &match?({kind, []} when kind in [:path, :path32], &1))
      refute Enum.any?(records, &match?({kind, []} when kind in [:path_cubic, :path_cubic32], &1))
    end

    test "Hybrid: the tick's SVG and canvas layers are those of the visible rows alone" do
      tick = fn points, shapes ->
        {:ok, frames} =
          Chart.compile(Chart.from_map!(design(:binary)),
            sources: %{points: points, shapes: shapes},
            size: {400, 300}
          )

        [compiled] = Map.values(frames)
        {payload, _} = Compiled.tick(compiled, %{points: points, shapes: shapes})
        payload
      end

      payload = tick.(unbroken(@points), @shapes)
      visible = tick.(visible(@points), visible(@shapes))

      assert payload.svg == visible.svg

      assert Decoder.decode(Base.decode64!(payload.canvas)) ==
               Decoder.decode(Base.decode64!(visible.canvas))

      refute payload.svg =~ ~s(d="")
      refute payload.svg =~ "behind"
    end
  end

  test "the generated IR holds no empty path" do
    group = Chart.generate(applied(@points, @shapes), resolve: :literal)
    refute Enum.any?(leaves(group), &match?(%Element{type: :path, path: %Path{commands: []}}, &1))
  end

  test "a line breaks at a clipped point rather than joining across it" do
    svg = Chart.render(applied(@points, @shapes), resolve: :literal)

    [d] = Regex.run(~r/<path d="([^"]*)" data-series="front"/, svg, capture: :all_but_first)
    # `a` alone before the clipped point, then `c` to `d`: a lone point draws no segment, so
    # the path is the one subpath after the break.
    assert [_, _] = Regex.scan(~r/-?[\d.]+,-?[\d.]+/, d)
    assert d =~ ~r/^M[^ML]+L[^ML]+$/

    # Without the clipped row the same line joins a to c: the break is the clip's.
    joined = Chart.render(applied(unbroken(@points), @shapes), resolve: :literal)
    [d] = Regex.run(~r/<path d="([^"]*)" data-series="front"/, joined, capture: :all_but_first)
    assert length(Regex.scan(~r/L/, d)) == 2
  end

  test "a line or an area that places no point draws no element" do
    rows = [%{lon: 170, lat: 0}, %{lon: 175, lat: 5}]
    data = %{source: :points, transforms: [%{op: :projection, fields: [:lon, :lat]}]}

    for type <- [:line, :area] do
      design = %{
        version: 2,
        sources: %{points: %{fields: [:lon, :lat]}},
        frames: %{main: @frame},
        marks: [%{type: type, data: data, channels: %{x: :x, y: :y}}]
      }

      {:ok, applied} = Chart.apply(Chart.from_map!(design), sources: %{points: rows})
      svg = Chart.render(applied, resolve: :literal)
      refute svg =~ "<path", "#{type}: #{svg}"
    end
  end

  test ":delaunay after a projection drops the clipped point" do
    projection = Projection.new(:orthographic) |> Projection.scale(80)
    opts = [projection: projection, size: [400, 300]]

    steps = [
      %{op: :projection, fields: [:lon, :lat]},
      %{op: :delaunay, fields: [:x, :y]}
    ]

    triangles = Transform.apply(steps, @points, opts)
    assert triangles == Transform.apply(steps, visible(@points), opts)

    expected =
      @points
      |> visible()
      |> Enum.map(&Projection.project(projection, &1.lon, &1.lat))
      |> Delaunay.new()
      |> Delaunay.triangles()

    assert Enum.map(triangles, & &1.vertices) == expected
  end

  # A canvas path that begins and is painted with nothing drawn into it.
  defp empty_canvas_path?(commands) do
    commands
    |> Enum.map(&elem(&1, 0))
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.any?(fn [a, b] -> a == :beginPath and b in [:fill, :stroke] end)
  end

  defp leaves(%Element{children: []} = element), do: [element]
  defp leaves(%Element{children: children}), do: Enum.flat_map(children, &leaves/1)
end
