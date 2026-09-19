defmodule Examples.Charts.StackedAreaChart do
  @moduledoc """
  Stacked area chart as a design (#125): a `:stack` transform under one `:area` mark.

  `Visualize.Shape.Stack` is a step of the mark's data pipeline rather than a call the
  caller makes (spec/14 §5.4.1): the transform yields one row per series per datum carrying
  `key`, `y0` and `y1`, the mark reads `y0` and `y1` as its baseline and top, and `key` as
  its `series` channel — which both splits the paths and colours them from the `color`
  scale the legend explains.

  The legend draws in the right margin the chart reserves for it (spec/14 §4.5, #136).
  """

  import Visualize.Chart.Build

  alias Examples.Charts.Design

  @margin %{top: 20, right: 100, bottom: 30, left: 50}
  @keys [:apples, :oranges, :bananas, :grapes, :pears]

  @data (for i <- 0..20 do
           %{
             x: i,
             apples: :rand.uniform(30) + 10,
             oranges: :rand.uniform(25) + 15,
             bananas: :rand.uniform(20) + 5,
             grapes: :rand.uniform(15) + 10,
             pears: :rand.uniform(10) + 5
           }
         end)

  def title, do: "Stacked Area Chart"
  def description, do: "Fruit production over time"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        source(:fruit, [:x | @keys]),
        style(:layer, opacity: 0.8, curve: :monotone_x),
        cartesian(opts[:width] || 600, opts[:height] || 400, margin: @margin),
        linear_scale(:x),
        linear_scale(:y, domain: [0, :auto], nice: true, transition: %{duration: 300}),
        ordinal_scale(:color, domain: @keys),
        axis(:x, :bottom, ticks: 10),
        axis(:y, :left, ticks: 5),
        legend(:color, position: :top_right, inside: false),
        area(stack(from(:fruit), @keys), %{x: :x, y: :y1, y0: :y0, series: :key}, style: :layer)
      ])

    {design, %{fruit: rows(opts)}}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  defp rows(opts) do
    case opts[:animation_tick] do
      nil -> opts[:data] || @data
      tick -> animated(tick)
    end
  end

  # Animation: flowing waves for each fruit category.
  defp animated(tick) do
    phase = tick * 0.1

    for i <- 0..20 do
      %{
        x: i,
        apples: max(20 + 15 * :math.sin(i / 4 + phase), 5),
        oranges: max(25 + 12 * :math.sin(i / 5 + phase * 1.2 + 1), 5),
        bananas: max(15 + 10 * :math.sin(i / 3 + phase * 0.8 + 2), 5),
        grapes: max(18 + 8 * :math.sin(i / 6 + phase * 1.5 + 3), 5),
        pears: max(12 + 6 * :math.sin(i / 4 + phase * 0.9 + 4), 5)
      }
    end
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    keys = [:apples, :oranges, :bananas, :grapes, :pears]

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Stacked Area Chart"}),
        source(:fruit, [:x | keys]),
        style(:layer, opacity: 0.8, curve: :monotone_x),
        cartesian(600, 400, margin: %{top: 20, right: 100, bottom: 30, left: 50}),
        linear_scale(:x),
        linear_scale(:y, domain: [0, :auto], nice: true, transition: %{duration: 300}),
        ordinal_scale(:color, domain: keys),
        axis(:x, :bottom, ticks: 10),
        axis(:y, :left, ticks: 5),
        legend(:color, position: :top_right, inside: false),

        # The stack is a step of the mark's pipeline; it yields key, y0 and y1 per row.
        area(stack(from(:fruit), keys), %{x: :x, y: :y1, y0: :y0, series: :key}, style: :layer)
      ])

    {:ok, applied} = Visualize.Chart.apply(design, sources: %{fruit: data})
    Visualize.Chart.render(applied)
    """
  end
end
