defmodule Visualize.Geo.Cartesian do
  @moduledoc false
  # d3-geo's src/cartesian.js (v3.1.1): a point of the unit sphere as an `{x, y, z}`
  # vector, for the spherical tests of the clip (spec/07 §2.2). Angles are radians here,
  # as in d3.

  @doc false
  # cartesian.js:7–10
  @spec cartesian({number(), number()}) :: {float(), float(), float()}
  def cartesian({lambda, phi}) do
    cos_phi = :math.cos(phi)
    {cos_phi * :math.cos(lambda), cos_phi * :math.sin(lambda), :math.sin(phi)}
  end

  @doc false
  # cartesian.js:12–14
  def dot({a0, a1, a2}, {b0, b1, b2}), do: a0 * b0 + a1 * b1 + a2 * b2

  @doc false
  # cartesian.js:16–18
  def cross({a0, a1, a2}, {b0, b1, b2}),
    do: {a1 * b2 - a2 * b1, a2 * b0 - a0 * b2, a0 * b1 - a1 * b0}

  @doc false
  # cartesian.js:30–33, returning the unit vector — or `nil` for the zero vector, where
  # d3 divides by zero and carries NaN, so every comparison made with the result is false.
  def normalize({d0, d1, d2}) do
    case :math.sqrt(d0 * d0 + d1 * d1 + d2 * d2) do
      l when l == 0 -> nil
      l -> {d0 / l, d1 / l, d2 / l}
    end
  end
end
