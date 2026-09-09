defmodule Examples.Charts.MultiLineChart do
  @moduledoc """
  Multi-series line chart as a design (#125): one `:line` mark with a `series` channel.

  The four hand-built path elements, their four colours and the hand-laid legend are one
  mark, one ordinal `color` scale and one `legend` node: a `series` channel splits the mark
  into one path per distinct value and colours each from the scale (spec/14 §5.6), and the
  legend explains the same scale. The data reaches the design as one table with a `series`
  column rather than as a map of series, which is what a mark reads.

  The legend draws *inside* the plot area, at the top right of the right margin the chart
  already reserved for it, because that is the only place the layer can put one (#136).
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
        source(:series, [:x, :y, :series]),
        style(:wave, stroke_width: 2, curve: :monotone_x),
        cartesian(opts[:width] || 600, opts[:height] || 400, margin: @margin),
        linear_scale(:x),
        linear_scale(:y, nice: true),
        ordinal_scale(:color),
        axis(:x, :bottom, ticks: 10),
        axis(:y, :left, ticks: 5),
        legend(:color, position: :top_right),
        line(:series, %{x: :x, y: :y, series: :series}, style: :wave)
      ])

    {design, %{series: rows(opts)}}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  # One row per point, the series named as the legend prints it. The key order is fixed by
  # sorting, so the colour a series takes never depends on map iteration order.
  defp rows(opts) do
    for {key, points} <- Enum.sort_by(series(opts), &elem(&1, 0)),
        point <- points,
        do: Map.put(point, :series, format_key(key))
  end

  defp series(opts) do
    case opts[:animation_tick] do
      nil -> opts[:data] || @data
      tick -> animated(tick)
    end
  end

  defp format_key(key) do
    key
    |> to_string()
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
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

    # One table with a series column, not a map of series: a mark reads rows.
    rows = [%{x: 0, y: 50.0, series: "Series A"}, %{x: 0, y: 45.0, series: "Series B"}, ...]

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Multi-line Chart"}),
        source(:series, [:x, :y, :series]),
        style(:wave, stroke_width: 2, curve: :monotone_x),
        cartesian(600, 400, margin: %{top: 20, right: 120, bottom: 30, left: 50}),
        linear_scale(:x),
        linear_scale(:y, nice: true),
        ordinal_scale(:color),
        axis(:x, :bottom, ticks: 10),
        axis(:y, :left, ticks: 5),
        legend(:color, position: :top_right),

        # `series` splits the mark into one path per value and colours each from `color`.
        line(:series, %{x: :x, y: :y, series: :series}, style: :wave)
      ])

    {:ok, applied} = Visualize.Chart.apply(design, sources: %{series: rows})
    Visualize.Chart.render(applied)
    """
  end
end
