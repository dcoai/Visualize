defmodule Examples.Charts.Streamgraph do
  @moduledoc """
  Streamgraph as a design (#128): the `:stack` transform with the `:silhouette` offset and
  the `:inside_out` order under one `:area` mark.

  The stack is a step of the mark's data pipeline (spec/14 §5.4.1): `offset: :silhouette`
  centres the stream on zero and `order: :inside_out` puts the series whose peaks come
  earliest in the middle — the two settings that make a stack a stream — and the mark reads
  each layer's `y0` and `y1` with `key` as its `series` channel, which both splits the paths
  and colours them from the `color` scale the legend explains. The basis curve is the
  style's; the legend sits in the right margin the chart reserves for it (§4.5, #136).

  The x axis prints `Month n` as the hand-written version did, the word the axis's
  `prefix` (spec/14 §4.4, #135).
  """

  import Visualize.Chart.Build

  alias Examples.Charts.Design

  @margin %{top: 20, right: 100, bottom: 40, left: 40}
  @keys [:rock, :pop, :jazz, :classical, :electronic, :hiphop]

  @data (for month <- 1..24 do
           %{
             month: month,
             rock: 20 + :rand.uniform(30) + if(month > 6 and month < 18, do: 20, else: 0),
             pop: 30 + :rand.uniform(25) + if(month > 3 and month < 15, do: 25, else: 0),
             jazz: 15 + :rand.uniform(20),
             classical: 10 + :rand.uniform(15) + if(month > 12, do: 15, else: 0),
             electronic: 25 + :rand.uniform(35) + if(month > 9 and month < 21, do: 20, else: 0),
             hiphop: 20 + :rand.uniform(25) + if(month < 12, do: 10, else: 20)
           }
         end)

  def title, do: "Streamgraph"
  def description, do: "Music genre popularity over time"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        source(:months, [:month | @keys]),
        style(:stream,
          fill_opacity: 0.8,
          stroke: {:field, :key},
          stroke_width: 0.5,
          curve: :basis
        ),
        cartesian(margin: @margin),
        linear_scale(:x),
        linear_scale(:y),
        ordinal_scale(:color, domain: @keys),
        axis(:x, :bottom, ticks: 8, prefix: "Month "),
        legend(:color, position: :top_right, inside: false),
        # The silhouette offset centres the stream; inside-out ordering puts the earliest
        # peaks in the middle (spec/14 §5.4.1).
        area(
          stack(from(:months), @keys, offset: :silhouette, order: :inside_out),
          %{x: :month, y: :y1, y0: :y0, series: :key},
          style: :stream
        )
      ])

    {design, %{months: rows(opts)}}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  defp rows(opts) do
    case opts[:animation_tick] do
      nil -> opts[:data] || @data
      tick -> animated(tick)
    end
  end

  # Animation: every genre's popularity flows as its own wave.
  defp animated(tick) do
    phase = tick * 0.1

    for month <- 1..24 do
      %{
        month: month,
        rock: max(10, 30 + 25 * :math.sin(month / 4 + phase)),
        pop: max(10, 35 + 20 * :math.sin(month / 5 + phase * 1.3 + 1)),
        jazz: max(10, 20 + 15 * :math.sin(month / 3 + phase * 0.7 + 2)),
        classical: max(10, 18 + 12 * :math.sin(month / 6 + phase * 1.1 + 3)),
        electronic: max(10, 32 + 22 * :math.sin(month / 4 + phase * 0.9 + 4)),
        hiphop: max(10, 28 + 18 * :math.sin(month / 5 + phase * 1.4 + 5))
      }
    end
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    keys = [:rock, :pop, :jazz, :classical, :electronic, :hiphop]

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Streamgraph"}),
        source(:months, [:month | keys]),
        style(:stream, fill_opacity: 0.8, stroke: {:field, :key}, stroke_width: 0.5, curve: :basis),
        cartesian(margin: %{top: 20, right: 100, bottom: 40, left: 40}),
        linear_scale(:x),
        linear_scale(:y),
        ordinal_scale(:color, domain: keys),
        axis(:x, :bottom, ticks: 8, prefix: "Month "),
        legend(:color, position: :top_right, inside: false),
        # A stack centred on zero, the earliest peaks in the middle (spec/14 §5.4.1).
        area(stack(from(:months), keys, offset: :silhouette, order: :inside_out),
          %{x: :month, y: :y1, y0: :y0, series: :key},
          style: :stream
        )
      ])

    {:ok, applied} = Visualize.Chart.apply(design, sources: %{months: months})
    Visualize.Chart.render(applied)
    """
  end
end
