defmodule Visualize.Chart.StatusCueTest do
  @moduledoc """
  Status beyond hue (spec/14 §21.7, spec/08 §7.5, #560, D-142): each role's glyph and dash,
  a mark drawing them through the role its datum has, a symbol keeping its glyph on a polar
  arc, and a grayscale render of a status gauge whose zones stay distinguishable.
  """
  use ExUnit.Case, async: true

  alias Visualize.Backend.SVG
  alias Visualize.{Chart, Render, Theme}
  alias Visualize.PNGPixels
  alias Visualize.Shape.Symbol

  @zones [
    %{from: 0, to: 60, mid: 30, zone: "ok"},
    %{from: 60, to: 85, mid: 72.5, zone: "warm"},
    %{from: 85, to: 100, mid: 92.5, zone: "hot"}
  ]

  # A status gauge: three zones colored by role, and — with `cues?` — each zone's glyph at
  # its middle; the zone outlines dashed by role.
  defp gauge(cues?) do
    glyphs =
      if cues?,
        do: [%{type: :symbol, data: :zones, channels: %{x: :mid, y: 0.775}, style: :cue}],
        else: []

    %{
      version: 2,
      sources: %{zones: %{fields: [:from, :to, :mid, :zone]}},
      styles: %{
        zone: %{
          fill: {:field, :zone},
          opacity: 0.35,
          stroke: :axis,
          stroke_dasharray: {:field, :zone}
        },
        cue: %{
          symbol: {:field, :zone},
          symbol_size: 180,
          fill: {:field, :zone},
          stroke: :background
        }
      },
      frames: %{
        main: %{
          kind: :polar,
          margin: %{top: 20, right: 20, bottom: 20, left: 20},
          scales: %{
            angle: %{kind: :linear, domain: [0, 100], start: -120, sweep: 240},
            r: %{kind: :linear, domain: [0, 1], range: [0, 180]},
            color: %{
              kind: :ordinal,
              domain: ["ok", "warm", "hot"],
              range: [:good, :warning, :bad]
            }
          }
        }
      },
      marks:
        [
          %{
            type: :rect,
            data: :zones,
            channels: %{x0: :from, x1: :to, y0: 0.7, y1: 0.85, value: :zone},
            style: :zone
          }
        ] ++ glyphs
    }
  end

  defp applied(design) do
    {:ok, applied} = Chart.apply(design, sources: %{zones: @zones}, size: {400, 400})
    applied
  end

  test "each role has a fixed glyph and dash, and anything but a role has none" do
    assert for(role <- Theme.role_names(), do: {role, Theme.cue(role)}) == [
             good: %{glyph: :circle, dash: nil},
             warning: %{glyph: :triangle, dash: "6 3"},
             bad: %{glyph: :cross, dash: "2 3"},
             info: %{glyph: :square, dash: "8 3 2 3"},
             neutral: %{glyph: :diamond, dash: "1 4"}
           ]

    assert_raise ArgumentError, ~r/a cue is a role's/, fn -> Theme.cue(:series_1) end
  end

  test "a field bound to symbol and stroke_dasharray draws the role's glyph and dash through the color scale" do
    svg = Chart.render(applied(gauge(true)))

    # The zones' outlines: warning's and bad's dashes, and good solid — no third dash.
    assert svg =~ ~s(stroke-dasharray="6 3") and svg =~ ~s(stroke-dasharray="2 3")
    assert length(Regex.scan(~r/stroke-dasharray=/, svg)) == 2

    # The glyphs keep their shape on the arc: each is its symbol type's own path.
    for type <- [:circle, :triangle, :cross] do
      d = Symbol.new() |> Symbol.type(type) |> Symbol.size(180) |> Symbol.generate_path(%{})
      assert svg =~ ~s(d="#{SVG.path_data(d)}"), "no #{type} glyph"
    end
  end

  test "a reading that is not a role is the key's own value, and a symbol that is neither a circle" do
    design = %{
      version: 2,
      sources: %{s: %{fields: [:x, :y, :shape, :dash]}},
      styles: %{g: %{symbol: {:field, :shape}, stroke_dasharray: {:field, :dash}}},
      frames: %{main: %{kind: :cartesian, scales: %{x: %{kind: :linear}, y: %{kind: :linear}}}},
      marks: [%{type: :symbol, data: :s, channels: %{x: :x, y: :y}, style: :g}]
    }

    rows = [%{x: 0, y: 0, shape: :star, dash: "4 4"}, %{x: 1, y: 1, shape: "nope", dash: :bad}]
    {:ok, applied} = Chart.apply(design, sources: %{s: rows})
    svg = Chart.render(applied)

    path = fn type ->
      Symbol.new() |> Symbol.type(type) |> Symbol.size(64) |> Symbol.generate_path(%{})
    end

    assert svg =~ SVG.path_data(path.(:star))
    assert svg =~ SVG.path_data(path.(:circle))
    assert svg =~ ~s(stroke-dasharray="4 4")
    # A role read without a color scale is still a role.
    assert svg =~ ~s(stroke-dasharray="2 3")
  end

  describe "a grayscale render (spec/14 §21.7)" do
    @describetag :resvg

    # The glyphs' centers in the document's pixels: the plot's center plus each bent point.
    defp centers(applied, scale) do
      frame = applied.frame
      cx = frame.margin.left + frame.plot.width / 2
      cy = frame.margin.top + frame.plot.height / 2
      angle = Map.fetch!(frame.scales, :angle)
      r = Map.fetch!(frame.scales, :r)

      for %{mid: mid} <- @zones do
        {x, y} =
          Visualize.Chart.Mark.Bend.point(
            {Visualize.Scale.apply(angle, mid), Visualize.Scale.apply(r, 0.775)}
          )

        {round((cx + x) * scale), round((cy + y) * scale)}
      end
    end

    # A square of grayscale luminance about a point, thresholded at its own middle: the
    # shape in it, whatever its lightness.
    defp mask(image, {px, py}, half) do
      lum =
        for y <- (py - half)..(py + half), x <- (px - half)..(px + half) do
          {r, g, b, _a} = PNGPixels.pixel(image, x, y)
          0.2126 * r + 0.7152 * g + 0.0722 * b
        end

      {lo, hi} = Enum.min_max(lum)
      Enum.map(lum, &(hi - lo > 8 and &1 < (lo + hi) / 2))
    end

    defp distance(a, b), do: Enum.zip(a, b) |> Enum.count(fn {p, q} -> p != q end)

    defp masks(cues?) do
      applied = applied(gauge(cues?))
      root = Chart.generate(applied, root: true, resolve: :literal)
      {:ok, png, _warnings} = Render.to_png(root, scale: 2, background: "#ffffff")
      image = PNGPixels.decode(png)
      for center <- centers(applied, 2), do: mask(image, center, 14)
    end

    test "with the glyphs every pair of zones differs in shape; without them they do not" do
      [good, warning, bad] = masks(true)

      for {a, b} <- [{good, warning}, {good, bad}, {warning, bad}] do
        assert distance(a, b) > 40
      end

      # The control: the same gauge without its glyphs is, in shape, three equal patches —
      # the roles differ only in tone there, and tone is what grayscale keeps least.
      [good, warning, bad] = masks(false)
      assert distance(good, warning) + distance(good, bad) + distance(warning, bad) < 40
    end
  end
end
