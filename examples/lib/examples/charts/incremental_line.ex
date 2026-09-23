defmodule Examples.Charts.IncrementalLine do
  @moduledoc """
  The incremental demo's chart as a design (#402): one line over a cartesian frame with a
  **viewport** — a streaming window on `x` (spec/14 §12.5) — so the compiled chart scrolls
  through the incremental canvas by exactly the whole pixels the window moved, the
  copy-shift of spec/09 §5.3 doing the rest. `/incremental` was a LiveView that built its
  own scales, shapes and `canvas_incremental` pushes; this is the same picture said as a
  design, drawn on any backend and measured by the performance drawer.

  The value is the demo's `sin(x / 20) · 100 + cos(x / 15) · 50` at `x = 2t`, a function
  of the absolute sample index `t`: a scroll may only copy what a fresh strip will agree
  with, so the demo's `:rand.uniform()` jitter — which cannot survive a copy-shift —
  becomes a hash of the sample, as *Scrolling series*' random line is.
  """

  import Visualize.Chart.Build

  alias Examples.Charts.Design
  alias Examples.Scroll

  @width 800
  @height 500
  @margin %{top: 20, right: 20, bottom: 30, left: 40}
  @inner_width @width - @margin.left - @margin.right

  def title, do: "Incremental line"

  def description, do: "One line streaming through a viewport, drawn by copy and shift"

  @doc "A streaming design: the drawer offers Incremental and a data rate (spec/14 §12.6)."
  def stream?, do: true

  @doc "The plot the viewport scrolls, `{x, y, width, height}` in the frame."
  def plot, do: {@margin.left, @margin.top, @inner_width, @height - @margin.top - @margin.bottom}

  @doc """
  The design and the rows of its window (spec/14 §16.1). Options: `samples_per_px`
  (default 1) and `origin` (default 0) — the window in `Examples.Scroll`'s terms — and
  `rows`, the window's rows when the caller already holds them (#408).
  """
  def design(opts \\ []) do
    scroll = scroll(opts)
    count = Scroll.count(scroll)
    rows = opts[:rows] || rows(scroll)

    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        style(:trace, stroke: :series_1, stroke_width: 2, curve: :monotone_x),
        source(:signal, [:t, :v], types: %{t: :number, v: :number}),
        # A viewport on x: the compiled chart windows x to [hi − span, hi] every tick and
        # scrolls the binary canvas by the pixels the window moved (spec/14 §12.5).
        cartesian(@width, @height, margin: @margin, viewport: %{scale: :x, span: count - 1}),
        linear_scale(:x),
        linear_scale(:y, domain: [0, 400]),
        axis(:x, :bottom, ticks: 10, grid: true),
        axis(:y, :left, ticks: 8, grid: true),
        title("One line, #{count} points in the window"),
        line(:signal, %{x: :t, y: :v}, style: :trace, render: :binary)
      ])

    {design, rows}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  @doc "The window's `Examples.Scroll` at `opts`."
  def scroll(opts) do
    %{Scroll.new(@inner_width, opts[:samples_per_px] || 1) | origin: opts[:origin] || 0}
  end

  @doc "The rows of the window: `t` the absolute sample, `v` its value."
  def rows(%Scroll{origin: origin} = scroll) do
    count = Scroll.count(scroll)
    %{signal: for(t <- origin..(origin + count - 1), do: %{t: t, v: value(t)})}
  end

  @doc """
  The window's rows after a scroll of `px` columns, from the rows it held (#408): the
  samples the scroll exposed appended and as many dropped from the front
  (`Examples.Scroll.shift/4`). Every value is a function of its absolute sample, so this
  is the list `rows/1` builds — 0.12 ms against 11.6 for a 22,201-row window.
  """
  @spec rows(Scroll.t(), non_neg_integer(), map() | nil) :: map()
  def rows(%Scroll{} = advanced, _px, nil), do: rows(advanced)

  def rows(%Scroll{} = advanced, px, %{signal: held}) do
    %{signal: Scroll.shift(advanced, held, px, fn t -> %{t: t, v: value(t)} end)}
  end

  @doc """
  The value at absolute sample `t`: the demo's two waves at `x = 2t`, with a hash of the
  sample for the jitter — one function for the whole render and for a strip, nothing that
  changes between frames (spec/09 §5.3).
  """
  @spec value(non_neg_integer()) :: float()
  def value(t) do
    x = t * 2
    :math.sin(x / 20) * 100 + :math.cos(x / 15) * 50 + 200 + :erlang.phash2(t, 1000) / 100
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    # A viewport on x: the compiled chart windows x to [hi − span, hi] every tick and
    # scrolls the binary canvas by the pixels the window moved (spec/14 §12.5), the hook
    # copying the canvas and repainting only the strip the scroll exposed (spec/09 §5.3).
    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Incremental line"}),
        style(:trace, stroke: :series_1, stroke_width: 2, curve: :monotone_x),
        source(:signal, [:t, :v]),
        cartesian(800, 500,
          margin: %{top: 20, right: 20, bottom: 30, left: 40},
          viewport: %{scale: :x, span: 740}
        ),
        linear_scale(:x),
        linear_scale(:y, domain: [0, 400]),
        axis(:x, :bottom, ticks: 10, grid: true),
        axis(:y, :left, ticks: 8, grid: true),
        line(:signal, %{x: :t, y: :v}, style: :trace, render: :binary)
      ])

    # Every row is a function of its absolute sample index, so a strip drawn fresh agrees
    # with the pixels the scroll copied.
    value = fn t -> :math.sin(t * 2 / 20) * 100 + :math.cos(t * 2 / 15) * 50 + 200 end
    rows = %{signal: for(t <- 0..740, do: %{t: t, v: value.(t)})}

    {:ok, applied} = Visualize.Chart.apply(design, sources: rows)
    Visualize.Chart.render(applied)
    """
  end
end
