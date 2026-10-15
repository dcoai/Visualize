defmodule Visualize.Units do
  @moduledoc """
  Lengths with their units (spec/08 §13, spec/14 §3.9, #651, D-174).

  A unit value is `{n, unit}`: data, stored and compared as a value. The **absolute**
  screen units convert to user units — CSS pixels — at CSS's fixed ratios, 96 px = 1 in =
  2.54 cm = 25.4 mm = 72 pt and 1 pc = 12 pt; the **relative** ones, `:em` and `:pct`, are
  measured against a font size and a box the caller gives (`resolve/2`). A bare number is
  user units, as it always was.

      iex> import Visualize.Units
      iex> pt(12)
      {12, :pt}
      iex> Visualize.Units.to_px(pt(12))
      16.0
      iex> Visualize.Units.resolve(em(1.5), %{em: 12})
      18.0
      iex> Visualize.Units.resolve(pct(50), %{box: 30})
      15.0

  The world lengths a scene measures its ground in (#620) — `:mm` … `:mi` — are a table of
  their own, in metres (`to_meters/2`, `convert_length/3`): a world length reaches the
  screen only through a scale a scene declares.
  """

  @typedoc "A screen unit (spec/08 §13.1, §13.2)."
  @type unit :: :px | :pt | :pc | :in | :cm | :mm | :em | :pct

  @typedoc "A length with its unit."
  @type t :: {number(), unit()}

  @typedoc "A world length unit (spec/08 §13.3)."
  @type length_unit :: :mm | :cm | :m | :km | :in | :ft | :yd | :mi

  @absolute [px: 1, pt: 4 / 3, pc: 16, in: 96, cm: 96 / 2.54, mm: 96 / 25.4]
  @px Map.new(@absolute)
  @relative [:em, :pct]
  @units Keyword.keys(@absolute) ++ @relative

  @lengths [mm: 0.001, cm: 0.01, m: 1, km: 1000, in: 0.0254, ft: 0.3048, yd: 0.9144, mi: 1609.344]
  @meters Map.new(@lengths)

  @doc "`{n, :px}`."
  @spec px(number()) :: t()
  def px(n) when is_number(n), do: {n, :px}

  @doc "`{n, :pt}`: a point, 1/72 of an inch."
  @spec pt(number()) :: t()
  def pt(n) when is_number(n), do: {n, :pt}

  @doc "`{n, :pc}`: a pica, 12 points."
  @spec pc(number()) :: t()
  def pc(n) when is_number(n), do: {n, :pc}

  @doc "`{n, :in}`: an inch, 96 user units. Named `inch` because `in` is an Elixir operator."
  @spec inch(number()) :: t()
  def inch(n) when is_number(n), do: {n, :in}

  @doc "`{n, :cm}`."
  @spec cm(number()) :: t()
  def cm(n) when is_number(n), do: {n, :cm}

  @doc "`{n, :mm}`."
  @spec mm(number()) :: t()
  def mm(n) when is_number(n), do: {n, :mm}

  @doc "`{n, :em}`: `n` times a font size, the one the context gives (spec/14 §3.9)."
  @spec em(number()) :: t()
  def em(n) when is_number(n), do: {n, :em}

  @doc "`{n, :pct}`: `n` percent of a box's length, the one the context gives (spec/14 §3.9)."
  @spec pct(number()) :: t()
  def pct(n) when is_number(n), do: {n, :pct}

  @doc "The screen units, absolute then relative."
  @spec units() :: [unit(), ...]
  def units, do: @units

  @doc "The absolute screen units (spec/08 §13.1)."
  @spec absolute_units() :: [unit(), ...]
  def absolute_units, do: Keyword.keys(@absolute)

  @doc """
  Whether a term is a unit value.

      iex> Visualize.Units.unit?({3, :mm})
      true
      iex> Visualize.Units.unit?({3, :furlong})
      false
  """
  @spec unit?(term()) :: boolean()
  def unit?({n, unit}) when is_number(n), do: unit in @units
  def unit?(_term), do: false

  @doc """
  A number as it is, an absolute unit value in user units; `ArgumentError` for a relative
  one, which has nothing to be measured against here.
  """
  @spec to_px(number() | t()) :: number()
  def to_px(n) when is_number(n), do: n
  def to_px({n, unit}) when is_number(n) and is_map_key(@px, unit), do: n * @px[unit] * 1.0

  def to_px({n, unit}) when is_number(n) and unit in @relative do
    raise ArgumentError,
          "#{inspect({n, unit})} is relative: resolve it against its context (spec/14 §3.9)"
  end

  @doc """
  `n` of one absolute unit in another.

      iex> Visualize.Units.convert(1, :in, :pt)
      72.0
  """
  @spec convert(number(), unit(), unit()) :: float()
  def convert(n, from, to) when is_map_key(@px, from) and is_map_key(@px, to),
    do: n * @px[from] / @px[to]

  @doc """
  A size in user units: a number as it is, an absolute unit value by `to_px/1`, an `em`
  against the context's `:em` (a font size) and a `pct` against its `:box` (a length).
  Raises `ArgumentError` naming the unit when the context lacks its measure.
  """
  @spec resolve(number() | t(), %{optional(:em) => number(), optional(:box) => number()}) ::
          number()
  def resolve(n, _context) when is_number(n), do: n

  def resolve({n, :em}, %{em: font}) when is_number(n) and is_number(font), do: n * font * 1.0

  def resolve({n, :pct}, %{box: box}) when is_number(n) and is_number(box),
    do: n / 100 * box

  def resolve({n, unit}, _context) when is_number(n) and unit in @relative do
    raise ArgumentError,
          "#{inspect({n, unit})} has nothing to be measured against here: an em needs a font " <>
            "size and a pct a box (spec/14 §3.9)"
  end

  def resolve(value, _context), do: to_px(value)

  @doc "The world length units (spec/08 §13.3)."
  @spec length_units() :: [length_unit(), ...]
  def length_units, do: Keyword.keys(@lengths)

  @doc """
  A world length in metres.

      iex> Visualize.Units.to_meters(1, :ft)
      0.3048
  """
  @spec to_meters(number(), length_unit()) :: number()
  def to_meters(n, unit) when is_number(n) and is_map_key(@meters, unit), do: n * @meters[unit]

  @doc """
  A world length in another world unit.

      iex> Visualize.Units.convert_length(2500, :m, :km)
      2.5
  """
  @spec convert_length(number(), length_unit(), length_unit()) :: float()
  def convert_length(n, from, to) when is_map_key(@meters, from) and is_map_key(@meters, to),
    do: n * @meters[from] / @meters[to]
end
