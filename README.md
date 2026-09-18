# Visualize

Server-side visualization for Elixir and Phoenix LiveView, in the shape of D3: scales,
shapes, axes, layouts, geographic projections and colour, producing SVG (or canvas
command streams and a binary transfer format) from plain Elixir data.

SVG is generated on the server and diffed by LiveView, so it suits charts of up to about
a thousand data points. Denser data goes through the canvas backends or is reduced to
panel resolution first; `spec/00-prior-art.md` explains the constraints.

## Example

A chart is a design: a map that says what the chart is, applied to rows and rendered by
the library on any backend (`spec/14`). `Visualize.Chart.Build` writes one.

```elixir
import Visualize.Chart.Build

{:ok, design} =
  Visualize.Chart.compose([
    chart(meta: %{name: "Daily total"}),
    source(:days, [:date, :value]),
    cartesian(500, 300, margin: %{top: 20, right: 20, bottom: 30, left: 40}),
    time_scale(:x),
    linear_scale(:y, domain: [0, :auto], nice: true),
    axis(:x, :bottom),
    axis(:y, :left, grid: true),
    line(:days, %{x: :date, y: :value}, style: %{curve: :step_after})
  ])

rows = [%{date: ~D[2024-01-01], value: 10}, %{date: ~D[2024-01-02], value: 25}]
{:ok, applied} = Visualize.Chart.apply(design, sources: %{days: rows})
Visualize.Chart.render(applied)
```

**Start at the gallery.** Every chart in `examples/` — twenty-nine of them, from a bar
chart to a globe — is a design, and each chart's page shows the `Build` calls that make
it, the map they fold to, and the same design on the canvas backends. It is the worked
introduction to the layer; the grammar below is what the layer is built from.

The primitives underneath, for a caller who wants them directly:

```elixir
alias Visualize.{Scale, Shape, IR.Element, Render}

data = [{~D[2024-01-01], 10}, {~D[2024-01-02], 25}, {~D[2024-01-03], 15}]

x = Scale.time() |> Scale.domain([~D[2024-01-01], ~D[2024-01-03]]) |> Scale.range([0, 500])
y = Scale.linear() |> Scale.domain([0, 25]) |> Scale.range([300, 0]) |> Scale.nice()

d =
  Shape.line()
  |> Shape.x(fn {date, _} -> Scale.apply(x, date) end)
  |> Shape.y(fn {_, value} -> Scale.apply(y, value) end)
  |> Shape.curve(:step_after)
  |> Shape.generate(data)

Element.root(500, 300)
|> Element.append(Element.path(d, %{fill: "none", stroke: "steelblue"}))
|> Render.to_svg_string()
```

## Installation

```elixir
def deps do
  [
    {:visualize, git: "git@gitlab.conet.yarina.org:dco-tek/visualize.git", tag: "v0.1.0"},
    {:nx, "~> 0.9"}      # optional: binary canvas encoding and Nx-accelerated paths
  ]
end
```

Pin the tag, not `branch: "main"`: a branch dependency takes whatever `main` happens to be
at fetch time, and two builds of it cannot be told apart. [`CHANGELOG.md`](CHANGELOG.md)
records what each tag changed in the surface and in behaviour, so it is what to read before
moving the pin. This is pre-1.0 — a breaking change opens `0.2.0` rather than bending the
meaning of a patch.

Phoenix is optional too: `phoenix_live_view` is declared `optional: true`, so a host that
has LiveView compiles `Visualize.Components` and `Visualize.Components.Tree`, and one that
does not never fetches Phoenix.

## Documentation

- [`spec/`](spec/README.md) is the specification and the source of truth. Every public
  function has a contract row there.
- [`API_SURFACE.md`](API_SURFACE.md) is generated from the spec and the code and gated in
  CI, so the two cannot disagree silently.
- [`usage-rules.md`](usage-rules.md) is the short form for contributors and agents.
- [`CHANGELOG.md`](CHANGELOG.md) records what each tag changed, for a consumer deciding
  which one to pin.
- `dev_docs/liveview_plotting_strategies.md` is the research essay behind the
  performance design; it describes strategies, not all of which are built.
- `examples/` is a Phoenix gallery of every chart type, every one a design with its
  `Build` calls beside it — the place to start: `cd examples && ./run.sh`, which
  serves <http://127.0.0.1:4080>. `./run.sh <ip>:<port>` binds elsewhere;
  `./run.sh 0.0.0.0:4020` reaches it from another machine, at the cost of exposing an
  unauthenticated development server to whatever can route to it.

Run `mix docs` for ExDoc output with the specification as extras.
