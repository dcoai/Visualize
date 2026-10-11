defmodule Visualize.Signals do
  @moduledoc """
  Generated sources (spec/08 §8): a chart under design has feeds that move without a host
  supplying any.

  A signal is a description — a kind, its fields, a window, a period, a range — from
  which `rows/2` yields the rows of a window ending at a tick, pure and deterministic, so
  the same tick always draws the same rows and a chart replays. The first field is time
  and carries the tick; every other field is a value column following the kind's wave,
  each shifted from the last so two columns are never the same line. A deployed design
  still binds to the host's pool under the same names; signals stand in for it while the
  chart is designed.

      iex> sine = Visualize.Signals.new(:sine, [:t, :value], window: 3, period: 4)
      iex> Visualize.Signals.rows(sine, 2) |> Enum.map(&{&1.t, round(&1.value)})
      [{0, 50}, {1, 100}, {2, 50}]
      iex> Visualize.Signals.rows(sine, 0) |> Enum.map(& &1.t)
      [0]

      iex> counter = Visualize.Signals.new(:discrete, [:t, :n], window: 2, min: 0, max: 2)
      iex> Visualize.Signals.rows(counter, 3)
      [%{t: 2, n: 2}, %{t: 3, n: 0}]
  """

  @kinds [:sine, :square, :random, :discrete]

  @typedoc "A signal (spec/08 §8.1)."
  @type t :: %{
          kind: :sine | :square | :random | :discrete,
          fields: [atom(), ...],
          window: pos_integer(),
          period: number(),
          min: number(),
          max: number(),
          seed: integer()
        }

  @defaults %{window: 24, period: 12, min: 0, max: 100, seed: 0}

  @doc "The four kinds, in the order of spec/08 §8.1."
  @spec kinds() :: [atom(), ...]
  def kinds, do: @kinds

  @doc "As `new/3` with no options."
  @spec new(atom(), [atom(), ...]) :: t()
  def new(kind, fields), do: new(kind, fields, [])

  @doc """
  A signal of the kind over the fields — the first field time, the rest values — with
  the defaults of spec/08 §8.1 under the given options (`window`, `period`, `min`, `max`,
  `seed`).

      iex> Visualize.Signals.new(:square, [:hour, :on], period: 2)
      %{kind: :square, fields: [:hour, :on], window: 24, period: 2, min: 0, max: 100, seed: 0}
  """
  @spec new(atom(), [atom(), ...], keyword() | map()) :: t()
  def new(kind, [_time | _] = fields, opts) when kind in @kinds do
    @defaults
    |> Map.merge(opts |> Map.new() |> Map.take(Map.keys(@defaults)))
    |> Map.merge(%{kind: kind, fields: fields})
  end

  @doc """
  The window of rows ending at the tick (spec/08 §8.2): one row per tick from
  `tick − window + 1` to `tick`, a tick below zero yielding none, the time column the
  tick and each value column its kind's value there.
  """
  @spec rows(t(), non_neg_integer()) :: [map()]
  def rows(signal, tick) when is_integer(tick) and tick >= 0 do
    signal = Map.merge(@defaults, signal)
    rows(signal, tick - signal.window + 1, tick)
  end

  @doc """
  One row per tick from `max(from, 0)` to `to`, whatever the signal's `window` — none when
  `to` is below that (spec/08 §8.2). How `Visualize.Feed.Signals` serves a window of
  ticks.

      iex> counter = Visualize.Signals.new(:discrete, [:t, :n], window: 2)
      iex> Visualize.Signals.rows(counter, -1, 2) |> Enum.map(& &1.t)
      [0, 1, 2]
  """
  @spec rows(t(), integer(), integer()) :: [map()]
  def rows(%{kind: kind, fields: [time | values]} = signal, from, to)
      when is_integer(from) and is_integer(to) do
    signal = Map.merge(@defaults, signal)
    count = length(values)

    for t <- max(from, 0)..to//1 do
      values
      |> Enum.with_index()
      |> Enum.reduce(%{time => t}, fn {field, n}, row ->
        Map.put(row, field, value(kind, signal, t, n, count))
      end)
    end
  end

  @doc """
  A pool — name to rows — from a map of named signals at a tick, ready for
  `Visualize.Chart.apply/2`.

      iex> pool = Visualize.Signals.pool(%{a: Visualize.Signals.new(:discrete, [:t, :n], window: 1)}, 5)
      iex> pool
      %{a: [%{t: 5, n: 5}]}
  """
  @spec pool(%{atom() => t()}, non_neg_integer()) :: %{atom() => [map()]}
  def pool(signals, tick) when is_map(signals),
    do: Map.new(signals, fn {name, s} -> {name, rows(s, tick)} end)

  # -- the kinds (spec/08 §8.2) -----------------------------------------------------------

  defp value(:sine, %{min: min, max: max, period: period}, t, n, count) do
    phase = n / count
    min + (max - min) * (1 + :math.sin(2 * :math.pi() * (t / period + phase))) / 2
  end

  defp value(:square, %{min: min, max: max, period: period}, t, n, count) do
    within = :math.fmod(t / period + n / count, 1.0)
    if within < 0.5, do: max, else: min
  end

  defp value(:random, %{min: min, max: max, seed: seed}, t, n, _count) do
    # One stream per column and tick, so a tick always draws the same value.
    state = :rand.seed_s(:exsss, {seed, n, t})
    {u, _} = :rand.uniform_real_s(state)
    min + (max - min) * u
  end

  defp value(:discrete, %{min: min, max: max}, t, n, _count) do
    span = trunc(max) - trunc(min) + 1
    trunc(min) + rem(t + n, max(span, 1))
  end
end
