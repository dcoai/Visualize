defmodule Visualize.Ease do
  @moduledoc """
  Easing functions for smooth animations and transitions.

  Easing functions take a normalized time `t` in [0, 1] and return
  a transformed value, typically also in [0, 1].

  ## Variants

  Most easing functions come in three variants:
  - `*_in` - Starts slow, accelerates (ease-in)
  - `*_out` - Starts fast, decelerates (ease-out)
  - `*_in_out` - Starts slow, speeds up, then slows down

  ## Examples

      # Apply quadratic easing to a time value
      Visualize.Ease.quad_in(0.5)  # => 0.25

      # Use with interpolation for animations
      t = 0.5
      eased_t = Visualize.Ease.cubic_in_out(t)
      current_value = start + (end - start) * eased_t

  ## CSS Integration

  For LiveView transitions, you can use CSS easing functions instead.
  These Elixir functions are useful for:
  - Server-side pre-computation of animation frames
  - Generating animated SVG paths
  - Data-driven animations with d3-style transitions

  """

  @tau 2 * :math.pi()

  # ============================================
  # Linear
  # ============================================

  @doc "Linear easing (no easing). Returns t unchanged."
  @spec linear(number()) :: float()
  def linear(t), do: t + 0.0

  # ============================================
  # Polynomial (Quadratic, Cubic, Poly)
  # ============================================

  @doc "Quadratic ease-in: t²"
  @spec quad_in(number()) :: float()
  def quad_in(t), do: t * t

  @doc "Quadratic ease-out: 1 - (1-t)²"
  @spec quad_out(number()) :: float()
  def quad_out(t), do: t * (2 - t)

  @doc "Quadratic ease-in-out"
  @spec quad_in_out(number()) :: float()
  def quad_in_out(t) when t < 0.5, do: 2 * t * t
  def quad_in_out(t), do: -1 + (4 - 2 * t) * t

  @doc "Cubic ease-in: t³"
  @spec cubic_in(number()) :: float()
  def cubic_in(t), do: t * t * t

  @doc "Cubic ease-out: 1 - (1-t)³"
  @spec cubic_out(number()) :: float()
  def cubic_out(t) do
    t1 = t - 1
    t1 * t1 * t1 + 1
  end

  @doc "Cubic ease-in-out"
  @spec cubic_in_out(number()) :: float()
  def cubic_in_out(t) when t < 0.5, do: 4 * t * t * t
  def cubic_in_out(t) do
    t1 = 2 * t - 2
    0.5 * t1 * t1 * t1 + 1
  end

  @doc """
  Polynomial ease-in with configurable exponent.

  ## Examples

      poly_in(0.5, 2)  # Same as quad_in(0.5)
      poly_in(0.5, 3)  # Same as cubic_in(0.5)
      poly_in(0.5, 4)  # Quartic ease-in

  """
  @spec poly_in(number(), number()) :: float()
  def poly_in(t, exponent \\ 3), do: :math.pow(t, exponent)

  @doc "Polynomial ease-out with configurable exponent"
  @spec poly_out(number(), number()) :: float()
  def poly_out(t, exponent \\ 3), do: 1 - :math.pow(1 - t, exponent)

  @doc "Polynomial ease-in-out with configurable exponent"
  @spec poly_in_out(number(), number()) :: float()
  def poly_in_out(t, exponent \\ 3)

  def poly_in_out(t, exponent) when t < 0.5 do
    :math.pow(2, exponent - 1) * :math.pow(t, exponent)
  end

  def poly_in_out(t, exponent) do
    1 - :math.pow(-2 * t + 2, exponent) / 2
  end

  # ============================================
  # Sinusoidal
  # ============================================

  @doc "Sinusoidal ease-in: 1 - cos(t * π/2)"
  @spec sin_in(number()) :: float()
  def sin_in(t), do: 1 - :math.cos(t * :math.pi() / 2)

  @doc "Sinusoidal ease-out: sin(t * π/2)"
  @spec sin_out(number()) :: float()
  def sin_out(t), do: :math.sin(t * :math.pi() / 2)

  @doc "Sinusoidal ease-in-out: -(cos(πt) - 1) / 2"
  @spec sin_in_out(number()) :: float()
  def sin_in_out(t), do: -(:math.cos(:math.pi() * t) - 1) / 2

  # ============================================
  # Exponential
  # ============================================

  @doc "Exponential ease-in: 2^(10(t-1))"
  @spec exp_in(number()) :: float()
  def exp_in(0), do: 0.0
  def exp_in(t), do: :math.pow(2, 10 * (t - 1))

  @doc "Exponential ease-out: 1 - 2^(-10t)"
  @spec exp_out(number()) :: float()
  def exp_out(1), do: 1.0
  def exp_out(t), do: 1 - :math.pow(2, -10 * t)

  @doc "Exponential ease-in-out"
  @spec exp_in_out(number()) :: float()
  def exp_in_out(0), do: 0.0
  def exp_in_out(1), do: 1.0
  def exp_in_out(t) when t < 0.5, do: :math.pow(2, 20 * t - 10) / 2
  def exp_in_out(t), do: (2 - :math.pow(2, -20 * t + 10)) / 2

  # ============================================
  # Circular
  # ============================================

  @doc "Circular ease-in: 1 - sqrt(1 - t²)"
  @spec circle_in(number()) :: float()
  def circle_in(t), do: 1 - :math.sqrt(1 - t * t)

  @doc "Circular ease-out: sqrt(1 - (t-1)²)"
  @spec circle_out(number()) :: float()
  def circle_out(t) do
    t1 = t - 1
    :math.sqrt(1 - t1 * t1)
  end

  @doc "Circular ease-in-out"
  @spec circle_in_out(number()) :: float()
  def circle_in_out(t) when t < 0.5 do
    (1 - :math.sqrt(1 - 4 * t * t)) / 2
  end

  def circle_in_out(t) do
    t1 = -2 * t + 2
    (:math.sqrt(1 - t1 * t1) + 1) / 2
  end

  # ============================================
  # Elastic
  # ============================================

  @c4 @tau / 3

  @doc """
  Elastic ease-in with spring-like oscillation.

  Overshoots then settles. Amplitude and period can be configured.
  """
  @spec elastic_in(number()) :: float()
  def elastic_in(0), do: 0.0
  def elastic_in(1), do: 1.0

  def elastic_in(t) do
    -:math.pow(2, 10 * t - 10) * :math.sin((t * 10 - 10.75) * @c4)
  end

  @doc "Elastic ease-out with spring-like oscillation"
  @spec elastic_out(number()) :: float()
  def elastic_out(0), do: 0.0
  def elastic_out(1), do: 1.0

  def elastic_out(t) do
    :math.pow(2, -10 * t) * :math.sin((t * 10 - 0.75) * @c4) + 1
  end

  @doc "Elastic ease-in-out with spring-like oscillation"
  @spec elastic_in_out(number()) :: float()
  def elastic_in_out(0), do: 0.0
  def elastic_in_out(1), do: 1.0

  def elastic_in_out(t) when t < 0.5 do
    c5 = @tau / 4.5
    -:math.pow(2, 20 * t - 10) * :math.sin((20 * t - 11.125) * c5) / 2
  end

  def elastic_in_out(t) do
    c5 = @tau / 4.5
    :math.pow(2, -20 * t + 10) * :math.sin((20 * t - 11.125) * c5) / 2 + 1
  end

  # ============================================
  # Back (overshooting)
  # ============================================

  @c1 1.70158
  @c2 @c1 * 1.525
  @c3 @c1 + 1

  @doc """
  Back ease-in: overshoots slightly before starting.

  The overshoot amount can be configured (default ~1.7).
  """
  @spec back_in(number()) :: float()
  def back_in(t) do
    @c3 * t * t * t - @c1 * t * t
  end

  @doc "Back ease-out: overshoots then settles at target"
  @spec back_out(number()) :: float()
  def back_out(t) do
    t1 = t - 1
    1 + @c3 * t1 * t1 * t1 + @c1 * t1 * t1
  end

  @doc "Back ease-in-out: overshoots at both ends"
  @spec back_in_out(number()) :: float()
  def back_in_out(t) when t < 0.5 do
    :math.pow(2 * t, 2) * ((@c2 + 1) * 2 * t - @c2) / 2
  end

  def back_in_out(t) do
    t1 = 2 * t - 2
    (:math.pow(t1, 2) * ((@c2 + 1) * t1 + @c2) + 2) / 2
  end

  @doc "Back ease-in with custom overshoot amount"
  @spec back_in(number(), number()) :: float()
  def back_in(t, overshoot) do
    s = overshoot
    (s + 1) * t * t * t - s * t * t
  end

  @doc "Back ease-out with custom overshoot amount"
  @spec back_out(number(), number()) :: float()
  def back_out(t, overshoot) do
    s = overshoot
    t1 = t - 1
    1 + (s + 1) * t1 * t1 * t1 + s * t1 * t1
  end

  # ============================================
  # Bounce
  # ============================================

  @n1 7.5625
  @d1 2.75

  @doc "Bounce ease-in: bounces at the start"
  @spec bounce_in(number()) :: float()
  def bounce_in(t), do: 1 - bounce_out(1 - t)

  @doc "Bounce ease-out: bounces at the end (like a ball)"
  @spec bounce_out(number()) :: float()
  def bounce_out(t) when t < 1 / @d1 do
    @n1 * t * t
  end

  def bounce_out(t) when t < 2 / @d1 do
    t1 = t - 1.5 / @d1
    @n1 * t1 * t1 + 0.75
  end

  def bounce_out(t) when t < 2.5 / @d1 do
    t1 = t - 2.25 / @d1
    @n1 * t1 * t1 + 0.9375
  end

  def bounce_out(t) do
    t1 = t - 2.625 / @d1
    @n1 * t1 * t1 + 0.984375
  end

  @doc "Bounce ease-in-out: bounces at both ends"
  @spec bounce_in_out(number()) :: float()
  def bounce_in_out(t) when t < 0.5 do
    (1 - bounce_out(1 - 2 * t)) / 2
  end

  def bounce_in_out(t) do
    (1 + bounce_out(2 * t - 1)) / 2
  end

  # ============================================
  # Utility functions
  # ============================================

  @doc """
  Returns an easing function by name.

  ## Examples

      easing = Visualize.Ease.by_name(:cubic_in_out)
      easing.(0.5)  # => 0.5

  """
  @spec by_name(atom()) :: (number() -> float())
  def by_name(:linear), do: &linear/1
  def by_name(:quad_in), do: &quad_in/1
  def by_name(:quad_out), do: &quad_out/1
  def by_name(:quad_in_out), do: &quad_in_out/1
  def by_name(:cubic_in), do: &cubic_in/1
  def by_name(:cubic_out), do: &cubic_out/1
  def by_name(:cubic_in_out), do: &cubic_in_out/1
  def by_name(:sin_in), do: &sin_in/1
  def by_name(:sin_out), do: &sin_out/1
  def by_name(:sin_in_out), do: &sin_in_out/1
  def by_name(:exp_in), do: &exp_in/1
  def by_name(:exp_out), do: &exp_out/1
  def by_name(:exp_in_out), do: &exp_in_out/1
  def by_name(:circle_in), do: &circle_in/1
  def by_name(:circle_out), do: &circle_out/1
  def by_name(:circle_in_out), do: &circle_in_out/1
  def by_name(:elastic_in), do: &elastic_in/1
  def by_name(:elastic_out), do: &elastic_out/1
  def by_name(:elastic_in_out), do: &elastic_in_out/1
  def by_name(:back_in), do: &back_in/1
  def by_name(:back_out), do: &back_out/1
  def by_name(:back_in_out), do: &back_in_out/1
  def by_name(:bounce_in), do: &bounce_in/1
  def by_name(:bounce_out), do: &bounce_out/1
  def by_name(:bounce_in_out), do: &bounce_in_out/1

  @doc """
  Returns all available easing function names.
  """
  @spec names() :: [atom()]
  def names do
    [
      :linear,
      :quad_in,
      :quad_out,
      :quad_in_out,
      :cubic_in,
      :cubic_out,
      :cubic_in_out,
      :sin_in,
      :sin_out,
      :sin_in_out,
      :exp_in,
      :exp_out,
      :exp_in_out,
      :circle_in,
      :circle_out,
      :circle_in_out,
      :elastic_in,
      :elastic_out,
      :elastic_in_out,
      :back_in,
      :back_out,
      :back_in_out,
      :bounce_in,
      :bounce_out,
      :bounce_in_out
    ]
  end

  @doc """
  Generates a list of eased values for animation frames.

  ## Examples

      # Generate 60 frames of cubic-eased animation
      frames = Visualize.Ease.frames(&Visualize.Ease.cubic_in_out/1, 60)

  """
  @spec frames((number() -> float()), pos_integer()) :: [float()]
  def frames(easing_fn, count) when count > 1 do
    for i <- 0..(count - 1) do
      t = i / (count - 1)
      easing_fn.(t)
    end
  end

  def frames(_easing_fn, 1), do: [1.0]
end
