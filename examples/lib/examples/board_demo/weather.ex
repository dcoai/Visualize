defmodule Examples.BoardDemo.Weather do
  @moduledoc """
  A synthetic weather station (spec/08 §11, spec/15 §10): a reading every ten seconds of
  the temperature, the wind and the pressure, each a slow wave of the instant, so every
  window asked is answered at once.

  The station posts its readings with the symbols a person types — `°C`, `km/h`, `hPa` —
  and the connector reads each with `Visualize.Unit.parse_alias/1` into the UCUM code its
  schema declares (D-155, D-157): the schema is what tells a design, and the viewer's unit
  system, what the numbers are.
  """
  @behaviour Visualize.Feed

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

  defstruct [:schema]

  @doc "The station's feed: its symbols read into codes, every reading described."
  def new do
    fields =
      Map.new(@posted, fn {field, {label, symbol}} ->
        {:ok, unit} = Visualize.Unit.parse_alias(symbol)
        quantity = Visualize.Quantity.of_unit(unit)

        {field,
         %{type: :number, label: label, unit: unit, quantity: quantity, continuity: 3 * @every}}
      end)

    # The readings are ordered by `t`, and a board's window is over it (spec/08 §10.1).
    time = %{type: :time, label: "Time", window: true}
    %__MODULE__{schema: Schema.new!(Map.put(fields, :t, time))}
  end

  @doc "The station's readings at an instant, in the units it posts."
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

  @doc "The newest reading the station has posted by an instant."
  def latest(%DateTime{} = now) do
    tick = div(DateTime.to_unix(now), @every)
    tick = Enum.find(tick..(tick - @outage)//-1, &reporting?/1)
    reading(DateTime.from_unix!(tick * @every))
  end

  @doc "The field's schema description: its label and unit, as a view writes it."
  def field(%__MODULE__{schema: schema}, name), do: Map.fetch!(schema.fields, name)

  @impl true
  def describe(%__MODULE__{schema: schema}), do: {Schema.version(schema), schema, [:window]}

  @impl true
  def fetch(%__MODULE__{schema: schema}, window, _budget) do
    now = DateTime.utc_now()
    [from, to] = window || [DateTime.add(now, -300), now]
    to = if DateTime.compare(to, now) == :gt, do: now, else: to
    first = div(DateTime.to_unix(from) + @every - 1, @every)
    last = div(DateTime.to_unix(to), @every)

    rows =
      for tick <- max(first, last - @most + 1)..last//1,
          reporting?(tick),
          do: reading(DateTime.from_unix!(tick * @every))

    {:ok, Delivery.new(rows, schema: Schema.version(schema))}
  end
end
