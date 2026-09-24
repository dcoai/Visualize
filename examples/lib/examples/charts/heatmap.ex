defmodule Examples.Charts.Heatmap do
  @moduledoc """
  Heatmap as a design (#128): one `:rect` mark over a linear `x` and a band `y`, its
  `value` reaching the `color` scale as each cell's fill.

  A cell is the hour's rectangle — `x0` the hour, `x1` the hour after, on a linear scale
  over the day — in the day's band, and its `value` is what a `:rect`'s `value` channel is:
  the reading the frame's `color` scale maps to the element's fill (spec/14 §5.6). The
  `:sequential` scale runs from the theme's background to its first series colour, so a
  palette swap recolours the map; the legend that explains it sits in the top margin
  (`inside: false`, §4.5, #136), and the two axes are real axes where the hand-written
  version placed its labels by hand.

  The activity pattern is deterministic — a hash of the cell stands in for the random draw
  the hand-written version made on every render — so the chart holds a golden.
  """

  import Visualize.Chart.Build

  alias Examples.Charts.Design

  @margin %{top: 36, right: 30, bottom: 45, left: 60}
  @days ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

  def title, do: "Heatmap"
  def description, do: "Hourly activity by day of week"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        source(:cells, [:day, :hour, :hour_end, :value]),
        style(:cell, stroke: :background, stroke_width: 1),
        cartesian(margin: @margin),
        linear_scale(:x, domain: [0, 24]),
        band_scale(:y, domain: @days),
        sequential_scale(:color, domain: [0, :auto]),
        axis(:x, :bottom, ticks: 6),
        axis(:y, :left),
        label({:axis, :x}, ["Hour"]),
        legend(:color, position: :top, inside: false, title: ["Activity"]),
        rect(:cells, %{x0: :hour, x1: :hour_end, y0: :day, y1: :day, value: :value},
          options: %{corner_radius: 2},
          style: :cell
        )
      ])

    {design, %{cells: rows(opts[:animation_tick])}}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  # One row per day per hour. Static, the working hours of a weekday and the afternoons of
  # a weekend are busy, with a deterministic scatter; animated, waves ripple across.
  defp rows(tick) do
    for {day, d} <- Enum.with_index(@days), hour <- 0..23 do
      %{day: day, hour: hour, hour_end: hour + 1, value: activity(d, hour, tick)}
    end
  end

  defp activity(day, hour, nil) do
    {base, spread} =
      cond do
        day < 5 and hour in 9..17 -> {70, 30}
        day < 5 and hour in 7..20 -> {30, 30}
        day < 5 -> {0, 20}
        hour in 10..22 -> {20, 40}
        true -> {0, 15}
      end

    base + rem(:erlang.phash2({day, hour}), spread) + 1
  end

  defp activity(day, hour, tick) do
    base =
      cond do
        day < 5 and hour in 9..17 -> 70
        day < 5 and hour in 7..20 -> 40
        day < 5 -> 15
        hour in 10..22 -> 35
        true -> 10
      end

    wave = 25 * :math.sin(day / 2 + hour / 4 + tick * 0.15)
    max(5, min(100, base + wave))
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Heatmap"}),
        source(:cells, [:day, :hour, :hour_end, :value]),
        style(:cell, stroke: :background, stroke_width: 1),
        cartesian(margin: %{top: 36, right: 30, bottom: 45, left: 60}),
        linear_scale(:x, domain: [0, 24]),
        band_scale(:y, domain: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]),
        # Background to the first series colour; a palette swap recolours the map.
        sequential_scale(:color, domain: [0, :auto]),
        axis(:x, :bottom, ticks: 6),
        axis(:y, :left),
        label({:axis, :x}, ["Hour"]),
        legend(:color, position: :top, inside: false, title: ["Activity"]),
        # Each cell is the hour's rectangle in the day's band; its value is its fill.
        rect(:cells, %{x0: :hour, x1: :hour_end, y0: :day, y1: :day, value: :value},
          options: %{corner_radius: 2},
          style: :cell
        )
      ])

    {:ok, applied} = Visualize.Chart.apply(design, sources: %{cells: cells})
    Visualize.Chart.render(applied)
    """
  end
end
