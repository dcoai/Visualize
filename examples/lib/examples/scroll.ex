defmodule Examples.Scroll do
  @moduledoc """
  The scroll contract's data model (spec/09 §5.3, spec/14 §12.6), shared by the pages that
  scroll a plot through `Visualize.Backend.CanvasIncremental` (#292, #296).

  A copy-shift frame is the previous frame translated by exactly the scroll, so a series is
  a function of an absolute sample index at a whole number of samples per pixel column: a
  sample is `1 / samples_per_px` pixels, a scroll of `px` pixels is `px × samples_per_px`
  samples, and the window's `origin` advances by that. Nothing else changes between frames,
  and a strip of the plot is the same series function over the columns under it.
  """

  alias Visualize.Scale

  @type t :: %__MODULE__{
          inner_width: pos_integer(),
          samples_per_px: pos_integer(),
          origin: non_neg_integer()
        }
  defstruct [:inner_width, :samples_per_px, origin: 0]

  @doc "The density nearest `requested` samples over `inner_width` columns, at least one per column."
  @spec density(number(), pos_integer()) :: pos_integer()
  def density(requested, inner_width), do: max(1, round(requested / inner_width))

  @doc "A window over `inner_width` columns at `samples_per_px`, its origin at zero."
  @spec new(pos_integer(), pos_integer()) :: t()
  def new(inner_width, samples_per_px) when samples_per_px >= 1 do
    %__MODULE__{inner_width: inner_width, samples_per_px: samples_per_px}
  end

  @doc """
  The samples in the window: one per sample column and one more, so `x_scale/1` maps a
  sample to exactly `1 / samples_per_px` pixels.
  """
  @spec count(t()) :: pos_integer()
  def count(%__MODULE__{inner_width: w, samples_per_px: d}), do: d * w + 1

  @doc "The x scale of the window: sample index `0..count - 1` over `0..inner_width` pixels."
  @spec x_scale(t()) :: Scale.Linear.t()
  def x_scale(%__MODULE__{inner_width: w} = scroll) do
    Scale.Linear.new()
    |> Scale.Linear.domain([0, count(scroll) - 1])
    |> Scale.Linear.range([0, w])
  end

  @doc """
  The window at another density, keeping its instant (spec/14 §12.6, #401): the origin is
  in samples and is carried over, so the window still starts at the sample it did — the
  rate may change mid-run without the chart jumping. The count follows the new density,
  and the caller repaints in full, the copy-shift contract holding only while the density
  is constant (spec/09 §5.3).

      iex> scroll = Examples.Scroll.new(100, 4) |> Examples.Scroll.advance(25)
      iex> scroll.origin
      100
      iex> retimed = Examples.Scroll.retimed(scroll, 2)
      iex> {retimed.origin, retimed.samples_per_px, Examples.Scroll.count(retimed)}
      {100, 2, 201}
  """
  @spec retimed(t(), pos_integer()) :: t()
  def retimed(%__MODULE__{} = scroll, samples_per_px) when samples_per_px >= 1,
    do: %{scroll | samples_per_px: samples_per_px}

  @doc """
  The window over another plot width, keeping its density and its newest sample
  (spec/14 §12.6, #459): a chart drawn at a new size is a window of that many columns at
  the same samples per pixel, so a narrower one shows a shorter span. The right edge is
  where a stream's samples arrive, so the origin moves by the columns the width changed —
  a narrower window drops its oldest samples — and is clamped at zero. The caller repaints
  in full, the copy-shift holding only within one plot (spec/14 §12.5).

      iex> scroll = Examples.Scroll.new(100, 4) |> Examples.Scroll.advance(25)
      iex> narrow = Examples.Scroll.resized(scroll, 60)
      iex> {narrow.origin, narrow.samples_per_px, Examples.Scroll.count(narrow)}
      {260, 4, 241}
      iex> narrow.origin + Examples.Scroll.count(narrow) == scroll.origin + Examples.Scroll.count(scroll)
      true
      iex> Examples.Scroll.resized(scroll, 200).origin
      0
  """
  @spec resized(t(), pos_integer()) :: t()
  def resized(
        %__MODULE__{inner_width: w, samples_per_px: d, origin: origin} = scroll,
        inner_width
      )
      when is_integer(inner_width) and inner_width > 0 do
    %{scroll | inner_width: inner_width, origin: max(0, origin + (w - inner_width) * d)}
  end

  @doc "The samples a scroll of `px` pixels is."
  @spec samples(t(), non_neg_integer()) :: non_neg_integer()
  def samples(%__MODULE__{samples_per_px: d}, px), do: px * d

  @doc "The window after a scroll of `px` pixels: the origin on by `samples/2`."
  @spec advance(t(), non_neg_integer()) :: t()
  def advance(%__MODULE__{origin: origin} = scroll, px) do
    %{scroll | origin: origin + samples(scroll, px)}
  end

  @doc """
  A sampled line after the scroll that produced `scroll`: the first `samples(scroll, px)`
  values dropped and `fresh.(j)` appended for each new absolute sample `j` at the window's
  right edge, so the line stays `count/1` long and its value at column `i` is the sample
  `scroll.origin + i`.
  """
  @spec shift(t(), [number()], non_neg_integer(), (non_neg_integer() -> number())) :: [number()]
  def shift(%__MODULE__{origin: origin} = scroll, line, px, fresh) do
    n = samples(scroll, px)
    count = count(scroll)
    Enum.drop(line, n) ++ for(i <- (count - n)..(count - 1)//1, do: fresh.(origin + i))
  end

  @doc """
  The sample range `{first, last}` under a strip `{x, width}` of the plot, in plot pixels,
  with `buffer` samples each side so a path enters and leaves the strip on its own line —
  or `nil` when the strip lies outside the plot or holds fewer than two samples.
  """
  @spec columns(t(), {number(), number()}, non_neg_integer()) ::
          {non_neg_integer(), non_neg_integer()} | nil
  def columns(%__MODULE__{inner_width: w, samples_per_px: d} = scroll, {x, width}, buffer \\ 2) do
    from = max(0, x)
    to = min(w, x + width)

    if from >= to do
      nil
    else
      last = count(scroll) - 1
      first = max(0, floor(from * d) - buffer)
      last = min(last, ceil(to * d) + buffer)
      if last - first < 1, do: nil, else: {first, last}
    end
  end
end
