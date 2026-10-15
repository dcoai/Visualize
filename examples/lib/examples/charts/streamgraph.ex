defmodule Examples.Charts.Streamgraph do
  @moduledoc """
  Streamgraph as a design (#128): the `:stack` transform with the `:silhouette` offset and
  an inside-out order fixed by the series keys under one `:area` mark.

  The stack is a step of the mark's data pipeline (spec/14 §5.4.1): `offset: :silhouette`
  centers the stream on zero and the order puts the heaviest series in the middle and the
  lighter ones outward on alternating sides — the two settings that make a stack a stream —
  and the mark reads each layer's `y0` and `y1` with `key` as its `series` channel, which
  both splits the paths and colors them from the `color` scale the legend explains. The
  basis curve is the style's; the legend sits in the right margin the chart reserves for it
  (§4.5, #136).

  **The order is fixed once, never per tick** (#492). `order: :inside_out` is computed
  from the rows it is given, so over the animated run it re-sorted every tick and a layer
  jumped to another place whenever the order moved — under the sum order of the time, the
  bottom layer changed every four to eight ticks. The order here is computed when the module is compiled, from each
  series' total over one turn of the run's phase (every wave once round, which ranks them as
  any longer run does), and passed as `order: {:keys, keys}`: each layer keeps its place
  however its wave moves, and the still chart stacks in the same order as the run.

  The x axis prints `Month n` as the hand-written version did, the word the axis's
  `prefix` (spec/14 §4.4, #135).
  """

  import Visualize.Chart.Build

  alias Examples.Charts.Design

  @margin %{top: 20, right: 100, bottom: 40, left: 40}
  @keys [:rock, :pop, :jazz, :classical, :electronic, :hiphop]

  # The run's waves (`animated/1`): per genre the level, the swing, the months per radian
  # and the phase's rate and offset, so a reading is
  # `max(10, level + swing · sin(month / months + phase · rate + offset))`.
  @waves [
    rock: {30, 25, 4, 1.0, 0},
    pop: {35, 20, 5, 1.3, 1},
    jazz: {20, 15, 3, 0.7, 2},
    classical: {18, 12, 6, 1.1, 3},
    electronic: {32, 22, 4, 0.9, 4},
    hiphop: {28, 18, 5, 1.4, 5}
  ]
  @phase_step 0.1

  # Each genre's total over one turn of the phase (ticks 0..62, every wave once round).
  @totals (for {key, {level, swing, months, rate, offset}} <- @waves, into: %{} do
             total =
               for tick <- 0..round(2 * :math.pi() / @phase_step - 1),
                   month <- 1..24,
                   reduce: 0 do
                 acc ->
                   phase = tick * @phase_step

                   acc +
                     max(10, level + swing * :math.sin(month / months + phase * rate + offset))
               end

             {key, total}
           end)

  # Inside-out by weight, bottom first: the heaviest series in the middle, then each lighter
  # one outward, alternately above and below. This is the chart's own ranking, not the
  # library's `:insideout`, which is d3's and ranks by where each series peaks (spec/04
  # §8.4, D-125).
  @order (fn ->
            heaviest_first = Enum.sort_by(@keys, &Map.fetch!(@totals, &1), :desc)
            above = Enum.take_every(heaviest_first, 2)
            below = heaviest_first |> Enum.drop(1) |> Enum.take_every(2)
            Enum.reverse(below) ++ above
          end).()

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

  @doc "The stacking order, bottom first, fixed when the module is compiled (#492)."
  def order, do: @order

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
        # The silhouette offset centers the stream; the order is inside-out by the run's
        # totals, fixed so no layer changes place as the waves move (spec/14 §5.4.1, #492).
        area(
          stack(from(:months), @keys, offset: :silhouette, order: {:keys, @order}),
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
    phase = tick * @phase_step

    for month <- 1..24 do
      for {key, {level, swing, months, rate, offset}} <- @waves, into: %{month: month} do
        {key, max(10, level + swing * :math.sin(month / months + phase * rate + offset))}
      end
    end
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    keys = [:rock, :pop, :jazz, :classical, :electronic, :hiphop]
    # Bottom first, inside-out by each genre's total over the run: the heaviest, pop, in
    # the middle. Computed once, so no layer changes place as the data moves.
    order = [:classical, :hiphop, :electronic, :pop, :rock, :jazz]

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
        # A stack centered on zero, its order fixed bottom first so no layer changes
        # place between frames (spec/14 §5.4.1).
        area(stack(from(:months), keys, offset: :silhouette, order: {:keys, order}),
          %{x: :month, y: :y1, y0: :y0, series: :key},
          style: :stream
        )
      ])

    {:ok, applied} = Visualize.Chart.apply(design, sources: %{months: months})
    Visualize.Chart.render(applied)
    """
  end
end
