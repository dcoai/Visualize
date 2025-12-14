defmodule Visualize.Random do
  @moduledoc """
  Random number generators for various probability distributions.

  Useful for generating synthetic data, jittering points,
  and Monte Carlo simulations.

  ## Examples

      # Uniform random in range [0, 100]
      Visualize.Random.uniform(0, 100)

      # Normal distribution with mean=50, stddev=10
      Visualize.Random.normal(50, 10)

      # Generate multiple samples
      Visualize.Random.samples(&Visualize.Random.normal(0, 1), 100)

  """

  @doc """
  Returns a random number uniformly distributed in [min, max).
  """
  @spec uniform(number(), number()) :: float()
  def uniform(min \\ 0, max \\ 1) do
    min + :rand.uniform() * (max - min)
  end

  @doc """
  Returns a random integer uniformly distributed in [min, max].
  """
  @spec uniform_int(integer(), integer()) :: integer()
  def uniform_int(min, max) do
    min + :rand.uniform(max - min + 1) - 1
  end

  @doc """
  Returns a random number from a normal (Gaussian) distribution.

  Uses the Box-Muller transform.
  """
  @spec normal(number(), number()) :: float()
  def normal(mean \\ 0, stddev \\ 1) do
    # Box-Muller transform
    u1 = :rand.uniform()
    u2 = :rand.uniform()

    z = :math.sqrt(-2 * :math.log(u1)) * :math.cos(2 * :math.pi() * u2)
    mean + z * stddev
  end

  @doc """
  Returns a random number from a log-normal distribution.

  If X is normal(mu, sigma), then exp(X) is log-normal.
  """
  @spec log_normal(number(), number()) :: float()
  def log_normal(mu \\ 0, sigma \\ 1) do
    :math.exp(normal(mu, sigma))
  end

  @doc """
  Returns a random number from an exponential distribution.

  Models time between events in a Poisson process.
  """
  @spec exponential(number()) :: float()
  def exponential(lambda \\ 1) do
    -:math.log(1 - :rand.uniform()) / lambda
  end

  @doc """
  Returns a random integer from a Poisson distribution.

  Models the number of events in a fixed interval.
  """
  @spec poisson(number()) :: non_neg_integer()
  def poisson(lambda) do
    l = :math.exp(-lambda)
    poisson_loop(l, 1.0, 0)
  end

  defp poisson_loop(l, p, k) when p > l do
    poisson_loop(l, p * :rand.uniform(), k + 1)
  end

  defp poisson_loop(_l, _p, k), do: k

  @doc """
  Returns a random number from a Bernoulli distribution.

  Returns 1 with probability p, 0 otherwise.
  """
  @spec bernoulli(number()) :: 0 | 1
  def bernoulli(p \\ 0.5) do
    if :rand.uniform() < p, do: 1, else: 0
  end

  @doc """
  Returns a random integer from a binomial distribution.

  Number of successes in n Bernoulli trials with probability p.
  """
  @spec binomial(non_neg_integer(), number()) :: non_neg_integer()
  def binomial(n, p) do
    Enum.reduce(1..n, 0, fn _, acc -> acc + bernoulli(p) end)
  end

  @doc """
  Returns a random integer from a geometric distribution.

  Number of failures before the first success.
  """
  @spec geometric(number()) :: non_neg_integer()
  def geometric(p) do
    trunc(:math.log(1 - :rand.uniform()) / :math.log(1 - p))
  end

  @doc """
  Returns a random number from a Pareto distribution.

  Models power law phenomena (wealth distribution, etc.)
  """
  @spec pareto(number()) :: float()
  def pareto(alpha \\ 1) do
    1 / :math.pow(1 - :rand.uniform(), 1 / alpha)
  end

  @doc """
  Returns a random number from a Cauchy distribution.

  A heavy-tailed distribution (undefined mean/variance).
  """
  @spec cauchy(number(), number()) :: float()
  def cauchy(location \\ 0, scale \\ 1) do
    location + scale * :math.tan(:math.pi() * (:rand.uniform() - 0.5))
  end

  @doc """
  Returns a random number from a beta distribution.

  Useful for modeling proportions and probabilities.
  """
  @spec beta(number(), number()) :: float()
  def beta(alpha, beta) do
    x = gamma(alpha)
    y = gamma(beta)
    x / (x + y)
  end

  @doc """
  Returns a random number from a gamma distribution.

  Uses the Marsaglia and Tsang method.
  """
  @spec gamma(number(), number()) :: float()
  def gamma(shape, scale \\ 1) when shape > 0 do
    if shape < 1 do
      # For shape < 1, use the relation with shape + 1
      gamma(shape + 1, scale) * :math.pow(:rand.uniform(), 1 / shape)
    else
      # Marsaglia and Tsang's method
      d = shape - 1 / 3
      c = 1 / :math.sqrt(9 * d)
      gamma_loop(d, c) * scale
    end
  end

  defp gamma_loop(d, c) do
    x = normal()
    v = 1 + c * x

    if v > 0 do
      v = v * v * v
      u = :rand.uniform()

      if u < 1 - 0.0331 * x * x * x * x or
         :math.log(u) < 0.5 * x * x + d * (1 - v + :math.log(v)) do
        d * v
      else
        gamma_loop(d, c)
      end
    else
      gamma_loop(d, c)
    end
  end

  @doc """
  Returns a random number from a Weibull distribution.

  Used in reliability engineering and survival analysis.
  """
  @spec weibull(number(), number()) :: float()
  def weibull(shape, scale \\ 1) do
    scale * :math.pow(-:math.log(1 - :rand.uniform()), 1 / shape)
  end

  @doc """
  Returns a random point uniformly distributed in a circle.
  """
  @spec in_circle(number(), number(), number()) :: {float(), float()}
  def in_circle(cx \\ 0, cy \\ 0, radius \\ 1) do
    # Use rejection sampling or sqrt for uniform distribution
    r = radius * :math.sqrt(:rand.uniform())
    theta = 2 * :math.pi() * :rand.uniform()
    {cx + r * :math.cos(theta), cy + r * :math.sin(theta)}
  end

  @doc """
  Returns a random point uniformly distributed on a circle's edge.
  """
  @spec on_circle(number(), number(), number()) :: {float(), float()}
  def on_circle(cx \\ 0, cy \\ 0, radius \\ 1) do
    theta = 2 * :math.pi() * :rand.uniform()
    {cx + radius * :math.cos(theta), cy + radius * :math.sin(theta)}
  end

  @doc """
  Returns a random point uniformly distributed in a rectangle.
  """
  @spec in_rect(number(), number(), number(), number()) :: {float(), float()}
  def in_rect(x0, y0, x1, y1) do
    {uniform(x0, x1), uniform(y0, y1)}
  end

  @doc """
  Generates n samples using the given random function.

  ## Example

      samples = Visualize.Random.samples(fn -> Visualize.Random.normal(0, 1) end, 100)

  """
  @spec samples((-> number()), non_neg_integer()) :: [number()]
  def samples(random_fn, n) do
    Enum.map(1..n, fn _ -> random_fn.() end)
  end

  @doc """
  Shuffles a list randomly (Fisher-Yates shuffle).
  """
  @spec shuffle([any()]) :: [any()]
  def shuffle(list) do
    Enum.shuffle(list)
  end

  @doc """
  Picks n random elements from a list.
  """
  @spec sample([any()], non_neg_integer()) :: [any()]
  def sample(list, n) do
    list |> Enum.shuffle() |> Enum.take(n)
  end

  @doc """
  Picks a single random element from a list.
  """
  @spec pick([any()]) :: any()
  def pick([]), do: nil
  def pick(list), do: Enum.random(list)

  @doc """
  Seeds the random number generator for reproducibility.
  """
  @spec seed(integer()) :: :rand.state()
  def seed(s) do
    :rand.seed(:exsss, {s, s * 2, s * 3})
  end
end
