defmodule Examples.Charts.DonutChart do
  @moduledoc """
  Donut chart as a design (#126): the pie chart's `:arc` with an inner radius, plus the two
  texts in the hole.

  The hole's total and its caption are frame labels at `{:data, [0, 0]}` — the polar frame's
  data anchor maps an angle and a radius through its own scales (spec/14 §6.3), and radius
  zero is the centre — which is why the frame declares an `angle` and an `r` scale it draws
  no axis for.

  The legend draws inside the plot area, in the right margin the chart already reserved for
  it (#136).
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

  def title, do: "Donut Chart"
  def description, do: "Revenue by product category"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    width = opts[:width] || 400
    height = opts[:height] || 400
    rows = rows(opts)
    outer = min(width, height) / 2 - 40
    total = rows |> Enum.map(& &1.revenue) |> Enum.sum()

    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        source(:slices, [:category, :revenue, :index]),
        style(:slice, fill: {:field, :index}, stroke: :background, stroke_width: 1),
        style(:total, extends: :label, font_size: 28, font_weight: :bold, text_anchor: :middle),
        style(:total_caption, extends: :label, font_size: 14, text_anchor: :middle),
        polar(width + @legend_width, height, margin: @margin),
        ordinal_scale(:color, domain: Enum.map(rows, & &1.category)),

        # Declared so the centre has coordinates; no axis draws either of them.
        linear_scale(:angle, domain: [0, 1]),
        linear_scale(:r, domain: [0, 1]),
        legend(:color, position: :right),
        arc(:slices, %{value: :revenue},
          options: %{inner_radius: outer * 0.6, outer_radius: outer, pad_angle: 0.02},
          style: :slice
        ),
        label({:data, [0, 0]}, [currency(total)], dy: -10, style: :total),
        label({:data, [0, 0]}, ["Total Revenue"], dy: 15, style: :total_caption)
      ])

    {design, %{slices: rows}}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  defp rows(opts) do
    data = opts[:data] || @data

    data =
      case opts[:animation_tick] do
        nil -> data
        tick -> animated(data, tick)
      end

    Enum.with_index(data, fn row, i -> Map.put(row, :index, i) end)
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
        source(:slices, [:category, :revenue, :index]),
        style(:slice, fill: {:field, :index}, stroke: :background, stroke_width: 1),
        style(:total, extends: :label, font_size: 28, font_weight: :bold, text_anchor: :middle),
        polar(520, 400, margin: %{top: 0, right: 120, bottom: 0, left: 0}),
        ordinal_scale(:color, domain: Enum.map(rows, & &1.category)),

        # Declared so the centre has coordinates; no axis draws either of them.
        linear_scale(:angle, domain: [0, 1]),
        linear_scale(:r, domain: [0, 1]),
        legend(:color, position: :right),

        # An inner radius is all that separates a donut from a pie.
        arc(:slices, %{value: :revenue},
          options: %{inner_radius: 96, outer_radius: 160, pad_angle: 0.02},
          style: :slice
        ),

        # A polar {:data, [angle, r]} anchor at radius zero is the hole.
        label({:data, [0, 0]}, ["$1000K"], dy: -10, style: :total)
      ])

    {:ok, applied} = Visualize.Chart.apply(design, sources: %{slices: rows})
    Visualize.Chart.render(applied)
    """
  end
end
