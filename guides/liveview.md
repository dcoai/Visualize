# LiveView

This guide is about putting charts on LiveView pages. It covers the JavaScript hooks and
how to install them, which rendering backend to choose, charts over live and streaming
data, and the interaction hooks. It assumes you have read
[Getting started](getting_started.md) and can build and apply a design.

The contracts behind this guide are in the specification. Spec 10 covers the components
and hooks, spec 09 the backends, and spec 14 §12 the compiled chart. Each section below
says where to look.

## Components or designs

`Visualize.Components` and `Visualize.Components.Tree` are function components for the
common chart types: `<.line_chart data={@rows} x={& &1.date} y={& &1.value} />`. They
render SVG and need no hooks. Their assigns are listed in
[spec/10 §2–3](../spec/10-liveview-integration.md).

Anything else is a design. You apply it, render it to a string, and put the string in the
template with `Phoenix.HTML.raw/1`, as [Getting started](getting_started.md) shows. The
rest of this guide is about designs.

## Installing the hooks

The hooks are JavaScript, but the library does not ship a JavaScript package. The
complete source is a string that `Visualize.Hooks.js_code/0` returns, and
`Visualize.Hooks.install!/0` writes it to `assets/js/visualize_hooks.js` in your project:

<!-- compile only: writes into the host's assets/js directory -->
```elixir
{:ok, "assets/js/visualize_hooks.js"} = Visualize.Hooks.install!()
```

Run it from your project's root, in `iex -S mix` or as `mix run -e
'Visualize.Hooks.install!()'`. Run it again after you upgrade visualize, so the hooks
match the server code, and commit the file like any other asset.

The file is one ES module whose default export holds all the hooks. Register them in
`assets/js/app.js`:

```javascript
import VisualizeHooks from "./visualize_hooks"

let liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: {...VisualizeHooks, ...MyHooks}
})
```

Register the library's hooks whole, and give any hook of your own a name of its own. If
your hook reused a library name such as `CanvasBinaryChart`, it would replace the
library's hook, and that hook would stop matching what the server sends
([spec/10 §9.2](../spec/10-liveview-integration.md)).

You can also skip the file and serve the module from a controller, as the gallery in
`examples/` does. It sends `Visualize.Hooks.js_code()` with the content type
`text/javascript`, so the hooks always match the running server.

`js_code/0` contains these hooks:

| Hook | Use it for |
|---|---|
| `CanvasChart` | Canvas commands as JSON or JavaScript |
| `CanvasBinaryChart` | the binary canvas stream |
| `CanvasIncrementalChart` | a scrolling canvas that redraws only the new strip |
| `ResizeHook` | telling the server the container's size |
| `TooltipHook`, `CrosshairHook`, `LegendHook` | hover and legend interaction |
| `BrushHook`, `ZoomHook` | selecting a range, and zoom and pan |
| `BuilderHook` | the chart builder (a work in progress) |

## Choosing a backend

Every backend draws the same design. The design never says how it is drawn: you choose
when you render. Start with SVG and move only when you have a reason to.

```elixir
import Visualize.Chart.Build

{:ok, design} =
  Visualize.Chart.compose([
    chart(meta: %{name: "A sine wave"}),
    source(:points, [:t, :v]),
    cartesian(margin: %{top: 10, right: 20, bottom: 30, left: 40}),
    linear_scale(:x),
    linear_scale(:y, domain: [0, :auto]),
    axis(:x, :bottom),
    axis(:y, :left),
    line(:points, %{x: :t, y: :v})
  ])

