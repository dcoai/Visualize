defmodule Examples.Charts.LoadAndAge do
  @moduledoc """
  The recent load and the long load **in one design** (#493): *Load*'s ten-minute history
  with its dial of the newest reading on top, and *Load age*'s three windows over three
  hours on a logarithmic age axis beneath — three frames on a grid of two rows.

  The two charts were two pictures because a design once had one coordinate system;
  frames make them one (#383, #384). The pieces are the two charts' own, not copies:
  `Examples.Charts.LoadChart` gives its sources and styles (`furniture/0`), its `history`
  and `now` frames (`history/1`, `dial/1`) and their rows (`sources/1`), and
  `Examples.Charts.LoadAge` its source and style (`furniture/1`), its view (`plot/3`) and
  its rows (`sources/1`). Both build their own designs from the same functions, so the
  three charts cannot drift apart. Where the two collide this design renames: both call
  their trace style `:trace`, so the age view's is `:age_trace` here.

  **One load axis.** The `age` frame adopts the history's `y` (`{:frame, :history, :y}`,
  spec/14 §4.3) rather than declaring its own, so the two axes are one scale — declared
  once over `[0, 4]`, drawing the same domain and the same ticks, each at its own frame's
  height. The domain being declared, the shared domain a compiled chart freezes (§12.1) is
  the one every tick would read anyway.

  **One clock.** A tick is three seconds of the machine's day (`Examples.Charts.Load.second/2`)
  and both frames' rows are built at the one `now`, counted from the age view's three
  hours — so the dial's reading and the history's newest point are `now`, and every age
  on the axis beneath is measured back from that same instant. The two charts it is made
  of keep their own origins.

  The dial keeps *Load*'s place — the top-right of the history — at the history cell's
  share of the box (`dial_box/0`), since a frame's `box` is a fraction of the whole box
  (spec/14 §4.2) and the history is now the top half of it.
  """

  import Visualize.Chart.Build

  alias Examples.Charts.{Design, Load, LoadAge, LoadChart}

  # The two views, stacked: the history over the age view, at equal weights (spec/14 §2.8).
  @rows [1, 1]
  @gap 8
  # One left margin for both, so the two load axes stand on one line.
  @history %{top: 24, right: 30, bottom: 34, left: 50}
  @age %{top: 30, right: 30, bottom: 45, left: 50}
  # The age view's trace style, renamed: *Load*'s history says `:trace` too.
  @age_trace :age_trace

  @doc "The size this chart is drawn at when the caller names none (spec/14 §4.2)."
  def size, do: {760, 760}

  def title, do: "Load + age"

  def description,
    do: "Ten minutes of load and its dial, over three hours of it on a logarithmic age axis"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    {width, _height} = Design.size(__MODULE__, opts)

    design =
      Design.fold(
        [
          chart(meta: %{name: title(), description: [description()]}),
          layout(rows: @rows, gap: @gap)
        ] ++
          LoadChart.furniture() ++
          LoadAge.furniture(@age_trace) ++
          LoadChart.history(cell: [0, 0], margin: @history) ++
          LoadChart.dial(dial_box()) ++
          in_frame(
            :age,
            LoadAge.plot(width, @age_trace,
              place: [cell: [0, 1], margin: @age],
              # The history's load axis, adopted: one scale, one domain (spec/14 §4.3).
              y: adopt(:y, :history)
            )
          )
      )

    {design, sources(now(opts))}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  @doc """
  The one instant both views read at a tick: the machine's clock counted from the age
  view's oldest age, so its three hours are filled at rest.
  """
  @spec now(keyword()) :: integer()
  def now(opts), do: Load.second(opts, LoadAge.oldest())

  @doc "Both views' rows at absolute second `now`: the history's and the dial's, and the age view's."
  def sources(now), do: Map.merge(LoadChart.sources(now), LoadAge.sources(now))

  @doc """
  The dial's box: *Load*'s, at the history cell's share of the box's height — the top
  row's weight over the rows' — so it sits in the history's top-right as it does there.
  """
  def dial_box do
    [x, y, w, h] = LoadChart.box()
    share = hd(@rows) / Enum.sum(@rows)
    [x, y * share, w, h * share]
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    # Two load views, one design: the history and its dial on top, the log-age view
    # beneath. One `now` builds both views' rows, so they show the same instant.
    newest = take(from(:load), 1)

    {:ok, design} =
      Visualize.Chart.compose(
        [
          chart(meta: %{name: "Load + age"}),
          layout(rows: [1, 1], gap: 8),
          source(:load, [:t, :v], types: %{t: :time, v: :number}),
          source(:loads, [:age, :load, :window]),
          style(:trace, stroke: :series_1, stroke_width: 2, curve: :monotone_x),
          # Both charts said `:trace`; the age view's is renamed.
          style(:age_trace, stroke_width: 2, curve: :monotone_x)
        ] ++
          in_frame(:history, [
            cartesian(cell: [0, 0], margin: %{top: 24, right: 30, bottom: 34, left: 50}),
            time_scale(:x),
            linear_scale(:y, domain: [0, 4]),
            axis(:x, :bottom, ticks: 6, format: "%H:%M"),
            axis(:y, :left, ticks: 4, grid: true),
            line(:load, %{x: :t, y: :v}, style: :trace)
          ]) ++
          in_frame(:now, [
            # A box is a fraction of the whole: the top-right of the top half.
            polar(box: [0.72, 0.02, 0.24, 0.12], z: 1, background: :background),
            linear_scale(:angle, domain: [0, 4], start: -120, sweep: 240),
            linear_scale(:r, domain: [0, 1]),
            rect(newest, %{x0: 0, x1: :v, y0: 0.62, y1: 0.92}),
            text(newest, %{x: 0, y: 0}, label: %{text: [{:field, :v}], anchor: :middle})
          ]) ++
          in_frame(:age, [
            cartesian(cell: [0, 1], margin: %{top: 30, right: 30, bottom: 45, left: 50}),
            log_scale(:x, domain: [5, 10_800], range: [680, 0]),
            # The history's load axis, adopted: the two views read one scale.
            adopt(:y, :history),
            ordinal_scale(:color, domain: ["1 min", "5 min", "15 min"], range: [:series_1, :series_2, :series_3]),
            axis(:x, :bottom, ticks: [5, 30, 60, 300, 900, 3600, 10_800], format: :duration),
            axis(:y, :left, ticks: 4, grid: true),
            legend(:color, position: :top_right),
            line(:loads, %{x: :age, y: :load, series: :window}, style: :age_trace)
          ])
      )

    {:ok, applied} = Visualize.Chart.apply(design, sources: %{load: load, loads: loads})
    Visualize.Chart.render(applied)
    """
  end
end
