defmodule Examples.Charts.DonutChart do
  @moduledoc """
  Donut chart as a design (#126): the pie chart's `:arc` with an inner radius, plus the two
  texts in the hole.

  The hole's total and its caption are frame labels at `{:frame, :center}`, the plot's
  centre — the polar origin (spec/14 §6.3, #489) — so the frame declares no `angle` or `r`
  scale only to give the centre coordinates.

  The legend draws in the right margin the chart reserves for it, `inside: false` at the
  right, centred (spec/14 §4.5, #136). The ring is sized from the plot area that margin
  leaves, not from the box, so it stays inside the plot, and a slice is filled by its
  category, the values the colour scale's domain holds (#487).
  """

  import Visualize.Chart.Build

  alias Examples.Charts.Design

  @legend_width 120
  @margin %{top: 0, right: @legend_width, bottom: 0, left: 0}

  @data [
    %{category: "Product A", revenue: 420_000},
    %{category: "Product B", revenue: 280_000},
    %{category: "Product C", revenue: 180_000},
    %{category: "Product D", revenue: 90_000},
    %{category: "Product E", revenue: 30_000}
  ]

  @doc "The size this chart is drawn at when the caller names none (spec/14 §4.2)."
  def size, do: {400, 400}

  def title, do: "Donut Chart"
  def description, do: "Revenue by product category"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    {width, height} = Design.size(__MODULE__, opts)
    rows = rows(opts)
    # The polar centre is the plot area's, so the ring is sized from the plot (#487).
    plot_width = width - @margin.left - @margin.right
    plot_height = height - @margin.top - @margin.bottom
    outer = min(plot_width, plot_height) / 2 - 20
    total = rows |> Enum.map(& &1.revenue) |> Enum.sum()

    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        source(:slices, [:category, :revenue]),
        style(:slice, fill: {:field, :category}, stroke: :background, stroke_width: 1),
        style(:total, extends: :label, font_size: 28, font_weight: :bold, text_anchor: :middle),
        style(:total_caption, extends: :label, font_size: 14, text_anchor: :middle),
        polar(margin: @margin),
        ordinal_scale(:color, domain: Enum.map(rows, & &1.category)),
        legend(:color, position: :right, inside: false),
        arc(:slices, %{value: :revenue},
          options: %{inner_radius: outer * 0.6, outer_radius: outer, pad_angle: 0.02},
          style: :slice
        ),
        label({:frame, :center}, [currency(total)], dy: -10, style: :total),
        label({:frame, :center}, ["Total Revenue"], dy: 15, style: :total_caption)
      ])

    {design, %{slices: rows}}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  defp rows(opts) do
    data = opts[:data] || @data

    case opts[:animation_tick] do
      nil -> data
      tick -> animated(data, tick)
    end
  end

  defp currency(value), do: "$#{trunc(value / 1000)}K"

  # Animation: vary slice sizes with different phases.
  defp animated(data, tick) do
    Enum.with_index(data, fn item, i ->
      %{item | revenue: item.revenue * (1.0 + 0.4 * :math.sin(tick * 0.12 + i * 0.7))}
    end)
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Donut Chart"}),
        source(:slices, [:category, :revenue]),
        # A slice is filled by its category: the values the colour scale's domain holds.
        style(:slice, fill: {:field, :category}, stroke: :background, stroke_width: 1),
        style(:total, extends: :label, font_size: 28, font_weight: :bold, text_anchor: :middle),
        polar(margin: %{top: 0, right: 120, bottom: 0, left: 0}),
        ordinal_scale(:color, domain: Enum.map(rows, & &1.category)),
        legend(:color, position: :right, inside: false),

        # An inner radius is all that separates a donut from a pie. The ring fits the
        # 280 x 400 plot the legend's margin leaves.
        arc(:slices, %{value: :revenue},
          options: %{inner_radius: 72, outer_radius: 120, pad_angle: 0.02},
          style: :slice
        ),

        # The plot's centre, the polar origin: the hole.
        label({:frame, :center}, ["$1000K"], dy: -10, style: :total)
      ])

    {:ok, applied} = Visualize.Chart.apply(design, sources: %{slices: rows})
    Visualize.Chart.render(applied)
    """
  end
end
