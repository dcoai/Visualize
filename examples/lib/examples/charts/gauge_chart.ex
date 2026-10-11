defmodule Examples.Charts.GaugeChart do
  @moduledoc """
  A gauge as a design (#389, #392): a polar frame whose `angle` scale sweeps 240° from
  −120° over the reading's domain (spec/14 §4.3), the axis drawn as an arc at 0.85 R with
  its ticks outward, a band of three `:rect` sectors — the good, warning and bad zones, coloured
  by the theme's roles (#533) and marked by each role's glyph, so they read in greyscale
  (#560) —
  arced around the chart by the polar transform (§5.2), an arced `:rect` filled from zero
  to the reading, and a `:needle` over the newest reading with the value labelled beyond
  its tip. Animated, the reading wanders and the needle follows.
  """

  import Visualize.Chart.Build

  alias Examples.Charts.Design

  @margin %{top: 20, right: 20, bottom: 20, left: 20}
  @zones [
    %{from: 0, to: 60, mid: 30, zone: "ok"},
    %{from: 60, to: 85, mid: 72.5, zone: "warm"},
    %{from: 85, to: 100, mid: 92.5, zone: "hot"}
  ]

  @doc "The size this chart is drawn at when the caller names none (spec/14 §4.2)."
  def size, do: {400, 400}

  def title, do: "Gauge"
  def description, do: "A load reading on a 240° arc with a needle"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    {width, height} = Design.size(__MODULE__, opts)
    outer = min(width - @margin.left - @margin.right, height - @margin.top - @margin.bottom) / 2
    reading = reading(opts)

    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        source(:reading, [:value], types: %{value: :number}),
        source(:zones, [:from, :to, :mid, :zone],
          types: %{from: :number, to: :number, mid: :number, zone: :text}
        ),
        style(:zone, fill: {:field, :zone}, opacity: 0.35),
        # A zone's role as its glyph too, so the zones read without their hue (spec/14 §21.7).
        style(:cue,
          symbol: {:field, :zone},
          symbol_size: 180,
          fill: {:field, :zone},
          stroke: :background,
          stroke_width: 1.5
        ),
        style(:fill, fill: :series_1, opacity: 0.8),
        style(:needle, fill: :text, stroke: :background, stroke_width: 1),
        style(:reading, extends: :label, font_size: 20, font_weight: :bold),
        style(:dial, extends: :axis),
        polar(margin: @margin),
        linear_scale(:angle, domain: [0, 100], start: -120, sweep: 240),
        linear_scale(:r, domain: [0, 1], range: [0, outer]),
        # The zones are status, so they take the theme's roles, not series colours: every
        # theme renders good, warning and bad in its own tones (spec/08 §7.5).
        ordinal_scale(:color, domain: ["ok", "warm", "hot"], range: [:good, :warning, :bad]),
        axis(:angle, :bottom, ticks: 5, radius: 0.85, unit: "%", style: :dial),
        # The zones: three sectors between 0.7 R and 0.85 R, arced around the dial.
        rect(:zones, %{x0: :from, x1: :to, y0: 0.7, y1: 0.85, value: :zone}, style: :zone),
        # Each zone's glyph at its middle: a circle, a triangle, a cross (spec/14 §21.7).
        symbol(:zones, %{x: :mid, y: 0.775}, style: :cue),
        # The fill: one sector from zero to the reading, just inside the zones.
        rect(:reading, %{x0: 0, x1: :value, y0: 0.55, y1: 0.68}, style: :fill),
        needle(:reading, %{x: :value, y: 0.8},
          options: %{width: 8, tail: 14, hub: 7},
          label: %{text: [{:field, :value}, "%"], dr: 30, style: :reading},
          style: :needle
        )
      ])

    {design, %{reading: [%{value: reading}], zones: @zones}}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  # The reading: given, else a load that wanders with the tick, 42% at rest.
  defp reading(opts) do
    case opts[:animation_tick] do
      nil -> (opts[:data] && hd(opts[:data]).value) || 42
      tick -> Float.round(55 + 35 * :math.sin(tick * 0.07) + 8 * :math.sin(tick * 0.31), 1)
    end
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Gauge"}),
        source(:reading, [:value], types: %{value: :number}),
        source(:zones, [:from, :to, :mid, :zone]),
        style(:zone, fill: {:field, :zone}, opacity: 0.35),
        # A zone's role as its glyph too, so it reads without its hue (spec/14 §21.7).
        style(:cue, symbol: {:field, :zone}, symbol_size: 180, fill: {:field, :zone}),
        style(:fill, fill: :series_1, opacity: 0.8),
        style(:needle, fill: :text),
        polar(margin: %{top: 20, right: 20, bottom: 20, left: 20}),
        # The angle scale sweeps 240° from -120° over the reading's domain (spec/14 §4.3).
        linear_scale(:angle, domain: [0, 100], start: -120, sweep: 240),
        linear_scale(:r, domain: [0, 1], range: [0, 180]),
        # Status zones take the theme's roles, so every theme renders them in its own tones.
        ordinal_scale(:color, domain: ["ok", "warm", "hot"], range: [:good, :warning, :bad]),
        # The axis is an arc of the sweep at 0.85 R (spec/14 §4.6).
        axis(:angle, :bottom, ticks: 5, radius: 0.85, unit: "%"),
        # A rect with x on angle and y on r is a sector, bent by the polar transform (§5.2).
        rect(:zones, %{x0: :from, x1: :to, y0: 0.7, y1: 0.85, value: :zone}, style: :zone),
        symbol(:zones, %{x: :mid, y: 0.775}, style: :cue),
        rect(:reading, %{x0: 0, x1: :value, y0: 0.55, y1: 0.68}, style: :fill),
        # The needle points at the reading; its label sits beyond the tip.
        needle(:reading, %{x: :value, y: 0.8},
          options: %{width: 8, tail: 14, hub: 7},
          label: %{text: [{:field, :value}, "%"], dr: 30},
          style: :needle
        )
      ])

    {:ok, applied} = Visualize.Chart.apply(design, sources: %{reading: [%{value: 42}], zones: zones})
    Visualize.Chart.render(applied)
    """
  end
end