rows = for t <- 0..99, do: %{t: t, v: 50 + 40 * :math.sin(t / 8)}
{:ok, applied} = Visualize.Chart.apply(design, sources: %{points: rows}, size: {600, 300})
```

**SVG** is the default and the right choice for most charts. The chart is markup, so CSS
can style it and screen readers can name it. Each element can carry data for a tooltip.
When it is re-rendered, LiveView sends only what changed. SVG slows down once a chart has
more than about a thousand elements on screen.

```elixir
svg = Visualize.Chart.render(applied, root: true)
```

**Canvas** draws the same chart as Canvas 2D commands. Use the JSON form with the
`CanvasChart` hook. It suits a chart with many elements that change little.

```elixir
json = Visualize.Chart.render(applied, backend: :canvas, format: :json)
```

```heex
<div id="canvas-chart" phx-hook="CanvasChart" phx-update="ignore" data-commands={@json}>
  <canvas width="600" height="300"></canvas>
</div>
```

**Binary canvas** is a compact byte stream of the same drawing, base64-encoded. The
`CanvasBinaryChart` hook reads it. It is the smallest form for dense data, and it needs
the optional `nx` dependency. The stream carries no text, so axis labels are lost when
the whole chart goes this way. Use the hybrid split below to keep them.

```elixir
binary = Visualize.Chart.render(applied, backend: :canvas, format: :binary_base64)
```

**Hybrid** draws the axes, grid, legend and labels once as SVG, and only the marks on a
canvas beneath them. That is what a compiled chart does, and the next section shows how.
Use it for dense data that changes often.

**Incremental** is hybrid for a chart that scrolls. When the window moves, the canvas
shifts the pixels it already has and draws only the newly exposed strip. Use it for a
streaming time series.

The backends are specified in [spec/09](../spec/09-rendering-backends.md), and the split
in [spec/14 §12.3–12.4](../spec/14-declarative-chart.md).

## Live data with a compiled chart

Re-rendering a whole chart on every update is fine a few times a second. For more,
compile it. `Visualize.Chart.compile/2` validates the design once and draws everything
that does not depend on the data once. Then each update draws only the parts that move.

The result is one compiled chart per frame, by name. A design with one frame gives a map
with one entry, `:main`:

```elixir
{:ok, %{main: compiled}} = Visualize.Chart.compile(applied)

static = Visualize.Chart.Compiled.static(compiled)
{tick, compiled} = Visualize.Chart.Compiled.tick(compiled, %{points: rows})

tick |> Map.keys() |> Enum.sort()
#=> [:backdrop, :bytes, :canvas, :canvas_format, :incremental, :svg]
```

`static/1` is the furniture as an SVG document. It is rendered once and is the same on
every tick. `tick/2` returns the tick's payload and the compiled chart to keep for the
next tick. In the payload, `canvas` is the marks for the canvas layer, `svg` is the SVG
that moves, and `bytes` is how much the tick sends.

Each mark goes to SVG or to the canvas by how many points it draws. Up to the `ceiling:`
option of `compile/2`, 1,000 by default, it stays SVG. Above it, it goes to the binary
canvas. A mark's `render:` option (`:svg`, `:canvas` or `:binary`) overrides the count:

```elixir
{:ok, %{main: compiled}} = Visualize.Chart.compile(applied, ceiling: 10)
Visualize.Chart.Compiled.targets(compiled)
#=> [binary: 100]
```

On the page, the canvas sits under the static SVG and the tick's SVG sits on top. The
SVG layers take no pointer events, so the canvas hook below them still receives them:

<!-- compile only: a LiveView needs an endpoint and a socket -->
```elixir
defmodule MyAppWeb.LiveChart do
  use Phoenix.LiveView
  import Visualize.Chart.Build

  @size {600, 300}

  defp design do
    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Live points"}),
        source(:points, [:t, :v]),
        cartesian(margin: %{top: 10, right: 20, bottom: 30, left: 40}),
        linear_scale(:x),
        linear_scale(:y, domain: [0, :auto]),
        axis(:x, :bottom),
        axis(:y, :left),
        line(:points, %{x: :t, y: :v}, render: :binary)
      ])

    design
  end

  def mount(_params, _session, socket) do
    rows = []
    {:ok, applied} = Visualize.Chart.apply(design(), sources: %{points: rows}, size: @size)
    {:ok, %{main: compiled}} = Visualize.Chart.compile(applied)
    {tick, compiled} = Visualize.Chart.Compiled.tick(compiled, %{points: rows})

    if connected?(socket), do: :timer.send_interval(100, :tick)

    {:ok,
     assign(socket,
       rows: rows,
       compiled: compiled,
       static: Visualize.Chart.Compiled.static(compiled),
       tick: tick,
       size: @size
     )}
  end

  def handle_info(:tick, socket) do
    t = System.monotonic_time(:millisecond)
    # Keep the last 2,000 points: the rows a page holds should stay bounded.
    rows = Enum.take(socket.assigns.rows ++ [%{t: t, v: :rand.uniform(100)}], -2000)
    {tick, compiled} = Visualize.Chart.Compiled.tick(socket.assigns.compiled, %{points: rows})

    {:noreply,
     socket
     |> assign(rows: rows, compiled: compiled, tick: tick)
     |> push_event("canvas_update", %{binary: tick.canvas})}
  end

  def render(assigns) do
    ~H"""
    <div style={"position: relative; width: #{elem(@size, 0)}px; height: #{elem(@size, 1)}px"}>
      <div
        id="live-chart-canvas"
        phx-hook="CanvasBinaryChart"
        phx-update="ignore"
        data-binary={@tick.canvas}
        data-width={elem(@size, 0)}
        data-height={elem(@size, 1)}
        style="position: absolute; top: 0; left: 0"
      >
        <canvas width={elem(@size, 0)} height={elem(@size, 1)}></canvas>
      </div>
      <div style="position: absolute; top: 0; left: 0; pointer-events: none">
        {Phoenix.HTML.raw(@static)}
      </div>
      <div style="position: absolute; top: 0; left: 0; pointer-events: none">
        {Phoenix.HTML.raw(@tick.svg)}
      </div>
    </div>
    """
  end
