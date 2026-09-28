defmodule Examples.Charts.ContextChart do
  @moduledoc """
  One load average at four time scales, **four frames attached left to right** (#383,
  #429): the last year up to a day ago, the last day up to an hour ago, the last hour up
  to a quarter ago, and the last fifteen minutes.

  A year of load in one plot is a smear and the last minute of it is a pixel wide. The
  four frames are four `:window` steps over the **same** source (spec/14 §5.4.1, #426) —
  `window(:t, from: [1, :year], to: [24, :hour])` and its three neighbours — and the
  windows are disjoint and contiguous by the step's own rule: a given `to` is exclusive,
  an absent one closes at `now` inclusively, so no reading is drawn twice and the newest
  is drawn once.

  The four sit in the **cells of a grid** (§2.8, #384): `columns: [4, 3, 2, 2]` with a
  gap, so the older spans have the room they need and the recent ones stay legible, and
  the design computes no fractions. A weight is not a fraction — the four are normalised
  over their sum — so the layout is read as proportions and edited as proportions.

  Each frame declares its own `x` — four scales called `x`, one per frame, which is what
  a scale name belonging to its frame is for (§4.3) — over the extent of its own window,
  since a scale infers its domain from the rows its frame's marks read *after* their
  transforms (D-62). The `y` is the **one** scale, said once: the `year` frame declares
  it and the other three **adopt** it (`{:frame, :year, :y}`, §4.3, #384), so its domain
  is inferred over all four windows and every frame draws that extent at its own size.
  The traces are therefore comparable across the seams without a ceiling written by
  hand; only the leftmost frame draws the axis, the other three carrying the grid alone.

  The rows are sampled **geometrically by age**, as `Examples.Charts.LoadAge` samples
  (#418): a year at one reading a second is thirty million rows and a year at one reading
  an hour has nothing to say about the last minute. Each row is the mean of the span its
  slot covers (`Examples.Charts.Load.mean/3`), so a point at the year scale is the load
  over a week and not one second of it chosen at random.
  """

  import Visualize.Chart.Build

  alias Examples.Charts.{Design, Load}

  @epoch ~U[2026-01-01 09:00:00Z]
  @newest 5
  @oldest 31_536_000
  @per_decade 45
  # The frame whose `y` the other three adopt (spec/14 §4.3, #384): the load axis is
  # declared once, over the whole year, and shared.
  @owner :year

  # The grid the four frames sit on (spec/14 §2.8, #384): the older the span, the less
  # room it needs, so the widths are weights and no fraction is computed here.
  @columns [4, 3, 2, 2]
  @gap 10

  # The four frames, left to right: the name, the window's ends as `:window` durations,
  # the words over it and the tick format its span reads by.
  @frames [
    {:year, [1, :year], [24, :hour], "the year", "%b"},
    {:day, [24, :hour], [1, :hour], "the day", "%H:%M"},
    {:hour, [1, :hour], [15, :minute], "the hour", "%H:%M"},
    {:recent, [15, :minute], nil, "the quarter", "%H:%M"}
  ]

  @doc "The size this chart is drawn at when the caller names none (spec/14 §4.2)."
  def size, do: {900, 320}

  def title, do: "Context"
  def description, do: "One load average at four time scales, four frames side by side"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    design =
      Design.fold(
        [
          chart(meta: %{name: title(), description: [description()]}),
          layout(columns: @columns, gap: @gap),
          source(:load, [:t, :v], types: %{t: :time, v: :number}),
          style(:trace, stroke: :series_1, stroke_width: 1.5, curve: :monotone_x),
          style(:volume, fill: :series_1, opacity: 0.18, curve: :monotone_x),
          style(:span, extends: :label, font_size: 11),
          # The grid without its axis: a grid line is drawn in the `:grid` style whatever
          # the axis's own style is (spec/14 §4.4), so this draws the lines and nothing else.
          style(:ghost, stroke: :none, fill: :none)
        ] ++ Enum.flat_map(Enum.with_index(@frames), &frame/1)
      )

    {design, %{load: rows(opts)}}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  # One frame of the four: its quarter of the box, its window of the one source, and the
  # axis only the leftmost draws.
  defp frame({{name, from, to, words, format}, index}) do
    leftmost? = index == 0

    in_frame(name, [
      cartesian(
        cell: [index, 0],
        margin: %{top: 26, right: 12, bottom: 32, left: if(leftmost?, do: 44, else: 14)}
      ),
      time_scale(:x),
      # One load axis across the four frames: the `year` frame declares it and the other
      # three adopt it, so its domain is inferred over every window and each draws the
      # same extent at its own size (spec/14 §4.3, #384).
      scale_of(name),
      axis(:x, :bottom, ticks: 3, format: format),
      # The load is the same in all four, so only the leftmost frame says what it is; the
      # other three carry the grid at the same ticks and nothing else.
      axis(:y, :left, ticks: 4, grid: true, style: if(leftmost?, do: :axis, else: :ghost)),
      area(window_of(from, to), %{x: :t, y: :v, y0: {:scale, :min}}, style: :volume),
      line(window_of(from, to), %{x: :t, y: :v}, style: :trace),
      label({:frame, :top_left}, [words], style: :span)
    ])
  end

  # The owner declares the load axis, zero-based so the volume reads; the rest adopt it.
  defp scale_of(@owner), do: linear_scale(:y, domain: [0, :auto], nice: true)
  defp scale_of(_name), do: adopt(:y, @owner)

  # The window step over the one source: the rows whose reading lies in the frame's span.
  defp window_of(from, nil), do: window(from(:load), :t, from: from)
  defp window_of(from, to), do: window(from(:load), :t, from: from, to: to)

  defp rows(opts) do
    now = second(opts)
    half = :math.pow(10, decades() / steps() / 2)

    # Oldest first, as a time series reads: the slots are geometric in *age*, so the loop
    # counts down from the oldest.
    for i <- steps()..0//-1 do
      age = @newest * :math.pow(10, i * decades() / steps())
      %{
        t: DateTime.add(@epoch, round(now - age), :second),
        v: Load.mean(:fifteen, now - age * half, now - age / half)
      }
    end
  end

  defp decades, do: :math.log10(@oldest / @newest)
  defp steps, do: round(decades() * @per_decade)

  # A tick is a minute of the machine's day: at this scale nothing else shows.
  defp second(opts), do: (opts[:animation_tick] || 0) * 60 + @oldest

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    # One source at four scales: four windows of it, four frames across the box. A given
    # `to` is exclusive and an absent one closes at now, so the four are disjoint and
    # contiguous and the newest reading is drawn exactly once.
    windows = [
      {:year, [from: [1, :year], to: [24, :hour]], "%b"},
      {:day, [from: [24, :hour], to: [1, :hour]], "%H:%M"},
      {:hour, [from: [1, :hour], to: [15, :minute]], "%H:%M"},
      {:recent, [from: [15, :minute]], "%H:%M"}
    ]

    frames =
      for {{name, span, format}, i} <- Enum.with_index(windows) do
        in_frame(name, [
          cartesian(box: [i * 0.25, 0, 0.25, 1], margin: %{top: 26, right: 12, bottom: 32, left: 44}),
          time_scale(:x),
          linear_scale(:y, domain: [0, 4]),
          axis(:x, :bottom, ticks: 3, format: format),
          line(window(from(:load), :t, span), %{x: :t, y: :v})
        ])
      end

    {:ok, design} =
      Visualize.Chart.compose(
        [chart(meta: %{name: "Context"}), source(:load, [:t, :v], types: %{t: :time, v: :number})] ++
          List.flatten(frames)
      )

    {:ok, applied} = Visualize.Chart.apply(design, sources: %{load: load})
    Visualize.Chart.render(applied)
    """
  end
end
