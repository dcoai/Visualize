defmodule Examples.Charts.LoadGauge do
  @moduledoc """
  A machine's load average on one dial (#415): a polar frame sweeping 240° from −120° over
  a load of 0 to 4, the angle axis an arc at 0.86 R with its numbers outward, a rim just
  inside it, and **three needles on the one dial** — the fifteen-, five- and
  one-minute windows (`Examples.Charts.Load`), each its own length so they read where they
  overlap and its own colour through the `color` scale (`fill: {:field, :window}`, spec/14
  §3.4). Animated, the three pointers chase each other as the load wanders: the one-minute
  needle swings, the fifteen-minute one drifts.

  Its neighbour `Examples.Charts.LoadAge` draws the same three windows over the last three
  hours. They are two designs because a design has one frame (§4) and a dial and a plot
  cannot share it; `frames` will let them sit in one chart (#383).
  """

  import Visualize.Chart.Build

  alias Examples.Charts.{Design, Load}

  @margin %{top: 30, right: 90, bottom: 30, left: 40}
  # The outermost needle is the longest: the shortest window swings the most.
  @lengths %{one: 0.62, five: 0.5, fifteen: 0.38}

  def title, do: "Load gauge"
  def description, do: "Three load averages as three needles on one dial"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    width = opts[:width] || 420
    height = opts[:height] || 420
    outer = min(width - @margin.left - @margin.right, height - @margin.top - @margin.bottom) / 2

    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        source(:reading, [:window, :load, :length],
          types: %{window: :category, load: :number, length: :number}
        ),
        source(:rim, [:at], types: %{at: :number}),
        style(:rim, fill: :grid, opacity: 0.45, stroke: :none),
        style(:pointer, fill: {:field, :window}, stroke: :background, stroke_width: 1),
        style(:dial, extends: :axis, font_size: 11),
        polar(width, height, margin: @margin),
        linear_scale(:angle, domain: [0, 4], start: -120, sweep: 240),
        linear_scale(:r, domain: [0, 1], range: [0, outer]),
        ordinal_scale(:color,
          domain: Enum.map(Load.windows(), &elem(&1, 1)),
          range: [:series_1, :series_2, :series_3]
        ),
        axis(:angle, :bottom, ticks: 5, radius: 0.86, grid: true, style: :dial),
        legend(:color, position: :top_right, inside: false),
        # The dial's rim, one sector of the whole sweep just inside the axis (§5.2).
        rect(:rim, %{x0: 0, x1: 4, y0: 0.72, y1: 0.84}, style: :rim),
        # Three rows, three needles, each its own length and colour (spec/14 §5.2).
        needle(:reading, %{x: :load, y: :length},
          options: %{width: 7, tail: 12, hub: 7},
          style: :pointer
        )
      ])

    {design, %{reading: rows(opts), rim: [%{at: 0}]}}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  defp rows(opts) do
    now = second(opts)

    for {window, name} <- Load.windows() do
      %{window: name, load: Load.at(window, now), length: @lengths[window]}
    end
  end

  # A tick is a second of the machine's day; at rest the dial reads its first second.
  defp second(opts), do: (opts[:animation_tick] || 0) * 3

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Load gauge"}),
        source(:reading, [:window, :load, :length]),
        # Each needle takes its colour from its row through the colour scale (§3.4).
        style(:pointer, fill: {:field, :window}, stroke: :background, stroke_width: 1),
        polar(420, 420, margin: %{top: 30, right: 90, bottom: 30, left: 40}),
        # 240° of dial from −120°, over a load of 0 to 4 (spec/14 §4.3).
        linear_scale(:angle, domain: [0, 4], start: -120, sweep: 240),
        linear_scale(:r, domain: [0, 1], range: [0, 150]),
        ordinal_scale(:color, domain: ["1 min", "5 min", "15 min"], range: [:series_1, :series_2, :series_3]),
        axis(:angle, :bottom, ticks: 5, radius: 0.86, grid: true),
        legend(:color, position: :top_right, inside: false),
        # One row per window: three needles on the one dial, each its own length.
        needle(:reading, %{x: :load, y: :length},
          options: %{width: 7, tail: 12, hub: 7},
          style: :pointer
        )
      ])

    reading = [
      %{window: "1 min", load: 2.4, length: 0.62},
      %{window: "5 min", load: 1.9, length: 0.5},
      %{window: "15 min", load: 1.3, length: 0.38}
    ]

    {:ok, applied} = Visualize.Chart.apply(design, sources: %{reading: reading})
    Visualize.Chart.render(applied)
    """
  end
end
