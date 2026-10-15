defmodule Examples.Charts.LoadGauge do
  @moduledoc """
  A machine's load average on one dial (#415): a polar frame sweeping 240° from −120° over
  a load of 0 to 4, the angle axis an arc at 0.86 R with its numbers outward, a rim just
  inside it, and **three needles on the one dial** — the fifteen-, five- and
  one-minute windows (`Examples.Charts.Load`), each its own length so they read where they
  overlap and its own color through the `color` scale (`fill: {:field, :window}`, spec/14
  §3.4). Animated, the three pointers chase each other as the load wanders: the one-minute
  needle swings, the fifteen-minute one drifts.

  **The needles have mass** (#417): the mark's `transition` eases each row's `load` toward
  its reading over 450 ms along `sin_in_out` — still at both ends, quickest in the middle,
  the travel of a pointer rather than of a number — so a reading that arrives once every
  three seconds is a sweep and not a jump.

  Its neighbor `Examples.Charts.LoadAge` draws the same three windows over the last three
  hours. They were two designs because a design had one frame and a dial and a plot could
  not share it; a design holds its frames by name now (§4.1, #383), and
  `Examples.Charts.LoadChart` is one source drawn both ways in one chart. These two stay
  as they are: three needles on one dial and three hours on a log axis are each a chart in
  their own right, and this one is the dial said in full.

  `Examples.Charts.LoadAgeGauge` (#498) insets this dial over the age view's upper-left
  corner, and it draws the dial from this chart's own pieces — `furniture/0`, `dial/2` and
  `sources/1`, the functions this design is built from — so the two dials cannot drift.
  """

  import Visualize.Chart.Build

  alias Examples.Charts.{Design, Load}

  @margin %{top: 30, right: 90, bottom: 30, left: 40}
  # The outermost needle is the longest: the shortest window swings the most.
  @lengths %{one: 0.62, five: 0.5, fifteen: 0.38}

  @doc "The size this chart is drawn at when the caller names none (spec/14 §4.2)."
  def size, do: {420, 420}

  def title, do: "Load gauge"
  def description, do: "Three load averages as three needles on one dial"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    {_width, _height} = Design.size(__MODULE__, opts)

    design =
      Design.fold(
        [chart(meta: %{name: title(), description: [description()]})] ++
          furniture() ++ dial(margin: @margin)
      )

    {design, sources(Load.second(opts, 0))}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  @doc """
  The sources and the styles the dial draws with: what `dial/2` names, said once here and
  in `Examples.Charts.LoadAgeGauge` (#498).
  """
  def furniture do
    [
      source(:reading, [:window, :load, :length],
        types: %{window: :category, load: :number, length: :number}
      ),
      source(:rim, [:at], types: %{at: :number}),
      style(:rim, fill: :grid, opacity: 0.45, stroke: :none),
      style(:pointer, fill: {:field, :window}, stroke: :background, stroke_width: 1),
      style(:dial, extends: :axis, font_size: 11)
    ]
  end

  @doc """
  The dial's fragments: its `polar` placed by `place` — a margin, or a `box`, `z` and
  `background` for a dial drawn over another frame (spec/14 §4.2) — its scales, its axis,
  its rim and its three needles.

  `opts`: `legend`, `true` by default — the windows' key in the right margin. A dial inset
  over a chart that keys the same three windows says `false`, the key being there already.
  Unframed, so this chart is one frame and a design of several puts it in one with
  `in_frame/2`.
  """
  def dial(place, opts \\ []) do
    [
      polar(place),
      linear_scale(:angle, domain: [0, 4], start: -120, sweep: 240),
      # `r`'s auto range is already [0, min(w, h) / 2] of the plot (spec/14 §4.3).
      linear_scale(:r, domain: [0, 1]),
      ordinal_scale(:color,
        domain: Enum.map(Load.windows(), &elem(&1, 1)),
        range: [:series_1, :series_2, :series_3]
      ),
      axis(:angle, :bottom, ticks: 5, radius: 0.86, grid: true, style: :dial)
    ] ++
      key(Keyword.get(opts, :legend, true)) ++
      [
        # The dial's rim, one sector of the whole sweep just inside the axis (§5.2).
        rect(:rim, %{x0: 0, x1: 4, y0: 0.72, y1: 0.84}, style: :rim),
        # Three rows, three needles, each its own length and color (spec/14 §5.2).
        needle(:reading, %{x: :load, y: :length},
          options: %{width: 7, tail: 12, hub: 7},
          style: :pointer,
          transition: %{duration: 450, easing: :sin_in_out}
        )
      ]
  end

  @doc """
  The rows the dial binds at absolute second `now`: each window's reading at that second,
  one needle a window, and the rim's one row.
  """
  def sources(now) do
    reading =
      for {window, name} <- Load.windows() do
        %{window: name, load: Load.at(window, now), length: @lengths[window]}
      end

    %{reading: reading, rim: [%{at: 0}]}
  end

  defp key(true), do: [legend(:color, position: :top_right, inside: false)]
  defp key(false), do: []

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Load gauge"}),
        source(:reading, [:window, :load, :length]),
        # Each needle takes its color from its row through the color scale (§3.4).
        style(:pointer, fill: {:field, :window}, stroke: :background, stroke_width: 1),
        polar(margin: %{top: 30, right: 90, bottom: 30, left: 40}),
        # 240° of dial from −120°, over a load of 0 to 4 (spec/14 §4.3).
        linear_scale(:angle, domain: [0, 4], start: -120, sweep: 240),
        linear_scale(:r, domain: [0, 1], range: [0, 150]),
        ordinal_scale(:color, domain: ["1 min", "5 min", "15 min"], range: [:series_1, :series_2, :series_3]),
        axis(:angle, :bottom, ticks: 5, radius: 0.86, grid: true),
        legend(:color, position: :top_right, inside: false),
        # One row per window: three needles on the one dial, each its own length.
        # The needle travels to its reading rather than appearing at it (spec/14 §12.5).
        needle(:reading, %{x: :load, y: :length},
          options: %{width: 7, tail: 12, hub: 7},
          style: :pointer,
          transition: %{duration: 450, easing: :sin_in_out}
        )
      ])

    reading = [
      %{window: "1 min", load: 2.4, length: 0.62},
      %{window: "5 min", load: 1.9, length: 0.5},
      %{window: "15 min", load: 1.3, length: 0.38}
    ]

    {:ok, applied} = Visualize.Chart.apply(design, sources: %{reading: reading})
    Visualize.Chart.render(applied)
    """
  end
end
