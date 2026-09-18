defmodule Examples.Charts.HorizontalBarChart do
  @moduledoc """
  Horizontal bar chart as a design (#125): a `:sort` transform under one `:rect` mark, with
  the band scale on `y`.

  The value at the end of each bar is the `:rect`'s own inline label at the `:x1` edge
  anchor (spec/14 §5.5, #134) — it once needed a zero-radius `:circle` to carry it. The x
  axis keeps its `M` through the axis's `unit` (spec/14 §4.4, #135), as the bar labels keep
  theirs through a literal part of their text; the ticks at a thousand and above print in
  exponent form until #354 fixes the default label.

  The `y` range is written out because `:auto` runs upward and the categories read downward,
  as `Visualize.Chart.Presets.horizontal_bar_chart/1` does.
  """

  import Visualize.Chart.Build

  alias Examples.Charts.Design

  @margin %{top: 20, right: 30, bottom: 40, left: 100}

  @data [
    %{country: "China", population: 1412},
    %{country: "India", population: 1380},
    %{country: "United States", population: 331},
    %{country: "Indonesia", population: 273},
    %{country: "Pakistan", population: 220},
    %{country: "Brazil", population: 212},
    %{country: "Nigeria", population: 206},
    %{country: "Bangladesh", population: 164}
  ]

  def title, do: "Horizontal Bar Chart"
  def description, do: "World population by country (millions)"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    width = opts[:width] || 600
    height = opts[:height] || 400
    {_plot_width, plot_height} = Design.plot(width, height, @margin)

    # Both marks read the same pipeline, so the band's domain is the sorted order once.
    data = sort(from(:countries), :population, order: :descending)

    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        source(:countries, [:country, :population]),
        cartesian(width, height, margin: @margin),
        linear_scale(:x, domain: [0, :auto], nice: true),
        band_scale(:y, padding: 0.2, range: [0, plot_height]),
        ordinal_scale(:color),
        axis(:x, :bottom, ticks: 5, unit: "M"),
        axis(:y, :left),
        rect(data, %{x0: 0, x1: :population, y0: :country, y1: :country, value: :country},
          options: %{corner_radius: 2},
          label: %{text: [{:field, :population}, "M"], anchor: :x1}
        )
      ])

    {design, %{countries: rows(opts)}}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  defp rows(opts) do
    data = opts[:data] || @data

    case opts[:animation_tick] do
      nil -> data
      tick -> animated(data, tick)
    end
  end

  # Animation: bars grow and shrink with different phases.
  defp animated(data, tick) do
    Enum.with_index(data, fn item, i ->
      %{item | population: item.population * (1.0 + 0.3 * :math.sin(tick * 0.1 + i * 0.4))}
    end)
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    # One pipeline read by both marks, so the band's domain is the sorted order once.
    data = sort(from(:countries), :population, order: :descending)

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Horizontal Bar Chart"}),
        source(:countries, [:country, :population]),
        cartesian(600, 400, margin: %{top: 20, right: 30, bottom: 40, left: 100}),
        linear_scale(:x, domain: [0, :auto], nice: true),

        # `:auto` on a band runs upward; the categories read downward, so the range is given.
        band_scale(:y, padding: 0.2, range: [0, 340]),
        ordinal_scale(:color),
        axis(:x, :bottom, ticks: 5, unit: "M"),
        axis(:y, :left),
        # The value past the end of each bar: the rect's own label at its x1 edge (#134).
        rect(data, %{x0: 0, x1: :population, y0: :country, y1: :country, value: :country},
          options: %{corner_radius: 2},
          label: %{text: [{:field, :population}, "M"], anchor: :x1}
        )
      ])

    {:ok, applied} = Visualize.Chart.apply(design, sources: %{countries: data})
    Visualize.Chart.render(applied)
    """
  end
end
