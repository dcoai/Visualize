defmodule Examples.Charts.BarChart do
  @moduledoc """
  Bar chart as a design (#125): one `:rect` mark over a band scale.

  A bar is `x0` and `x1` on the same field: through a `:band` scale `x0` is the band's start
  and `x1` its end, so the rectangle is the band (spec/14 §5.2). `value` on a `:rect` reaches
  the `color` scale, which is how each letter takes its own colour without a `rem/2` over a
  palette, and the axis prints its percentages through `Visualize.Format`'s `.1%` rather than
  through a formatting function a design could not hold.
  """

  import Visualize.Chart.Build

  alias Examples.Charts.Design

  @margin %{top: 20, right: 20, bottom: 30, left: 40}

  @data [
    %{letter: "A", frequency: 0.08167},
    %{letter: "B", frequency: 0.01492},
    %{letter: "C", frequency: 0.02782},
    %{letter: "D", frequency: 0.04253},
    %{letter: "E", frequency: 0.12702},
    %{letter: "F", frequency: 0.02288},
    %{letter: "G", frequency: 0.02015},
    %{letter: "H", frequency: 0.06094},
    %{letter: "I", frequency: 0.06966},
    %{letter: "J", frequency: 0.00153},
    %{letter: "K", frequency: 0.00772},
    %{letter: "L", frequency: 0.04025},
    %{letter: "M", frequency: 0.02406},
    %{letter: "N", frequency: 0.06749},
    %{letter: "O", frequency: 0.07507},
    %{letter: "P", frequency: 0.01929},
    %{letter: "Q", frequency: 0.00095},
    %{letter: "R", frequency: 0.05987},
    %{letter: "S", frequency: 0.06327},
    %{letter: "T", frequency: 0.09056},
    %{letter: "U", frequency: 0.02758},
    %{letter: "V", frequency: 0.00978},
    %{letter: "W", frequency: 0.02360},
    %{letter: "X", frequency: 0.00150},
    %{letter: "Y", frequency: 0.01974},
    %{letter: "Z", frequency: 0.00074}
  ]

  def title, do: "Bar Chart"
  def description, do: "Letter frequency in English text"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        source(:letters, [:letter, :frequency]),
        cartesian(margin: @margin),
        band_scale(:x, padding: 0.1),
        linear_scale(:y, domain: [0, :auto], nice: true, transition: %{duration: 300}),
        ordinal_scale(:color),
        axis(:x, :bottom),
        axis(:y, :left, ticks: 10, format: ".1%"),
        rect(:letters, %{x0: :letter, x1: :letter, y0: 0, y1: :frequency, value: :letter})
      ])

    {design, %{letters: rows(opts)}}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  defp rows(opts) do
    data = opts[:data] || @data

    case opts[:animation_tick] do
      nil -> data
      tick -> animated(data, tick)
    end
  end

  # Animation: smoothly vary frequencies using sine waves, each bar at its own phase.
  defp animated(data, tick) do
    Enum.with_index(data, fn item, i ->
      %{item | frequency: item.frequency * (1.0 + 0.5 * :math.sin(tick * 0.1 + i * 0.3))}
    end)
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    data = [%{letter: "A", frequency: 0.08167}, %{letter: "B", frequency: 0.01492}, ...]

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Bar Chart"}),
        source(:letters, [:letter, :frequency]),
        cartesian(margin: %{top: 20, right: 20, bottom: 30, left: 40}),
        band_scale(:x, padding: 0.1),
        linear_scale(:y, domain: [0, :auto], nice: true, transition: %{duration: 300}),
        ordinal_scale(:color),
        axis(:x, :bottom),
        axis(:y, :left, ticks: 10, format: ".1%"),

        # x0 and x1 on the same field are the band's start and end: the bar is the band.
        # `value` on a :rect reaches the colour scale.
        rect(:letters, %{x0: :letter, x1: :letter, y0: 0, y1: :frequency, value: :letter})
      ])

    {:ok, applied} = Visualize.Chart.apply(design, sources: %{letters: data})
    Visualize.Chart.render(applied)
    """
  end
end
