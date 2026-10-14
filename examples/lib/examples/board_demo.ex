defmodule Examples.BoardDemo do
  @moduledoc """
  The demo board of `/board` (spec/15 §8–§10, #576, D-146): eight cells over live feeds,
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
  - **requests** and **errors** are one design, a line per `service`, over two synthetic
    feeds (`Examples.BoardDemo.Services`); **services** is a bar per service over a feed
    that calls the field `name` (`Examples.BoardDemo.Latest`). Picking a service in one
    selects it in all three (spec/15 §13.2): the board's `links: %{name: :service}` says
    `name` is `service`. A click on a bar drills down to the detail board (`detail/1`),
    which the page opens with the bar's service (spec/15 §13.3).

  The board shares one window, the last five minutes by default, in UTC and shown in the
  board's zone; one sync group joins the time charts' hover and brush. The board is
  started once, on the first visit, and every visitor sees the same board: its window is
  the board's shared state (spec/15 §8.2).
  """

  use Supervisor

  import Visualize.Chart.Build

  alias Examples.BoardDemo.{Fixed, Latest, Services, Unreachable, Wave}
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
      boards: %{detail: detail_value("api")},
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
      links: %{name: :service},
      cells: %{
        load: %{x: 0, y: 0, w: 8, h: 4, ref: {:composite, 1}, title: "Load", sync: false},
        memory: %{x: 8, y: 0, w: 4, h: 2, ref: {:composite, 3}, title: "Memory (MB)"},
        queue: %{x: 8, y: 2, w: 4, h: 2, ref: {:composite, 3}, title: "Run queue"},
        wave: %{x: 0, y: 4, w: 8, h: 3, ref: {:composite, 2}, title: "Wave"},
        offline: %{x: 8, y: 4, w: 4, h: 3, ref: {:composite, 2}, title: "Offline"},
        requests: %{x: 0, y: 7, w: 4, h: 3, ref: {:composite, 4}, title: "Requests"},
        errors: %{x: 4, y: 7, w: 4, h: 3, ref: {:composite, 4}, title: "Errors"},
        services: %{
          x: 8,
          y: 7,
          w: 4,
          h: 3,
          ref: {:composite, 5},
          title: "Services: click to drill down",
          sync: false,
          drill: %{board: :detail, vars: %{service: {:datum, :name}}}
        }
      }
    })
  end

  @doc """
  The detail board a click on a service's bar opens (spec/15 §13.3): one service's
  requests and errors, its variable `service` filtering both cells' rows.
  """
  @spec detail_value(String.t()) :: Board.t()
  def detail_value(service) do
    Board.from_map!(%{
      meta: %{name: "Service detail", description: "One service's requests and errors"},
      window: %{last: 300},
      sync: "detail",
      vars: %{service: service},
      cells: %{
        requests: %{x: 0, y: 0, w: 6, h: 4, ref: {:composite, 6}, title: "Requests"},
        errors: %{x: 6, y: 0, w: 6, h: 4, ref: {:composite, 6}, title: "Errors"}
      }
    })
  end

  @doc """
  A detail board for one service, started linked to the caller — the page that shows it —
  so each visitor's detail board is their own and stops when the page does.
  """
  @spec detail(String.t()) :: {:ok, pid()} | {:error, term()}
  def detail(service) do
    Server.start_link(
      board: detail_value(service),
      store: store(),
      binding:
        Binding.new(%{{:requests, :requests} => :requests, {:errors, :requests} => :errors}),
      feeds: %{requests: Services.new(1), errors: Services.new(0.08)},
      tick: 1000
    )
  end

  @doc "The board's components by id: two gallery designs and one board design."
  def store do
    {load, _rows} = LoadChart.design([])
    {line, _rows} = LineChart.design([])

    %{
      {:composite, 1} => load,
      {:composite, 2} => put_in(line, [:frames, :main, :scales, :x], %{kind: :time}),
      {:composite, 3} => metric(),
      {:composite, 4} => by_service(nil),
      {:composite, 5} => latest(),
      {:composite, 6} => by_service(Visualize.Chart.var(:service))
    }
  end

  # A line per service over time; with a service, only that one's rows (a `:filter` step
  # on the board's variable).
  defp by_service(only) do
    data =
      case only do
        nil ->
          :requests

        var ->
          %{
            source: :requests,
            transforms: [%{op: :filter, field: :service, test: :eq, value: var}]
          }
      end

    Design.fold([
      chart(meta: %{name: "By service"}),
      source(:requests, [:t, :service, :value], types: %{t: :time, value: :number}),
      if(only, do: var(:service, "api"), else: %{}),
      style(:trace, stroke_width: 2),
      cartesian(margin: %{top: 10, right: 16, bottom: 26, left: 40}),
      time_scale(:x),
      linear_scale(:y, domain: [0, :auto], nice: true),
      ordinal_scale(:color, domain: Services.services()),
      axis(:x, :bottom, ticks: 4, format: "%H:%M"),
      axis(:y, :left, ticks: 3, grid: true),
      line(data, %{x: :t, y: :value, series: :service}, style: :trace)
    ])
  end

  # The newest value of each service, a bar each.
  defp latest do
    Design.fold([
      chart(meta: %{name: "Services"}),
      source(:latest, [:name, :value], types: %{value: :number}),
      cartesian(margin: %{top: 10, right: 12, bottom: 26, left: 40}),
      band_scale(:x, padding: 0.2),
      linear_scale(:y, domain: [0, :auto], nice: true),
      ordinal_scale(:color, domain: Services.services()),
      axis(:x, :bottom),
      axis(:y, :left, ticks: 3, grid: true),
      rect(:latest, %{x0: :name, x1: :name, y0: 0, y1: :value, value: :name})
    ])
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
      {:offline, :points} => :offline,
      {:requests, :requests} => :requests,
      {:errors, :requests} => :errors,
      {:services, :latest} => :latest
    })
  end

  @doc "The feeds by the names the binding uses."
  def feeds do
    telemetry = Visualize.Feed.Telemetry.feeds(@collector)

    Map.merge(telemetry, %{
      load: Wave.new(Visualize.Signals.new(:sine, [:t, :v], period: 90, min: 0.4, max: 3.2)),
      wave: Wave.new(Visualize.Signals.new(:sine, [:x, :y], period: 40, min: 10, max: 90)),
      dial: Fixed.new([%{at: 0}], %{at: %{type: :number}}),
      offline: Unreachable.new(%{x: %{type: :time}, y: %{type: :number}}),
      requests: Services.new(1),
      errors: Services.new(0.08),
      latest: Latest.new()
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

defmodule Examples.BoardDemo.Services do
  @moduledoc """
  A synthetic feed of three services' rates over time (spec/08 §11): a reading every ten
  seconds for each of `api`, `web` and `db`, each its own slow wave, scaled by the feed's
  `scale` — so one module is the board's requests and, scaled down, its errors. The rows
  are a function of the instant, so every window asked is answered at once, and a brushed
  window is answered with exactly its readings (spec/15 §13.1).
  """
  @behaviour Visualize.Feed

  alias Visualize.Data.{Delivery, Schema}

  @services ["api", "web", "db"]
  @every 10
  # At most this many readings per service, however wide the window.
  @most 400

  defstruct [:scale, :schema]

  @doc "The services, in the order every design colours them."
  def services, do: @services

  @doc "A feed whose readings are the waves times `scale`."
  def new(scale) do
    schema =
      Schema.new!(%{
        t: %{type: :time, label: "Time"},
        service: %{type: :category, label: "Service", identity: true},
        value: %{type: :number, label: "Rate", continuity: 3 * @every}
      })

    %__MODULE__{scale: scale, schema: schema}
  end

  @doc "One service's reading at an instant, at a scale."
  def value(scale, service, %DateTime{} = t) do
    i = Enum.find_index(@services, &(&1 == service))
    s = DateTime.to_unix(t)
    base = Enum.at([40, 25, 12], i)
    wave = :math.sin(2 * :math.pi() * s / Enum.at([180, 240, 300], i) + i)
    Float.round(scale * (base + base * 0.5 * wave), 2)
  end

  @impl true
  def describe(%__MODULE__{schema: schema}), do: {Schema.version(schema), schema, [:window]}

  @impl true
  def fetch(%__MODULE__{} = feed, window, _budget) do
    now = DateTime.utc_now()
    [from, to] = window || [DateTime.add(now, -300), now]
    first = div(DateTime.to_unix(from) + @every - 1, @every)
    last = div(DateTime.to_unix(min_time(to, now)), @every)

    rows =
      for tick <- max(first, last - @most + 1)..last//1,
          t = DateTime.from_unix!(tick * @every),
          service <- @services,
          do: %{t: t, service: service, value: value(feed.scale, service, t)}

    {:ok, Delivery.new(rows, schema: Schema.version(feed.schema))}
  end

  defp min_time(a, b), do: if(DateTime.compare(a, b) == :gt, do: b, else: a)
end

defmodule Examples.BoardDemo.Latest do
  @moduledoc """
  Each service's newest request rate, a row per service, under the field `name`: a feed
  that names the services differently from `Examples.BoardDemo.Services`, which the board's
  `links: %{name: :service}` reconciles (spec/15 §13.2).
  """
  @behaviour Visualize.Feed

  alias Examples.BoardDemo.Services
  alias Visualize.Data.{Delivery, Schema}

  defstruct [:schema]

  def new do
    %__MODULE__{
      schema:
        Schema.new!(%{
          name: %{type: :category, label: "Service", identity: true},
          value: %{type: :number}
        })
    }
  end

  @impl true
  def describe(%__MODULE__{schema: schema}), do: {Schema.version(schema), schema, []}

  @impl true
  def fetch(%__MODULE__{schema: schema}, _window, _budget) do
    now = DateTime.utc_now()

    rows =
      for service <- Services.services(),
          do: %{name: service, value: Services.value(1, service, now)}

    {:ok, Delivery.new(rows, schema: Schema.version(schema))}
  end
end
