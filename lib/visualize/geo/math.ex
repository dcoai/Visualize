defmodule Visualize.Geo.Math do
  @moduledoc false
  # d3-geo's src/math.js `asin` and `acos`, and d3-geo-projection's src/math.js `sqrt`:
  # the inverse sine and cosine clamped to their domain, and the square root of a quantity
  # non-negative on the sphere clamped at zero (spec/07 §1.2, D-149). Rounding carries a
  # value that is exactly ±1 or 0 at a pole or the antimeridian a few ulps past it, where
  # `:math` raises and JavaScript returns NaN; every inverse sine and cosine in
  # `Visualize.Geo` goes through here so that no point at the edge of a domain raises.

  @half_pi :math.pi() / 2

  @doc false
  # math.js: `x > 1 ? halfPi : x < -1 ? -halfPi : Math.asin(x)`.
  @spec asin(number()) :: float()
  def asin(x) when x > 1, do: @half_pi
  def asin(x) when x < -1, do: -@half_pi
  def asin(x), do: :math.asin(x)

  @doc false
  # math.js: `x > 1 ? 0 : x < -1 ? pi : Math.acos(x)`.
  @spec acos(number()) :: float()
  def acos(x) when x > 1, do: 0.0
  def acos(x) when x < -1, do: :math.pi()
  def acos(x), do: :math.acos(x)

  @doc false
  # d3-geo-projection math.js: `x > 0 ? Math.sqrt(x) : 0`.
  @spec sqrt(number()) :: float()
  def sqrt(x) when x > 0, do: :math.sqrt(x)
  def sqrt(_x), do: 0.0
end
