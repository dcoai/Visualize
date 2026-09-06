defmodule Visualize.Scale.Radial do
  @moduledoc """
  An angle scale: a cyclic domain — bearing, hour of day, day of year — to radians
  (spec/03 §14, D-30).

  The mapping is `Visualize.Scale.Linear`'s with a range in radians, one full turn by
  default; angles follow `Visualize.Shape.Arc`'s convention, clockwise from 12 o'clock, so a
  bearing domain `[0, 360]` needs no offset. `ticks/2` returns `count` equal divisions of
  the domain — exact, not the nice-step sequence — and `nice/1` is identity: the domain of
  a cyclic quantity is its period.

      bearing = Visualize.Scale.radial() |> Visualize.Scale.domain([0, 360])
      Visualize.Scale.apply(bearing, 90)      # => π/2
      Visualize.Scale.ticks(bearing, 4)       # => [0.0, 90.0, 180.0, 270.0]

  """

  @behaviour Visualize.Scale.Behaviour

  alias Visualize.Scale.Linear

  @tau 2 * :math.pi()
  # A range this close to a full turn puts its last division on its first.
  @epsilon 1.0e-9

  defstruct domain: [0, 1],
            range: [0, @tau],
            clamp?: false

  @type t :: %__MODULE__{
          domain: [number()],
          range: [number()],
          clamp?: boolean()
        }

  @doc "Creates a radial scale: domain `[0, 1]`, range `[0, 2π]`"
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Sets the domain"
  @spec domain(t(), [number()]) :: t()
  @impl true
  def domain(%__MODULE__{} = scale, [d0, d1]), do: %{scale | domain: [d0, d1]}

  @doc "Sets the range, in radians"
  @spec range(t(), [number()]) :: t()
  @impl true
  def range(%__MODULE__{} = scale, [r0, r1]), do: %{scale | range: [r0, r1]}

  @doc "Enables or disables clamping"
  @spec clamp(t(), boolean()) :: t()
  @impl true
  def clamp(%__MODULE__{} = scale, clamp?), do: %{scale | clamp?: clamp?}

  @doc "Maps a domain value to radians"
  @spec apply(t(), number()) :: float()
  @impl true
  def apply(%__MODULE__{} = scale, value), do: Linear.apply(linear(scale), value)

  @doc "Maps radians back to the domain; never clamps"
  @spec invert(t(), number()) :: float()
  @impl true
  def invert(%__MODULE__{} = scale, value), do: Linear.invert(linear(scale), value)

  @doc """
  Returns `count` equal divisions of the domain from `d0`.

  The last division, `d1`, is dropped when the range is a full turn — it coincides with
  the first on the circle — and kept otherwise. `count <= 0` yields `[]`.
  """
  @spec ticks(t(), integer()) :: [float()]
  @impl true
  def ticks(%__MODULE__{}, count) when count <= 0, do: []

  def ticks(%__MODULE__{domain: [d0, d1], range: [r0, r1]}, count) do
    last = if abs(r1 - r0) >= @tau - @epsilon, do: count - 1, else: count
    step = (d1 - d0) / count
    Enum.map(0..last, fn i -> d0 + i * step end)
  end

  @doc "Identity: the domain of a cyclic quantity is its period"
  @spec nice(t()) :: t()
  @impl true
  def nice(%__MODULE__{} = scale), do: scale

  @doc "Identity: a radial scale has no padding"
  @spec padding(t(), number()) :: t()
  @impl true
  def padding(%__MODULE__{} = scale, _padding), do: scale

  @doc "Returns `0`: a radial scale has no bandwidth"
  @spec bandwidth(t()) :: 0
  @impl true
  def bandwidth(%__MODULE__{}), do: 0

  defp linear(%__MODULE__{domain: domain, range: range, clamp?: clamp?}) do
    %Linear{domain: domain, range: range, clamp?: clamp?}
  end
end
