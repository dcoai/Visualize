# Visualize

Visualize is a data-visualization library for Elixir and Phoenix LiveView that renders on the
server: describe a chart as plain data, apply your rows, and get SVG or canvas output.

> Pre-1.0 and a work in progress.

## Why use it

- Charts in Elixir, with no JavaScript charting library and no JavaScript build step.
- A chart is a value you can store, validate, compose and edit, not code you have to rerun.
- D3's model (scales, shapes, axes, layouts, projections), for anyone who already thinks in it.
- Built for LiveView, with canvas streaming for data that is dense or moving fast.

## Features

- **Charts as data.** A design is a plain map: validated, versioned, JSON-encodable, and built
  from fragments that compose and stack like styles.
- **Rendered on the server**, interpolated into HEEx; LiveView ships only what changed.
- **Five backends from one design**: SVG, Canvas, binary canvas, Hybrid and Incremental.
- **Live data.** A compiled chart ticks with new data: a scrolling viewport, eased scale
  transitions, a data rate independent of the frame rate.
- **The D3 toolkit in Elixir**: eleven scale types, shapes with ten curves, axes and
  formatting, hierarchy and network layouts, geographic projections, Voronoi and contours.
- **Frames and composition**: several frames in one design, shared scales, polar as a transform.
- **Data transforms** on a mark's data: filter, bin, stack, fold, sum, sort, take, window, FFT.
- **Themes and a style grammar**: one style serves SVG (as CSS variables) and canvas.
- **LiveView integration**: components, and hooks for zoom, brush, tooltip, crosshair and legend.
- **A visual chart builder**: a LiveComponent that edits a design in the browser.
- **Zero required runtime dependencies.** Phoenix, Nx and `table` are all optional.
- **Specified and gated**: every public function has a contract, and CI fails on drift.

## Example

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

The design records no size; the host gives it when the chart is applied. The same design
renders on any of the backends:

- **SVG** (`Visualize.Backend.SVG`): markup, diffed by LiveView. The default.
- **Canvas** (`Visualize.Backend.Canvas`): Canvas 2D drawing commands, as JavaScript or JSON.
- **Binary canvas** (`Visualize.Backend.CanvasBinary`): a compact command stream pushed over
  the socket and drawn by the client hooks, for dense data.
- **Hybrid** (`Visualize.Backend.Hybrid`): the static furniture as SVG, the changing marks as
  canvas.
- **Incremental** (`Visualize.Incremental`): only the newly exposed strip of a scrolling chart.

## Installation

<!-- compile only: a deps/0 fragment of the host's mix.exs -->
```elixir
def deps do
  [
    {:visualize, git: "git@gitlab.conet.yarina.org:dco-tek/visualize.git", tag: "v0.1.0"},
    {:nx, "~> 0.9"}      # optional: binary canvas encoding and Nx-accelerated paths
  ]
end
```

Pin a tag, and read the [changelog](CHANGELOG.md) before moving it.

## Running the examples

The gallery in `examples/` is a Phoenix LiveView app: every chart type with its design, the
chart builder and the performance view.

```sh
cd examples
./run.sh                  # http://127.0.0.1:4080
```

`./run.sh 4020` picks another port and `./run.sh 0.0.0.0:4020` another address. An address
other than loopback exposes an unauthenticated development server. `examples/README.md` has
the rest.

## Documentation

- [Specification](spec/README.md): the source of truth, with a contract for every public
  function.
- [Usage rules](usage-rules.md): the short form, for developers and agents.
- [Changelog](CHANGELOG.md): what each tag changed.
- [API surface](API_SURFACE.md): the generated record of the spec and code agreeing.
- `mix docs` builds the documentation, with the specification included.
