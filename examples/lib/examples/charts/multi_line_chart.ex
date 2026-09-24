defmodule Examples.Charts.MultiLineChart do
  @moduledoc """
  Multi-series line chart as a design (#125, #237): one `:line` mark over a **wide** feed.

  The four hand-built path elements, their four colours and the hand-laid legend are one
  mark, one ordinal `color` scale and one `legend` node: the feed is wide — one row per
  point with a column per series — a `:fold` step turns it long, one row per point per
  column the row has (spec/14 §5.4.1), and a `series` channel on the folded key splits the
  mark into one path per column and colours each from the scale (§5.6); the legend
  explains the same scale. A column the feed drops is a line that is simply not there.

  The legend draws in the right margin the chart reserves for it, `inside: false` at the
  top right (spec/14 §4.5, #136).
  """

  import Visualize.Chart.Build

  alias Examples.Charts.Design

  @margin %{top: 20, right: 120, bottom: 30, left: 50}

  @data %{
    series_a: for(i <- 0..30, do: %{x: i, y: :math.sin(i / 5) * 30 + 50}),
    series_b: for(i <- 0..30, do: %{x: i, y: :math.cos(i / 5) * 25 + 45}),
    series_c: for(i <- 0..30, do: %{x: i, y: :math.sin(i / 3) * 20 + 60}),
    series_d: for(i <- 0..30, do: %{x: i, y: :math.cos(i / 4) * 15 + 40})
  }

  def title, do: "Multi-line Chart"
  def description, do: "Multiple data series comparison"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        # The source declares the column every row has; the fold lists the ones a row may.
        source(:series, [:x]),
        style(:wave, stroke_width: 2, curve: :monotone_x),
        cartesian(margin: @margin),
        linear_scale(:x),
        linear_scale(:y, nice: true, transition: %{duration: 300}),
        ordinal_scale(:color),
        axis(:x, :bottom, ticks: 10),
        axis(:y, :left, ticks: 5),
        legend(:color, position: :top_right, inside: false),
        line(
          fold(:series, [:series_a, :series_b, :series_c, :series_d], as: [:series, :y]),
          %{x: :x, y: :y, series: :series},
          style: :wave
        )
      ])

    {design, %{series: rows(opts)}}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  # One row per point with a column per series — the wide shape a feed of several
  # metrics has; the fold's field order fixes the colour each takes.
  defp rows(opts) do
    series = series(opts)

    for i <- 0..30 do
      Enum.reduce(series, %{x: i}, fn {key, points}, row ->
        Map.put(row, key, Enum.at(points, i).y)
      end)
    end
  end

  defp series(opts) do
    case opts[:animation_tick] do
      nil -> opts[:data] || @data
      tick -> animated(tick)
    end
  end

  # Animation: moving waves with different frequencies.
  defp animated(tick) do
    phase = tick * 0.12

    %{
      series_a: for(i <- 0..30, do: %{x: i, y: :math.sin(i / 5 + phase) * 30 + 50}),
      series_b: for(i <- 0..30, do: %{x: i, y: :math.cos(i / 5 + phase * 1.2) * 25 + 45}),
      series_c: for(i <- 0..30, do: %{x: i, y: :math.sin(i / 3 + phase * 0.8) * 20 + 60}),
      series_d: for(i <- 0..30, do: %{x: i, y: :math.cos(i / 4 + phase * 1.5) * 15 + 40})
    }
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    # A wide feed: one row per point, a column per series.
    rows = [%{x: 0, series_a: 50.0, series_b: 45.0, series_c: 60.0, series_d: 40.0}, ...]

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Multi-line Chart"}),
        source(:series, [:x]),
        style(:wave, stroke_width: 2, curve: :monotone_x),
        cartesian(margin: %{top: 20, right: 120, bottom: 30, left: 50}),
        linear_scale(:x),
        linear_scale(:y, nice: true, transition: %{duration: 300}),
        ordinal_scale(:color),
        axis(:x, :bottom, ticks: 10),
        axis(:y, :left, ticks: 5),
        legend(:color, position: :top_right, inside: false),

        # The fold makes one row per point per column the row has; `series` on the folded
        # key splits the mark into one path per column and colours each from `color`.
        line(
          fold(:series, [:series_a, :series_b, :series_c, :series_d], as: [:series, :y]),
          %{x: :x, y: :y, series: :series},
          style: :wave
        )
      ])

    {:ok, applied} = Visualize.Chart.apply(design, sources: %{series: rows})
    Visualize.Chart.render(applied)
    """
  end
end
