defmodule Examples.Charts.LineChart do
  @moduledoc """
  Line chart as a design (#125): one `:line` mark over a cartesian frame.

  The fifteen lines of scale wiring this module opened with are the frame's now — the `x`
  and `y` domains are inferred from the mark's channels (spec/14 §4.3), the axes are the
  frame's furniture, and the curve is a style key rather than a call on a generator.
  """

  import Visualize.Chart.Build

  alias Examples.Charts.Design

  @margin %{top: 20, right: 20, bottom: 30, left: 50}

  @data (for i <- 0..50 do
           %{x: i, y: :math.sin(i / 5) * 40 + :math.sin(i / 3) * 15 + 50}
         end)

  def title, do: "Line Chart"
  def description, do: "Composite sine wave"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        source(:points, [:x, :y]),
        style(:wave, stroke_width: 2, curve: :monotone_x),
        cartesian(margin: @margin),
        linear_scale(:x),
        linear_scale(:y, nice: true, transition: %{duration: 300}),
        axis(:x, :bottom, ticks: 10),
        axis(:y, :left, ticks: 5),
        line(:points, %{x: :x, y: :y}, style: :wave)
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

  # Animation: create a moving sine wave.
  defp animated(tick) do
    phase = tick * 0.15

    for i <- 0..50 do
      y = :math.sin(i / 5 + phase) * 40 + :math.sin(i / 3 + phase * 1.5) * 15 + 50
      %{x: i, y: y}
    end
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Line Chart"}),
        source(:points, [:x, :y]),
        style(:wave, stroke_width: 2, curve: :monotone_x),
        cartesian(margin: %{top: 20, right: 20, bottom: 30, left: 50}),
        linear_scale(:x),
        linear_scale(:y, nice: true, transition: %{duration: 300}),
        axis(:x, :bottom, ticks: 10),
        axis(:y, :left, ticks: 5),
        line(:points, %{x: :x, y: :y}, style: :wave)
      ])

    {:ok, applied} = Visualize.Chart.apply(design, sources: %{points: data})
    Visualize.Chart.render(applied)
    """
  end
end
