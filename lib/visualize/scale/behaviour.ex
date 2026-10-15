defmodule Visualize.Scale.Behaviour do
  @moduledoc """
  The protocol every scale module implements (spec/03 §1.3).

  `Visualize.Scale` dispatches each of these operations to the module named by the scale
  struct (`scale.__struct__`). A module that declares this behaviour and omits a callback
  fails to compile under `--warnings-as-errors`, which is what keeps the facade total: no
  scale reaches `Visualize.Scale.apply/2` without an `apply/2` of its own.

  Operations that do not apply to a scale kind are still defined and behave as identity
  (`nice/1`, `padding/2`, `clamp/2`), return `nil` (`invert/2`), or return `0`
  (`bandwidth/1`). The discretizing scales (`Quantile`, `Quantize`, `Threshold`) return their
  thresholds from `ticks/2`.
  """

  @typedoc "Any scale struct."
  @type scale :: struct()

  @doc "Sets the input domain; the argument shape is the module's own."
  @callback domain(scale, term()) :: scale

  @doc "Sets the output range; the argument shape is the module's own."
  @callback range(scale, term()) :: scale

  @doc "Maps a domain value to a range value."
  @callback apply(scale, term()) :: term()

  @doc "Maps a range value back to the domain; `nil` where the scale is not invertible."
  @callback invert(scale, term()) :: term() | nil

  @doc "Representative domain values; `count` is a hint, never a guarantee."
  @callback ticks(scale, integer()) :: [term()]

  @doc "Extends the domain outward to round values; identity where that has no meaning."
  @callback nice(scale) :: scale

  @doc "Sets band padding; identity for every scale but `Band`."
  @callback padding(scale, number()) :: scale

  @doc "The band width; `0` for every scale but `Band`."
  @callback bandwidth(scale) :: number()

  @doc "Enables or disables clamping; identity where the scale never extrapolates."
  @callback clamp(scale, boolean()) :: scale
  @doc """
  The position of `value` between `a` and `b` as a fraction, `0.5` when `a == b`.

  d3-scale's `normalize`: a collapsed domain maps every value to the middle of the range and
  a collapsed range inverts to the middle of the domain, instead of dividing by zero (D-49).
  Every continuous scale's `apply/2` and `invert/2` go through it.
  """
  @spec normalize(number(), number(), number()) :: float()
  def normalize(_value, a, b) when a == b, do: 0.5
  def normalize(value, a, b), do: (value - a) / (b - a)
end