end
```

The canvas element has `phx-update="ignore"`, so LiveView never patches it. New frames
reach it as `canvas_update` events. The `y` axis here is inferred from the data, so it
moves, and it arrives in `tick.svg` each time.

### Scrolling: the viewport

A frame's `viewport` makes a streaming window. The named scale shows the last `span` of
its domain, ending at the newest value in the data. For a time scale the span is in
seconds. When the marks are on the binary canvas, each tick returns an `incremental`
payload instead of a whole `canvas`:

```elixir
{:ok, streaming} =
  Visualize.Chart.compose([
    chart(meta: %{name: "Streaming samples"}),
    source(:samples, [:t, :v]),
    cartesian(
      margin: %{top: 10, right: 20, bottom: 30, left: 40},
      viewport: %{scale: :x, span: 200}
    ),
    linear_scale(:x),
    linear_scale(:y, domain: [-1, 1]),
    axis(:x, :bottom),
    axis(:y, :left),
    line(:samples, %{x: :t, y: :v}, render: :binary)
  ])

samples = for t <- 0..400, do: %{t: t, v: :math.sin(t / 20)}

{:ok, %{main: window}} =
  Visualize.Chart.compile(streaming, sources: %{samples: samples}, size: {600, 300})

{first, window} = Visualize.Chart.Compiled.tick(window, %{samples: samples})
first.incremental.mode
#=> "full"

