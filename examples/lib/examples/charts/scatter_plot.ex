defmodule Examples.Charts.ScatterPlot do
  @moduledoc """
  Scatter plot as a design (#125): one `:circle` mark, coloured by category.

  A `:circle`'s `value` channel is its radius in user units and names no scale (spec/14
  §5.2), so the radius is a column of the rows; the colour is a `{:field, :category}` on the
  style's `fill`, which is read per element and passed through the frame's `color` scale
  (§3.2), and the legend explains that same scale.

  The legend draws inside the plot area (#136) and prints the category values under a title,
  where the hand-laid one wrote "Category A" per entry.
  """

  import Visualize.Chart.Build

  alias Examples.Charts.Design

  @margin %{top: 20, right: 20, bottom: 40, left: 50}
  @categories ["A", "B", "C"]

  @data (for _ <- 1..100 do
           %{
             x: :rand.uniform() * 100,
             y: :rand.uniform() * 100,
             size: :rand.uniform() * 20 + 5,
             category: Enum.random(["A", "B", "C"])
           }
         end)

  def title, do: "Scatter Plot"
  def description, do: "Random data points with categories"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        source(:points, [:x, :y, :r, :category]),
        style(:point, fill: {:field, :category}, opacity: 0.7),
        cartesian(opts[:width] || 600, opts[:height] || 400, margin: @margin),
        linear_scale(:x, domain: [0, 100]),
        linear_scale(:y, domain: [0, 100]),
        ordinal_scale(:color, domain: @categories),
        axis(:x, :bottom, ticks: 10),
        axis(:y, :left, ticks: 10),
        legend(:color, position: :top_right, title: ["Category"]),
        circle(:points, %{x: :x, y: :y, value: :r}, style: :point)
      ])

    {design, %{points: rows(opts)}}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  # The radius is a column, because a `:circle`'s `value` is user units and names no scale.
  defp rows(opts) do
    data = opts[:data] || @data

    data =
      case opts[:animation_tick] do
        nil -> data
        tick -> animated(data, tick)
      end

    Enum.map(data, &Map.put(&1, :r, &1.size / 5 + 3))
  end

  # Animation: each point orbits in a small circle at its own speed.
  defp animated(data, tick) do
    Enum.with_index(data, fn item, i ->
      angle = tick * (0.05 + rem(i, 5) * 0.02) + i * 0.5
      radius = 5 + rem(i, 3) * 3

      %{
        item
        | x: max(5, min(95, item.x + radius * :math.cos(angle))),
          y: max(5, min(95, item.y + radius * :math.sin(angle)))
      }
    end)
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Scatter Plot"}),
        source(:points, [:x, :y, :r, :category]),

        # A {:field, f} on a colour key goes through the `color` scale, per element.
        style(:point, fill: {:field, :category}, opacity: 0.7),
        cartesian(600, 400, margin: %{top: 20, right: 20, bottom: 40, left: 50}),
        linear_scale(:x, domain: [0, 100]),
        linear_scale(:y, domain: [0, 100]),
        ordinal_scale(:color, domain: ["A", "B", "C"]),
        axis(:x, :bottom, ticks: 10),
        axis(:y, :left, ticks: 10),
        legend(:color, position: :top_right, title: ["Category"]),

        # `value` on a :circle is its radius in user units and names no scale.
        circle(:points, %{x: :x, y: :y, value: :r}, style: :point)
      ])

    {:ok, applied} = Visualize.Chart.apply(design, sources: %{points: data})
    Visualize.Chart.render(applied)
    """
  end
end
