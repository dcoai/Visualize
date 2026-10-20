defmodule Examples.Sources.Vehicles do
  @moduledoc """
  Six vehicles' positions over time, a reading every five seconds each (spec/08 §11, #781,
  work item #834): `vehicle` is the identity and `t` the window field, so a request may ask
  for a box — a range of `t`, a region of `x` and `y` — and for each vehicle's latest row
  (D-168). The feed supports only its time window; `Visualize.Feed.finish/3` does the rest.
  """
  @behaviour Visualize.Feed

  alias Examples.BoardDemo.Clock
  alias Visualize.Data.{Delivery, Schema}

  @names ~w(v1 v2 v3 v4 v5 v6)
  @every 5

  defstruct [:schema, :clock]

  @doc "The vehicles' names."
  def names, do: @names

  @doc "The feed, reading now from `clock` (`DateTime.utc_now/0` by default)."
  def new(clock \\ &DateTime.utc_now/0) do
    %__MODULE__{
      clock: clock,
      schema:
        Schema.new!(%{
          t: %{type: :time, label: "Time"},
          vehicle: %{type: :category, label: "Vehicle", identity: true},
          x: %{type: :number, bounds: [0, 100]},
          y: %{type: :number, bounds: [0, 100]}
        })
    }
  end

  @impl true
  def describe(%__MODULE__{schema: schema}), do: {Schema.version(schema), schema, [:window]}

  @impl true
  def fetch(%__MODULE__{schema: schema} = feed, window, _budget) do
    with {:ok, from, to} <- Clock.window(window, feed.clock.()) do
      {ticks, served, capped} = Clock.ticks(from, to, @every, 100)

      rows =
        for tick <- ticks, {name, i} <- Enum.with_index(@names) do
          s = tick * @every
          a = s / (40 + 9 * i) + i

          %{
            t: DateTime.from_unix!(s),
            vehicle: name,
            x: Float.round(50 + 42 * :math.cos(a), 2),
            y: Float.round(50 + 42 * :math.sin(a * 1.3), 2)
          }
        end

      {:ok, Delivery.new(rows, window: served, capped: capped, schema: Schema.version(schema))}
    end
  end
end
