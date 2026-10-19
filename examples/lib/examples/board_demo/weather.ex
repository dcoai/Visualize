defmodule Examples.BoardDemo.Weather do
  @moduledoc """
  A synthetic weather station (spec/08 §11, spec/15 §10): a reading every ten seconds of
  the temperature, the wind and the pressure, each a slow wave of the instant, so every
  window asked is answered at once.

  The station posts its readings with the symbols a person types — `°C`, `km/h`, `hPa` —
  and the connector reads each with `Visualize.Unit.parse_alias/1` into the UCUM code its
  schema declares (D-155, D-157): the schema is what tells a design, and the viewer's unit
  system, what the numbers are.

  Its firmware decides the temperature's symbol: `new(temperature: "°F")` is the same
  station posting Fahrenheit, a schema of another version, which a page holding its own
  loop sees as a stale chart (spec/14 §12.1) and a compatible schema (D-159).
  """
  @behaviour Visualize.Feed

  alias Examples.BoardDemo.Clock
  alias Visualize.Data.{Delivery, Schema}

  @every 10
  @most 400
  # Every this many readings the station misses `@outage` in a row.
  @outage_every 24
  @outage 4

  # What the station says of its readings, as it says it. The connector adds the quantity
  # each unit implies, as `Visualize.Feed.Telemetry` does, so a design can read both.
  @posted %{
    temperature: {"Temperature", "°C"},
    wind: {"Wind", "km/h"},
    pressure: {"Pressure", "hPa"}
  }

  defstruct [:schema, temperature: "Cel", clock: &DateTime.utc_now/0]

  @doc """
  The station's feed: its symbols read into codes, every reading described. Option:
  `temperature:`, the symbol its firmware posts the temperature in (`"°C"`).
  """
  def new(opts \\ []) do
    posted =
      Map.update!(@posted, :temperature, fn {label, symbol} ->
        {label, Keyword.get(opts, :temperature, symbol)}
      end)

    fields =
      Map.new(posted, fn {field, {label, symbol}} ->
        {:ok, unit} = Visualize.Unit.parse_alias(symbol)
        quantity = Visualize.Quantity.of_unit(unit)

        {field,
         %{type: :number, label: label, unit: unit, quantity: quantity, continuity: 3 * @every}}
      end)

    # The readings are ordered by `t`, and a board's window is over it (spec/08 §10.1).
    time = %{type: :time, label: "Time", window: true}
    schema = Schema.new!(Map.put(fields, :t, time))

    %__MODULE__{
      schema: schema,
      temperature: schema.fields.temperature.unit,
      clock: Clock.clock(opts)
    }
  end

  @doc "The station's readings at an instant, in the units a feed of it posts them in."
  def reading(%__MODULE__{temperature: unit}, %DateTime{} = t),
    do:
      Map.update!(
        reading(t),
        :temperature,
        &Float.round(Visualize.Unit.convert(&1, "Cel", unit), 1)
      )

  @doc "The station's readings at an instant, as it measures them: °C, km/h and hPa."
  def reading(%DateTime{} = t) do
    s = DateTime.to_unix(t)
    wave = fn period, phase -> :math.sin(2 * :math.pi() * s / period + phase) end

    %{
      t: t,
      temperature: Float.round(14 + 7 * wave.(600, 0) + 1.5 * wave.(97, 1), 1),
      wind: Float.round(max(0.0, 18 + 12 * wave.(420, 2) + 4 * wave.(53, 0)), 1),
      pressure: Float.round(1013 + 6 * wave.(900, 3), 1)
    }
  end

  @doc """
  Whether the station reported at a tick: it drops off for forty seconds every four minutes,
  longer than its fields' `continuity`, so a line breaks there rather than bridging what the
  station never said (spec/08 §10.1).
  """
  def reporting?(tick), do: rem(tick, @outage_every) >= @outage

  @doc "The newest reading the station has posted by an instant, as a feed of it posts it."
  def latest(%__MODULE__{} = feed, %DateTime{} = now) do
    tick = div(DateTime.to_unix(now), @every)
    tick = Enum.find(tick..(tick - @outage)//-1, &reporting?/1)
    reading(feed, DateTime.from_unix!(tick * @every))
  end

  @doc "The field's schema description: its label and unit, as a view writes it."
  def field(%__MODULE__{schema: schema}, name), do: Map.fetch!(schema.fields, name)

  @impl true
  def describe(%__MODULE__{schema: schema}), do: {Schema.version(schema), schema, [:window]}

  @impl true
  def fetch(%__MODULE__{schema: schema} = feed, window, _budget) do
    with {:ok, from, to} <- Clock.window(window, feed.clock.()) do
      {ticks, served, capped} = Clock.ticks(from, to, @every, @most)

      rows =
        for tick <- ticks,
            reporting?(tick),
            do: reading(feed, DateTime.from_unix!(tick * @every))

      {:ok, Delivery.new(rows, window: served, capped: capped, schema: Schema.version(schema))}
    end
  end
end
