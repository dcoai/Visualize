# Visualize

Visualize is a data-visualization library for Elixir and Phoenix LiveView. You describe a chart
as plain data, apply your rows on the server, and get SVG or canvas output.

## The problem it solves

Putting a chart in a LiveView app usually means leaving Elixir: a JavaScript charting library,
a build step to bundle it, and glue to keep its state in step with the server's. The chart
itself ends up as code in the browser, which you can't store, check or reuse from Elixir.

Visualize keeps the whole chart on the server:

- **No JavaScript charting library and no JS build step.** Charts render in Elixir and are
  interpolated into HEEx; LiveView sends only what changed.
- **A chart is data.** A design is a plain map that you can store, validate, compose, edit and
  round-trip through JSON, not code you have to rerun.
- **One design, five backends.** The same design draws as SVG, Canvas, a binary canvas stream,
  a hybrid of the two, or an incremental strip.
- **Live and dense data.** A compiled chart ticks with new rows and streams them over the
  LiveView socket, so tens of thousands of points can scroll at full frame rate.
- **d3's model.** Scales, shapes, axes, layouts and projections, for anyone who already thinks
  in them.

## Features

- **Charts as data**: validated, versioned and JSON-encodable designs, built from fragments that
  compose and stack like styles.
- **Five backends from one design**: SVG, Canvas, binary canvas, Hybrid and Incremental.
- **Live data**: scrolling viewports, eased scale transitions, and a data rate independent of
  the frame rate.
- **The d3 toolkit in Elixir**: eleven scale types, shapes with ten curves, axes and number/time
  formatting, hierarchy and network layouts, geographic projections, Voronoi and contours.
- **Frames and composition**: several frames in one design, shared scales, polar as a transform.
- **Data transforms** on a mark's data: filter, bin, stack, fold, sum, sort, take, window, FFT.
- **Themes and a style grammar**: one style serves SVG (as CSS variables) and canvas.
- **LiveView integration**: components, and hooks for zoom, brush, tooltip, crosshair and legend.
- **No required runtime dependencies**: Phoenix, Nx and `table` are all optional.
- **Specified and gated**: every public function has a contract, and CI fails on drift.

## Installation

Visualize is on [Hex](https://hex.pm/packages/visualize):

<!-- compile only: a deps/0 fragment of the host's mix.exs -->
```elixir
def deps do
  [
    {:visualize, "~> 0.6"},
    {:nx, "~> 0.9"}      # optional: binary canvas encoding and Nx-accelerated paths
  ]
end
```

Then `mix deps.get`. The API reference and these guides are on
[HexDocs](https://hexdocs.pm/visualize); read the [changelog](CHANGELOG.md) before moving
to a new minor version.

## Example

A design composed from fragments, applied to rows, and rendered:

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
    line(:days, %{x: :date, y: :value}, style: %{curve: :step_after})
  ])

rows = [%{date: ~D[2024-01-01], value: 10}, %{date: ~D[2024-01-02], value: 25}]
{:ok, applied} = Visualize.Chart.apply(design, sources: %{days: rows}, size: {500, 300})

Visualize.Chart.render(applied, root: true)         # an <svg> document
Visualize.Chart.render(applied, backend: :canvas)   # Canvas 2D commands
```

The design records no size; the host gives one when the chart is applied.

## Running the examples

`examples/` is a Phoenix LiveView app over the library:

- **The gallery** (`/`): every chart type, each with its design and the `Build` calls that make
  it, a backend switch and a performance drawer (`/chart/<name>`).
- **Interaction** (`/interaction`) and **Dashboard** (`/dashboard`): the tooltip, crosshair
  and legend hooks, and three panels whose crosshairs and brushes move together.
- **A board** (`/board`): a dashboard of cells over live feeds, with a shared window, linked
  selection, drill-down, and export to SVG, PNG and print.
- **The chart builder** (`/builder`): a LiveComponent that edits a design, a theme or a board
  in the browser.
- **Performance** (`/performance`) and **Hybrid** (`/hybrid`): every design run through
  each backend and compared, and SVG furniture under canvas marks.

```sh
cd examples
./run.sh                  # http://127.0.0.1:4080
```

`./run.sh 4020` picks another port and `./run.sh 0.0.0.0:4020` another address. An address
other than loopback exposes an unauthenticated development server. See
`examples/README.md` for the rest.

## Documentation

- [Getting started](guides/getting_started.md): install, a first chart in IEx, the same chart
  in a LiveView.
- [Charts in LiveView](guides/liveview.md): components, hooks, choosing a backend, live data.
- [Designing charts](guides/designing_charts.md): a tour of the declarative layer.
- [Cheatsheet](https://hexdocs.pm/visualize/cheatsheet.html): the `Build` functions and common recipes.
- [Changelog](CHANGELOG.md): what each tag changed.

`mix docs` builds the API reference with the guides and the changelog. Three more documents
ship in the package and are read on GitHub:

- [Usage rules](https://github.com/dcoai/Visualize/blob/main/usage-rules.md):
  the short form, for developers and agents.
- [Specification](https://github.com/dcoai/Visualize/blob/main/spec/README.md):
  the source of truth, with a contract for every public function.
- [API surface](https://github.com/dcoai/Visualize/blob/main/API_SURFACE.md):
  the generated record of the spec and code agreeing.

## Where it's going

Visualize is growing from a chart library into **the dashboard library that applications
share**. You hand it chart definitions and data sources, and it watches the sources and keeps
the charts current. Any application can show the same dashboard, drawn the same way, without
an iframe or a second renderer.

The pieces, in layers:

- **Designs** are charts as data. They are versioned, validated and stored, and checked when
  loaded from somewhere you don't control.
- **Feeds** are sources that describe their fields by meaning (unit, label, order, what a
  state means) and deliver rows. A feed has only to return rows. A time window, a point
  budget and push updates are optional, and visualize finishes whatever a feed leaves out.
- **Boards** lay designs out on a grid with a shared time window, linked selection and
  drill-down. Each board and each cell runs in its own process, so one slow or broken chart
  never stalls the rest.
- **Themes** choose every colour, including meaning-bearing ramps (status, thermal) that hold
  under a dark or colour-blind-safe theme. Data never names a colour.

### Integrating it

- **Draw a chart:** compose a design, apply your rows, and render it in HEEx. See
  [Getting started](guides/getting_started.md).
- **Feed live data:** implement the `Visualize.Feed` behaviour over your data, whether a
  database, an HTTP API or `:telemetry` (a provider for `:telemetry` ships with the library).
  Then run `Visualize.Feed.Conformance` in your test suite to prove the feed honours the
  contract.
- **Show a dashboard:**
  1. Add `Visualize.Board.Supervisor` to your supervision tree.
  2. Bind each cell's source slots to your feeds. A binding is your application's data and
     never travels with the board.
  3. Render the board LiveView component.
- **Let people build:** mount the builder with a catalog of your feeds, and they can lay out
  boards, bind cells and tune themes. Boards travel between applications as bundles, and as
  snapshots for sharing a frozen view.

These layers are new: expect them to settle over the next few releases, and tell us where
they don't fit your application.

## Status and feedback

Visualize is pre-1.0, and its API can still change between tags. **The chart builder is a work
in progress, not a finished product**: try it, but expect gaps.

Feedback is welcome and encouraged. Bug reports, rough edges, charts you couldn't make and
ideas are all useful: open an issue on
[GitHub](https://github.com/dcoai/Visualize/issues).

MIT licensed.
