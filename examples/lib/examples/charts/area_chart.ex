defmodule Examples.Charts.AreaChart do
  @moduledoc """
  Area chart as a design (#125, #133): an `:area` mark under a `:line` over a cartesian
  frame, the area filled with a vertical gradient from the series color at 0.8 to 0.1 at
  the baseline.

  The gradient is a paint the design declares under `defs` (spec/14 §2.7) and the area's
  style refers to as `{:paint, :fade}`; the frame emits the `<defs><linearGradient>` and
  resolves the reference, so the chart that was left imperative for want of a paint server
  is the design it always was.
  """

  import Visualize.Chart.Build

  alias Examples.Charts.Design

  @margin %{top: 20, right: 20, bottom: 30, left: 50}

  @data (for i <- 0..60 do
           # Main wave with two higher frequency harmonics for interesting texture
           y =
             :math.sin(i / 4) * 30 +
               :math.sin(i * 31 * :math.pi() * 2 / 100) * 8 +
               :math.sin(i * 27 * :math.pi() * 2 / 100) * 5 +
               50

           %{x: i, y: y}
         end)

  def title, do: "Area Chart"
  def description, do: "Filled area under curve"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        source(:points, [:x, :y]),
        gradient(:fade, :linear, stops: [{0, :series_1, 0.8}, {1, :series_1, 0.1}]),
        style(:area, fill: paint(:fade), curve: :monotone_x),
        style(:edge, stroke: :series_1, stroke_width: 2, curve: :monotone_x),
        cartesian(margin: @margin),
        linear_scale(:x),
        linear_scale(:y, domain: [0, :auto], nice: true, transition: %{duration: 300}),
        axis(:x, :bottom, ticks: 10),
        axis(:y, :left, ticks: 5),
        area(:points, %{x: :x, y: :y}, style: :area),
        line(:points, %{x: :x, y: :y}, style: :edge)
      ])

    {design, %{points: rows(opts)}}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  defp rows(opts) do
    case opts[:animation_tick] do
      nil -> opts[:data] || @data
      tick -> animated(tick)
    end
  end

  # Animation: a moving wave with higher frequency harmonics.
  defp animated(tick) do
    phase = tick * 0.15

    for i <- 0..60 do
      y =
        :math.sin(i / 4 + phase) * 30 +
          :math.sin(i * 31 * :math.pi() * 2 / 100 + phase * 2.1) * 8 +
          :math.sin(i * 27 * :math.pi() * 2 / 100 + phase * 1.7) * 5 +
          50

      %{x: i, y: max(5, y)}
    end
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Area Chart"}),
        source(:points, [:x, :y]),
        gradient(:fade, :linear, stops: [{0, :series_1, 0.8}, {1, :series_1, 0.1}]),
        style(:area, fill: paint(:fade), curve: :monotone_x),
        style(:edge, stroke: :series_1, stroke_width: 2, curve: :monotone_x),
        cartesian(margin: %{top: 20, right: 20, bottom: 30, left: 50}),
        linear_scale(:x),
        linear_scale(:y, domain: [0, :auto], nice: true, transition: %{duration: 300}),
        axis(:x, :bottom, ticks: 10),
        axis(:y, :left, ticks: 5),
        area(:points, %{x: :x, y: :y}, style: :area),
        line(:points, %{x: :x, y: :y}, style: :edge)
      ])

    {:ok, applied} = Visualize.Chart.apply(design, sources: %{points: data})
    Visualize.Chart.render(applied)
    """
  end
end
