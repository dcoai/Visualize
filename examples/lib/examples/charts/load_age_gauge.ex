defmodule Examples.Charts.LoadAgeGauge do
  @moduledoc """
  The long load with its dial **inset over the plot** (#498): *Load age*'s three windows
  over three hours on a logarithmic age axis fill the box, and *Load gauge*'s dial of the
  same three windows sits over the plot's upper-left corner — one design of two frames,
  one drawn over the other.

  It is the gallery's example of an **overlapping inset frame** (spec/14 §4.2). The `age`
  frame is the whole box, `[0, 0, 1, 1]`; the `gauge` frame is a box of fractions of it
  (`box/0`) inside the age frame's plot area, clear of both axes and of the plot's top,
  and drawn after it (`z: 1`): 231×210 px at the default size, half again the first
  inset's 154×140 at the same upper-left origin (#514). It has **no background**. The
  dial now overlaps the traces of the plot's upper-left — ages from three hours back to
  about twelve minutes, loads from 1.5 up — and they show through it rather than being
  hidden, so nothing of the age view is lost under the inset. The dial hugs its box — as
  wide as it is tall at its radius. The age view's key stays where it was, in the plot's
  top-right corner, with the width of the plot between the two, and the dial carries no
  key of its own: its needles are the key's three colors.

  The traces flatten towards the left as they do on the age view alone: an old point is
  its bucket's mean, so the ten-minute swing is averaged down with age (to about 40% at
  three hours; `Examples.Charts.LoadAge`, #418). That is the expected reading of a
  bucketed history, not lost data.

  The pieces are the two charts' own, not copies: `Examples.Charts.LoadAge` gives its
  source and style (`furniture/0`), its view (`plot/1`) and its rows (`sources/1`), and
  `Examples.Charts.LoadGauge` its sources and styles (`furniture/0`), its dial
  (`dial/2`, here without its key) and its rows (`sources/1`). Both build their own designs
  from the same functions, so the three charts cannot drift apart. Nothing collides: the
  age view says `:loads` and `:trace`, the dial `:reading`, `:rim`, `:pointer` and `:dial`.

  **One clock.** A tick is three seconds of the machine's day (`Examples.Charts.Load.second/2`),
  and both frames' rows are built at the one `now`, counted from the age view's three hours
  — so the dial's needles read the load at the instant every age on the axis is measured
  back from. The two charts it is made of keep their own origins.
  """

  import Visualize.Chart.Build

  alias Examples.Charts.{Design, Load, LoadAge, LoadGauge}

  # The dial's box, fractions of the whole (spec/14 §4.2): its pixels at the default size
  # are [58, 36, 231, 210], inside the age plot's [50, 30, 680, 345] by 8 on the left and 6
  # at the top, so it covers neither axis nor the plot's top edge. It has no background:
  # the traces beneath show through the dial (#514).
  @box [0.0763, 0.0857, 0.3039, 0.5]
  @dial %{top: 18, right: 18, bottom: 4, left: 18}

  @doc "The size this chart is drawn at when the caller names none (spec/14 §4.2)."
  def size, do: {760, 420}

  def title, do: "Load age + gauge"

  def description,
    do:
      "Three hours of load on a logarithmic age axis, its dial inset over the plot's corner; " <>
        "an old point is its bucket's mean, so the swing is averaged down with age"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    {width, _height} = Design.size(__MODULE__, opts)

    design =
      Design.fold(
        [chart(meta: %{name: title(), description: [description()]})] ++
          LoadAge.furniture() ++
          LoadGauge.furniture() ++
          in_frame(:age, LoadAge.plot(width)) ++
          in_frame(
            :gauge,
            LoadGauge.dial([box: @box, margin: @dial, z: 1],
              legend: false
            )
          )
      )

    {design, sources(now(opts))}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  @doc """
  The one instant both frames read at a tick: the machine's clock counted from the age
  view's oldest age, so its three hours are filled at rest.
  """
  @spec now(keyword()) :: integer()
  def now(opts), do: Load.second(opts, LoadAge.oldest())

  @doc "Both frames' rows at absolute second `now`: the age view's and the dial's."
  def sources(now), do: Map.merge(LoadAge.sources(now), LoadGauge.sources(now))

  @doc "The dial's box, fractions of the whole box (spec/14 §4.2): the age plot's upper-left."
  def box, do: @box

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    # Two frames, one over the other: the log-age view fills the box, and the dial sits
    # in a box over its plot's upper-left corner, drawn after it with no background, so
    # the traces beneath show through it.
    {:ok, design} =
      Visualize.Chart.compose(
        [
          chart(meta: %{name: "Load age + gauge"}),
          source(:loads, [:age, :load, :window]),
          source(:reading, [:window, :load, :length]),
          style(:trace, stroke_width: 2, curve: :monotone_x),
          style(:pointer, fill: {:field, :window}, stroke: :background, stroke_width: 1)
        ] ++
          in_frame(:age, [
            cartesian(margin: %{top: 30, right: 30, bottom: 45, left: 50}),
            log_scale(:x, domain: [5, 10_800], range: [680, 0]),
            linear_scale(:y, domain: [0, 4]),
            ordinal_scale(:color, domain: ["1 min", "5 min", "15 min"], range: [:series_1, :series_2, :series_3]),
            axis(:x, :bottom, ticks: [5, 30, 60, 300, 900, 3600, 10_800], format: :duration),
            axis(:y, :left, ticks: 4, grid: true),
            legend(:color, position: :top_right),
            line(:loads, %{x: :age, y: :load, series: :window}, style: :trace)
          ]) ++
          in_frame(:gauge, [
            # Fractions of the whole box, inside the age plot: clear of both axes.
            polar(box: [0.0763, 0.0857, 0.3039, 0.5], z: 1),
            linear_scale(:angle, domain: [0, 4], start: -120, sweep: 240),
            linear_scale(:r, domain: [0, 1]),
            ordinal_scale(:color, domain: ["1 min", "5 min", "15 min"], range: [:series_1, :series_2, :series_3]),
            axis(:angle, :bottom, ticks: 5, radius: 0.86, grid: true),
            needle(:reading, %{x: :load, y: :length}, style: :pointer)
          ])
      )

    # One `now` builds both frames' rows, so the dial reads the instant the ages count from.
    {:ok, applied} = Visualize.Chart.apply(design, sources: %{loads: loads, reading: reading})
    Visualize.Chart.render(applied)
    """
  end
end
