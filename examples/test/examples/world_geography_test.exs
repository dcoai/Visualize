defmodule Examples.WorldGeographyTest do
  @moduledoc """
  The gallery's maps draw Natural Earth's 1:110m land (#499): `land/0` is the stored file,
  one row per feature with a stable id, and the World Map and the Globe render it — the
  Globe animating on the canvas within the light budget its class allows.
  """
  use ExUnit.Case, async: true

  alias Examples.Charts.{Design, Globe, WorldGeography, WorldMap}
  alias Examples.Frames

  @file_path Path.expand("../../priv/geo/ne_110m_land.geojson", __DIR__)

  # The light class's budget of the gallery's cost guard (spec/14 §12.6, #469).
  @light_budget 4_000_000

  defp file_features, do: Jason.decode!(File.read!(@file_path))["features"]

  defp positions(%{"type" => "Polygon", "coordinates" => rings}),
    do: Enum.flat_map(rings, & &1)

  defp positions(%{"type" => "MultiPolygon", "coordinates" => polygons}),
    do: Enum.flat_map(polygons, fn rings -> Enum.flat_map(rings, & &1) end)

  defp box(feature) do
    {lons, lats} =
      feature["geometry"]
      |> positions()
      |> Enum.map(fn [lon, lat | _] -> {lon, lat} end)
      |> Enum.unzip()

    {Enum.min(lons), Enum.min(lats), Enum.max(lons), Enum.max(lats)}
  end

  defp within?({w, s, e, n}, {bw, bs, be, bn}), do: w >= bw and s >= bs and e <= be and n <= bn

  test "land/0 is the stored file: one row per feature, in its order, every position kept" do
    rows = WorldGeography.land()
    features = file_features()

    assert length(rows) == 127
    assert length(rows) == length(features)
    assert Enum.map(rows, & &1.shape) == features

    total = fn shapes -> shapes |> Enum.map(&length(positions(&1["geometry"]))) |> Enum.sum() end
    assert total.(Enum.map(rows, & &1.shape)) == 5143

    for %{shape: shape} <- rows do
      assert %{"type" => "Feature", "geometry" => %{"type" => type}} = shape
      assert type in ["Polygon", "MultiPolygon"]

      # Every ring closed, of at least four positions, in degrees.
      for ring <-
            if(type == "Polygon",
              do: shape["geometry"]["coordinates"],
              else: Enum.concat(shape["geometry"]["coordinates"])
            ) do
        assert length(ring) >= 4
        assert hd(ring) == List.last(ring)

        assert Enum.all?(ring, fn [lon, lat] ->
                 lon >= -180 and lon <= 180 and lat >= -90 and lat <= 90
               end)
      end
    end
  end

  test "a row's name is its stable id, land-<n> by its place in the file" do
    names = Enum.map(WorldGeography.land(), & &1.name)
    assert names == Enum.map(1..127, &"land-#{&1}")
  end

  test "the islands the hand-drawn outlines lacked are there: Iceland and New Zealand's South Island" do
    boxes = Enum.map(WorldGeography.land(), &box(&1.shape))

    assert [_iceland] = Enum.filter(boxes, &within?(&1, {-25, 63, -13, 67}))
    assert [_south_island] = Enum.filter(boxes, &within?(&1, {166, -47, 175, -40}))
  end

  test "the World Map draws every land mass: the ocean, 17 graticule lines, 127 land paths, the rim" do
    svg = WorldMap.render([])
    assert svg =~ "Natural Earth 1:110m"
    assert length(String.split(svg, "<path")) - 1 == 1 + 17 + 127 + 1
  end

  # The land mark's paths, each as its subpaths' vertices: the `mark-path` group drawn with
  # the land's fill opacity (the World Map's 0.8, the Globe's 0.9).
  defp land_subpaths(svg, opacity \\ "0.8") do
    [_, land | _] = String.split(svg, ~s(<g class="mark mark-path" fill-opacity="#{opacity}"))
    [land | _] = String.split(land, "</g>")

    for [d] <- Regex.scan(~r/ d="([^"]*)"/, land, capture: :all_but_first),
        subpath <- String.split(d, "M", trim: true) do
      ~r/-?\d+(?:\.\d+)?/
      |> Regex.scan(subpath)
      |> List.flatten()
      |> Enum.map(&elem(Float.parse(&1), 0))
      |> Enum.chunk_every(2)
    end
  end

  # A ring joined the long way round crosses the map in one edge (spec/07 §2.2.1, #509).
  test "the rotating World Map draws no land edge across the map, at any tick" do
    {width, _} = WorldMap.size()

    for tick <- [0, 15, 45, 90, 135, 179] do
      subpaths = land_subpaths(WorldMap.render(animation_tick: tick))
      assert length(subpaths) >= 127

      longest =
        subpaths
        |> Enum.flat_map(fn points -> Enum.zip(points, tl(points)) end)
        |> Enum.map(fn {[x0, _], [x1, _]} -> abs(x1 - x0) end)
        |> Enum.max()

      assert longest < width / 2, "tick #{tick}: a land edge #{longest} wide on a #{width} map"
    end
  end

  test "every land mass draws under the uncircled projections at any rotation, no edge across the map" do
    land = WorldGeography.land()

    for type <- [:natural_earth, :equirectangular, :mollweide, :mercator],
        rotate <- [{0, 0, 0}, {45, 0, 0}, {90, 0, 0}, {180, 0, 0}, {-135, 0, 0}, {30, 20, 10}] do
      {lambda, phi, gamma} = rotate

      projection =
        Visualize.Geo.Projection.new(type)
        |> Visualize.Geo.Projection.scale(100)
        |> Visualize.Geo.Projection.translate(350, 200)
        |> Visualize.Geo.Projection.rotate(lambda, phi, gamma)

      geo = Visualize.Geo.Path.new(projection)

      for %{name: name, shape: shape} <- land do
        commands = Visualize.Geo.Path.path(geo, shape).commands
        assert commands != [], "#{type} #{inspect(rotate)}: #{name} drew nothing"

        edges =
          for [{_, x0, _}, {:L, x1, _}] <- Enum.chunk_every(commands, 2, 1, :discard),
              do: abs(x1 - x0)

        # The map is 2π · 100 wide on the equirectangular, the widest of the four.
        assert Enum.max(edges, fn -> 0 end) < 100 * :math.pi(),
               "#{type} #{inspect(rotate)}: #{name} has an edge across the map"
      end
    end
  end

  test "at tick 45 the seam cuts land, and Antarctica still closes along the map's foot" do
    {width, _} = WorldMap.size()
    subpaths = land_subpaths(WorldMap.render(animation_tick: 45))

    # More rings than features: the seam at 90° west cuts the Americas and Antarctica.
    assert length(subpaths) > 127

    # The ring that reaches the south pole's line runs along it from one side of the seam
    # to the other: Antarctica, cut and rejoined, wider than half the map. Joined the long
    # way round it would be slabs that never reach the pole.
    foot = fn points -> points |> Enum.map(&Enum.at(&1, 1)) |> Enum.max() end
    antarctica = Enum.max_by(subpaths, foot)
    {xs, _} = antarctica |> Enum.map(&List.to_tuple/1) |> Enum.unzip()
    assert Enum.max(xs) - Enum.min(xs) > width / 2
    assert Enum.count(antarctica, &(Enum.at(&1, 1) == foot.(antarctica))) > 100
  end

  test "the Globe draws the near hemisphere's land and credits the data" do
    svg = Globe.render([])
    assert svg =~ "Natural Earth 1:110m"
    # The far hemisphere's land masses draw nothing, so fewer than all of them.
    land_paths = length(String.split(svg, "<path")) - 1 - 2 - 17
    assert land_paths > 20 and land_paths < 127
  end

  # #522, D-130: the land is filled through an inferred ordinal domain. When the projection
  # dropped the rows it clipped, the domain was whichever land masses faced the viewer —
  # 46, 73 and 106 of the 127 at these ticks — and a land mass's color moved as it turned.
  test "the Globe's color domain is every land mass, in one order, whatever the viewpoint" do
    names = Enum.map(WorldGeography.land(), & &1.name)

    scales =
      for tick <- [0, 40, 80] do
        Design.applied(Globe, animation_tick: tick).frame.scales["color"]
      end

    for scale <- scales, do: assert(scale.domain == names)

    # So each land mass keeps one color through the animation.
    colors = for scale <- scales, do: Enum.map(names, &Visualize.Scale.apply(scale, &1))
    assert length(Enum.uniq(colors)) == 1
  end

  # The Globe's disc: the plot's center, and the radius `design/1` gives the orthographic.
  defp globe_disc do
    {width, height} = Globe.size()
    {{width / 2, height / 2}, min(width, height) / 2 - 20}
  end

  # A land mass crossing the horizon is closed along it (spec/07 §2.2.1, #510). Before the
  # small-circle clip the vertices behind it were dropped and their neighbors joined, so
  # the land closed by chords through the disc — the Americas a wedge across the North
  # Atlantic at tick 0. No edge of Natural Earth 1:110m is longer than about 18 px on this
  # disc, so an edge longer than 24 px is either the horizon or a chord: it must lie on the
  # rim, both ends and its midpoint within half a pixel of it, which no chord does.
  test "the Globe closes its land along the horizon, never by a chord across the disc, at any tick" do
    {{cx, cy}, r} = globe_disc()
    off_rim = fn [x, y] -> abs(:math.sqrt((x - cx) ** 2 + (y - cy) ** 2) - r) end

    for tick <- 0..179//3 do
      subpaths = land_subpaths(Globe.render(animation_tick: tick), "0.9")

      for points <- subpaths,
          {a, b} <- Enum.zip(points, tl(points) ++ [hd(points)]),
          [[x0, y0], [x1, y1]] = [a, b],
          :math.sqrt((x1 - x0) ** 2 + (y1 - y0) ** 2) > 24 do
        mid = [(x0 + x1) / 2, (y0 + y1) / 2]

        assert off_rim.(a) < 0.5 and off_rim.(b) < 0.5 and off_rim.(mid) < 0.5,
               "tick #{tick}: a land edge #{inspect(a)} → #{inspect(b)} cuts across the disc"
      end
    end

    # At tick 0 the Americas and Afro-Eurasia cross the horizon: their rings run along it,
    # the 2° steps of d3's circle, many points on the rim one after another.
    rim_runs =
      for points <- land_subpaths(Globe.render(animation_tick: 0), "0.9") do
        points
        |> Enum.chunk_by(&(off_rim.(&1) < 0.01))
        |> Enum.filter(&(off_rim.(hd(&1)) < 0.01))
        |> Enum.map(&length/1)
        |> Enum.max(fn -> 0 end)
      end

    assert Enum.count(rim_runs, &(&1 >= 10)) >= 2
  end

  test "every land mass draws under the circled projections at any rotation" do
    land = WorldGeography.land()

    for type <- [
          :orthographic,
          :stereographic,
          :gnomonic,
          :azimuthal_equal_area,
          :azimuthal_equidistant
        ],
        rotate <- [{0, 0, 0}, {45, -20, 0}, {90, 30, 0}, {180, 0, 0}, {-135, 60, 10}] do
      {lambda, phi, gamma} = rotate

      projection =
        Visualize.Geo.Projection.new(type)
        |> Visualize.Geo.Projection.scale(100)
        |> Visualize.Geo.Projection.translate(350, 200)
        |> Visualize.Geo.Projection.rotate(lambda, phi, gamma)

      geo = Visualize.Geo.Path.new(projection)
      drawn = Enum.count(land, &(Visualize.Geo.Path.path(geo, &1.shape).commands != []))
      # Some land is always in view; a whole-sphere azimuthal shows all of it.
      assert drawn > 0, "#{type} #{inspect(rotate)}: no land drew"

      if type in [:azimuthal_equal_area, :azimuthal_equidistant],
        do: assert(drawn == length(land), "#{type} #{inspect(rotate)}: #{drawn} drew")
    end
  end

  test "the Globe animates on the canvas, each tick within the light budget" do
    state = Frames.prepare(Globe, [animation_tick: 0], :canvas)

    {canvases, _state} =
      Enum.map_reduce([0, 1, 2, 30], state, fn tick, state ->
        {work, {frame, state}} =
          Visualize.Work.reductions(fn ->
            Frames.frame(Globe, [animation_tick: tick], :canvas, state)
          end)

        assert work <= @light_budget, "tick #{tick} cost #{work} reductions"
        [%{canvas: canvas}] = frame.plots
        assert is_binary(canvas) and byte_size(canvas) > 0
        {canvas, state}
      end)

    # The globe turns: no two ticks draw the same picture.
    assert length(Enum.uniq(canvases)) == length(canvases)
  end

  # Both maps turn as the Earth does (#523): the land drifts east, so Greenwich on the
  # equator moves right from one tick to the next.
  for chart <- [WorldMap, Globe] do
    test "#{inspect(chart)} turns the way the Earth does, the land drifting east" do
      greenwich_x = fn tick ->
        {design, sources} = unquote(chart).design(animation_tick: tick)
        {:ok, applied} = Visualize.Chart.apply(design, sources: sources)
        projection = Visualize.Chart.Frame.projection(applied.frame)
        {x, _y} = Visualize.Geo.Projection.project(projection, 0, 0)
        x
      end

      assert greenwich_x.(10) > greenwich_x.(0)
    end
  end
end
