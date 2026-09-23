defmodule Examples.Charts.ScrollingSeries do
  @moduledoc """
  The High-Performance chart as a design (#322, #327): an area and four lines over a
  cartesian frame with a **viewport** — a streaming window on `x` (spec/14 §12.5) — so
  the compiled chart scrolls through the incremental canvas by exactly the whole pixels
  the window moved.

  Every series is a function of an absolute sample index, at a whole number of samples
  per pixel column (`Examples.Scroll`): the window shows `count = samples_per_px × plot
  width + 1` samples from `origin`, the viewport's span is `count − 1` samples, and a
  frame's rows are `t = origin .. origin + count − 1`. The random line is a hash of its
  sample index, so it is a function of `t` like the others and the scroll contract of
  spec/09 §5.3 holds without a stored line.
  """

  import Visualize.Chart.Build

  alias Examples.Charts.Design
  alias Examples.Scroll

  @width 900
  @height 500
  @margin %{top: 40, right: 30, bottom: 50, left: 60}
  @inner_width @width - @margin.left - @margin.right
  @series [:area, :line_1, :line_2, :line_3, :line_4]

  def title, do: "Scrolling series"

  def description,
    do: "An area and four lines streaming through a viewport, drawn incrementally"

  @doc "A streaming design: the drawer offers Incremental and a data rate (spec/14 §12.6)."
  def stream?, do: true

  @doc "The plot the viewport scrolls, `{x, y, width, height}` in the frame."
  def plot, do: {@margin.left, @margin.top, @inner_width, @height - @margin.top - @margin.bottom}

  @doc """
  The design and the rows of its window (spec/14 §16.1). Options: `samples_per_px`
  (default 1), `origin` (default 0) — the window in `Examples.Scroll`'s terms — `rows`,
  the window's rows when the caller already holds them (#408), and the usual
  `width`/`height` are the frame's own.
  """
  def design(opts \\ []) do
    scroll = scroll(opts)
    count = Scroll.count(scroll)
    rows = opts[:rows] || rows(scroll)

    design =
      Design.fold(
        [
          chart(meta: %{name: title(), description: [description()]}),
          style(:area, fill: "#4e79a7", fill_opacity: 0.7, stroke: "#4e79a7", stroke_width: 1),
          style(:line, stroke_width: 2),
          cartesian(@width, @height, margin: @margin, viewport: %{scale: :x, span: count - 1}),
          linear_scale(:x),
          linear_scale(:y, domain: [-100, 100]),
          axis(:x, :bottom, ticks: 10, grid: true),
          axis(:y, :left, ticks: 10, grid: true),
          title("Area + four lines, #{count * length(@series)} points in the window")
        ] ++
          for(name <- @series, do: source(name, [:t, :v])) ++
          [area(:area, %{x: :t, y: :v}, style: :area, render: :binary)] ++
          for(name <- tl(@series), do: line(name, %{x: :t, y: :v}, style: :line, render: :binary))
      )

    {design, rows}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  @doc "The window's `Examples.Scroll` at `opts`."
  def scroll(opts) do
    %{Scroll.new(@inner_width, opts[:samples_per_px] || 1) | origin: opts[:origin] || 0}
  end

  @doc "The rows of every series over the window: `t` the absolute sample, `v` its value."
  def rows(%Scroll{origin: origin} = scroll) do
    count = Scroll.count(scroll)

    for name <- @series, into: %{} do
      {name, for(t <- origin..(origin + count - 1), do: %{t: t, v: value(name, t, count)})}
    end
  end

  @doc """
  The window's rows after a scroll of `px` columns, from the rows it held (#408): per
  series the samples the scroll exposed appended and as many dropped from the front
  (`Examples.Scroll.shift/4`). Every value is a function of its absolute sample and the
  window's count, so this is the list `rows/1` builds while the density holds.
  """
  @spec rows(Scroll.t(), non_neg_integer(), map() | nil) :: map()
  def rows(%Scroll{} = advanced, _px, nil), do: rows(advanced)

  def rows(%Scroll{} = advanced, px, held) when is_map(held) do
    count = Scroll.count(advanced)

    for name <- @series, into: %{} do
      {name,
       Scroll.shift(advanced, held[name], px, fn t -> %{t: t, v: value(name, t, count)} end)}
    end
  end

  @doc """
  A series' value at absolute sample `t` of a window `count` samples wide: one function
  for the whole render and a strip, nothing that changes between frames (spec/09 §5.3).
  """
  def value(:area, t, count) do
    x = t / count
    :math.sin(x * 8) * 25 + :math.sin(x * 3) * 15 - 20
  end

  # The random line: a hash of its sample, so it is random and yet a function of t.
  def value(:line_1, t, _count), do: :erlang.phash2(t, 1000) / 1000 * 60 + 40

  def value(name, t, count) do
    idx = Enum.find_index(@series, &(&1 == name))
    offset = idx * 0.8
    amplitude = 35 - idx * 5
    frequency = 12 + idx * 4
    x = t / count

    :math.sin(x * frequency + offset) * amplitude +
      :math.cos(x * (frequency / 2.5) + offset) * (amplitude / 3) + (idx - 1.5) * 15
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    # A viewport on x: the compiled chart windows x to [hi − span, hi] every tick and
    # scrolls the binary canvas by the pixels the window moved (spec/14 §12.5).
    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Scrolling series"}),
        style(:area, fill: "#4e79a7", fill_opacity: 0.7, stroke: "#4e79a7"),
        style(:line, stroke_width: 2),
        cartesian(900, 500, margin: %{top: 40, right: 30, bottom: 50, left: 60},
          viewport: %{scale: :x, span: 810}),
        linear_scale(:x),
        linear_scale(:y, domain: [-100, 100]),
        axis(:x, :bottom, ticks: 10, grid: true),
        axis(:y, :left, ticks: 10, grid: true),
        source(:area, [:t, :v]), source(:line_1, [:t, :v]),
        area(:area, %{x: :t, y: :v}, style: :area, render: :binary),
        line(:line_1, %{x: :t, y: :v}, style: :line, render: :binary)
      ])

    {:ok, applied} = Visualize.Chart.apply(design, sources: rows)
    Visualize.Chart.render(applied)
    """
  end
end
