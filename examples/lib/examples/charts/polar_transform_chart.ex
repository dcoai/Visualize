defmodule Examples.Charts.PolarTransformChart do
  @moduledoc """
  The polar transform in one frame (#389, #394): every ordinary mark laid out in
  `(angle, r)` and bent around the arc (spec/14 §5.2). The `angle` scale is linear over
  time and sweeps 270° from −135° (§4.3); `r` is the signal's value over an annular band.
  A `:line` with a translucent `:area` under it wraps around the arc; a `:rule` per
  event is an indicator spoke across the band, labelled; a `:rule` at `y` is a threshold
  arc across the sweep; and `:rect`s whose `y` reads a `:band` scale through `scales:
  %{r: :lane}` are bars arced around the outside, one lane each. The angle axis is the
  arc at R and the `r` axis's spoke stands at −135°. Animated, the signal's phase drifts
  and the events advance.
  """

  import Visualize.Chart.Build

  alias Examples.Charts.Design

  @margin %{top: 24, right: 24, bottom: 24, left: 24}
  @samples 120
  @lanes ~w(build test deploy)

  def title, do: "Polar transform"
  def description, do: "A wrapped line, indicator spokes, a threshold arc and arced bars"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    width = opts[:width] || 480
    height = opts[:height] || 480
    outer = min(width - @margin.left - @margin.right, height - @margin.top - @margin.bottom) / 2
    tick = opts[:animation_tick] || 0

    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        source(:signal, [:t, :v], types: %{t: :number, v: :number}),
        source(:events, [:at, :name], types: %{at: :number, name: :text}),
        source(:levels, [:level], types: %{level: :number}),
        source(:tasks, [:from, :to, :lane], types: %{from: :number, to: :number, lane: :category}),
        style(:trace, stroke: :series_1, stroke_width: 2, curve: :monotone_x),
        style(:under, fill: :series_1, fill_opacity: 0.15, curve: :monotone_x),
        style(:event, stroke: :series_3, stroke_width: 1.5, stroke_dasharray: "4 3"),
        style(:event_word, extends: :label, font_size: 10, fill: :series_3),
        style(:threshold, stroke: :series_2, stroke_width: 1.5),
        style(:task, fill: {:field, :lane}, opacity: 0.85),
        polar(width, height, margin: @margin),
        linear_scale(:angle, domain: [0, 100], start: -135, sweep: 270),
        linear_scale(:r, domain: [0, 100], range: [outer * 0.3, outer * 0.78]),
        band_scale(:lane, domain: @lanes, range: [outer * 0.84, outer], padding: 0.25),
        ordinal_scale(:color, domain: @lanes, range: [:series_4, :series_2, :series_1]),
        axis(:angle, :bottom, ticks: 10, radius: 0.8, grid: true),
        axis(:r, :top, ticks: 4, at: -135, grid: true),
        # The line graph wraps around the arc, its area under it to the inner radius.
        area(:signal, %{x: :t, y: :v}, style: :under),
        line(:signal, %{x: :t, y: :v}, style: :trace),
        # An indicator spoke per event, across the band, each named at its foot.
        rule(:events, %{x: :at}, style: :event, label: %{text: [{:field, :name}], style: :event_word}),
        # A threshold at a radius: an arc across the whole sweep.
        rule(:levels, %{y: :level}, style: :threshold),
        # Bars arced around the outside: the angle their span, a lane each.
        rect(:tasks, %{x0: :from, x1: :to, y0: :lane, y1: :lane, value: :lane},
          scales: %{r: :lane},
          style: :task
        )
      ])

    {design,
     %{
       signal: signal(tick),
       events: events(tick),
       levels: [%{level: 70}],
       tasks: [
         %{from: 5, to: 30, lane: "build"},
         %{from: 32, to: 55, lane: "test"},
         %{from: 58, to: 72, lane: "build"},
         %{from: 75, to: 96, lane: "deploy"}
       ]
     }}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  # Two sines and an offset, the phase drifting with the tick.
  defp signal(tick) do
    phase = tick * 0.08

    for i <- 0..(@samples - 1) do
      t = i * 100 / (@samples - 1)
      v = 50 + 28 * :math.sin(t / 9 + phase) + 12 * :math.sin(t / 2.3 - phase * 1.4)
      %{t: t, v: Float.round(v, 2)}
    end
  end

  # Three events advancing round the ring, a third of the sweep apart.
  defp events(tick) do
    for {name, i} <- Enum.with_index(~w(alpha beta gamma)) do
      %{at: Float.round(:math.fmod(tick * 0.3 + i * 33.3 + 12, 100), 1), name: name}
    end
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Polar transform"}),
        source(:signal, [:t, :v]),
        source(:events, [:at, :name]),
        source(:levels, [:level]),
        source(:tasks, [:from, :to, :lane]),
        style(:trace, stroke: :series_1, stroke_width: 2, curve: :monotone_x),
        style(:under, fill: :series_1, fill_opacity: 0.15, curve: :monotone_x),
        style(:event, stroke: :series_3, stroke_dasharray: "4 3"),
        style(:threshold, stroke: :series_2),
        style(:task, fill: {:field, :lane}),
        polar(480, 480, margin: %{top: 24, right: 24, bottom: 24, left: 24}),
        # The sweep is the angle scale's: 270° from -135° over the time column (spec/14 §4.3).
        linear_scale(:angle, domain: [0, 100], start: -135, sweep: 270),
        # r over an annular band; a band scale for the bars' lanes outside it.
        linear_scale(:r, domain: [0, 100], range: [65, 168]),
        band_scale(:lane, domain: ~w(build test deploy), range: [181, 216], padding: 0.25),
        ordinal_scale(:color, domain: ~w(build test deploy)),
        axis(:angle, :bottom, ticks: 10, radius: 0.8, grid: true),
        axis(:r, :top, ticks: 4, at: -135, grid: true),
        # In a polar frame x names angle and y names r: the line wraps around the arc,
        # the area fills to the inner radius (spec/14 §5.2).
        area(:signal, %{x: :t, y: :v}, style: :under),
        line(:signal, %{x: :t, y: :v}, style: :trace),
        # A rule at x is a spoke across the band; at y, an arc across the sweep.
        rule(:events, %{x: :at}, style: :event, label: %{text: [{:field, :name}]}),
        rule(:levels, %{y: :level}, style: :threshold),
        # A rect with its y on a band scale (renamed from r) is a bar arced around the chart.
        rect(:tasks, %{x0: :from, x1: :to, y0: :lane, y1: :lane, value: :lane},
          scales: %{r: :lane},
          style: :task
        )
      ])

    {:ok, applied} = Visualize.Chart.apply(design, sources: sources)
    Visualize.Chart.render(applied)
    """
  end
end
