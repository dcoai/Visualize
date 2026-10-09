defmodule Examples.Charts.LoadChart do
  @moduledoc """
  A machine's load average as a history and a dial, **from one source in two frames**
  (#383, #429): the ten minutes behind us as a line over the whole box, and the newest
  reading alone as a gauge in the corner over it.

  This is what frames are for. The two marks read the same `load` source — the gauge's
  data is `take(from(:load), 1)`, the newest row of the very rows the line draws in full
  (spec/14 §5.4.1, #426) — so the dial cannot disagree with the trace behind it. Before
  frames a design had one coordinate system, so a dial and a plot were two charts
  (`Examples.Charts.LoadGauge` and `Examples.Charts.LoadAge` still are, and read well as
  two); here they are one picture.

  The `history` frame fills the box (`[0, 0, 1, 1]`) and the `now` frame sits in the
  top-right quarter of it (`[0.72, 0.04, 0.24, 0.24]`) at `z: 1` with a `background`, so
  it hides the trace beneath it and nothing else (§4.2). Each frame declares its own
  scales: `history` an `x` in time and a `y` in load, `now` an `angle` over the same load
  domain and an `r` — two `x`-like scales that never collide, because a scale name belongs
  to its frame.

  The load is `Examples.Charts.Load`'s one-minute window, a pure function of its absolute
  second, so a frame redraws the same ten minutes whenever it is drawn.
  """

  import Visualize.Chart.Build

  alias Examples.Charts.{Design, Load}

  @margin %{top: 24, right: 24, bottom: 34, left: 46}
  @dial %{top: 6, right: 6, bottom: 6, left: 6}
  @epoch ~U[2026-01-01 09:00:00Z]
  # Ten minutes of history at one reading every two seconds.
  @span 600
  @every 2
  @ceiling 4
  @box [0.72, 0.04, 0.24, 0.24]

  @doc "The size this chart is drawn at when the caller names none (spec/14 §4.2)."
  def size, do: {760, 400}

  def title, do: "Load"
  def description, do: "Ten minutes of load average, and the newest reading on a dial"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    design =
      Design.fold(
        [chart(meta: %{name: title(), description: [description()]})] ++
          furniture() ++ history() ++ dial()
      )

    {design, sources(Load.second(opts, @span))}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  @doc """
  The sources and styles the history and its dial draw with: what `history/1` and `dial/1`
  name, said once here and in `Examples.Charts.LoadAndAge` (#493).
  """
  def furniture do
    [
      source(:load, [:t, :v], types: %{t: :time, v: :number}),
      # One row, so the dial's track is drawn once rather than once per reading.
      source(:dial, [:at], types: %{at: :number}),
      style(:trace, stroke: :series_1, stroke_width: 2, curve: :monotone_x),
      style(:volume, fill: :series_1, opacity: 0.18, curve: :monotone_x),
      style(:track, fill: :grid, opacity: 0.5),
      style(:reading, fill: :series_1),
      style(:value, extends: :label, font_size: 16, font_weight: :bold)
    ]
  end

  @doc """
  The `history` frame: ten minutes of the one-minute load as a line over its volume.
  `place` is where its `cartesian` goes — the margin, and the `cell` of a design with a
  grid (spec/14 §2.8) — and the box's whole when it says no more.
  """
  def history(place \\ [margin: @margin]) do
    in_frame(:history, [
      cartesian(place),
      time_scale(:x),
      linear_scale(:y, domain: [0, @ceiling]),
      axis(:x, :bottom, ticks: 6, format: "%H:%M"),
      axis(:y, :left, ticks: 4, grid: true),
      # The volume under the trace reaches the scale's floor, not the series' own
      # minimum (spec/14 §5.2, #420).
      area(:load, %{x: :t, y: :v, y0: {:scale, :min}}, style: :volume),
      line(:load, %{x: :t, y: :v}, style: :trace),
      label({:frame, :bottom_left}, ["load average — one minute"])
    ])
  end

  @doc """
  The `now` frame: the newest reading on a dial at `box`, fractions of the whole box
  (spec/14 §4.2), over the history on its own background.
  """
  def dial(box \\ @box) do
    in_frame(:now, [
      polar(box: box, margin: @dial, z: 1, background: :background),
      linear_scale(:angle, domain: [0, @ceiling], start: -120, sweep: 240),
      linear_scale(:r, domain: [0, 1]),
      # Two sectors the polar transform arcs (spec/14 §5.2): the dial's track over
      # the whole domain, and the newest reading over it. The dial is an inch across
      # and carries no axis: the number in the middle is what it is read by.
      rect(:dial, %{x0: 0, x1: @ceiling, y0: 0.62, y1: 0.92}, style: :track),
      rect(newest(), %{x0: 0, x1: :v, y0: 0.62, y1: 0.92}, style: :reading),
      text(newest(), %{x: 0, y: 0},
        label: %{text: [{:field, :v}], anchor: :middle, style: :value}
      )
    ])
  end

  @doc "The dial's box in this chart, the top-right quarter of the history (spec/14 §4.2)."
  def box, do: @box

  @doc """
  The rows the history and the dial bind at absolute second `now`: the ten minutes up to
  and including it, one reading every two seconds, the newest last.
  """
  def sources(now) do
    load =
      for second <- (now - @span)..now//@every do
        %{t: DateTime.add(@epoch, second, :second), v: Float.round(Load.at(:one, second), 2)}
      end

    %{load: load, dial: [%{at: 0}]}
  end

  @doc "The instant a history row stands for, as absolute seconds of the machine's day."
  def second_of(%{t: t}), do: DateTime.diff(t, @epoch, :second)

  # The newest row of the same rows the history line draws (spec/14 §5.4.1, #426).
  defp newest, do: take(from(:load), 1)

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    # One source, two frames: the history over the whole box, the dial in the corner of it.
    newest = take(from(:load), 1)

    {:ok, design} =
      Visualize.Chart.compose(
        [
          chart(meta: %{name: "Load"}),
          source(:load, [:t, :v], types: %{t: :time, v: :number}),
          # One row, so the dial's track is drawn once rather than once per reading.
          source(:dial, [:at], types: %{at: :number}),
          style(:trace, stroke: :series_1, stroke_width: 2, curve: :monotone_x),
          style(:reading, fill: :series_1)
        ] ++
          in_frame(:history, [
            cartesian(margin: %{top: 24, right: 24, bottom: 34, left: 46}),
            time_scale(:x),
            linear_scale(:y, domain: [0, 4]),
            axis(:x, :bottom, ticks: 6, format: "%H:%M"),
            axis(:y, :left, ticks: 4, grid: true),
            line(:load, %{x: :t, y: :v}, style: :trace)
          ]) ++
          in_frame(:now, [
            # The box is fractions of whatever size the page gives the chart (§4.2).
            polar(box: [0.72, 0.04, 0.24, 0.24], z: 1, background: :background),
            linear_scale(:angle, domain: [0, 4], start: -120, sweep: 240),
            linear_scale(:r, domain: [0, 1]),
            # A rect in a polar frame is an arced bar: the reading, from zero.
            rect(newest, %{x0: 0, x1: :v, y0: 0.62, y1: 0.92}, style: :reading),
            text(newest, %{x: 0, y: 0}, label: %{text: [{:field, :v}], anchor: :middle})
          ])
      )

    load = for s <- 0..600//2, do: %{t: DateTime.add(~U[2026-01-01 09:00:00Z], s), v: 1.2}

    {:ok, applied} = Visualize.Chart.apply(design, sources: %{load: load})
    Visualize.Chart.render(applied)
    """
  end
end
