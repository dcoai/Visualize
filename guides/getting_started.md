# Getting started

This guide takes you from an empty project to a chart in IEx, and then to the same chart
in a Phoenix LiveView. It assumes you know Elixir and have seen a LiveView before. You do
not need to know any JavaScript or any charting library.

Visualize draws charts on the server. You describe a chart as data, called a *design*.
You hand it rows, and you get back SVG markup, or drawing commands for a `<canvas>`.

## Installation

Visualize is on [Hex](https://hex.pm/packages/visualize):

<!-- compile only: a deps/0 fragment of the host's mix.exs -->
```elixir
def deps do
  [
    {:visualize, "~> 0.2"},
    # Optional. Each one switches on a feature and is never required:
    {:phoenix_live_view, "~> 1.0"}, # the function components and the chart builder
    {:nx, "~> 0.9"},                # the binary canvas stream, for dense data
    {:jason, "~> 1.4"}              # Visualize.Chart.to_json/1 and from_json/1
  ]
end
```

Then run `mix deps.get`. Visualize is pre-1.0, so a minor version can break: read the
[changelog](../CHANGELOG.md) before you move to one.

PNG output needs no package. It runs the `resvg` command-line tool, version 0.45 or
later, if your host has it (`apt install resvg` on Debian and Ubuntu). Everything else in
this guide works without it.

## A first chart in IEx

Start `iex -S mix` in your project. A design is built from small pieces called
*fragments*. Each function of `Visualize.Chart.Build` returns one fragment, and
`Visualize.Chart.compose/1` merges a list of them into a design:

```elixir
import Visualize.Chart.Build

{:ok, design} =
  Visualize.Chart.compose([
    chart(meta: %{name: "Daily total"}),
    source(:days, [:date, :value]),
    cartesian(margin: %{top: 20, right: 20, bottom: 30, left: 40}),
    time_scale(:x),
    linear_scale(:y, domain: [0, :auto], nice: true),
    axis(:x, :bottom),
    axis(:y, :left, grid: true),
    line(:days, %{x: :date, y: :value})
  ])
```

Read it from top to bottom. The chart has one data source, `:days`, whose rows have a
`:date` and a `:value`. It has one cartesian frame, the plot area and its margins. The
frame has a time scale on `x` and a linear scale on `y`, from zero to whatever the data
reaches (`:auto`), rounded to nice numbers. It has two axes, and one line mark that reads
`:date` through the `x` scale and `:value` through the `y` scale.

The design is a plain map. Nothing in it is a function, so you can store it, send it as
JSON, or compare two versions of it:

```elixir
design.marks
#=> [%{type: :line, data: :days, channels: %{x: :date, y: :value}}]
```

### Apply the data

A design names its data but holds none. `Visualize.Chart.apply/2` binds rows to the
sources, checks the result and works out every scale's domain. The size is also given
here, because the size is the page's business, not the design's:

```elixir
rows = [
  %{date: ~D[2024-01-01], value: 10},
  %{date: ~D[2024-01-02], value: 25},
  %{date: ~D[2024-01-03], value: 18},
  %{date: ~D[2024-01-04], value: 32}
]

{:ok, applied} = Visualize.Chart.apply(design, sources: %{days: rows}, size: {500, 300})
```

Rows can be a list of maps, as here, or a map of columns
(`%{date: [...], value: [...]}`), an Nx tensor, or an Explorer data frame with the
optional `table` package (`Visualize.Data.Table.rows/1` lists what is accepted).

If the rows do not fit the design, you get the problems back as a value, all of them at
once. Each error is a path into the design and a reason:

```elixir
{:error, errors} =
  Visualize.Chart.apply(design, sources: %{days: [%{date: ~D[2024-01-01]}]})

Enum.map(errors, &Visualize.Chart.Validator.format/1)
#=> ["sources.days: has no field :value"]
```

### Render it

`Visualize.Chart.render/2` turns the applied chart into a string. With `root: true` you
get a whole `<svg>` document, with the chart's name as its accessible title:

```elixir
svg = Visualize.Chart.render(applied, root: true)
String.starts_with?(svg, "<svg")
#=> true

path = Path.join(System.tmp_dir!(), "daily_total.svg")
File.write!(path, svg)
```

Open that file in a browser and you will see the line, the two axes and the grid.

Without `root: true` you get the chart's `<g>` group alone, for placing inside an `<svg>`
of your own. The same applied chart can be drawn as Canvas 2D commands instead, with
`backend: :canvas`. The [LiveView guide](liveview.md) explains when you would want that.

```elixir
group = Visualize.Chart.render(applied)
canvas = Visualize.Chart.render(applied, backend: :canvas)
```

### A PNG, if resvg is installed

`Visualize.Render.to_png/2` rasterises the chart. resvg cannot read the CSS variables the
default SVG uses for theme colours, so generate the chart with literal colours first:

```elixir
root = Visualize.Chart.generate(applied, root: true, resolve: :literal)

case Visualize.Render.to_png(root, scale: 2, background: "#ffffff") do
  {:ok, png, _warnings} -> File.write!(Path.join(System.tmp_dir!(), "daily_total.png"), png)
  {:error, :no_rasterizer} -> :no_resvg_on_this_host
end
```

## The same chart in a LiveView

There are two ways to put a chart on a LiveView page.

### A ready-made component

For the common chart types, `Visualize.Components` has function components. They take
your rows and accessor functions as assigns, and need no design and no JavaScript:

<!-- compile only: a LiveView needs an endpoint and a socket -->
```elixir
defmodule MyAppWeb.SalesLive do
  use Phoenix.LiveView
  import Visualize.Components

  def mount(_params, _session, socket) do
    rows = [
      %{date: ~D[2024-01-01], value: 10},
      %{date: ~D[2024-01-02], value: 25},
      %{date: ~D[2024-01-03], value: 18}
    ]

    {:ok, assign(socket, rows: rows)}
  end

  def render(assigns) do
    ~H"""
    <.line_chart
      data={@rows}
      x={& &1.date}
      y={& &1.value}
      width={500}
      height={300}
      title="Daily total"
      show_points
    />
    """
  end
end
```

There are line, area, bar, horizontal bar, stacked bar, scatter and pie charts, and tree,
treemap and sunburst diagrams in `Visualize.Components.Tree`. Each is a preset design
underneath, so it draws exactly what the declarative layer draws.

### Your own design

For anything a component does not cover, render the design yourself and put the markup
in the template. `Visualize.Chart.render/2` returns a plain string, so it goes through
`Phoenix.HTML.raw/1`:

<!-- compile only: a LiveView needs an endpoint and a socket -->
```elixir
defmodule MyAppWeb.DailyTotalLive do
  use Phoenix.LiveView
  import Visualize.Chart.Build

  # The design never changes; only the rows do.
  defp design do
    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Daily total"}),
        source(:days, [:date, :value]),
        cartesian(),
        time_scale(:x),
        linear_scale(:y, domain: [0, :auto], nice: true),
        axis(:x, :bottom),
        axis(:y, :left, grid: true),
        line(:days, %{x: :date, y: :value})
      ])

    design
  end

  def mount(_params, _session, socket) do
    rows = [%{date: ~D[2024-01-01], value: 10}, %{date: ~D[2024-01-02], value: 25}]
    {:ok, assign(socket, rows: rows, svg: draw(rows))}
  end

  def handle_info({:new_row, row}, socket) do
    rows = socket.assigns.rows ++ [row]
    {:noreply, assign(socket, rows: rows, svg: draw(rows))}
  end

  defp draw(rows) do
    {:ok, applied} = Visualize.Chart.apply(design(), sources: %{days: rows}, size: {600, 300})
    Visualize.Chart.render(applied, root: true)
  end

  def render(assigns) do
    ~H"""
    <div class="chart">{Phoenix.HTML.raw(@svg)}</div>
    """
  end
end
```

When a new row arrives, the view applies and renders again, and LiveView sends the
browser only the parts of the SVG that changed.

This page needs no JavaScript hooks. You need them for canvas rendering, for a chart that
follows its container's width, and for tooltips, crosshairs, brushing and zooming. The
[LiveView guide](liveview.md) covers all of these.

## Where to go next

- [LiveView](liveview.md): installing the hooks, choosing a backend, live and streaming
  data, and interaction.
- [Designing charts](designing_charts.md): the declarative layer in depth. It covers
  frames, scales, marks and channels, styles and themes, transforms and composition.
- [Cheatsheet](https://hexdocs.pm/visualize/cheatsheet.html): the `Build` functions and common recipes on one page.
- [Usage rules](../usage-rules.md): the library's conventions in short form.
- [The specification](../spec/README.md): the contract for every public function.
- The gallery in `examples/` is a Phoenix app with every chart type and its code. Run it
  with `cd examples && ./run.sh` and open <http://127.0.0.1:4080>.
