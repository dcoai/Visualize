defmodule Visualize.Geo.Adder do
  @moduledoc false
  # d3-array's Adder (src/fsum.js, v3.2.4), which d3-geo sums spherical angles with: a sum
  # of floats exact to the last bit, kept as non-overlapping partials (Shewchuk's
  # algorithm, CPython's math.fsum). `polygon_contains?` decides which side of a ring is
  # inside by the sign of such a sum near zero, where a naive sum's rounding would decide
  # it instead.

  @doc false
  @spec new() :: [float()]
  def new, do: []

  @doc false
  # fsum.js:7–19: fold `x` into the partials, lowest first, dropping zero remainders. d3
  # holds at most 32 partials; a sum of doubles needs far fewer.
  @spec add([float()], number()) :: [float()]
  def add(partials, x), do: add(partials, x, [])

  defp add([], x, kept), do: Enum.reverse([x | kept])

  defp add([y | rest], x, kept) do
    hi = x + y
    lo = if abs(x) < abs(y), do: x - (hi - y), else: y - (hi - x)
    add(rest, hi, if(lo != 0, do: [lo | kept], else: kept))
  end

  @doc false
  # fsum.js:20–37: the partials summed from the highest, with the half-way correction
  # that makes the rounding exact.
  @spec value([float()]) :: float()
  def value([]), do: 0.0

  def value(partials) do
    [hi | lower] = Enum.reverse(partials)
    sum_down(hi, lower)
  end

  defp sum_down(hi, []), do: hi

  defp sum_down(x, [y | rest]) do
    hi = x + y
    lo = y - (hi - x)

    cond do
      lo == 0 -> sum_down(hi, rest)
      rest == [] -> hi
      true -> round_half(hi, lo, hd(rest))
    end
  end

  defp round_half(hi, lo, next) when (lo < 0 and next < 0) or (lo > 0 and next > 0) do
    y = lo * 2
    x = hi + y
    if y == x - hi, do: x, else: hi
  end

  defp round_half(hi, _lo, _next), do: hi
end
