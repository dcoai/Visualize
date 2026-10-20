defmodule Visualize.Chart.TilesTest do
  @moduledoc """
  The `:tiles` mark of spec/14 §5.2 (#475): its validation faults, the attribution it
  always draws, its place beneath every other mark whatever the design's order, the
  view fitted to a source with the tiles following, and its region and target in a
  compiled chart. No tile is fetched: the URLs are asserted as strings.
  """
  use ExUnit.Case, async: true

  alias Visualize.Chart
  alias Visualize.Chart.{Compiled, Frame, Validator}
  alias Visualize.Geo.{Projection, Tiles}

  @url "https://{s}.tile.example/{z}/{x}/{y}.png"
  @attribution "© OpenStreetMap contributors"

  @track [
    %{lon: -0.1300, lat: 51.5000},
    %{lon: -0.1210, lat: 51.5080},
    %{lon: -0.1100, lat: 51.5150},
    %{lon: -0.1000, lat: 51.5200}
  ]

  @size {400, 300}
  @pad 12

  defp tiles_mark(extra \\ %{}),
    do: Map.merge(%{type: :tiles, tiles: %{url: @url, attribution: @attribution}}, extra)

  defp track_mark do
    %{
      type: :line,
      data: %{source: :track, transforms: [%{op: :projection, fields: [:lon, :lat]}]},
      channels: %{x: :x, y: :y}
    }
  end

  # A basemap under a track, the view fitted to the track; the track is declared first.
  defp design(marks \\ nil, projection \\ nil) do
    %{
      version: 3,
      sources: %{track: %{fields: [:lon, :lat]}},
      frames: %{
        main: %{
          kind: :geo,
          margin: %{top: 0, right: 0, bottom: 0, left: 0},
          projection:
            projection ||
              %{type: :mercator, fit: %{data: :track, fields: [:lon, :lat], padding: @pad}}
        }
      },
      marks: marks || [track_mark(), tiles_mark()]
    }
  end

  defp errors(design) do
    {:error, errors} = Validator.validate(design)
    errors
  end

  defp applied(design) do
    {:ok, applied} = Chart.apply(design, sources: %{track: @track}, size: @size)
    applied
  end

  defp frame(design), do: applied(design).frame

  defp group(design, type) do
    frame = frame(design)

    frame
    |> Frame.generate(sources: %{track: @track})
    |> Map.fetch!(:children)
    |> Enum.find(&(&1.style[:class] =~ "mark-#{type}"))
  end

  describe "validation" do
    test "a basemap under a fitted Mercator view validates, with no data of its own" do
      assert Validator.validate(design()) == :ok
    end

    test "a projection that is not Mercator is refused" do
      design = design(nil, %{type: :equirectangular})

      assert errors(design) == [{[:marks, 1, :type], {:tiles, :projection, :equirectangular}}]

      assert Validator.format(hd(errors(design))) =~
               "marks[1].type: draws tiles over :equirectangular"
    end

    test "a frame that is not :geo, a center latitude and a tilt are refused" do
      cartesian = put_in(design(), [:frames, :main], %{kind: :cartesian})
      assert errors(cartesian) == [{[:marks, 1, :type], {:tiles, :projection, :cartesian}}]

      centered = design(nil, %{type: :mercator, center: [0, 51]})
      assert errors(centered) == [{[:marks, 1, :type], {:tiles, :projection, :center}}]

      tilted = design(nil, %{type: :mercator, rotate: [0, 0, 10]})
      assert errors(tilted) == [{[:marks, 1, :type], {:tiles, :projection, :rotate}}]

      # A center longitude and a rotation's lambda shift the map: tiles still lie under it.
      assert Validator.validate(design(nil, %{type: :mercator, center: [10, 0], rotate: [5]})) ==
               :ok
    end

    test "a missing attribution is required, and a blank one refused" do
      missing = design([tiles_mark(%{tiles: %{url: @url}})])
      assert errors(missing) == [{[:marks, 0, :tiles, :attribution], :required}]

      blank = design([tiles_mark(%{tiles: %{url: @url, attribution: "  "}})])
      assert errors(blank) == [{[:marks, 0, :tiles, :attribution], {:tiles, :attribution}}]
    end

    test "the provider node: required of :tiles, invalid elsewhere, its url a tile set" do
      assert errors(design([%{type: :tiles}])) == [{[:marks, 0, :tiles], :required}]

      on_line = Map.put(track_mark(), :tiles, %{url: @url, attribution: @attribution})
      assert errors(design([on_line])) == [{[:marks, 0, :tiles], {:invalid_for, :line}}]

      no_xyz = tiles_mark(%{tiles: %{url: "https://t/{z}.png", attribution: @attribution}})
      assert errors(design([no_xyz])) == [{[:marks, 0, :tiles, :url], {:tiles, :url}}]

      no_hosts = tiles_mark(%{tiles: %{url: @url, attribution: @attribution, subdomains: []}})

      assert errors(design([no_hosts])) ==
               [{[:marks, 0, :tiles, :subdomains], {:tiles, :subdomains}}]
    end

    test "a fit reads fields or field, not neither nor both" do
      # The design is written with atoms; its faults name the frame by its string (D-195).
      at = [:frames, :main, :projection, :fit]
      path = [:frames, "main", :projection, :fit]

      neither = put_in(design(), at, %{data: :track})
      assert errors(neither) == [{path ++ [:fields], :required}]

      both = put_in(design(), at, %{data: :track, fields: [:lon, :lat], field: :lon})
      assert errors(both) == [{path ++ [:field], {:invalid_for, :fit}}]

      assert errors(put_in(design(), at ++ [:data], :nope)) ==
               [{path ++ [:data], {:undeclared, :source, "nope"}}]
    end
  end

  describe "rendering" do
    test "one image per covering tile, its URL the template's, in plot pixels" do
      frame = frame(design())
      images = Enum.filter(group(design(), :tiles).children, &(&1.type == :image))
      tiles = Tiles.cover(frame.projection, {frame.plot.width, frame.plot.height})

      assert length(images) == length(tiles) and tiles != []

      for {image, tile} <- Enum.zip(images, tiles) do
        assert image.attrs == %{
                 href: Tiles.url(@url, tile, ["a", "b", "c"]),
                 x: tile.left,
                 y: tile.top,
                 width: tile.size,
                 height: tile.size
               }
      end

      # The URLs are strings in the markup; nothing is fetched.
      svg = Chart.render(applied(design()))
      %{z: z, x: x, y: y} = hd(tiles)
      assert svg =~ ~r{href="https://[abc]\.tile\.example/#{z}/#{x}/#{y}\.png"}
    end

    test "the attribution is drawn in the bottom-right corner in the mark's style" do
      styled = design([track_mark(), tiles_mark(%{style: %{font_size: 9, fill: "#555"}})])
      [text] = Enum.filter(group(styled, :tiles).children, &(&1.type == :text))
      {w, h} = @size

      assert text.content == @attribution
      assert text.attrs == %{x: w - 4, y: h - 4}
      assert text.style.class == "mark-attribution"
      assert text.style.text_anchor == :end
      assert text.style.font_size == 9
      assert text.style.fill == "#555"

      # With no style of its own it is the built-in label's.
      [plain] = Enum.filter(group(design(), :tiles).children, &(&1.type == :text))
      assert plain.style.fill == "var(--vis-text, #333333)"
    end

    test "tiles go beneath every other mark, even declared after them" do
      frame = frame(design())

      [first, second] =
        frame
        |> Frame.generate(sources: %{track: @track}, paths: true)
        |> Map.fetch!(:children)
        |> Enum.filter(&(&1.type == :group))

      assert first.style.class == "mark mark-tiles"
      assert first.attrs["data-node"] == "marks[1]"
      assert second.style.class =~ "mark mark-line"
      assert second.attrs["data-node"] == "marks[0]"
      # The line keeps its paint for its own position.
      assert second.style.stroke == "var(--vis-series-1, #3b6fa8)"

      svg = Chart.render(applied(design()))
      {tiles_at, _} = :binary.match(svg, "mark-tiles")
      {line_at, _} = :binary.match(svg, "mark-line")
      assert tiles_at < line_at
    end

    test "a design with no tiles draws its marks in design order, as before" do
      marks = [track_mark(), Map.put(track_mark(), :style, %{class: "second"})]
      [a, b] = Enum.filter(group_children(design(marks)), &(&1.type == :group))
      refute a.style.class =~ "second"
      assert b.style.class =~ "second"
    end

    defp group_children(design) do
      design |> frame() |> Frame.generate(sources: %{track: @track}) |> Map.fetch!(:children)
    end
  end

  describe "the fit and the tiles follow it" do
    test "the track fills the padded plot and the projection stays tile-aligned" do
      frame = frame(design())
      {w, h} = @size
      assert Tiles.aligned(frame.projection) == :ok

      {xs, ys} =
        @track |> Enum.map(&Projection.project(frame.projection, &1.lon, &1.lat)) |> Enum.unzip()

      {x0, x1} = Enum.min_max(xs)
      {y0, y1} = Enum.min_max(ys)
      assert x0 >= @pad - 1.0e-6 and x1 <= w - @pad + 1.0e-6
      assert y0 >= @pad - 1.0e-6 and y1 <= h - @pad + 1.0e-6

      assert abs(x0 - @pad) < 1.0e-6 or abs(y0 - @pad) < 1.0e-6
    end

    test "each track point lands on its tile's pixel for that point" do
      frame = frame(design())
      tiles = Tiles.cover(frame.projection, {frame.plot.width, frame.plot.height})
      z = hd(tiles).z
      n = Integer.pow(2, z)

      for %{lon: lon, lat: lat} <- @track do
        {px, py} = Projection.project(frame.projection, lon, lat)
        phi = lat * :math.pi() / 180
        wx = (lon + 180) / 360 * n
        wy = (1 - :math.log(:math.tan(phi) + 1 / :math.cos(phi)) / :math.pi()) / 2 * n
        tile = Enum.find(tiles, &(&1.x == floor(wx) and &1.y == floor(wy)))
        assert_in_delta tile.left + (wx - floor(wx)) * tile.size, px, 1.0e-6
        assert_in_delta tile.top + (wy - floor(wy)) * tile.size, py, 1.0e-6
      end
    end

    test "another track moves the view, and the tiles with it" do
      far = Enum.map(@track, &%{&1 | lon: &1.lon + 2.0})
      {:ok, moved} = Chart.apply(design(), sources: %{track: far}, size: @size)
      refute moved.frame.projection == frame(design()).projection
    end
  end

  describe "a compiled chart" do
    test "a basemap is :svg with no points, and static unless its view is fitted" do
      fixed = design(nil, %{type: :mercator, scale: 50_000, center: [-0.115, 0]})
      {:ok, %{"main" => compiled}} = Chart.compile(fixed, sources: %{track: @track}, size: @size)

      assert Compiled.targets(compiled) |> Enum.at(1) == {:svg, 0}

      assert Compiled.regions(compiled) == [
               {{:mark, 1}, :static},
               {{:mark, 0}, {:dynamic, :data}}
             ]

      # The static basemap's attribution is in the static SVG; its images are the backdrop.
      assert Compiled.static(compiled) =~ "mark-tiles"
      assert Compiled.static(compiled) =~ @attribution

      {:ok, %{"main" => fitted}} = Chart.compile(design(), sources: %{track: @track}, size: @size)

      assert Compiled.regions(fitted) ==
               [{{:mark, 1}, {:dynamic, :data}}, {{:mark, 0}, {:dynamic, :data}}]
    end
  end

  # The backdrop of spec/14 §12.3 and §12.4 (#476, D-120): on a hybrid page the canvas
  # sits beneath the SVG layers, so a basemap drawn there would hide a canvas track.
  describe "the backdrop beneath the canvas" do
    defp images(svg), do: length(Regex.scan(~r/<image /, svg))

    defp tile_count(compiled) do
      frame = frame(design())
      assert compiled.plot == frame.plot
      length(Tiles.cover(frame.projection, {frame.plot.width, frame.plot.height}))
    end

    test "a static basemap's images are the static backdrop, its attribution the static SVG" do
      fixed = design(nil, %{type: :mercator, scale: 50_000, center: [-0.115, 0]})

      {:ok, %{"main" => compiled}} =
        Chart.compile(fixed, sources: %{track: @track}, size: @size, ceiling: 1)

      backdrop = Compiled.backdrop(compiled)
      static = Compiled.static(compiled)
      {:ok, applied} = Chart.apply(fixed, sources: %{track: @track}, size: @size)
      n = length(Tiles.cover(applied.frame.projection, {400, 300}))

      assert n > 0
      assert images(backdrop) == n
      assert backdrop =~ ~s(class="mark mark-tiles")
      refute backdrop =~ @attribution
      # The backdrop is a page-ready document of the static one's shape.
      # A layer of the picture the page names: aria-hidden (spec/14 §21.4, D-142).
      assert backdrop =~ ~s(<svg aria-hidden="true" height="300")
      assert backdrop =~ ~s(viewBox="0 0 400 300")

      assert images(static) == 0
      assert static =~ @attribution

      # The track is the data, and dense enough here to go to the canvas.
      assert [{track_target, 4}, {:svg, 0}] = Compiled.targets(compiled)
      assert track_target in [:binary, :canvas]

      {payload, _} = Compiled.tick(compiled, %{track: @track})
      assert payload.canvas != ""
      # Static: nothing of the basemap travels with a tick.
      assert payload.backdrop == ""
      assert images(payload.svg) == 0
      refute payload.svg =~ @attribution

      # The chart map holds the images in `backdrop` and none in either SVG list.
      map = Compiled.render(compiled, %{track: @track})
      assert [%{children: children}] = map.backdrop
      assert length(children) == n and Enum.all?(children, &(&1.type == :image))
      refute Enum.any?(List.flatten(walk(map.static ++ map.dynamic_svg)), &(&1 == :image))
    end

    test "a fitted basemap's images travel in the tick's backdrop, its attribution in its SVG" do
      {:ok, %{"main" => compiled}} =
        Chart.compile(design(), sources: %{track: @track}, size: @size, ceiling: 1)

      assert Compiled.backdrop(compiled) == ""
      refute Compiled.static(compiled) =~ "<image"

      {payload, _} = Compiled.tick(compiled, %{track: @track})
      assert images(payload.backdrop) == tile_count(compiled)
      refute payload.backdrop =~ @attribution
      assert images(payload.svg) == 0
      assert payload.svg =~ @attribution
      assert payload.canvas != ""

      assert payload.bytes ==
               byte_size(payload.svg) + byte_size(payload.backdrop) + byte_size(payload.canvas)

      # Another track moves the view, and the backdrop with it.
      far = Enum.map(@track, &%{&1 | lon: &1.lon + 2.0})
      {moved, _} = Compiled.tick(compiled, %{track: far})
      refute moved.backdrop == payload.backdrop
    end

    test "the one-string form keeps the basemap whole, first in the frame" do
      applied = applied(design())
      {:ok, %{"main" => compiled}} = Chart.compile(applied, ceiling: 1_000_000)
      svg = Compiled.svg(compiled, applied.sources)
      assert images(svg) == tile_count(compiled)
      assert svg =~ @attribution
    end

    test "a design without tiles has an empty backdrop" do
      {:ok, %{"main" => compiled}} =
        Chart.compile(design([track_mark()]), sources: %{track: @track}, size: @size)

      assert Compiled.backdrop(compiled) == ""
      assert Compiled.render(compiled, %{track: @track}).backdrop == []
      {payload, _} = Compiled.tick(compiled, %{track: @track})
      assert payload.backdrop == ""
    end

    defp walk(elements) when is_list(elements), do: Enum.map(elements, &walk/1)
    defp walk(%{type: type, children: children}), do: [type | walk(children)]
  end

  describe "a compiled chart: the one-string form and the target" do
    test "the one-string form is the frame's render, tiles first" do
      for design <- [design(), design(nil, %{type: :mercator, scale: 50_000})] do
        applied = applied(design)
        {:ok, %{"main" => compiled}} = Chart.compile(applied)
        assert Compiled.svg(compiled, applied.sources) == Chart.render(applied)
      end
    end

    test "a tiles mark marked for the canvas stays on SVG" do
      design = design([track_mark(), tiles_mark(%{render: :canvas})])
      {:ok, %{"main" => compiled}} = Chart.compile(design, sources: %{track: @track}, size: @size)
      assert Enum.at(Compiled.targets(compiled), 1) == {:svg, 0}
    end
  end

  describe "the builder" do
    test "tiles/3 is a mark with no data and its provider" do
      tiles = %{url: @url, attribution: @attribution}

      assert Chart.Build.tiles(nil, %{}, tiles: tiles) ==
               %{marks: [%{type: :tiles, channels: %{}, tiles: tiles}]}
    end
  end
end
