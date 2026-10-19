defmodule Examples.BoardDemo.Latency do
  @moduledoc """
  A synthetic feed of request latency percentiles (spec/08 §11, spec/15 §10): every ten
  seconds the 5th, 25th, 50th, 75th and 95th percentile of the requests served, in
  milliseconds, the median rising past its target now and then.

  The schema says what a design needs to draw the overlays itself (#565, D-143): each
  percentile's `unit`, and the median's `target` and `polarity`, so a rule and a status
  color read them as facts rather than numbers written into the design.
  """
  @behaviour Visualize.Feed

  alias Examples.BoardDemo.Clock
  alias Visualize.Data.{Delivery, Schema}

  @every 10
  @most 400
  @target 250

  defstruct [:schema]

  def new do
    percentile = fn label ->
      %{type: :number, label: label, unit: "ms", quantity: :duration, continuity: 3 * @every}
    end

    median =
      percentile.("Median")
      |> Map.merge(%{target: @target, polarity: :lower_is_better, bounds: [0, nil]})

    %__MODULE__{
      schema:
        Schema.new!(%{
          t: %{type: :time, label: "Time"},
          p5: percentile.("5th percentile"),
          p25: percentile.("25th percentile"),
          p50: median,
          p75: percentile.("75th percentile"),
          p95: percentile.("95th percentile")
        })
    }
  end

  @doc "The percentiles at an instant: a slow swell of load, the tail widening with it."
  def reading(%DateTime{} = t) do
    s = DateTime.to_unix(t)
    load = 0.5 + 0.5 * :math.sin(2 * :math.pi() * s / 240) * :math.cos(2 * :math.pi() * s / 97)
    median = 150 + 160 * load
    spread = 30 + 90 * load

    %{
      t: t,
      p5: Float.round(median - 1.6 * spread, 1),
      p25: Float.round(median - 0.6 * spread, 1),
      p50: Float.round(median, 1),
      p75: Float.round(median + 0.8 * spread, 1),
      p95: Float.round(median + 2.4 * spread, 1)
    }
  end

  @impl true
  def describe(%__MODULE__{schema: schema}), do: {Schema.version(schema), schema, [:window]}

  @impl true
  def fetch(%__MODULE__{schema: schema}, window, _budget) do
    with {:ok, from, to} <- Clock.window(window) do
      {ticks, served, capped} = Clock.ticks(from, to, @every, @most)

      rows =
        for tick <- ticks,
            do: reading(DateTime.from_unix!(tick * @every))

      {:ok, Delivery.new(rows, window: served, capped: capped, schema: Schema.version(schema))}
    end
  end
end
