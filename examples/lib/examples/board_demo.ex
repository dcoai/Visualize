defmodule Examples.BoardDemo do
  @moduledoc """
  The demo board of `/board` (spec/15 §8–§10, #576, D-146): twelve cells over live feeds,
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

  - **memory** and **queue**'s axes, and **weather**'s two, take their `measure` from the
    feed's own facts (D-138, D-155..D-157): the telemetry unit `MBy` and the station's `Cel`
    and `km/h`, shown in the viewer's unit system.
  - **latency** is a percentile band over a feed of request latency percentiles
    (`Examples.BoardDemo.Latency`), and **status** a state timeline of each service's
    stretches in one state (`Examples.BoardDemo.Status`). With **memory** and **queue** they
    draw their overlays as marks read from the feeds' facts (#565, D-143): a rule at the
    `target`, readings colored by a threshold scale at it placed by the `polarity` (which
    the telemetry definitions carry in `reporter_options`, D-160), and states colored by the
    feed's own `status` map. Every time design brushes with its own `brush: :x`.
  - **links** is a bar per network link over a feed that names a link by two fields,
    `host` and `iface` (`Examples.BoardDemo.Links`, D-167), so a pick is a composite
    selection; **stale**, **no_data**, **capped** and **invalid** are the *Line Chart* over
    feeds made to be in that state (`Examples.BoardDemo.States`), so every cell state of
    spec/15 §8.4 is on the page (#781, work item #821).

  The board shares one window, the last five minutes by default, in UTC and shown in the
  board's zone; one sync group joins the time charts' hover and brush. The board is
  started once per unit system, on the first visit in it, and every visitor in that system
  sees the same board: its window is the board's shared state (spec/15 §8.2), and the
  system is the viewer's, so it is a board per system rather than a setting of one.
  """

  use Supervisor

  import Visualize.Chart.Build
  import Visualize.Chart, only: [fact: 3]
  import Visualize.Generators, only: [generate: 2]

  alias Examples.BoardDemo.{Fixed, Hosts, Latency, Latest, Services, Status, Unreachable, Wave}
  alias Examples.BoardDemo.{Endpoints, Links, MemoryHistory, States, Weather}
  alias Examples.Charts.{Design, LineChart, LoadChart}
  alias Visualize.Board
  alias Visualize.Board.{Binding, Server}

  @board Examples.BoardDemo.Board
  @memory "examples.vm.memory"
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

  @doc """
  The two metrics the probe emits, as `Telemetry.Metrics` definitions, each carrying the
  facts of its feed's `value` in `reporter_options[:visualize]` (D-160): which way is
  better, where values lie and the target a design draws its rule at.
  """
  def metrics do
    [
      Telemetry.Metrics.last_value("examples.vm.memory",
        unit: :megabyte,
        description: "Memory in use",
        reporter_options: [visualize: [polarity: :lower_is_better, bounds: [0, nil], target: 200]]
      ),
      Telemetry.Metrics.last_value("examples.vm.run_queue",
        description: "Run queue",
        reporter_options: [visualize: [polarity: :lower_is_better, bounds: [0, nil], target: 2]]
      )
    ]
  end

  @systems [{"As posted", :as_posted}, {"Metric", :metric}, {"US", :us}, {"UK", :uk}]

  @doc "The unit systems a viewer may choose, with their names (spec/14 §4.4, D-156)."
  def systems, do: @systems

  @doc """
  The system a page's `units` parameter names, `:as_posted` for anything else: the
  parameter is a person's, so it is matched against the four, never made an atom.
  """
  @spec system(String.t() | nil) :: atom()
  def system(param) do
    Enum.find_value(@systems, :as_posted, fn {_name, system} ->
      if Atom.to_string(system) == param, do: system
    end)
  end

  @doc """
  The demo board in a unit system (default `:as_posted`), started under `Examples.Boards`
  on the first call and the same process on every later one: `{:ok, pid}`, or the reason
  it could not start. The system is the viewer's choice and every cell is drawn in it, so a
  board runs per system (spec/15 §8), each registered by its own.
  """
  @spec board(atom()) :: {:ok, pid()} | {:error, term()}
  def board(system \\ :as_posted) do
    case Process.whereis(name(system)) do
      nil -> start(system)
      pid -> {:ok, pid}
    end
  end

  # Each system's board under a name written here, so no name is ever built at run time
  # (atoms are never collected; #778).
  defp name(:as_posted), do: @board
  defp name(:metric), do: Examples.BoardDemo.Board.Metric
  defp name(:us), do: Examples.BoardDemo.Board.Us
  defp name(:uk), do: Examples.BoardDemo.Board.Uk

  defp start(system) do
    opts = [
      name: name(system),
      system: system,
      board: value(),
      store: store(),
      binding: slots(),
      feeds: feeds(),
      boards: %{detail: detail_value("api")},
      virtual_sources: [Examples.BoardDemo.Sources],
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
        memory: %{x: 8, y: 0, w: 4, h: 2, ref: {:composite, 3}, title: "Memory"},
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
        },
        hosts: %{
          x: 0,
          y: 10,
          w: 12,
          h: 3,
          ref: {:composite, 7},
          title: "Hosts: health and trend",
          sync: false
        },
        weather: %{
          x: 0,
          y: 13,
          w: 12,
          h: 3,
          ref: {:composite, 8},
          title: "Weather station: temperature and wind"
        },
        latency: %{x: 0, y: 16, w: 6, h: 3, ref: {:composite, 9}, title: "Latency against target"},
        status: %{x: 6, y: 16, w: 6, h: 3, ref: {:composite, 10}, title: "Service status"},
        colored: %{
          x: 0,
          y: 19,
          w: 6,
          h: 3,
          ref: {:composite, 12},
          title: "Services, colored by a host function",
          sync: false
        },
        links: %{
          x: 6,
          y: 19,
          w: 6,
          h: 3,
          ref: {:composite, 13},
          title: "Links: host and interface",
          sync: false
        },
        stale: %{x: 0, y: 22, w: 3, h: 3, ref: {:composite, 2}, title: "Stale"},
        no_data: %{x: 3, y: 22, w: 3, h: 3, ref: {:composite, 2}, title: "No data"},
        capped: %{x: 6, y: 22, w: 3, h: 3, ref: {:composite, 2}, title: "Capped"},
        invalid: %{x: 9, y: 22, w: 3, h: 3, ref: {:composite, 2}, title: "Invalid binding"}
      },
      virtual_sources: virtual_sources()
    })
  end

  @doc """
  The detail board a click on a service's bar opens (spec/15 §13.3): one service's
  requests and errors, its variable `service` filtering both cells' rows.
  """
  @spec detail_value(String.t()) :: Board.t()
  def detail_value(service) do
    Board.from_map!(%{
      meta: %{
        name: "Service detail",
        description: "One service's requests, errors and endpoints"
      },
      window: %{last: 300},
      sync: "detail",
      vars: %{service: service},
      cells: %{
        requests: %{x: 0, y: 0, w: 6, h: 4, ref: {:composite, 6}, title: "Requests"},
        errors: %{x: 6, y: 0, w: 6, h: 4, ref: {:composite, 6}, title: "Errors"},
        endpoints: %{
          x: 3,
          y: 4,
          w: 6,
          h: 3,
          ref: {:composite, 11},
          title: "Requests by endpoint, the last minute",
          sync: false
        }
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
        Binding.new(%{
          {:requests, :requests} => :requests,
          {:errors, :requests} => :errors,
          {:endpoints, :endpoints} => :endpoints
        }),
      feeds: %{requests: Services.new(1), errors: Services.new(0.08), endpoints: Endpoints.new()},
      tick: 1000
    )
  end

  @doc "The board's components by id: two gallery designs and one board design."
  def store do
    {load, _rows} = LoadChart.design([])
    {line, _rows} = LineChart.design([])

    %{
      {:composite, 1} => load,
      {:composite, 2} => put_in(line, [:frames, "main", :scales, "x"], %{kind: :time}),
      {:composite, 3} => metric(),
      {:composite, 4} => by_service(nil),
      {:composite, 5} => latest(),
      {:composite, 6} => by_service(Visualize.Chart.var(:service)),
      {:composite, 7} => hosts(),
      {:composite, 8} => weather(),
      {:composite, 9} => latency(),
      {:composite, 10} => status(),
      {:composite, 11} => endpoints(),
      {:composite, 12} => colored(),
      {:composite, 13} => links()
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
      interaction(brush: :x),
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

  # One metric over time: the shape every telemetry feed has (`t`, `value`). The axis says
  # what the value is from the feed's own facts (D-138, D-156), so the telemetry unit — `MBy`
  # for memory, `1` of `:count` for the run queue — reaches it, shown in the viewer's system.
  #
  # Its overlays are marks of the design, read from the same facts (#565, D-143): a rule at
  # the feed's `target`, and the newest reading as a dot whose color is a `:threshold` scale
  # over the status ramp at that target, placed by the feed's `polarity` — good on the
  # better side of the target, bad beyond it, whichever way the feed says is better.
  defp metric do
    newest = take(from(:metric), 1)

    Design.fold([
      chart(meta: %{name: "Metric"}),
      source(:metric, [:t, :value], types: %{t: :time, value: :number}),
      interaction(brush: :x),
      style(:trace, stroke: %{color: :series_2, width: 2}),
      style(:reading, fill: %{color: {:field, :value}}, stroke: %{color: :background, width: 1}),
      # A glow under the newest reading: its status color, blurred (an effect, spec/14 §3.1).
      style(:glow,
        fill: %{color: {:field, :value}, opacity: 0.45},
        effect: %{type: :blur, radius: 3}
      ),
      cartesian(margin: %{top: 10, right: 16, bottom: 26, left: 48}),
      time_scale(:x),
      linear_scale(:y, domain: [0, :auto], nice: true),
      threshold_scale(:color,
        domain: [fact(:metric, :value, :target)],
        range: {:ramp, :status},
        polarity: fact(:metric, :value, :polarity)
      ),
      axis(:x, :bottom, ticks: 4, format: "%H:%M"),
      axis(:y, :left, ticks: 3, grid: true, measure: measure(:metric, :value)),
      line(:metric, %{x: :t, y: :value}, style: :trace),
      rule(newest, %{y: fact(:metric, :value, :target)}, style: [:bad, :dashed]),
      circle(newest, %{x: :t, y: :value}, style: :glow, options: %{radius: 8}),
      circle(newest, %{x: :t, y: :value}, style: :reading, options: %{radius: 4})
    ])
  end

  # A station's temperature on the left axis and its wind on the right, each axis's
  # measure read from the station's schema: the viewer's system shows them in °F and mi/h,
  # or °C and mi/h, without the design naming a unit (spec/14 §4.4, D-156). The axes give no
  # tick count or format: each derives its own from its size and its domain (D-138).
  defp weather do
    Design.fold([
      chart(meta: %{name: "Weather"}),
      source(:weather, [:t, :temperature, :wind],
        types: %{t: :time, temperature: :number, wind: :number}
      ),
      interaction(brush: :x),
      style(:temperature, stroke: %{color: :series_3, width: 2}),
      style(:wind, stroke: %{color: :series_1, width: 1.5, dash: [4, 3]}),
      cartesian(margin: %{top: 10, right: 56, bottom: 26, left: 56}),
      time_scale(:x),
      linear_scale(:y, nice: true),
      linear_scale(:wind, domain: [0, :auto], nice: true),
      axis(:x, :bottom),
      axis(:y, :left, grid: true, measure: measure(:weather, :temperature)),
      axis(:wind, :right, measure: measure(:weather, :wind)),
      label({:axis, :y}, ~S"#{fact(:weather, :temperature, :label)}"),
      label({:axis, :wind}, ~S"#{fact(:weather, :wind, :label)}"),
      line(:weather, %{x: :t, y: :temperature}, style: :temperature),
      line(:weather, %{x: :t, y: :wind}, style: :wind, scales: %{y: :wind})
    ])
  end

  # The latency percentiles as one band (the 5th to the 95th, the 25th to the 75th, the
  # median), the median's target a rule and each median reading a dot in its status by the
  # target and the feed's polarity: every overlay a mark, every number a fact (D-143).
  defp latency do
    Design.fold([
      chart(meta: %{name: "Latency"}),
      source(:latency, [:t, :p5, :p25, :p50, :p75, :p95],
        types: %{t: :time, p5: :number, p25: :number, p50: :number, p75: :number, p95: :number}
      ),
      interaction(brush: :x),
      style(:reading, fill: %{color: {:field, :p50}}),
      # The note in the corner, in italic, its number a fact of the feed (spec/14 §3.1, §7.4).
      style(:note, extends: :label, font: %{style: :italic, size: 11}),
      cartesian(margin: %{top: 10, right: 16, bottom: 26, left: 56}),
      time_scale(:x),
      linear_scale(:y, domain: [0, :auto], nice: true),
      threshold_scale(:color,
        domain: [fact(:latency, :p50, :target)],
        range: {:ramp, :status},
        polarity: fact(:latency, :p50, :polarity)
      ),
      axis(:x, :bottom, format: "%H:%M"),
      axis(:y, :left, ticks: 4, grid: true, measure: measure(:latency, :p50)),
      percentile_band(:latency, %{
        x: :t,
        median: :p50,
        inner_lo: :p25,
        inner_hi: :p75,
        outer_lo: :p5,
        outer_hi: :p95
      }),
      rule(take(from(:latency), 1), %{y: fact(:latency, :p50, :target)}, style: [:bad, :dashed]),
      circle(:latency, %{x: :t, y: :p50}, style: :reading, options: %{radius: 2.5}),
      label(
        {:frame, :top_right},
        "The median against its \#{fact(:latency, :p50, :target)} ms target: lower is better",
        style: :note
      )
    ])
  end

  # Each service's state over time as a state timeline: a `:band` per stretch, at its
  # service's row, filled by its state through an ordinal color scale whose domain is the
  # feed's declared states and whose range is its own meaning of each — a map from state to
  # role — both read as facts (D-143), so the legend lists every state, present or not.
  defp status do
    Design.fold([
      chart(meta: %{name: "Service status"}),
      source(:status, [:service, :since, :until, :state], types: %{since: :time, until: :time}),
      interaction(brush: :x),
      style(:stretch, fill: %{color: {:field, :state}}),
      cartesian(margin: %{top: 8, right: 16, bottom: 26, left: 40}),
      time_scale(:x),
      band_scale(:y, domain: Services.services(), padding: 0.25),
      ordinal_scale(:color,
        domain: fact(:status, :state, :values),
        range: fact(:status, :state, :status)
      ),
      axis(:x, :bottom, format: "%H:%M"),
      axis(:y, :left),
      band(:status, %{x0: :since, x1: :until, y: :service},
        style: :stretch,
        options: %{height: 14}
      ),
      legend(:color, title: "State", position: :bottom, inside: false)
    ])
  end

  # Each service's newest rate, a bar in the color the host's own function gives it
  # (`Examples.BoardDemo.Generators`, spec/14 §3.13), called as the cell draws: when that
  # function raises, only this cell is down, shown crashed and restarted (spec/15 §8.3).
  defp colored do
    Design.fold([
      chart(meta: %{name: "Services by host color"}),
      source(:latest, [:name, :value], types: %{value: :number}),
      cartesian(margin: %{top: 10, right: 12, bottom: 26, left: 40}),
      band_scale(:x, padding: 0.3),
      linear_scale(:y, domain: [0, :auto], nice: true),
      axis(:x, :bottom),
      axis(:y, :left, ticks: 3, grid: true),
      rect(:latest, %{x0: :name, x1: :name, y0: 0, y1: :value},
        style: %{fill: %{color: generate(:service_color, [{:field, :name}])}}
      )
    ])
  end

  # Each link's throughput, a bar per host and interface. The feed names a link by both
  # fields (D-167), so a click on a bar picks the composite identity `%{host, iface}`, which
  # the board selects: that bar `:selected`, every other `:muted` (spec/15 §13.2).
  defp links do
    Design.fold([
      chart(meta: %{name: "Links"}),
      source(:links, [:host, :iface, :link, :mbps], types: %{mbps: :number}),
      cartesian(margin: %{top: 10, right: 12, bottom: 26, left: 48}),
      band_scale(:x, padding: 0.25),
      linear_scale(:y, domain: [0, :auto], nice: true),
      ordinal_scale(:color, domain: Links.ifaces()),
      axis(:x, :bottom),
      axis(:y, :left, ticks: 3, grid: true, measure: %{unit: fact(:links, :mbps, :unit)}),
      rect(:links, %{x0: :link, x1: :link, y0: 0, y1: :mbps, value: :iface},
        tooltip: %{fields: [:host, :iface, :mbps], template: "{host} {iface}: {mbps} Mbit/s"}
      ),
      legend(:color, title: "Interface", position: :top, inside: true)
    ])
  end

  # One service's share of requests by endpoint, a slice each, the legend at the right
  # naming them. Endpoints are named as routes are, too long for a side legend, so the
  # legend cuts each label to 24 characters and keeps the whole name in its title for a
  # hover and a screen reader (`max_label`, spec/14 §4.5, D-169).
  defp endpoints do
    only = %{
      source: :endpoints,
      transforms: [
        %{op: :filter, field: :service, test: :eq, value: Visualize.Chart.var(:service)}
      ]
    }

    Design.fold([
      chart(meta: %{name: "Endpoints"}),
      source(:endpoints, [:service, :endpoint, :requests], types: %{requests: :number}),
      var(:service, "api"),
      style(:slice, fill: %{color: {:field, :endpoint}}, stroke: %{color: :background, width: 1}),
      polar(margin: %{top: 8, right: 240, bottom: 8, left: 8}),
      ordinal_scale(:color),
      legend(:color, position: :right, inside: false, max_label: 24, title: "Endpoint"),
      arc(only, %{value: :requests},
        style: :slice,
        options: %{inner_radius: 30, outer_radius: 80, pad_angle: 0.02}
      )
    ])
  end

  # An axis's measure as the feed's schema states it: its unit and its quantity.
  defp measure(slot, field) do
    %{
      unit: fact(slot, field, :unit),
      quantity: fact(slot, field, :quantity)
    }
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
      {:services, :latest} => :latest,
      {:hosts, :hosts} => :hosts,
      {:weather, :weather} => :weather,
      {:latency, :latency} => :latency,
      {:status, :status} => :status,
      {:colored, :latest} => :latest,
      {:links, :links} => :links,
      {:stale, :points} => :stale,
      {:no_data, :points} => :no_data,
      {:capped, :points} => :capped,
      {:invalid, :points} => :invalid
    })
  end

  @doc """
  The feeds by the names the binding uses. The memory metric is the live `:telemetry` feed
  with the store's history behind it, one `Visualize.Feed.Combine` (D-159), so a window
  wider than the node's uptime is filled from the store.
  """
  def feeds do
    telemetry = Visualize.Feed.Telemetry.feeds(@collector)

    telemetry
    |> Map.update!(@memory, &Visualize.Feed.Combine.new([&1, MemoryHistory.new()]))
    |> Map.merge(%{
      load: Wave.new(Visualize.Signals.new(:sine, [:t, :v], period: 90, min: 0.4, max: 3.2)),
      wave: Wave.new(Visualize.Signals.new(:sine, [:x, :y], period: 40, min: 10, max: 90)),
      dial: Fixed.new([%{at: 0}], %{at: %{type: :number}}),
      offline: Unreachable.new(%{x: %{type: :time}, y: %{type: :number}}),
      requests: Services.new(1),
      errors: Services.new(0.08),
      latest: Latest.new(),
      hosts: Hosts.new(),
      weather: Weather.new(),
      latency: Latency.new(),
      status: Status.new(),
      links: Links.new()
    })
    |> Map.merge(Map.new(States.modes(), &{&1, States.new(&1)}))
  end

  @doc """
  Whether the memory store's rows read as the live feed's (D-159): what a connector asks
  before it puts the two in one `Visualize.Feed.Combine`, `:ok` or the reasons they do not.
  """
  @spec memory_compatibility() :: :ok | {:error, list()}
  def memory_compatibility do
    %Visualize.Feed.Combine{feeds: [live, history]} = Map.fetch!(feeds(), @memory)
    {_version, live, _supports} = Visualize.Feed.describe(live)
    {_version, history, _supports} = Visualize.Feed.describe(history)
    Visualize.Data.Schema.compatibility(live, history)
  end

  @doc """
  The board's virtual sources (spec/15 §14, D-194), one of each kind: `health`, a stored
  function the board carries — each host's state by its newest reading — and `trend`, the
  host's own function `Examples.BoardDemo.Sources.trend/1`, named here and registered with
  the board's `virtual_sources:` option.
  """
  def virtual_sources do
    %{
      health: %{
        from: [{:hosts, %{last: 6}}],
        per: :identity,
        schema: %{
          host: %{type: :category, identity: true},
          state: %{
            type: :category,
            label: "Health",
            values: [:good, :warning, :bad],
            status: %{good: :good, warning: :warning, bad: :bad}
          },
          note: %{type: :category, label: "Note"}
        },
        # A statistic of `Visualize.Data` and a label built with interpolation (#769).
        elixir: """
        fn rows ->
          newest = Enum.at(rows, -1)
          latest = newest.cpu
          mean = rows |> Enum.map(& &1.cpu) |> Visualize.Data.mean() |> Float.round(1)

          state =
            cond do
              latest > 80 -> :bad
              latest > 60 -> :warning
              true -> :good
            end

          %{state: state, note: "\#{newest.host} averaged \#{mean}% over its last \#{Enum.count(rows)}"}
        end
        """
      },
      trend: %{
        from: [{:hosts, %{last: 6}}],
        per: :identity,
        schema: %{
          host: %{type: :category, identity: true},
          trend: %{type: :category, label: "Trend", values: [:increasing, :decreasing, :neutral]}
        },
        function: :trend
      }
    }
  end

  # Each host's newest reading as a bar in its health's style, an icon chosen by the same
  # field beneath it, and a legend of the field's declared values (spec/15 §10, D-194).
  defp hosts do
    newest = %{source: :hosts, transforms: [%{op: :window, field: :t, latest: true}]}
    state = :"health.state"

    Design.fold([
      chart(meta: %{name: "Hosts"}),
      source(:hosts, [:t, :host, :cpu, state, :"trend.trend", :"health.note"],
        types: %{t: :time, cpu: :number}
      ),
      cartesian(margin: %{top: 10, right: 110, bottom: 26, left: 40}),
      band_scale(:x, padding: 0.3),
      linear_scale(:y, domain: [-12, 100]),
      axis(:x, :bottom),
      axis(:y, :left, ticks: 3, grid: true),
      # Hovering a bar shows the host's reading, health and trend; a click on one is the
      # declared event `host_picked`, which the page receives with the row (spec/14 §5.7,
      # D-170).
      rect(newest, %{x0: :host, x1: :host, y0: 0, y1: :cpu},
        style: {:field, state},
        tooltip: %{
          fields: [:host, :cpu, state, :"trend.trend", :"health.note"],
          template: "{host}: {cpu}% CPU, {health.state}, {trend.trend}\n{health.note}",
          event: :host_picked
        }
      ),
      choose(newest, %{x: :host, y: -6},
        on: state,
        cases: %{
          good: %{type: :circle, style: :good, options: %{radius: 4}},
          warning: %{type: :symbol, style: :warning},
          bad: %{type: :symbol, style: :bad}
        }
      ),
      %{
        frames: %{
          main: %{
            legend: %{
              values: fact(:hosts, state, :values),
              title: "Health",
              position: :right,
              inside: false
            }
          }
        }
      }
    ])
  end
end
