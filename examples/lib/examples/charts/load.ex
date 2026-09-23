defmodule Examples.Charts.Load do
  @moduledoc """
  The synthetic load average the gauge and the log-age chart share (#415).

  A machine's load over a ten-minute sine — `1.2 + 0.8 · sin(2π t / 600)` — under a hash
  of the second, so it wanders and yet looks random, and is a pure function of its
  absolute second: the same instant reads the same whenever it is drawn, which is what
  lets a chart redraw a window without keeping it.

  The three windows are **modelled, not averaged**: a mean over the last 60, 300 and 900
  samples would cost a thousand evaluations a point. The one-minute window is jumpy and
  prompt, the five-minute smoother and a minute behind, the fifteen-minute smoothest and
  three minutes behind — the shape of the real thing, said here to be synthetic.
  """

  @windows [
    {:one, "1 min", 0, 0.55, 1},
    {:five, "5 min", 60, 0.22, 5},
    {:fifteen, "15 min", 180, 0.09, 15}
  ]

  @typedoc "A load window: its key, the name it is drawn under, and how it is modelled."
  @type window :: :one | :five | :fifteen

  @doc "The windows in the order they are drawn, outermost needle first."
  @spec windows() :: [{window(), String.t()}]
  def windows, do: for({key, name, _lag, _noise, _step} <- @windows, do: {key, name})

  @doc "The name a window is drawn under."
  @spec name(window()) :: String.t()
  def name(window) do
    {_key, name, _lag, _noise, _step} = List.keyfind(@windows, window, 0)
    name
  end

  @doc """
  The load a window reads at absolute second `t`: the sine at the window's lag under a
  noise of the window's amplitude, held for the window's step so a longer average is the
  steadier line. Never below `0.05` — a machine at rest still has a load.

      iex> Examples.Charts.Load.at(:one, 0) == Examples.Charts.Load.at(:one, 0)
      true
  """
  @spec at(window(), number()) :: float()
  def at(window, t) do
    {_key, _name, lag, noise, step} = List.keyfind(@windows, window, 0)
    second = round(t)
    wave = 1.2 + 0.8 * :math.sin(2 * :math.pi() * (second - lag) / 600)
    jitter = noise * (:erlang.phash2({window, div(second, step)}, 1000) / 1000 - 0.5) * 2
    Float.round(max(0.05, wave + jitter), 3)
  end
end
