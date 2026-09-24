defmodule Examples.Charts.GroupedBarChart do
  @moduledoc """
  Grouped bar chart as a design (#125, #132): one `:rect` mark over one row per bar, the
  series placed within the quarter's band by an **offset** — `offset: %{x: :series}` on
  the mark and an `x_offset` band scale in the frame whose range is the quarter band's
  width (spec/14 §4.3, §5.1, D-109). The wide rows of the imperative chart are folded
  to long ones by the `:fold` transform, so the design reads `quarter`, `series`, `value`.
  """

  import Visualize.Chart.Build

  alias Examples.Charts.Design

  @margin %{top: 30, right: 100, bottom: 50, left: 60}

  @data [
    %{category: "Q1", sales: 120, expenses: 90, profit: 30},
    %{category: "Q2", sales: 150, expenses: 100, profit: 50},
    %{category: "Q3", sales: 180, expenses: 120, profit: 60},
    %{category: "Q4", sales: 200, expenses: 130, profit: 70}
  ]
  @series [:sales, :expenses, :profit]

  @doc "The size this chart is drawn at when the caller names none (spec/14 §4.2)."
  def size, do: {500, 350}

  def title, do: "Grouped Bar Chart"
  def description, do: "Quarterly financial comparison"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        source(:quarters, [:category, :sales, :expenses, :profit]),
        style(:bar, fill: {:field, :series}),
        cartesian(margin: @margin),
        band_scale(:x, padding: 0.2),
        band_scale(:x_offset, padding: 0.05),
        linear_scale(:y, domain: [0, :auto], nice: true, transition: %{duration: 300}),
        ordinal_scale(:color, domain: @series),
        axis(:x, :bottom),
        axis(:y, :left, ticks: 5, grid: true),
        legend(:color, position: :top_right, inside: false),
        # One row per bar: the wide quarter folded to (quarter, series, value); the series
        # places the bar within its quarter's band through the offset (D-109).
        rect(
          fold(:quarters, @series, as: [:series, :value]),
          %{x0: :category, x1: :category, y0: 0, y1: :value},
          offset: %{x: :series},
          options: %{corner_radius: 2},
          style: :bar
        )
      ])

    {design, %{quarters: rows(opts)}}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  defp rows(opts) do
    base = opts[:data] || @data

    case opts[:animation_tick] do
      nil -> base
      tick -> animate(base, tick)
    end
  end

  # Animation: each series oscillates about its value with its own phase.
  defp animate(data, tick) do
    for {item, i} <- Enum.with_index(data) do
      phase = i * 0.5

      %{
        item
        | sales: item.sales * (1.0 + 0.3 * :math.sin(tick * 0.1 + phase)),
          expenses: item.expenses * (1.0 + 0.3 * :math.sin(tick * 0.1 + phase + 1)),
          profit: item.profit * (1.0 + 0.4 * :math.sin(tick * 0.1 + phase + 2))
      }
    end
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Grouped Bar Chart"}),
        source(:quarters, [:category, :sales, :expenses, :profit]),
        style(:bar, fill: {:field, :series}),
        cartesian(margin: %{top: 30, right: 100, bottom: 50, left: 60}),
        band_scale(:x, padding: 0.2),
        # The band within the band: its range is the quarter band's width (spec/14 §4.3).
        band_scale(:x_offset, padding: 0.05),
        linear_scale(:y, domain: [0, :auto], nice: true, transition: %{duration: 300}),
        ordinal_scale(:color, domain: [:sales, :expenses, :profit]),
        axis(:x, :bottom),
        axis(:y, :left, ticks: 5, grid: true),
        legend(:color, position: :top_right, inside: false),
        # One rect per bar; the series places it within its quarter (D-109).
        rect(fold(:quarters, [:sales, :expenses, :profit], as: [:series, :value]),
          %{x0: :category, x1: :category, y0: 0, y1: :value},
          offset: %{x: :series},
          style: :bar
        )
      ])

    {:ok, applied} = Visualize.Chart.apply(design, sources: %{quarters: quarters})
    Visualize.Chart.render(applied)
    """
  end
end
