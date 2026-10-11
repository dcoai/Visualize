defmodule Examples.BoardDemo do
  @moduledoc """
  The demo board of `/board` (spec/15 §8–§9, #576, D-146): five cells over live feeds,
  run by the library's board runtime under `Examples.Boards`, the
  `Visualize.Board.Supervisor` in the examples' tree.

  - **load** is the gallery's *Load* design (`Examples.Charts.LoadChart`), its history
    fed by a `Visualize.Signals` sine on the wall clock (`Examples.BoardDemo.Wave`) and its
    dial's track by a fixed feed.
  - **wave** is the gallery's *Line Chart*, its `x` a time scale, over a second signal.
  - **memory** and **queue** are one board design over two in-process `:telemetry`
    metrics (`Visualize.Feed.Telemetry`), which `Examples.BoardDemo.Probe` emits: one
    component in two cells, each bound to its own feed.
  - **offline** is the *Line Chart* bound to a feed that cannot be reached, so its designed
    "feed down" state is always on the page.

  The board shares one window, the last five minutes by default, in UTC and shown in the
  board's zone; one sync group joins the time charts' hover and brush. The board is
  started once, on the first visit, and every visitor sees the same board: its window is
  the board's shared state (spec/15 §8.2).
  """

  use Supervisor

  import Visualize.Chart.Build

  alias Examples.BoardDemo.{Fixed, Unreachable, Wave}
  alias Examples.Charts.{Design, LineChart, LoadChart}
  alias Visualize.Board
  alias Visualize.Board.{Binding, Server}

  @board Examples.BoardDemo.Board
  @collector Examples.BoardDemo.Telemetry

  @doc "The demo's feeds' processes: the telemetry collector and the probe that feeds it."
  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    children = [
      {Visualize.Feed.Telemetry, name: @collector, metrics: metrics(), every: 1000},
      Examples.BoardDemo.Probe
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  @doc "The two metrics the probe emits, as `Telemetry.Metrics` definitions."
  def metrics do
    [
      Telemetry.Metrics.last_value("examples.vm.memory",
        unit: :megabyte,
        description: "Memory in use"
      ),
      Telemetry.Metrics.last_value("examples.vm.run_queue", description: "Run queue")
    ]
  end

  @doc """
  The demo board, started under `Examples.Boards` on the first call and the same process
  on every later one: `{:ok, pid}`, or the reason it could not start.
  """
  @spec board() :: {:ok, pid()} | {:error, term()}
  def board do
    case Process.whereis(@board) do
      nil -> start()
      pid -> {:ok, pid}
    end
  end

  defp start do
    opts = [
      name: @board,
      board: value(),
      store: store(),
      binding: slots(),
      feeds: feeds(),
      tick: 1000
    ]

    case Server.start(Examples.Boards, opts) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, _reason} = error -> error
    end
  end

  @doc "The board as a value (spec/15 §1)."
  @spec value() :: Board.t()
  def value do
    Board.from_map!(%{
      meta: %{name: "Live board", description: "Signals and in-process telemetry"},
      window: %{last: 300},
      sync: "board",
      stale_after: 30,
      cells: %{
        load: %{x: 0, y: 0, w: 8, h: 4, ref: {:composite, 1}, title: "Load", sync: false},
        memory: %{x: 8, y: 0, w: 4, h: 2, ref: {:composite, 3}, title: "Memory (MB)"},
        queue: %{x: 8, y: 2, w: 4, h: 2, ref: {:composite, 3}, title: "Run queue"},
        wave: %{x: 0, y: 4, w: 8, h: 3, ref: {:composite, 2}, title: "Wave"},
        offline: %{x: 8, y: 4, w: 4, h: 3, ref: {:composite, 2}, title: "Offline"}
      }
    })
  end

  @doc "The board's components by id: two gallery designs and one board design."
  def store do
    {load, _rows} = LoadChart.design([])
    {line, _rows} = LineChart.design([])

    %{
      {:composite, 1} => load,
      {:composite, 2} => put_in(line, [:frames, :main, :scales, :x], %{kind: :time}),
      {:composite, 3} => metric()
    }
  end

  # One metric over time: the shape every telemetry feed has (`t`, `value`).
  defp metric do
    Design.fold([
      chart(meta: %{name: "Metric"}),
      source(:metric, [:t, :value], types: %{t: :time, value: :number}),
      style(:trace, stroke: :series_2, stroke_width: 2),
      cartesian(margin: %{top: 10, right: 16, bottom: 26, left: 48}),
      time_scale(:x),
      linear_scale(:y, domain: [0, :auto], nice: true),
      axis(:x, :bottom, ticks: 4, format: "%H:%M"),
      axis(:y, :left, ticks: 3, grid: true),
      line(:metric, %{x: :t, y: :value}, style: :trace)
    ])
  end

  @doc "The connector's part (spec/15 §4.2): each cell's slots bound to a feed by name."
  def slots do
    Binding.new(%{
      {:load, :load} => :load,
      {:load, :dial} => :dial,
      {:wave, :points} => :wave,
      {:memory, :metric} => "examples.vm.memory",
      {:queue, :metric} => "examples.vm.run_queue",
      {:offline, :points} => :offline
    })
  end

  @doc "The feeds by the names the binding uses."
  def feeds do
    telemetry = Visualize.Feed.Telemetry.feeds(@collector)

    Map.merge(telemetry, %{
      load: Wave.new(Visualize.Signals.new(:sine, [:t, :v], period: 90, min: 0.4, max: 3.2)),
      wave: Wave.new(Visualize.Signals.new(:sine, [:x, :y], period: 40, min: 10, max: 90)),
      dial: Fixed.new([%{at: 0}], %{at: %{type: :number}}),
      offline: Unreachable.new(%{x: %{type: :time}, y: %{type: :number}})
    })
  end
