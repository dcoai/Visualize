defmodule Examples.Charts.StackedBarChart do
  @moduledoc """
  Stacked bar chart as a design (#125): a `:stack` transform under one `:rect` mark.

  The same transform the stacked area uses (spec/14 §5.4.1), read by a rectangle instead of
  an area: `x0` and `x1` on the year are the band, `y0` and `y1` are the segment's baseline
  and top, and the `key` column reaches the `color` scale through the mark's style, which is
  what the legend explains.

  The hand-drawn tick lines are a real y axis with `grid: true` now, its ticks carrying
  the `%` through the axis's `unit` — the values are shares already, which a specifier's
  `%` would multiply by a hundred (spec/14 §4.4, #135). The legend
  draws in the right margin the chart reserves for it (spec/14 §4.5, #136).
  """

  import Visualize.Chart.Build

  alias Examples.Charts.Design

  @margin %{top: 30, right: 100, bottom: 50, left: 50}
  @keys [:desktop, :mobile, :tablet, :other]

  @data [
    %{year: "2019", desktop: 45, mobile: 35, tablet: 15, other: 5},
    %{year: "2020", desktop: 40, mobile: 42, tablet: 13, other: 5},
    %{year: "2021", desktop: 35, mobile: 48, tablet: 12, other: 5},
    %{year: "2022", desktop: 30, mobile: 52, tablet: 12, other: 6},
    %{year: "2023", desktop: 28, mobile: 55, tablet: 11, other: 6}
  ]

  def title, do: "Stacked Bar Chart"
  def description, do: "Device usage trends"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        source(:devices, [:year | @keys]),
        style(:segment, fill: {:field, :key}),
        cartesian(opts[:width] || 500, opts[:height] || 350, margin: @margin),
        band_scale(:x, padding: 0.2),
        linear_scale(:y, domain: [0, :auto], transition: %{duration: 300}),
        ordinal_scale(:color, domain: @keys),
        axis(:x, :bottom),
        axis(:y, :left, ticks: 5, grid: true, unit: "%"),
        legend(:color, position: :top_right, inside: false),
        rect(stack(from(:devices), @keys), %{x0: :year, x1: :year, y0: :y0, y1: :y1},
          style: :segment
        )
      ])

    {design, %{devices: rows(opts)}}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  defp rows(opts) do
    data = opts[:data] || @data

    case opts[:animation_tick] do
      nil -> data
      tick -> animated(data, tick)
    end
  end

  # Animation: device usage shifts over time, each category at its own phase.
  defp animated(data, tick) do
    Enum.with_index(data, fn item, i ->
      phase = i * 0.6

      %{
        item
        | desktop: item.desktop * (1.0 + 0.25 * :math.sin(tick * 0.08 + phase)),
          mobile: item.mobile * (1.0 + 0.2 * :math.sin(tick * 0.08 + phase + 1.5)),
          tablet: item.tablet * (1.0 + 0.3 * :math.sin(tick * 0.08 + phase + 3)),
          other: item.other * (1.0 + 0.35 * :math.sin(tick * 0.08 + phase + 4.5))
      }
    end)
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    keys = [:desktop, :mobile, :tablet, :other]

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Stacked Bar Chart"}),
        source(:devices, [:year | keys]),

        # A {:field, f} on a colour key is read per element, through the `color` scale.
        style(:segment, fill: {:field, :key}),
        cartesian(500, 350, margin: %{top: 30, right: 100, bottom: 50, left: 50}),
        band_scale(:x, padding: 0.2),
        linear_scale(:y, domain: [0, :auto], transition: %{duration: 300}),
        ordinal_scale(:color, domain: keys),
        axis(:x, :bottom),
        axis(:y, :left, ticks: 5, grid: true, unit: "%"),
        legend(:color, position: :top_right, inside: false),
        rect(stack(from(:devices), keys), %{x0: :year, x1: :year, y0: :y0, y1: :y1},
          style: :segment
        )
      ])

    {:ok, applied} = Visualize.Chart.apply(design, sources: %{devices: data})
    Visualize.Chart.render(applied)
    """
  end
end
