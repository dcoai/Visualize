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
  neighbour `Examples.Charts.LoadGauge` puts on a dial.
  """

  import Visualize.Chart.Build

  alias Examples.Charts.{Design, Load}

  @margin %{top: 30, right: 30, bottom: 45, left: 50}
  @newest 5
  @oldest 10_800
  @per_decade 60

  def title, do: "Load age"
  def description, do: "Three hours of load average on a logarithmic age axis"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    width = opts[:width] || 720
    height = opts[:height] || 360
    inner = width - @margin.left - @margin.right

    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        source(:loads, [:age, :load, :window],
          types: %{age: :number, load: :number, window: :category}
        ),
        style(:trace, stroke_width: 2, curve: :monotone_x),
        cartesian(width, height, margin: @margin),
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
      ])

    {design, %{loads: rows(opts)}}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  @doc """
  The ages a frame draws, geometrically spaced from the newest to the oldest: even on the
  log axis, and a few hundred rather than the ten thousand seconds they span.
  """
  @spec ages() :: [number()]
  def ages do
    decades = :math.log10(@oldest / @newest)
    steps = round(decades * @per_decade)

    for i <- 0..steps, do: @newest * :math.pow(10, i * decades / steps)
  end

  defp rows(opts) do
    now = second(opts)

    for {window, name} <- Load.windows(),
        age <- ages(),
        do: %{age: age, load: Load.at(window, now - age), window: name}
  end

  # A tick is three seconds of the machine's day, as the gauge's is.
  defp second(opts), do: (opts[:animation_tick] || 0) * 3 + @oldest

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Load age"}),
        source(:loads, [:age, :load, :window]),
        style(:trace, stroke_width: 2, curve: :monotone_x),
        cartesian(720, 360, margin: %{top: 30, right: 30, bottom: 45, left: 50}),
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

    # Sampled geometrically by age, so the log axis is evenly covered.
    rows =
      for window <- ["1 min", "5 min", "15 min"],
          i <- 0..200,
          age = 5 * :math.pow(10, i * :math.log10(2160) / 200),
          do: %{age: age, load: load_at(window, now - age), window: window}

    {:ok, applied} = Visualize.Chart.apply(design, sources: %{loads: rows})
    Visualize.Chart.render(applied)
    """
  end
end