more = samples ++ for t <- 401..410, do: %{t: t, v: :math.sin(t / 20)}
{next, _window} = Visualize.Chart.Compiled.tick(window, %{samples: more})
next.incremental.mode
#=> "scroll_x"
```

Push `tick.incremental` as the `canvas_incremental` event to an element with the
`CanvasIncrementalChart` hook. That canvas is the plot area only. Size it to
`compiled.plot` and place it at the frame's margins, `compiled.margin.left` and
`compiled.margin.top`. The first payload is a full redraw, and so is any jump of half
the plot or more. A tick where the window did not move is `"none"`, which you can skip
pushing.

The window ends at the newest `x` in the data, unless you pass `now:` to `tick/3`. Pass
it when a clock should drive the window rather than the data.

### Data rate and frame rate

How often data arrives and how often you draw are two separate things. Keep them apart:

- Append samples to the rows as they arrive, from PubSub or a GenServer. Do not draw.
- Draw on a timer at the frame rate you want, ticking the compiled chart with the rows
  you hold at that moment.

A burst of samples then costs one frame, not one per sample. A quiet source still lets
the window move if you tick with `now:`. Drop rows that have left the window, so the
rows you hold stay bounded.

If frames arrive faster than the browser can draw them, they queue up in the browser.
The canvas hooks can acknowledge what they have drawn. Add `data-ack="frame_drawn"` to
the element, put a `seq` number in each payload, and handle the `frame_drawn` event. Its
`seq` tells you how far behind the browser is, and you can skip frames until it catches
up ([spec/10 §9.2](../spec/10-liveview-integration.md)).

### Scale transitions

A scale with a `transition` eases to a new domain instead of jumping to it. The frames
in between are drawn by the ticks you send. The `at:` option gives the clock in
milliseconds, and defaults to the system's monotonic clock:

```elixir
{:ok, eased} =
  Visualize.Chart.compose([
    chart(meta: %{name: "Easing"}),
    source(:points, [:t, :v]),
    cartesian(),
    linear_scale(:x),
    linear_scale(:y, domain: [0, :auto], transition: %{duration: 300}),
    line(:points, %{x: :t, y: :v})
  ])

{:ok, %{main: easing}} = Visualize.Chart.compile(eased, sources: %{points: rows})

{_group, easing} = Visualize.Chart.Compiled.step(easing, %{points: rows}, at: 0)
taller = Enum.map(rows, &%{&1 | v: &1.v * 2})
{_halfway, _easing} = Visualize.Chart.Compiled.step(easing, %{points: taller}, at: 150)
```

`step/3` returns the frame's SVG group as an element, for an all-SVG chart. `tick/3`
takes the same `at:` option. A mark can take a `transition` too, so that a gauge's
needle sweeps to a new reading ([spec/14 §12.5](../spec/14-declarative-chart.md)).

### Following the container's size

A design has no size. To fit the chart to its container, put `ResizeHook` on the
container. It pushes `resize` with the width and height each time the size settles.
Apply again at the new size, or compile again for a compiled chart.
`Visualize.Chart.Compiled.carry/2` keeps a running transition going across that
recompile. Usually you take the width and keep your own aspect ratio, because a
container's height often depends on its content:

<!-- compile only: an event handler needs a socket -->
```elixir
def handle_event("resize", %{"width" => width}, socket) do
  {:noreply, assign(socket, size: {width, round(width * 0.5)})}
end
```

```heex
<div id="chart-box" phx-hook="ResizeHook">{Phoenix.HTML.raw(@svg)}</div>
```

## Interaction

The interaction hooks read data attributes that the server writes into the markup.
Hovering never goes back to the server. A hook pushes an event only when you ask it to.
The gallery's `/interaction` page shows the tooltip, crosshair and legend hooks working.

### Tooltips

Give a mark a `tooltip` and each element it draws carries its row's fields. Put
`TooltipHook` on any element around the chart:

```elixir
{:ok, with_tooltips} =
  Visualize.Chart.compose([
    chart(meta: %{name: "Points with tooltips"}),
    source(:points, [:t, :v]),
    cartesian(),
    linear_scale(:x),
    linear_scale(:y),
    circle(:points, %{x: :t, y: :v},
      tooltip: %{fields: [:t, :v], template: "t = {t}\nv = {v}", event: :point_click}
    )
  ])

