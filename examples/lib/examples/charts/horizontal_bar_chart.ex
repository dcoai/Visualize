defmodule Examples.Charts.HorizontalBarChart do
  @moduledoc """
  Horizontal bar chart as a design (#125): a `:sort` transform under one `:rect` mark, with
  the band scale on `y`.

  Two things the layer decides differently from the imperative chart, both filed:

  - **The value at the end of each bar needs a carrier mark.** A `:rect`'s inline label
    anchors at the rectangle's *centre* (spec/14 §5.5), and there is no `:text` mark, so the
    text is carried by a second mark — a `:circle` whose `value` channel is the constant `0`,
    which draws `<circle r="0">` and nothing else (#134).
  - **The x axis lost its `M`.** A `Visualize.Format` specifier has no unit suffix (#135), so
    the millions are named in the axis title instead of on every tick. The bar labels keep
    theirs, because a label's text is a list and a literal is one of its parts.

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
        style(:value, fill: :none),
        cartesian(width, height, margin: @margin),
        linear_scale(:x, domain: [0, :auto], nice: true),
        band_scale(:y, padding: 0.2, range: [0, plot_height]),
        ordinal_scale(:color),
        axis(:x, :bottom, ticks: 5),
        axis(:y, :left),
        label({:axis, :x}, ["population (millions)"]),
        rect(data, %{x0: 0, x1: :population, y0: :country, y1: :country, value: :country},
          options: %{corner_radius: 2}
        ),
        circle(data, %{x: :population, y: :country, value: 0},
          label: %{text: [{:field, :population}, "M"], anchor: :right},
          style: :value
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
        style(:value, fill: :none),
        cartesian(600, 400, margin: %{top: 20, right: 30, bottom: 40, left: 100}),
        linear_scale(:x, domain: [0, :auto], nice: true),

        # `:auto` on a band runs upward; the categories read downward, so the range is given.
        band_scale(:y, padding: 0.2, range: [0, 340]),
        ordinal_scale(:color),
        axis(:x, :bottom, ticks: 5),
        axis(:y, :left),
        label({:axis, :x}, ["population (millions)"]),
        rect(data, %{x0: 0, x1: :population, y0: :country, y1: :country, value: :country},
          options: %{corner_radius: 2}
        ),

        # The carrier for the value text: `value: 0` is a zero-radius circle (#134).
        circle(data, %{x: :population, y: :country, value: 0},
          label: %{text: [{:field, :population}, "M"], anchor: :right},
          style: :value
        )
      ])

    {:ok, applied} = Visualize.Chart.apply(design, sources: %{countries: data})
    Visualize.Chart.render(applied)
    """
  end
end