end

defmodule Examples.BoardDemo.Probe do
  @moduledoc """
  Emits the demo's `:telemetry` event, `[:examples, :vm]`, every half second: the memory
  in use in megabytes and the run queue's length, which the collector turns into two
  feeds (spec/08 §11.6).
  """
  use GenServer

  @every 500

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    send(self(), :probe)
    {:ok, nil}
  end

  @impl true
  def handle_info(:probe, state) do
    :telemetry.execute(
      [:examples, :vm],
      %{
        memory: Float.round(:erlang.memory(:total) / 1_048_576, 2),
        run_queue: :erlang.statistics(:total_run_queue_lengths_all)
      },
      %{}
    )

    Process.send_after(self(), :probe, @every)
    {:noreply, state}
  end
end

defmodule Examples.BoardDemo.Wave do
  @moduledoc """
  A `Visualize.Signals` signal on the wall clock (spec/08 §8, §11.6): the library's
  `Visualize.Feed.Signals` provider ticking once a second from an origin fifteen minutes
  before the feed was made, its tick read as that instant in UTC. A board's window is in
  UTC (spec/15 §1.5), and a signal counts ticks, so this is the one conversion between
  them: a window of instants asked as ticks, and the rows' ticks answered as instants.
  """
  @behaviour Visualize.Feed

  alias Visualize.Data.{Delivery, Schema}

  @enforce_keys [:inner, :origin, :every, :schema]
  defstruct [:inner, :origin, :every, :schema]

  @doc "A signal ticking every `every:` milliseconds (`1000`), with fifteen minutes behind it."
  def new(%{fields: [time | values]} = signal, opts \\ []) do
    every = Keyword.get(opts, :every, 1000)
    origin = System.os_time(:millisecond) - 15 * 60 * 1000
    clock = fn -> System.os_time(:millisecond) end
    inner = Visualize.Feed.Signals.new(signal, every: every, clock: clock, origin: origin)

    # A reading is one tick apart; three missed in a row is a gap (spec/08 §10.1).
    fields =
      values
      |> Map.new(&{&1, %{type: :number, continuity: every * 3 / 1000}})
      |> Map.put(time, %{type: :time, label: "Time"})

    %__MODULE__{inner: inner, origin: origin, every: every, schema: Schema.new!(fields)}
  end

  @impl true
  def describe(%__MODULE__{schema: schema}), do: {Schema.version(schema), schema, [:window]}

  @impl true
  def fetch(%__MODULE__{} = feed, window, budget) do
    with {:ok, %Delivery{} = delivery} <-
           Visualize.Feed.fetch(feed.inner, ticks(feed, window), budget) do
      [time | _values] = feed.inner.signal.fields
      rows = Enum.map(delivery.rows, &Map.update!(&1, time, fn tick -> instant(feed, tick) end))
      window = delivery.window && Enum.map(delivery.window, &(&1 && instant(feed, &1)))

      {:ok, %{delivery | rows: rows, window: window, schema: Schema.version(feed.schema)}}
    end
  end

  defp ticks(_feed, nil), do: nil

  defp ticks(feed, [from, to]) do
    [from && ceil(ms(from, feed) / feed.every), to && floor(ms(to, feed) / feed.every)]
  end

  defp ms(%DateTime{} = t, feed), do: DateTime.to_unix(t, :millisecond) - feed.origin

  defp instant(feed, tick),
    do: DateTime.from_unix!(feed.origin + tick * feed.every, :millisecond)
end

defmodule Examples.BoardDemo.Fixed do
  @moduledoc "A feed that always answers the same rows: a design's constant slot, such as a dial's track."
  @behaviour Visualize.Feed

  alias Visualize.Data.{Delivery, Schema}

  defstruct [:rows, :schema]

  def new(rows, fields), do: %__MODULE__{rows: rows, schema: Schema.new!(fields)}

  @impl true
  def describe(%__MODULE__{schema: schema}), do: {Schema.version(schema), schema, []}

  @impl true
  def fetch(%__MODULE__{rows: rows, schema: schema}, _window, _budget),
    do: {:ok, Delivery.new(rows, schema: Schema.version(schema))}
end

defmodule Examples.BoardDemo.Unreachable do
  @moduledoc """
  A feed whose source cannot be reached: it describes itself, and every fetch answers
  `{:error, :unreachable}`, which a cell draws as its "feed down" state (spec/15 §8.4).
  """
  @behaviour Visualize.Feed

  alias Visualize.Data.Schema

  defstruct [:schema]

  def new(fields), do: %__MODULE__{schema: Schema.new!(fields)}

  @impl true
  def describe(%__MODULE__{schema: schema}), do: {Schema.version(schema), schema, [:window]}

  @impl true
  def fetch(_feed, _window, _budget), do: {:error, :unreachable}
end
