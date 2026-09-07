# Visualize

Server-side visualization for Elixir and Phoenix LiveView, in the shape of D3: scales,
shapes, axes, layouts, geographic projections and colour, producing SVG (or canvas
command streams and a binary transfer format) from plain Elixir data.

SVG is generated on the server and diffed by LiveView, so it suits charts of up to about
a thousand data points. Denser data goes through the canvas backends or is reduced to
panel resolution first; `spec/00-prior-art.md` explains the constraints.

## Example

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
    {:visualize, git: "git@gitlab.conet.yarina.org:dco-tek/visualize.git", branch: "main"},
    {:nx, "~> 0.9"}      # optional: binary canvas encoding and Nx-accelerated paths
  ]
end
```

Phoenix is optional too: `phoenix_live_view` is declared `optional: true`, so a host that
has LiveView compiles `Visualize.Components` and `Visualize.Components.Tree`, and one that
does not never fetches Phoenix.

## Documentation

- [`spec/`](spec/README.md) is the specification and the source of truth. Every public
  function has a contract row there.
- [`API_SURFACE.md`](API_SURFACE.md) is generated from the spec and the code and gated in
  CI, so the two cannot disagree silently.
- [`usage-rules.md`](usage-rules.md) is the short form for contributors and agents.
- `dev_docs/liveview_plotting_strategies.md` is the research essay behind the
  performance design; it describes strategies, not all of which are built.
- `examples/` is a Phoenix gallery of every chart type: `cd examples && ./run.sh`.

Run `mix docs` for ExDoc output with the specification as extras.
