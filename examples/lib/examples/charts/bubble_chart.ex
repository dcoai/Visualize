defmodule Examples.Charts.BubbleChart do
  @moduledoc """
  Bubble chart as a design (#125): three dimensions on one `:circle` mark, with a second,
  filtered `:text` mark naming the big ones.

  The pipeline does the work the caller used to: `:sort` draws the largest bubbles first,
  and a `:filter` on the radius is what makes only the big ones carry a name — a condition
  on a *label* is a condition on the rows the labeling mark reads. That second mark is a
  `:text` (spec/14 §5.2, #134); it once was a zero-radius circle carrying a label.
  Each name is haloed in the page color, its stroke drawn under its glyphs, so it reads
  over the translucent bubbles and the grid behind it (spec/14 §3.1, #927, D-235).

  The bubble's radius is a column, because a `:circle`'s `value` is user units and names no
  scale (spec/14 §5.2). The hand-drawn ticks are real axes now, their units on every tick
  through the axes' `prefix` and `unit` — `$…T`, `…M` (spec/14 §4.4, #135); the legend is
  in the right margin the chart reserves for it (spec/14 §4.5, #136).
  """

  import Visualize.Chart.Build

  alias Examples.Charts.Design

  @margin %{top: 30, right: 120, bottom: 50, left: 70}
  @regions ["Americas", "Asia", "Europe", "Oceania"]

  @data [
    %{name: "US", gdp: 21.4, population: 331, region: "Americas"},
    %{name: "China", gdp: 14.7, population: 1412, region: "Asia"},
    %{name: "Japan", gdp: 5.1, population: 126, region: "Asia"},
    %{name: "Germany", gdp: 4.2, population: 83, region: "Europe"},
    %{name: "UK", gdp: 2.8, population: 67, region: "Europe"},
    %{name: "France", gdp: 2.9, population: 67, region: "Europe"},
    %{name: "India", gdp: 2.9, population: 1380, region: "Asia"},
    %{name: "Italy", gdp: 2.1, population: 60, region: "Europe"},
    %{name: "Brazil", gdp: 1.4, population: 213, region: "Americas"},
    %{name: "Canada", gdp: 1.6, population: 38, region: "Americas"},
    %{name: "Russia", gdp: 1.5, population: 144, region: "Europe"},
    %{name: "Australia", gdp: 1.3, population: 26, region: "Oceania"},
    %{name: "Spain", gdp: 1.4, population: 47, region: "Europe"},
    %{name: "Mexico", gdp: 1.1, population: 129, region: "Americas"},
    %{name: "Indonesia", gdp: 1.1, population: 274, region: "Asia"}
  ]

  def title, do: "Bubble Chart"
  def description, do: "GDP vs Population (bubble = GDP per capita)"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    largest_first = sort(from(:countries), :r, order: :descending)
    named = filter(largest_first, :r, test: :gt, value: 15)

    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        source(:countries, [:name, :gdp, :population, :region, :r]),
        style(:bubble,
          fill: {:field, :region},
          fill_opacity: 0.7,
          stroke: {:field, :region},
          stroke_width: 1
        ),
        # A halo in the page color under each name, so it reads over the bubbles and the
        # grid it crosses (spec/14 §3.1, D-235).
        style(:name,
          extends: :label,
          font_size: 9,
          font_weight: :bold,
          stroke: :background,
          stroke_width: 3,
          stroke_linejoin: :round
        ),
        style(:caption, extends: :label, font_size: 9, fill: :axis),
        cartesian(margin: @margin),
        linear_scale(:x, domain: [0, 1500]),
        linear_scale(:y, domain: [0, 25]),
        ordinal_scale(:color, domain: @regions),
        axis(:x, :bottom, ticks: [0, 300, 600, 900, 1200, 1500], unit: "M"),
        axis(:y, :left, ticks: [0, 5, 10, 15, 20, 25], grid: true, prefix: "$", unit: "T"),
        label({:axis, :x}, ["Population"]),
        label({:axis, :y}, ["GDP"]),
        label({:frame, :bottom_right}, ["Size = GDP/capita"], style: :caption),
        legend(:color, position: :top_right, inside: false),
        circle(largest_first, %{x: :population, y: :gdp, value: :r}, style: :bubble),
        text(named, %{x: :population, y: :gdp},
          label: %{text: [{:field, :name}], anchor: :middle, style: :name}
        )
      ])

    {design, %{countries: rows(opts)}}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  # The radius is a column: GDP per capita over the data's own maximum, 5 to 40 user units.
  defp rows(opts) do
    data = opts[:data] || @data

    data =
      case opts[:animation_tick] do
        nil -> data
        tick -> animated(data, tick)
      end

    per_capita = Enum.map(data, &(&1.gdp * 1000 / &1.population))
    max = Enum.max(per_capita)

    Enum.zip_with(data, per_capita, fn row, value ->
      Map.put(row, :r, 5 + 35 * value / max)
    end)
  end

  # Animation: bubbles gently float and pulse.
  defp animated(data, tick) do
    Enum.with_index(data, fn item, i ->
      phase = i * 0.7

      %{
        item
        | gdp: item.gdp * (1.0 + 0.15 * :math.sin(tick * 0.08 + phase)),
          population: item.population * (1.0 + 0.03 * :math.sin(tick * 0.05 + phase + 2))
      }
    end)
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    # The pipeline does the work: largest first, and only the big ones are named.
    largest_first = sort(from(:countries), :r, order: :descending)
    named = filter(largest_first, :r, test: :gt, value: 15)

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Bubble Chart"}),
        source(:countries, [:name, :gdp, :population, :region, :r]),
        style(:bubble,
          fill: {:field, :region},
          fill_opacity: 0.7,
          stroke: {:field, :region},
          stroke_width: 1
        ),
        # A halo in the page color, drawn under each name: it reads over the bubbles.
        style(:name,
          extends: :label,
          font_size: 9,
          font_weight: :bold,
          stroke: :background,
          stroke_width: 3,
          stroke_linejoin: :round
        ),
        cartesian(margin: %{top: 30, right: 120, bottom: 50, left: 70}),
        linear_scale(:x, domain: [0, 1500]),
        linear_scale(:y, domain: [0, 25]),
        ordinal_scale(:color, domain: ["Americas", "Asia", "Europe", "Oceania"]),
        axis(:x, :bottom, ticks: [0, 300, 600, 900, 1200, 1500], unit: "M"),
        axis(:y, :left, ticks: [0, 5, 10, 15, 20, 25], grid: true, prefix: "$", unit: "T"),
        label({:axis, :x}, ["Population"]),
        label({:axis, :y}, ["GDP"]),
        legend(:color, position: :top_right, inside: false),
        circle(largest_first, %{x: :population, y: :gdp, value: :r}, style: :bubble),

        # The names: a :text mark over the filtered rows (#134).
        text(named, %{x: :population, y: :gdp},
          label: %{text: [{:field, :name}], anchor: :middle, style: :name}
        )
      ])

    {:ok, applied} = Visualize.Chart.apply(design, sources: %{countries: data})
    Visualize.Chart.render(applied)
    """
  end
end