{:ok, tooltip_chart} = Visualize.Chart.apply(with_tooltips, sources: %{points: rows})
Visualize.Chart.render(tooltip_chart, root: true) =~ ~s(data-datum="t v")
#=> true
```

```heex
<div id="tooltip-chart" phx-hook="TooltipHook">{Phoenix.HTML.raw(@svg)}</div>
```

With `event:`, a click on a point pushes that event with the fields as strings, here
`handle_event("point_click", %{"t" => "4", "v" => "..."}, socket)`.

### Crosshair

`CrosshairHook` snaps a vertical rule, and a marker per series, to the nearest `x`. It
works over SVG and over a canvas alike, because the server writes the mark's pixel
positions once as attributes:

```elixir
crosshair = Visualize.Hooks.Crosshair.attrs(applied.frame, applied.sources)
Map.keys(crosshair)
#=> ["data-plot", "data-size", "data-xs", "data-ys"]
```

```heex
<div id="crosshair-chart" phx-hook="CrosshairHook" {@crosshair} data-crosshair-event="hover">
  {Phoenix.HTML.raw(@svg)}
</div>
```

With `data-crosshair-event` set, the hook pushes `hover` with the row index when the
nearest point changes.

### Legend toggle

A frame's legend and the elements a series draws carry the same `data-series` value. That
needs a `series` channel on every mark of the series. With `LegendHook` around the chart,
a click on a legend entry hides or shows that series. Set `data-legend-event` to be told
about it:

```heex
<div id="legend-chart" phx-hook="LegendHook" data-legend-event="legend_toggle">
  {Phoenix.HTML.raw(@svg)}
</div>
```

### Brush and zoom

`BrushHook` lets the user drag out a range. On release it pushes `brush_select` with the
selection in SVG coordinates, and `brush_clear` when it is cleared. The plot starts at
the frame's left margin, so take that off before you convert the pixels to data values:

```elixir
x_scale = Visualize.Chart.Frame.scale(applied.frame, :x)
left = applied.frame.margin.left

selection = %{x0: 100 - left, x1: 300 - left}
{from, to} = Visualize.Hooks.Brush.selection_to_domain(selection, x_scale: x_scale)
from < to
#=> true
```

```heex
<div id="brush-chart" phx-hook="BrushHook" data-brush-type="x">{Phoenix.HTML.raw(@svg)}</div>
```

The event's keys are strings (`%{"x0" => x0, "x1" => x1, ...}`), so build the atom-keyed
selection from them as above. `Visualize.Hooks.Brush.filter_selection/3` returns the rows
inside a selection instead of its domain.

`ZoomHook` applies zoom and pan to a group inside an SVG on the client, and pushes `zoom`
with the transform. The helpers in `Visualize.Hooks.Zoom` do the same arithmetic on the
server ([spec/10 §5–6](../spec/10-liveview-integration.md)).

### Sync groups

Charts that share a time or linear `x` can share hover and brushing. Give each design
the same group:

```elixir
Visualize.Chart.Build.interaction(sync: "dashboard")
#=> %{interaction: %{sync: "dashboard"}}
```

Compose that fragment into each design. Pointing at one chart then moves the crosshair
and tooltip on every chart in the group. A brush on one shows as a band on all of them.
Only the chart under the pointer talks to its server. In a group, `brush_select` also
carries `domain: [lo, hi]` in data units, so you do not need the conversion above. The
`/dashboard` page of the gallery shows three synced panels
([spec/10 §4.3](../spec/10-liveview-integration.md)).

## PNG export

`Visualize.Render.to_png/2` rasterises a chart through the resvg binary, if the host has
it. Generate the chart with `resolve: :literal` first. To offer a download from a
LiveView, render the PNG in an event handler and send it with `push_event/3` to a small
hook of your own, or serve it from a controller with `send_download/3`:

<!-- compile only: a controller action needs a conn -->
```elixir
def png(conn, _params) do
  {:ok, applied} = MyApp.Charts.daily_total()
  root = Visualize.Chart.generate(applied, root: true, resolve: :literal)
  png = Visualize.Render.to_png!(root, scale: 2, background: "#ffffff")
  send_download(conn, {:binary, png}, filename: "daily_total.png")
end
```

The options, the errors and the font settings are in `Visualize.Render.to_png/2` and
[spec/09 §9](../spec/09-rendering-backends.md).
