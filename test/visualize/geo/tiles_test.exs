defmodule Visualize.Geo.TilesTest do
  @moduledoc """
  The Web-Mercator tile arithmetic of spec/07 §8 (#475), held to the standard slippy-map
  formulas computed independently here: the zoom, the covering set and its offsets for a
  fixed centre, zoom and size, the alignment of a projected point with its tile, the
  wrap, the subdomain rotation, and the projection-aware fit of spec/07 §1.6.
  """
  use ExUnit.Case, async: true

  alias Visualize.Geo.{Projection, Tiles}

  doctest Tiles
  doctest Projection, only: [fit: 3]

  @tau 2 * :math.pi()

  # The slippy-map formulas: a point's world pixel at zoom `z` (256-pixel tiles).
  defp world_px(lon, lat, z) do
    n = Integer.pow(2, z) * 256
    phi = lat * :math.pi() / 180
    x = (lon + 180) / 360 * n
    y = (1 - :math.log(:math.tan(phi) + 1 / :math.cos(phi)) / :math.pi()) / 2 * n
    {x, y}
  end

  # The slippy tile of a point at zoom `z`, and its fractions within it.
  defp slippy(lon, lat, z) do
    {x, y} = world_px(lon, lat, z)
    {floor(x / 256), floor(y / 256), x / 256 - floor(x / 256), y / 256 - floor(y / 256)}
  end

  # A Mercator projection whose world is `world` pixels wide, with (lon0, lat0) at the
  # plot pixel (cx, cy): the centre's longitude shifts the map, its latitude through the
  # translate, so the projection stays tile-aligned.
  defp view(lon0, lat0, world, {cx, cy}) do
    k = world / @tau
    phi = lat0 * :math.pi() / 180
    merc = :math.log(:math.tan(:math.pi() / 4 + phi / 2))

    Projection.new(:mercator)
    |> Projection.scale(k)
    |> Projection.center(lon0, 0)
    |> Projection.translate(cx, cy + k * merc)
  end

  describe "zoom/2" do
    test "a world of 256 · 2^z pixels is zoom z" do
      for z <- [0, 3, 12, 17] do
        assert Tiles.zoom(view(0, 0, 256 * Integer.pow(2, z), {0, 0})) == z
      end
    end

    test "a fractional zoom takes the nearest level, half away from zero" do
      at = fn factor -> Tiles.zoom(view(0, 0, 256 * 1024 * factor, {0, 0})) end
      assert at.(1.3) == 10
      assert at.(1.5) == 11
      assert at.(:math.sqrt(2)) == 11
      assert at.(0.75) == 10
    end

    test "it is clamped to [0, max_zoom]" do
      assert Tiles.zoom(view(0, 0, 40, {0, 0})) == 0
      assert Tiles.zoom(view(0, 0, 256 * Integer.pow(2, 22), {0, 0})) == 19
      assert Tiles.zoom(view(0, 0, 256 * Integer.pow(2, 22), {0, 0}), max_zoom: 16) == 16
    end
  end

  describe "cover/3" do
    test "the covering set and offsets for a fixed centre, zoom and size" do
      {lon0, lat0, z, {w, h}} = {-0.1276, 51.5072, 12, {640, 480}}
      proj = view(lon0, lat0, 256 * Integer.pow(2, z), {w / 2, h / 2})

      # Independently: the plot's top-left in world pixels, and the tiles it touches.
      {xc, yc} = world_px(lon0, lat0, z)
      {ox, oy} = {xc - w / 2, yc - h / 2}
      columns = floor(ox / 256)..(ceil((ox + w) / 256) - 1)
      rows = floor(oy / 256)..(ceil((oy + h) / 256) - 1)

      expected =
        for j <- rows, i <- columns, do: {z, i, j, i * 256 - ox, j * 256 - oy, 256.0}

      tiles = Tiles.cover(proj, {w, h})
      assert length(tiles) == length(expected)
      # London is tile 12/2046/1362; a 640 × 480 view about it spans columns 2045–2047
      # and rows 1361–1362.
      assert Enum.map(tiles, & &1.x) |> Enum.uniq() == [2045, 2046, 2047]
      assert Enum.map(tiles, & &1.y) |> Enum.uniq() == [1361, 1362]

      for {tile, {ez, ex, ey, left, top, size}} <- Enum.zip(tiles, expected) do
        assert {tile.z, tile.x, tile.y} == {ez, ex, ey}
        assert_in_delta tile.left, left, 1.0e-6
        assert_in_delta tile.top, top, 1.0e-6
        assert_in_delta tile.size, size, 1.0e-9
      end
    end

    test "a tile only touching the plot's edge is not in the set" do
      # The world at zoom 1 exactly fills a 512 plot: four tiles, no fifth column or row.
      proj = view(0, 0, 512, {256, 256})
      tiles = Tiles.cover(proj, {512, 512})
      assert Enum.map(tiles, &{&1.x, &1.y}) == [{0, 0}, {1, 0}, {0, 1}, {1, 1}]

      assert Enum.map(tiles, &{&1.left, &1.top}) == [
               {0.0, 0.0},
               {256.0, 0.0},
               {0.0, 256.0},
               {256.0, 256.0}
             ]
    end

    test "rows stop at the Mercator square, and a column past the antimeridian wraps" do
      # The world at zoom 1 is 512 px; a 1200 × 900 plot centred on 180° shows it more
      # than twice across and runs past both poles.
      proj = view(180, 0, 512, {600, 450})
      tiles = Tiles.cover(proj, {1200, 900})

      assert Enum.uniq(Enum.map(tiles, & &1.y)) == [0, 1]
      assert Enum.all?(tiles, &(&1.x in [0, 1]))
      lefts = tiles |> Enum.filter(&(&1.y == 0)) |> Enum.map(& &1.left)
      assert lefts == Enum.sort(lefts)
      assert Enum.map(Enum.filter(tiles, &(&1.y == 0)), & &1.x) == [1, 0, 1, 0, 1, 0]
      # Tile 0 starts at the antimeridian, which the centre puts at x = 600.
      assert Enum.any?(tiles, &(&1.x == 0 and &1.y == 0 and abs(&1.left - 600) < 1.0e-9))
    end

    test "a fractional zoom scales the tiles to the projection" do
      proj = view(10, 45, 256 * 1024 * 1.3, {200, 150})
      [tile | _] = Tiles.cover(proj, {400, 300})
      assert tile.z == 10
      assert_in_delta tile.size, 256 * 1.3, 1.0e-9
    end

    test "a rotation's lambda shifts the map as the centre's longitude does" do
      by_center = view(30, 20, 256 * 64, {100, 100})
      by_rotate = %{by_center | center: {0, 0}, rotate: {30, 0, 0}}
      assert Tiles.cover(by_center, {200, 200}) == Tiles.cover(by_rotate, {200, 200})
    end

    test "a projection that is not tile-aligned is refused" do
      assert_raise ArgumentError, ~r/tile-aligned/, fn ->
        Tiles.cover(Projection.new(:equirectangular), {100, 100})
      end
    end
  end

  describe "alignment" do
    test "a projected point lands where its slippy tile and fraction put it" do
      views = [
        {view(-0.1276, 51.5072, 256 * 4096, {320, 240}), {640, 480}},
        # A fractional zoom: the tiles are scaled, the alignment holds.
        {view(13.4, 52.52, 256 * 4096 * 1.37, {300, 200}), {600, 400}},
        {view(-122.42, 37.77, 256 * 256 * 0.8, {250, 250}), {500, 500}}
      ]

      for {proj, {w, h}} <- views do
        tiles = Tiles.cover(proj, {w, h})
        %{z: z} = hd(tiles)
        {c_lon, c_lat} = Projection.invert(proj, w / 2, h / 2)

        for {dlon, dlat} <- [{0, 0}, {0.01, -0.007}, {-0.02, 0.013}, {0.004, 0.009}] do
          {lon, lat} =
            {c_lon + dlon * 4096 / Integer.pow(2, z), c_lat + dlat * 4096 / Integer.pow(2, z)}

          {px, py} = Projection.project(proj, lon, lat)
          {tx, ty, fx, fy} = slippy(lon, lat, z)
          tile = Enum.find(tiles, &(&1.x == tx and &1.y == ty))
          assert tile, "no tile #{z}/#{tx}/#{ty} in the covering set"
          assert_in_delta tile.left + fx * tile.size, px, 1.0e-6
          assert_in_delta tile.top + fy * tile.size, py, 1.0e-6
        end
      end
    end
  end

  describe "url/3" do
    test "z, x and y are the tile's, and {s} rotates by (x + y) mod n" do
      template = "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"

      assert Tiles.url(template, %{z: 12, x: 2046, y: 1361}, ["a", "b", "c"]) ==
               "https://c.tile.openstreetmap.org/12/2046/1361.png"

      subs = for x <- 0..2, y <- 0..1, do: Tiles.url("{s}", %{z: 1, x: x, y: y}, ["a", "b", "c"])
      assert subs == ["a", "b", "b", "c", "c", "a"]
      assert Tiles.url("/{z}/{x}/{y}", %{z: 3, x: 1, y: 2}, []) == "/3/1/2"
    end

    test "{s} with no subdomains is refused" do
      assert_raise ArgumentError, ~r/subdomain/, fn ->
        Tiles.url("https://{s}.t/{z}/{x}/{y}", %{z: 0, x: 0, y: 0}, [])
      end
    end
  end

  describe "aligned/1" do
    test "a Mercator projection with no centre latitude and no tilt or roll" do
      merc = Projection.new(:mercator)
      assert Tiles.aligned(merc) == :ok
      assert Tiles.aligned(Projection.center(merc, 40, 0)) == :ok
      assert Tiles.aligned(Projection.rotate(merc, 40, 0)) == :ok

      assert Tiles.aligned(Projection.new(:equirectangular)) ==
               {:error, {:type, :equirectangular}}

      assert Tiles.aligned(Projection.center(merc, 0, 10)) == {:error, :center}
      assert Tiles.aligned(Projection.rotate(merc, 0, 10)) == {:error, :rotate}
      assert Tiles.aligned(Projection.rotate(merc, 0, 0, 5)) == {:error, :rotate}
    end
  end

  describe "Projection.fit/3" do
    test "the points' projected bounds fill the box on the tighter axis, centred" do
      points = [{-0.13, 51.50}, {-0.10, 51.52}, {-0.12, 51.51}]
      proj = Projection.fit(Projection.new(:mercator), [[10, 10], [390, 290]], points)
      assert proj.center == {0, 0}
      assert Tiles.aligned(proj) == :ok

      {xs, ys} =
        points |> Enum.map(&Projection.project(proj, elem(&1, 0), elem(&1, 1))) |> Enum.unzip()

      {x0, x1} = Enum.min_max(xs)
      {y0, y1} = Enum.min_max(ys)
      # Taller than wide in Mercator pixels at this latitude: the height fills the box,
      # the width is centred within it.
      assert_in_delta y0, 10, 1.0e-6
      assert_in_delta y1, 290, 1.0e-6
      assert_in_delta (x0 + x1) / 2, 200, 1.0e-6
      assert x0 >= 10 and x1 <= 390
    end

    test "one point keeps the scale and is centred; no point changes nothing" do
      merc = Projection.scale(Projection.new(:mercator), 1000)
      one = Projection.fit(merc, [[0, 0], [100, 50]], [{10, 20}])
      assert one.scale == 1000
      {x, y} = Projection.project(one, 10, 20)
      assert_in_delta x, 50, 1.0e-9
      assert_in_delta y, 25, 1.0e-9
      assert Projection.fit(merc, [[0, 0], [100, 50]], []) == merc
    end
  end
end
