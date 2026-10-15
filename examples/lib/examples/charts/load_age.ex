defmodule Examples.Charts.LoadAge do
  @moduledoc """
  Three hours of load average on a **logarithmic age** axis (#415): `x` is how long ago a
  reading was taken — five seconds at the right edge, three hours at the left — on a
  `:log` scale, so the last minute is spread across a third of the plot and the third hour
  is squeezed into the last inch. Animated, a reading drifts leftward and compresses as it
  ages: the chart scrolls right to left without ever moving the axis.

  It is an age axis rather than a windowed clock because a log window cannot be scrolled
  by copying pixels — the mapping is not a translation, so a sample a minute old and one
  an hour old move by different amounts in the same tick (#416). Here the axis is fixed
  and every frame is drawn whole, which after #414 is a few milliseconds.

  The rows are sampled **geometrically by age** — about sixty a decade — so the log axis
  is evenly covered by a few hundred points rather than by the ten thousand a uniform
  second would need. The load is `Examples.Charts.Load`'s, the same three windows its
  neighbor `Examples.Charts.LoadGauge` puts on a dial. `Examples.Charts.ContextChart`
  answers the same question with four frames and four windows rather than one log axis
  (#383, #429); both are here because they read differently, and this one scrolls without
  ever moving its axis.

  **A point stands for a bucket, and is drawn as the bucket's mean** (#418). The slots are
  a fifth of a second apart at the newest end and seven minutes apart at the oldest, so a
  point sample there read one second of a span it claimed to summarize — and since the
  clock advances three seconds a tick, it read a *different* second each tick and the aged
  trace boiled instead of drifting. `Examples.Charts.Load.mean/3` averages the slot's own
  span on an absolute-second stride; at the newest end, where the span is under a second,
  that is the single reading it always was.

  So the swing is averaged down with age, and that is the reading, not a loss (#514).
  Each point is its bucket's mean, and a slot at age *a* spans about 3.9% of *a*; a mean
  over a span *w* scales the load's ten-minute sine by sinc(πw/600). That is about 0.92
  at one hour (a 138 s span) and 0.38 at three (415 s), so the oldest traces converge on
  the load's mean. It is a bucketed history's expected reading, as RRD's is, not lost
  data.
  """

  import Visualize.Chart.Build

  alias Examples.Charts.{Design, Load}

  @margin %{top: 30, right: 30, bottom: 45, left: 50}
  @newest 5
  @oldest 10_800
  @per_decade 60

  @doc "The size this chart is drawn at when the caller names none (spec/14 §4.2)."
  def size, do: {720, 360}

  def title, do: "Load age"

  def description,
    do:
      "Three hours of load average on a logarithmic age axis; " <>
        "an old point is its bucket's mean, so the swing is averaged down with age"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    {width, _height} = Design.size(__MODULE__, opts)

    design =
      Design.fold(
        [chart(meta: %{name: title(), description: [description()]})] ++
          furniture() ++ plot(width)
      )

    {design, sources(Load.second(opts, @oldest))}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  @doc """
  The source and the style the age view draws with: what `plot/1` names, said once here and
  in `Examples.Charts.LoadAgeGauge` (#498).
  """
  def furniture do
    [
      source(:loads, [:age, :load, :window],
        types: %{age: :number, load: :number, window: :category}
      ),
      style(:trace, stroke_width: 2, curve: :monotone_x)
    ]
  end

  @doc """
  The age view's fragments, for a frame `width` wide: its `cartesian` at `margin/0`, the log
  age axis and the load axis, the windows' key in the plot's top-right corner and the three
  traces. Unframed, so this chart is one frame and a design of several puts it in one with
  `in_frame/2`.
  """
  def plot(width) do
    inner = width - @margin.left - @margin.right

    [
      cartesian(margin: @margin),
      # Age on a log axis, newest at the right: a reading drifts left as it ages.
      log_scale(:x, domain: [@newest, @oldest], range: [inner, 0]),
      linear_scale(:y, domain: [0, 4]),
      ordinal_scale(:color,
        domain: Enum.map(Load.windows(), &elem(&1, 1)),
        range: [:series_1, :series_2, :series_3]
      ),
      axis(:x, :bottom, ticks: [5, 30, 60, 300, 900, 3600, 10_800], format: :duration),
      axis(:y, :left, ticks: 4, grid: true),
      legend(:color, position: :top_right),
      label({:axis, :x}, ["age — newest at the right"]),
      line(:loads, %{x: :age, y: :load, series: :window}, style: :trace)
    ]
  end

  @doc """
  The age view's margin in pixels (spec/14 §4.2): where its plot area begins, which a frame
  drawn over the plot reads to stay inside it (#498).
  """
  def margin, do: @margin

  @doc "The oldest age the view draws, three hours: the second it reads at rest."
  def oldest, do: @oldest

  @doc """
  The ages a frame draws, geometrically spaced from the newest to the oldest: even on the
  log axis, and a few hundred rather than the ten thousand seconds they span.
  """
  @spec ages() :: [number()]
  def ages do
    for i <- 0..steps(), do: @newest * :math.pow(10, i * decades() / steps())
  end

  @doc """
  The rows the age view binds at absolute second `now`: every window at every age, each
  the mean of the span its slot covers, measured back from `now`.
  """
  def sources(now) do
    half = :math.pow(10, decades() / steps() / 2)

    loads =
      for {window, name} <- Load.windows(), age <- ages() do
        %{age: age, load: Load.mean(window, now - age * half, now - age / half), window: name}
      end

    %{loads: loads}
  end

  # The span a slot covers: half a step either side of it, in the grid's own ratio.
  defp decades, do: :math.log10(@oldest / @newest)
  defp steps, do: round(decades() * @per_decade)

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Load age"}),
        source(:loads, [:age, :load, :window]),
        style(:trace, stroke_width: 2, curve: :monotone_x),
        cartesian(margin: %{top: 30, right: 30, bottom: 45, left: 50}),
        # x is how long ago: five seconds at the right edge, three hours at the left, on a
        # log scale — the last minute takes a third of the plot, the third hour an inch.
        log_scale(:x, domain: [5, 10_800], range: [640, 0]),
        linear_scale(:y, domain: [0, 4]),
        ordinal_scale(:color, domain: ["1 min", "5 min", "15 min"], range: [:series_1, :series_2, :series_3]),
        axis(:x, :bottom, ticks: [5, 30, 60, 300, 900, 3600, 10_800], format: :duration),
        axis(:y, :left, ticks: 4, grid: true),
        legend(:color, position: :top_right),
        line(:loads, %{x: :age, y: :load, series: :window}, style: :trace)
      ])

    # Sampled geometrically by age, so the log axis is evenly covered — and each point is
    # the mean over the span its slot covers, since a slot is minutes wide at the old end.
    rows =
      for window <- ["1 min", "5 min", "15 min"],
          i <- 0..200,
          age = 5 * :math.pow(10, i * :math.log10(2160) / 200),
          half = :math.pow(10, :math.log10(2160) / 400),
          do: %{
            age: age,
            load: load_over(window, now - age * half, now - age / half),
            window: window
          }

    {:ok, applied} = Visualize.Chart.apply(design, sources: %{loads: rows})
    Visualize.Chart.render(applied)
    """
  end
end
