defmodule ExamplesWeb.PerformanceLive.MultiLine do
  @moduledoc """
  The performance page's Multi-Line chart: 48 scrolling ridgelines on the scroll model of
  `Examples.Scroll` (spec/14 §12.6, #296).

  One builder, `ridges/3`, draws the lines over a column range in one geometry — the plot
  `init/2` is given, the rectangle inside the page's margin that the hybrid backends' axes
  frame — for every backend: the full render is the range of every column, and an
  incremental frame's strips are the columns under them, so a strip is the full render's
  picture there, and the plot is the record's viewport, so the margin is never copied or
  drawn over (#298). `advance/1` scrolls by exactly `px_per_frame/0` pixels'
  worth of samples, and each line's value is a function of its absolute sample index, so
  the next frame is this one translated by that many pixels — the copy-shift contract of
  spec/09 §5.3.
  """

  alias Examples.Scroll
  alias Visualize.Backend.CanvasIncremental
  alias Visualize.IR.{Element, Transform}
  alias Visualize.{Scale, Shape}

  @lines 48
  @width 700
  @height 400
  @px_per_frame 1

  @typedoc "The plot `{x, y, width, height}` in canvas pixels."
  @type plot :: {number(), number(), pos_integer(), pos_integer()}

  @type t :: %__MODULE__{plot: plot(), scroll: Scroll.t(), params: [map()], data: [[number()]]}
  defstruct [:plot, :scroll, :params, :data]

  @doc "The ridgelines' count."
  @spec lines() :: pos_integer()
  def lines, do: @lines

  @doc "The pixels one frame scrolls by."
  @spec px_per_frame() :: pos_integer()
  def px_per_frame, do: @px_per_frame

  @doc "The canvas the chart fills, `{width, height}`."
  @spec size() :: {pos_integer(), pos_integer()}
  def size, do: {@width, @height}

  @doc """
  The chart in `plot` at the density nearest `requested` points over its lines: a window
  of the plot's columns, each line its `Examples.Scroll.count/1` samples from sample zero,
  with its own wave.
  """
  @spec init(pos_integer(), plot()) :: t()
  def init(requested, {_x, _y, w, _h} = plot) do
    scroll = Scroll.new(w, Scroll.density(requested / @lines, w))
    params = for idx <- 0..(@lines - 1), do: params(idx)
    count = Scroll.count(scroll)
    data = for p <- params, do: for(i <- 0..(count - 1), do: value(p, i))
    %__MODULE__{plot: plot, scroll: scroll, params: params, data: data}
  end

  @doc "The points in play: lines × samples per line."
  @spec points(t()) :: pos_integer()
  def points(%__MODULE__{scroll: scroll}), do: @lines * Scroll.count(scroll)

  @doc "The chart one frame on: the window scrolled by `px_per_frame/0`, every line shifted."
  @spec advance(t()) :: t()
  def advance(%__MODULE__{scroll: scroll, params: params, data: data} = chart) do
    scroll = Scroll.advance(scroll, @px_per_frame)

    data =
      Enum.zip_with(data, params, fn line, p ->
        Scroll.shift(scroll, line, @px_per_frame, &value(p, &1))
      end)

    %{chart | scroll: scroll, data: data}
  end

  @doc "The whole chart as a root element of the canvas's size."
  @spec element(t()) :: Element.t()
  def element(%__MODULE__{scroll: scroll} = chart) do
    Element.root(@width, @height, children: [ridges(chart, 0, Scroll.count(scroll) - 1)])
  end

  @doc """
  The ridgelines over columns `first..last`: a group at the plot's origin, each line a
  linear path — a curve would depend on samples beyond the range and a strip's would
  differ from the full render's — at its ridge's offset, coloured bottom to top.
  """
  @spec ridges(t(), non_neg_integer(), non_neg_integer()) :: Element.t()
  def ridges(%__MODULE__{plot: {px, py, _w, h}, scroll: scroll, data: data}, first, last) do
    x_scale = Scroll.x_scale(scroll)
    n = length(data)
    spacing = h / n

    y_scale =
      Scale.Linear.new() |> Scale.Linear.domain([0, 100]) |> Scale.Linear.range([spacing * 3, 0])

    line =
      Shape.Line.new()
      |> Shape.Line.x(fn d -> Scale.Linear.apply(x_scale, d.x) end)
      |> Shape.Line.y(fn d -> Scale.Linear.apply(y_scale, d.y) end)

    ridges =
      for {samples, idx} <- Enum.with_index(data) do
        points =
          samples
          |> Enum.slice(first..last)
          |> Enum.with_index(first)
          |> Enum.map(fn {y, i} -> %{x: i, y: y} end)

        path = Shape.Line.generate_path(line, points)
        stroke = color(idx / max(1, n - 1))

        Element.group([Element.path(path, %{fill: :none, stroke: stroke, stroke_width: 1.5})],
          transform: Transform.translate(0, h - (idx + 1) * spacing)
        )
      end

    Element.group(ridges, transform: Transform.translate(px, py))
  end

  @doc "The full-redraw record of the chart, for the incremental hook's first frame."
  @spec full(t()) :: binary()
  def full(chart), do: CanvasIncremental.encode_full_redraw(element(chart), size())

  @doc """
  The frame's incremental record: the strips `exposed_regions/2` yields for the frame's
  scroll of the plot, each `ridges/3` over the columns under it, with the plot as the
  viewport (D-106), so the margin around it is neither copied nor drawn over.
  """
  @spec incremental(t()) :: binary()
  def incremental(%__MODULE__{plot: {px, py, w, h} = plot, scroll: scroll} = chart) do
    dx = @px_per_frame

    regions =
      for {rx, ry, rw, rh} <- CanvasIncremental.exposed_regions({dx, 0}, {w, h}) do
        children =
          case Scroll.columns(scroll, {rx, rw}) do
            {first, last} -> [ridges(chart, first, last)]
            nil -> []
          end

        {{px + rx, py + ry, rw, rh}, Element.root(@width, @height, children: children)}
      end

    CanvasIncremental.encode_incremental({dx, 0}, size(), regions, viewport: plot)
  end

  @doc "The ridge colour at `t` in `0..1`, deep purple at the bottom to orange at the top."
  @spec color(number()) :: String.t()
  def color(t) when t >= 0 and t <= 1 do
    {r1, g1, b1} = {0x5B, 0x21, 0xB6}
    {r2, g2, b2} = {0xF9, 0x73, 0x16}

    [r1 + (r2 - r1) * t, g1 + (g2 - g1) * t, b1 + (b2 - b1) * t]
    |> Enum.map_join(fn c -> c |> round() |> Integer.to_string(16) |> String.pad_leading(2, "0") end)
    |> then(&("#" <> &1))
  end

  # Each line's wave: a primary and a secondary sine, amplitude and phases its own, drawn
  # once at init — nothing here changes between frames.
  defp params(idx) do
    %{
      amplitude: 30 + :rand.uniform() * 20,
      freq1: 0.02 + idx / @lines * 0.03,
      freq2: 0.05 + :rand.uniform() * 0.03,
      phase1: idx * 0.5 + :rand.uniform() * :math.pi(),
      phase2: :rand.uniform() * 2 * :math.pi(),
      amp_ratio: 0.3 + :rand.uniform() * 0.4
    }
  end

  # A line's value at absolute sample `x`, centred on 50.
  defp value(p, x) do
    primary = :math.sin(x * p.freq1 + p.phase1) * p.amplitude
    secondary = :math.sin(x * p.freq2 + p.phase2) * p.amplitude * p.amp_ratio
    50 + primary + secondary
  end
end
