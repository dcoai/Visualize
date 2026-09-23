defmodule Examples.Charts.Load do
  @moduledoc """
  The synthetic load average the gauge and the log-age chart share (#415).

  A machine's load over a ten-minute sine — `1.2 + 0.8 · sin(2π t / 600)` — under a noise
  that wanders, so it looks random and is a pure function of its absolute second: the same
  instant reads the same whenever it is drawn, which is what lets a chart redraw a window
  without keeping it.

  The three windows are **modelled, not averaged**: a mean over the last 60, 300 and 900
  samples would cost a thousand evaluations a point. The one-minute window is jumpy and
  prompt, the five-minute smoother and a minute behind, the fifteen-minute smoothest and
  three minutes behind — the shape of the real thing, said here to be synthetic.

  **The noise is band-limited** (#418): it is a random knot every `knot` seconds —
  ten for the one-minute window, forty-five for the five, two minutes for the fifteen —
  smoothstepped between them, rather than an independent value each second. An
  independent second said a sixty-second mean could change by half a load in one second,
  which no average does; and a chart that samples the signal more coarsely than a second
  — every log-age chart does, at its old end — aliased that noise into a trace that boiled
  rather than drifting.
  """

  # Key, the name it is drawn under, its lag in seconds, its noise amplitude, and the
  # seconds between the noise's knots — the grain at which that window can change.
  @windows [
    {:one, "1 min", 0, 0.55, 10},
    {:five, "5 min", 60, 0.22, 45},
    {:fifteen, "15 min", 180, 0.09, 120}
  ]

  # How many samples a span is averaged over (`mean/3`): enough that one leaving the span
  # moves the mean by a fraction, few enough that a frame stays a fraction of a millisecond.
  @samples 8

  @typedoc "A load window: its key, the name it is drawn under, and how it is modelled."
  @type window :: :one | :five | :fifteen

  @doc "The windows in the order they are drawn, outermost needle first."
  @spec windows() :: [{window(), String.t()}]
  def windows, do: for({key, name, _lag, _noise, _knot} <- @windows, do: {key, name})

  @doc "The name a window is drawn under."
  @spec name(window()) :: String.t()
  def name(window) do
    {_key, name, _lag, _noise, _knot} = List.keyfind(@windows, window, 0)
    name
  end

  @doc """
  The load a window reads at absolute second `t`: the sine at the window's lag under a
  noise of the window's amplitude, drifting between knots at the window's own grain so a
  longer average is the steadier line. Never below `0.05` — a machine at rest still has a
  load.

      iex> Examples.Charts.Load.at(:one, 0) == Examples.Charts.Load.at(:one, 0)
      true
  """
  @spec at(window(), number()) :: float()
  def at(window, t), do: Float.round(raw(model(window), round(t)), 3)

  @doc """
  The mean load a window read over the seconds `from..to` — what a point standing for a
  span of history shows, rather than one second chosen from it (#418).

  The samples are on an **absolute-second stride**, so a clock that advances keeps all but
  at most one of them and the mean drifts where a point sample would jump. A span under a
  stride is one reading, which is what the newest end of a log-age axis is.
  """
  @spec mean(window(), number(), number()) :: float()
  def mean(window, from, to) do
    model = model(window)
    stride = max(1, round((to - from) / @samples))

    case seconds(from, to, stride) do
      [] ->
        Float.round(raw(model, round((from + to) / 2)), 3)

      seconds ->
        sum = Enum.reduce(seconds, 0.0, &(raw(model, &1) + &2))
        Float.round(sum / length(seconds), 3)
    end
  end

  # The model rows are read once per span, not once per sample: the same load through a
  # list lookup a thousand times a frame was a third of what a frame cost.
  defp model(window), do: List.keyfind(@windows, window, 0)

  # The load at a whole second, unrounded.
  defp raw({window, _name, lag, noise, knot}, second) do
    wave = 1.2 + 0.8 * :math.sin(2 * :math.pi() * (second - lag) / 600)
    max(0.05, wave + noise * drift(window, second, knot))
  end

  # The multiples of `stride` inside the span: the grid is absolute, never relative to the
  # span, which is the whole point of it.
  defp seconds(from, to, stride) do
    first = ceil(from / stride) * stride
    if first > to, do: [], else: Enum.to_list(first..trunc(to)//stride)
  end

  # The noise at a second: smoothstep between the knots either side of it.
  defp drift(window, second, knot) do
    k = floor(second / knot)
    u = second / knot - k
    a = knot_at(window, k)
    a + (knot_at(window, k + 1) - a) * (u * u * (3 - 2 * u))
  end

  defp knot_at(window, k), do: :erlang.phash2({window, k}, 1000) / 1000 * 2 - 1
end
