defmodule ExamplesWeb.BoardLive.Station do
  @moduledoc """
  The `/board` page's own loop over the weather station (spec/08 §11.4, spec/15 §10): what
  a host writes when it shows a feed outside a board.

  It is a value the page keeps in its assigns: a `Visualize.Feed.Monitor` over the one
  feed, ticked by the page's timer, and the chart the page compiled over its deliveries
  (`Visualize.Chart.compile/2`), drawn each tick with `Visualize.Chart.Compiled.svg/2`. The
  station's firmware can change what it posts (`firmware/2`): the next delivery names a
  schema the chart was not compiled with, `Visualize.Chart.Compiled.stale?/2` says so, and
  the loop compiles again, carries the state across and records what changed and whether
  the two schemas are compatible (`Visualize.Data.Schema.compatibility/2`).
  """

  import Visualize.Chart.Build
  import Visualize.Chart, only: [fact: 3]

  alias Examples.BoardDemo.Weather
  alias Examples.Charts.Design
  alias Visualize.Chart
  alias Visualize.Chart.Compiled
  alias Visualize.Data.Schema
  alias Visualize.Data.Schema.Cache
  alias Visualize.Feed.Monitor

  @size {420, 120}

  defstruct [:monitor, :feed, :system, :compiled, :schema, :change, svg: nil]

  @type t :: %__MODULE__{}

  @doc "A loop over the station as its firmware posts it, drawn in the viewer's system."
  @spec new(atom(), keyword()) :: t()
  def new(system, opts \\ []) do
    feed = Weather.new(opts)
    %__MODULE__{monitor: Monitor.new(%{station: feed}, every: 2000), feed: feed, system: system}
  end

  @doc """
  One turn: the monitor ticked, and the chart compiled on the first delivery, or again
  when the delivery's schema is not the one it was compiled with.
  """
  @spec tick(t()) :: t()
  def tick(%__MODULE__{} = station) do
    station = %{station | monitor: Monitor.tick(station.monitor)}

    case Monitor.deliveries(station.monitor) do
      %{station: delivery} -> draw(station, %{station: delivery})
      _none -> station
    end
  end

  defp draw(%{compiled: nil} = station, sources), do: compiled(station, sources, nil)

  defp draw(station, sources) do
    if Compiled.stale?(station.compiled, sources),
      do: compiled(station, sources, station.schema),
      else: %{station | svg: Compiled.svg(station.compiled, sources)}
  end

  # The chart compiled over the delivery's schema, and — when it replaces one compiled
  # over another — the change: the two versions and whether the old rows read as the new.
  defp compiled(station, %{station: delivery} = sources, before) do
    {:ok, schema} = Cache.fetch(Monitor.cache(station.monitor), :station, delivery.schema)

    {:ok, %{"main" => fresh}} =
      Chart.compile(design(),
        sources: sources,
        schemas: Monitor.cache(station.monitor),
        size: @size,
        system: station.system
      )

    compiled = if station.compiled, do: Compiled.carry(station.compiled, fresh), else: fresh
    change = before && change(before, schema)

    %{
      station
      | compiled: compiled,
        schema: schema,
        change: change || station.change,
        svg: Compiled.svg(compiled, sources)
    }
  end

  defp change(%Schema{version: version}, %Schema{version: version}), do: nil

  defp change(before, now) do
    %{
      from: short(before.version),
      to: short(now.version),
      unit: {before.fields.temperature.unit, now.fields.temperature.unit},
      compatibility: Schema.compatibility(before, now)
    }
  end

  defp short(version), do: String.slice(version, 0, 8)

  @doc """
  The station with new firmware posting the temperature in `symbol`: the monitor's feed
  replaced, so its next fetch names the new schema.
  """
  @spec firmware(t(), String.t()) :: t()
  def firmware(%__MODULE__{} = station, symbol) do
    feed = Weather.new(temperature: symbol)
    %{station | feed: feed, monitor: Monitor.put(station.monitor, :station, feed)}
  end

  @doc "Whether the station's firmware posts the temperature in `symbol`."
  def posts?(%__MODULE__{feed: feed}, symbol),
    do: Visualize.Unit.parse_alias(symbol) == {:ok, feed.temperature}

  @doc "The feed's state as the monitor reports it: `:loading`, `:live`, `:stale` or down."
  def status(%__MODULE__{monitor: monitor}), do: Monitor.status(monitor).station

  @doc """
  The newest reading of each field with the measure its schema gives it, `[]` before the
  first delivery: what the page writes in the viewer's system.
  """
  @spec readings(t()) :: [%{label: String.t(), value: number(), measure: map()}]
  def readings(%__MODULE__{schema: nil}), do: []

  def readings(%__MODULE__{schema: schema, monitor: monitor}) do
    %{station: %{rows: rows}} = Monitor.deliveries(monitor)
    newest = List.last(rows)

    for field <- [:temperature, :wind, :pressure], newest do
      description = Map.fetch!(schema.fields, field)

      %{
        label: description.label,
        value: newest[field],
        measure: Map.take(description, [:unit, :quantity])
      }
    end
  end

  # The temperature as a host's small chart of it: the line, its axis's measure read from
  # the schema's facts, so a change of unit is a change of what the chart says.
  defp design do
    Design.fold([
      chart(meta: %{name: "Station temperature"}),
      source(:station, [:t, :temperature], types: %{t: :time, temperature: :number}),
      style(:temperature, stroke: %{color: :series_3, width: 2}),
      cartesian(margin: %{top: 8, right: 12, bottom: 22, left: 52}),
      time_scale(:x),
      linear_scale(:y, nice: true),
      axis(:x, :bottom, ticks: 4, format: "%H:%M"),
      axis(:y, :left,
        ticks: 3,
        grid: true,
        measure: %{
          unit: fact(:station, :temperature, :unit),
          quantity: fact(:station, :temperature, :quantity)
        }
      ),
      line(:station, %{x: :t, y: :temperature}, style: :temperature)
    ])
  end

  @doc "The chart's width and height."
  def size, do: @size
end
