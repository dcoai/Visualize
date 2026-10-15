defmodule Visualize.Chart.Compiled do
  @moduledoc """
  A design compiled for rendering per tick (spec/14 §12, D-66).

  `Visualize.Chart.compile/2` is the only constructor. The frame's drawing order is a list
  of *regions* — the grid, each mark, each axis, the legend, the labels, or a facet's
  panels — and each is static, drawn once here in `:css` mode and byte for byte the same
  on every tick, or dynamic, drawn per tick by its closure over the frame realised for the
  tick's sources: a mark is always dynamic, a facet's panels are, and anything else is
  dynamic exactly when it reads a scale whose domain moves — inferred (`:auto`) or
  windowed by a `viewport`. `regions/1` and `dynamic_regions/1` report the split and why.

  The render target of each mark is decided once, at compilation, from the rows it draws
  over the binding (`targets/1`): `:svg` at or below the ceiling, the binary path above
  it. `render/2` is the hybrid chart map of `Visualize.Backend.Hybrid` with `dynamic_svg`
  added for the SVG layer's moving part and `backdrop` for the layer beneath the canvas;
  `static/1` is the static SVG string and `backdrop/1` the static backdrop; `tick/3` is
  the per-tick payload, and for a design with a viewport it slides the canvas layer
  through `Visualize.Incremental`, whose state the struct carries. `svg/2` is the
  one-string form, the frame's own group, equal to `Visualize.Chart.Frame.render/2` when
  every mark targets `:svg`.

  A `:force` step is warm here (spec/14 §12.5, D-132): the struct carries each graph's
  last layout, every node's position and velocity by id, and `tick/3` and `step/3` move
  the graph on from it — reheated to the step's `alpha` for at most its `ticks`
  iterations — where `Visualize.Chart.render/2` lays it out cold every time. The marks of
  one graph share that one run, and `carry/2` carries the layout across a recompilation.

  ## Examples

      iex> design = %{
      ...>   version: 2,
      ...>   sources: %{primary: %{fields: [:t, :v]}},
      ...>   frames: %{main: %{
      ...>     kind: :cartesian,
      ...>     scales: %{x: %{kind: :linear, domain: [0, 10]}, y: %{kind: :linear}},
      ...>     axes: [%{scale: :x, side: :bottom}, %{scale: :y, side: :left, grid: true}]
      ...>   }},
      ...>   marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v}}]
      ...> }
      iex> {:ok, %{main: compiled}} = Visualize.Chart.compile(design, sources: %{primary: %{t: [1, 2], v: [3, 9]}})
      iex> Visualize.Chart.Compiled.dynamic_regions(compiled)
      [{:grid, {:inferred, [:y]}}, {{:mark, 0}, :data}, {{:axis, 1}, {:inferred, [:y]}}]
      iex> Visualize.Chart.Compiled.targets(compiled)
      [{:svg, 2}]

  """

  alias Visualize.Backend.{CanvasBinary, Hybrid}
  alias Visualize.{Chart, Render, Theme}
  alias Visualize.Chart.{Applied, Frame, Mark}
  alias Visualize.Chart.Compiled.{Motion, Regions, Transition, Window}
  alias Visualize.Chart.Frame.{Defs, Furniture, Scales}
  alias Visualize.Chart.Frame.Motion, as: FrameMotion
  alias Visualize.Chart.Transform.Force
  alias Visualize.Data.Delivery
  alias Visualize.IR.{Element, Transform}

  @default_ceiling 1000

  @enforce_keys [:chart, :theme, :layout, :regions, :targets, :ceiling]
  defstruct [
    :chart,
    :theme,
    :layout,
    :regions,
    :targets,
    :ceiling,
    :static,
    :size,
    :margin,
    :plot,
    :box,
    :viewport,
    :generated,
    motion: :full,
    system: :as_posted,
    backdrop: "",
    defs: [],
    transitions: %{},
    eased: %{},
    motions: %{},
    moving: %{},
    forces: %{},
    schemas: %{},
    versions: %{}
  ]

  @typedoc "A render target of spec/14 §12.3."
  @type target :: :svg | :canvas | :binary

  @typedoc "A region of spec/14 §12.2: the grid, a mark, an axis, the legend, the labels, a facet's panels."
  @type region ::
          :grid
          | {:grid, :outer}
          | {:mark, non_neg_integer()}
          | {:axis, non_neg_integer()}
          | :legend
          | :labels
          | :panels

  @typedoc "Why a region is dynamic (spec/14 §12.2)."
  @type reason :: :data | :facet | {:inferred, [atom()]}

  @typedoc "The frame's drawing order: regions, and a centred group of regions in a polar frame."
  @type layout :: [region() | {:centered, [region()]}]

  @typedoc """
  The warm force layouts of spec/14 §12.5 (D-132): per graph, each node's position and
  velocity by id.
  """
  @type forces :: %{
          term() => %{term() => %{x: number(), y: number(), vx: number(), vy: number()}}
        }

  @typedoc "The per-tick payload of spec/14 §12.4."
  @type payload :: %{
          svg: String.t(),
          backdrop: String.t(),
          canvas: String.t(),
          canvas_format: :binary_base64 | :json,
          incremental: map() | nil,
          bytes: non_neg_integer()
        }

  @type t :: %__MODULE__{
          chart: Chart.t(),
          theme: Theme.t(),
          layout: layout(),
          regions: [map()],
          targets: [{target(), non_neg_integer()}],
          ceiling: pos_integer(),
          static: String.t(),
          backdrop: String.t(),
          defs: [Element.t()],
          margin: %{top: number(), right: number(), bottom: number(), left: number()},
          plot: %{width: number(), height: number()},
          box: %{x: number(), y: number(), width: number(), height: number()},
          viewport: map() | nil,
          motion: :full | :reduce,
          system: Visualize.Quantity.system(),
          generated: struct() | nil,
          transitions: %{atom() => map()},
          eased: %{atom() => map()},
          motions: %{non_neg_integer() => map()},
          moving: %{non_neg_integer() => map()},
          forces: forces(),
          schemas: %{atom() => Visualize.Data.Schema.t()},
          versions: %{atom() => String.t() | nil}
        }

  @doc false
  # One frame of an applied chart, compiled (spec/14 §12.1, #385);
  # `Visualize.Chart.compile/2` calls it once per frame.
  #
  # Everything below reads `chart`, which is the design **restricted to this frame** — its
  # `frames` the one frame, its `marks` and `labels` the ones that say it — so the regions,
  # the window and the transitions never ask how many frames a design has.
  @spec new(Applied.t(), atom(), keyword()) :: t()
  def new(%Applied{sources: sources} = applied, name, opts) do
    frame = frame!(applied, name)
    chart = restrict(applied.chart, frame)
    ceiling = ceiling!(Keyword.get(opts, :ceiling, @default_ceiling))
    motion = motion!(Keyword.get(opts, :motion, :full))
    window = Window.new(chart)
    {layout, regions} = Regions.build(chart, window && window.scale)
    frame = window_frame(window, chart, frame, sources, nil)

    regions =
      Enum.map(regions, fn
        %{status: :static, build: build} = region ->
          %{region | static: build.(frame, sources, :css)}

        region ->
          region
      end)

    targets = targets(chart, frame, sources, ceiling)

    compiled = %__MODULE__{
      chart: chart,
      theme: frame.theme,
      system: frame.system,
      # The generators every tick's frame calls (spec/14 §3.13): the applied frame's.
      generated: frame.generated,
      layout: layout,
      regions: regions,
      targets: targets,
      ceiling: ceiling,
      motion: motion,
      size: frame.size,
      margin: frame.margin,
      plot: frame.plot,
      box: box(frame),
      viewport: window && Map.put(window, :full, stale?(chart, window.scale, targets)),
      transitions: Transition.scales(chart, window && window.scale),
      motions: Motion.marks(chart),
      # The layout the chart is compiled over, cold, is where the first tick starts from
      # (spec/14 §12.5, D-132).
      forces: Force.warm(frame.forces),
      # The schema versions its facts were read from: another one recompiles (§12.1).
      versions: applied.versions,
      # The slots' schemas, whose declared identity a `latest` step reads (D-168).
      schemas: frame.schemas
    }

    # The design's defs go first in the static layer (spec/14 §12.4, #356): the gradients
    # it declares and the filters any mark's effect needs, found over every mark rendered
    # once in `:css` here, so a `url(#id)` on either SVG layer resolves on the page.
    drawn = drawn(compiled, frame, sources, nil, true)
    static = layer(compiled, drawn, :static, false)

    defs =
      Defs.defs(frame, :css, Element.group(static ++ all_marks(compiled, frame, sources)),
        all: true
      )

    compiled = %{compiled | defs: defs}

    %{
      compiled
      | static: root(compiled, defs ++ static),
        backdrop: static_backdrop(compiled, drawn)
    }
  end

  # The static regions' backdrop — a basemap's images, drawn once (spec/14 §12.3, #476).
  defp static_backdrop(compiled, drawn),
    do: fragment(compiled, layer(compiled, drawn, :static_backdrop, false))

  # The realised frame of this name; an `%Applied{}` assembled by hand carries one frame
  # and no `frames`, as `Visualize.Chart.generate/2` reads it.
  defp frame!(%Applied{frames: frames, frame: frame}, name) do
    case frames do
      %{^name => realised} -> realised
      _absent -> frame
    end
  end

  # The design this plot draws: the one frame, and the marks and labels that say it — which
  # the realised frame already holds, filtered (spec/14 §4.7, §5.1).
  defp restrict(%Chart{} = chart, %Frame{name: name} = frame) do
    node = Map.get(chart.frames, name) || chart.frames |> Map.values() |> hd()

    %{
      chart
      | frames: %{name => resolved(node, chart, frame.domains)},
        marks: frame.marks,
        labels: frame.labels
    }
  end

  # A scale adopted from another frame becomes that frame's node, and **every scale the
  # application resolved a domain for — the adopters' and the owner's — is fixed at it**
  # (spec/14 §4.3, §12.1, #384). This chart then holds one frame and reaches for no
  # other, and the shared domain cannot drift: a compiled chart is compiled over a
  # binding, and the other frames' rows are not in it to be read again.
  defp resolved(node, chart, domains) do
    case Map.get(node, :scales) do
      scales when is_map(scales) ->
        Map.put(node, :scales, Map.new(scales, &scale(&1, chart, domains)))

      _absent ->
        node
    end
  end

  defp scale({name, entry}, chart, domains) do
    node = Scales.node(entry, chart)

    case Map.fetch(domains, name) do
      {:ok, extent} -> {name, Map.put(node, :domain, extent)}
      :error -> {name, node}
    end
  end

  # The frame's own pixel box within the render's size (spec/14 §4.2): where a page puts
  # this plot's canvas, and what its static document is translated by.
  defp box(%Frame{box: [x, y, w, h], size: size}) do
    %{x: x * size.width, y: y * size.height, width: w * size.width, height: h * size.height}
  end

  defp all_marks(%{regions: regions}, frame, sources) do
    Enum.flat_map(regions, fn
      %{region: {:mark, _}, build: build} -> build.(frame, sources, :css)
      _other -> []
    end)
  end

  @doc "Every region in the frame's drawing order, `{region, :static | {:dynamic, reason}}`."
  @spec regions(t()) :: [{region(), :static | {:dynamic, reason()}}]
  def regions(%__MODULE__{regions: regions}), do: Enum.map(regions, &{&1.region, &1.status})

  @doc "The dynamic regions alone, `{region, reason}` (spec/14 §12.2)."
  @spec dynamic_regions(t()) :: [{region(), reason()}]
  def dynamic_regions(%__MODULE__{regions: regions}) do
    for %{status: {:dynamic, reason}} = region <- regions, do: {region.region, reason}
  end

  @doc "`{target, points}` per mark in design order (spec/14 §12.3)."
  @spec targets(t()) :: [{target(), non_neg_integer()}]
  def targets(%__MODULE__{targets: targets}), do: targets

  @doc """
  A freshly compiled chart carrying the easing of the one it replaces (spec/14 §12.5,
  #434).

  A compiled chart's `plot` is part of its state, so a chart drawn at a new size is a new
  compilation — and a scale that was mid-transition when the size changed should go on
  from where it stood rather than jump back to its target. The eased scale states and the
  mark motions of `previous` are kept for the scales and marks `fresh` still has, and so is
  its warm force layout for each graph `fresh` still has (D-132): a caller that compiles
  again because a tick's marks differ keeps the graph where it stood. Anything else is
  dropped, since a state for a scale the design no longer eases, or for a graph it no
  longer draws, would never be read again.

      iex> design = %{version: 2, sources: %{s: %{fields: [:t, :v]}},
      ...>   frames: %{main: %{kind: :cartesian, scales: %{
      ...>     x: %{kind: :linear, domain: [0, 10]},
      ...>     y: %{kind: :linear, transition: %{duration: 300}}}}},
      ...>   marks: [%{type: :line, data: :s, channels: %{x: :t, y: :v}}]}
      iex> rows = %{s: [%{t: 1, v: 3}, %{t: 2, v: 9}]}
      iex> {:ok, %{main: first}} = Visualize.Chart.compile(design, sources: rows)
      iex> {_group, first} = Visualize.Chart.Compiled.step(first, rows, at: 0)
      iex> {:ok, %{main: wider}} = Visualize.Chart.compile(design, sources: rows, size: {900, 400})
      iex> Visualize.Chart.Compiled.carry(first, wider).eased == first.eased
      true
  """
  @spec carry(t(), t()) :: t()
  def carry(%__MODULE__{} = previous, %__MODULE__{} = fresh) do
    %{
      fresh
      | eased: Map.take(previous.eased, Map.keys(fresh.transitions)),
        moving: Map.take(previous.moving, Map.keys(fresh.motions)),
        forces: Map.merge(fresh.forces, Map.take(previous.forces, Map.keys(fresh.forces)))
    }
  end

  @doc "The static SVG string, rendered once at compilation (spec/14 §12.4)."
  @spec static(t()) :: String.t()
  def static(%__MODULE__{static: static}), do: static

  @doc """
  The static backdrop (spec/14 §12.3, §12.4, #476, D-120): a static `:tiles` mark's
  images as one SVG root of the shape of `static/1`, rendered once at compilation, or
  `""` when there are none. A page stacks it beneath the canvas, so a dense mark drawn
  there sits over the basemap; the attribution is in `static/1`, over the canvas.
  """
  @spec backdrop(t()) :: String.t()
  def backdrop(%__MODULE__{backdrop: backdrop}), do: backdrop

  @doc """
  The hybrid chart map over the sources by slot name (spec/14 §12.4): `width`, `height`,
  `margin`, `static`, `dynamic`, `dynamic_style`, `canvas_format`, `dynamic_svg` and
  `backdrop`, the layer beneath the canvas (a basemap's images, #476).

  Raises `ArgumentError` as `Visualize.Chart.Frame.new/2` does for a value a scale
  cannot take.
  """
  @spec render(t(), map()) :: map()
  def render(%__MODULE__{} = compiled, sources) when is_map(sources) do
    sources = sources!(compiled, sources)
    {frame, hi} = realize(compiled, sources, nil)
    drawn = drawn(compiled, frame, sources, hi, true)
    canvas = layer(compiled, drawn, :canvas, false)

    %{
      width: compiled.size.width,
      height: compiled.size.height,
      margin: compiled.margin,
      static: moving(compiled.defs ++ layer(compiled, drawn, :static, false)),
      dynamic: if(canvas == [], do: nil, else: canvas),
      dynamic_style: %{},
      canvas_format: format(compiled),
      dynamic_svg: moving(layer(compiled, drawn, :dynamic_svg, false)),
      backdrop: layer(compiled, drawn, :backdrop, false)
    }
  end

  @doc """
  The one-string form (spec/14 §12.4): the frame's group with the static and the dynamic
  regions in the frame's own order, as SVG; equal to `Visualize.Chart.Frame.render/2`
  when every mark targets `:svg`.
  """
  @spec svg(t(), map()) :: String.t()
  def svg(%__MODULE__{} = compiled, sources) when is_map(sources) do
    sources = sources!(compiled, sources)
    {frame, hi} = realize(compiled, sources, nil)
    children = moving(layer(compiled, drawn(compiled, frame, sources, hi, true), :svg, true))

    Element.group(compiled.defs ++ children,
      style: %{class: "frame"},
      attrs: group_attrs(frame),
      transform: placed(compiled)
    )
    |> Render.to_string(backend: :svg)
  end

  @doc """
  One frame of the one-string form with the state after it (spec/14 §12.5, #360): the
  frame's group of `svg/2` as a `Visualize.IR.Element`, its eased scales at their shown
  domains for this tick, and the compiled chart carrying the easing on. `:now`, `:at`
  and `:motion` as `tick/3` takes them. A caller that wants a page-ready document wraps it in
  `Visualize.IR.Element.root/3`.
  """
  @spec step(t(), map(), keyword()) :: {Element.t(), t()}
  def step(%__MODULE__{} = compiled, sources, opts \\ []) when is_map(sources) do
    sources = sources!(compiled, sources)
    compiled = retarget(compiled, Keyword.get(opts, :frame), sources)
    {frame, hi} = realize(compiled, sources, Keyword.get(opts, :now))
    compiled = %{compiled | forces: Force.warm(frame.forces)}
    {frame, moved, compiled} = ease(compiled, frame, sources, opts)

    children =
      moving(layer(compiled, drawn(compiled, frame, sources, hi, true, moved), :svg, true))

    group =
      Element.group(compiled.defs ++ children,
        style: %{class: "frame"},
        attrs: group_attrs(frame),
        transform: placed(compiled)
      )

    {group, compiled}
  end

  @doc """
  The realised rows of the frame's mark at `index` as a tick over the sources draws it
  (spec/14 §5.7, D-170): the frame realised as `step/3` realises it and a viewport's
  window taken, so a `data-row` ordinal the mark wrote counts in these rows. `[]` for an
  index the frame has no mark at. A mark that eases keeps its rows' positions (§12.5), so
  the rows here are the ones the eased elements stand for, at their own values.
  """
  @spec rows(t(), map(), non_neg_integer()) :: [map()]
  def rows(%__MODULE__{chart: chart} = compiled, sources, index)
      when is_map(sources) and is_integer(index) and index >= 0 do
    case Enum.at(chart.marks, index) do
      nil ->
        []

      mark ->
        sources = sources!(compiled, sources)
        {frame, hi} = realize(compiled, sources, nil)
        Mark.rows(frame, mark, mark_sources(compiled, frame, mark, sources, hi))
    end
  end

  # Where this plot's group sits: its margins, out of its own box (spec/14 §4.2) — the
  # design's own translate for a frame that fills the box, as every single-frame design's
  # does.
  # The tick's node says `{:frame, …}` wherever the design does, and this chart holds one
  # frame: the scale the application resolved is carried over from the node the chart was
  # compiled with, rather than looked up in frames that are not here (spec/14 §4.3, §12.1).
  defp carried(node, current) do
    case Map.get(node, :scales) do
      scales when is_map(scales) ->
        Map.put(node, :scales, Map.new(scales, &carried_scale(&1, current)))

      _absent ->
        node
    end
  end

  defp carried_scale({name, {:frame, _f, _s} = adoption}, current) do
    case get_in(current, [:scales, name]) do
      resolved when is_map(resolved) ->
        {name, resolved}

      _absent ->
        raise ArgumentError,
              "a tick gave a frame carrying #{inspect(adoption)} that the compiled chart " <>
                "does not hold: a scale adopted from another frame is resolved when the " <>
                "design is applied (spec/14 §4.3), so a chart that gains one is compiled " <>
                "again (§12.5)"
    end
  end

  defp carried_scale(pair, _current), do: pair

  # The frame's sync and brush attributes, as the frame's own group carries them (spec/14
  # §2.9, §12.4, D-146): a compiled chart in a group joins its bus from its SVG alone.
  defp group_attrs(frame), do: Map.merge(Frame.sync_attrs(frame), Frame.brush_attrs(frame))

  defp placed(%{margin: margin, box: box}),
    do: Transform.translate(margin.left + box.x, margin.top + box.y)

  # The frame at its eased scales' shown domains, and the chart carrying the states on;
  # nothing to do for a chart with no transition.
  defp ease(%{transitions: transitions, motions: motions} = compiled, frame, _sources, _opts)
       when map_size(transitions) == 0 and map_size(motions) == 0,
       do: {frame, %{}, compiled}

  defp ease(compiled, frame, sources, opts) do
    at = Keyword.get_lazy(opts, :at, fn -> System.monotonic_time(:millisecond) end)
    {transitions, motions} = easings(compiled, Keyword.get(opts, :motion, compiled.motion))
    {frame, eased} = Transition.apply(frame, transitions, compiled.eased, at)
    {moved, moving} = Motion.apply(motions, compiled.moving, sources, at)
    {frame, moved, %{compiled | eased: eased, moving: moving}}
  end

  # The easings of a tick (spec/14 §21.6, D-142): as compiled under `:full`; under
  # `:reduce` each with no duration, so every shown value is its target on the tick it
  # changes while the states — the target, the clock, a pending shrink — run as ever.
  defp easings(%{transitions: transitions, motions: motions}, motion) do
    case motion!(motion) do
      :full ->
        {transitions, motions}

      :reduce ->
        {Map.new(transitions, fn {name, node} -> {name, Map.put(node, :duration, 0)} end),
         Map.new(motions, fn {index, m} -> {index, %{m | node: Map.put(m.node, :duration, 0)}} end)}
    end
  end

  @doc "As `tick/3` with `[]` options."
  @spec tick(t(), map()) :: {payload(), t()}
  def tick(%__MODULE__{} = compiled, sources), do: tick(compiled, sources, [])

  @doc """
  The per-tick payload and the compiled chart holding the tick's state (spec/14 §12.4).

  `svg` is the SVG layer's dynamic regions as one SVG root of the shape of `static/1`
  (`""` when there are none); `backdrop` the dynamic regions' backdrop — a fitted
  basemap's images, for the page to stack beneath the canvas (#476) — in the same shape
  (`""` when there are none); `canvas` the canvas layer through
  `Visualize.Backend.Hybrid.render_dynamic/1` (`""` when there is none, or when the
  layer streams incrementally); `incremental` the `canvas_incremental` payload of
  `Visualize.Incremental` for a design with a viewport and a binary canvas layer
  (spec/14 §12.5), else `nil`; `bytes` the byte size of what the tick transmits.

  ## Options

    * `:now` - the window's upper end for a viewport design; by default the newest
      value the marks bind to the viewport scale
    * `:at` - the clock in milliseconds a scale's transition eases by (spec/14 §12.5);
      by default `System.monotonic_time(:millisecond)`
    * `:frame` - the tick's own frame node (spec/14 §12.5, #424): when it differs from the
      one the chart was compiled with, the frame is re-realised at it and the static
      regions re-rendered, which is what a design animating through its frame needs
    * `:motion` - `:full` or `:reduce` for this tick, by default the compiled chart's
      (spec/14 §21.6, D-142): under `:reduce` every transition and mark motion steps to
      its target instead of easing there
  """
  @spec tick(t(), map(), keyword()) :: {payload(), t()}
  def tick(%__MODULE__{} = compiled, sources, opts) when is_map(sources) do
    sources = sources!(compiled, sources)
    compiled = retarget(compiled, Keyword.get(opts, :frame), sources)
    {frame, hi} = realize(compiled, sources, Keyword.get(opts, :now))
    compiled = %{compiled | forces: Force.warm(frame.forces)}
    {frame, moved, compiled} = ease(compiled, frame, sources, opts)
    format = format(compiled)

    # A scroll tick never builds the whole window (§12.5, #404): where the payload is the
    # incremental one, the canvas-layer marks are drawn for their SVG part alone — their
    # inline labels — and the whole window's geometry is the function below, which
    # `Window.scroll/6` calls in the full-redraw branch and nowhere else.
    scrolling? = compiled.viewport != nil and format == :binary_base64
    drawn = drawn(compiled, frame, sources, hi, not scrolling?, moved)
    svg = fragment(compiled, layer(compiled, drawn, :dynamic_svg, false))
    backdrop = fragment(compiled, layer(compiled, drawn, :dynamic_backdrop, false))

    # A scroll strip is built over the strip's rows and their neighbours (§12.5, D-108).
    strip = fn bounds ->
      layer(compiled, drawn_strip(compiled, frame, sources, hi, bounds), :canvas, false)
    end

    whole = fn ->
      drawn = if scrolling?, do: drawn(compiled, frame, sources, hi, true, moved), else: drawn
      layer(compiled, drawn, :canvas, false)
    end

    {canvas, incremental, window} = canvas(compiled, frame, whole, strip, hi)

    bytes =
      byte_size(svg) + byte_size(backdrop) + byte_size(canvas) +
        if(incremental, do: byte_size(incremental.binary), else: 0)

    payload = %{
      svg: svg,
      backdrop: backdrop,
      canvas: canvas,
      canvas_format: format,
      incremental: incremental,
      bytes: bytes
    }

    # The tick's rows are the tick's: a compiled chart that kept them was 2.1 MB of what
    # a renderer is handed every frame, and nothing ever read them back (#412).
    {payload, %{compiled | viewport: window}}
  end

  # -- per tick -------------------------------------------------------------------------

  @doc """
  Whether a delivery among the sources names a schema version other than the one its
  slot was compiled with (spec/14 §12.1, D-136): the facts the chart read — a label, a
  tick unit, an ordinal domain — may no longer hold, and a schema change recompiles,
  as a resize does. A source that is not a delivery claims no version and is never
  stale. `tick/3`, `step/3`, `render/2` and `svg/2` raise `ArgumentError` for a stale
  delivery; the caller compiles again and `carry/2`s the state across.
  """
  @spec stale?(t(), map()) :: boolean()
  def stale?(%__MODULE__{} = compiled, sources) when is_map(sources),
    do: changed(compiled, sources) != nil

  defp changed(%{versions: versions}, sources) do
    Enum.find_value(sources, fn
      {slot, %Delivery{schema: version}} ->
        compiled = Map.get(versions, slot)
        if version != compiled, do: {slot, compiled, version}

      _plain ->
        nil
    end)
  end

  # The tick's sources as the chart reads them: a delivery is the source it carries
  # (spec/08 §10.4), once it is known to name the schema the chart was compiled with.
  defp sources!(compiled, sources) do
    case changed(compiled, sources) do
      nil ->
        Map.new(sources, fn {name, source} -> {name, Delivery.source(source)} end)

      {slot, compiled_with, delivered} ->
        raise ArgumentError,
              "slot #{inspect(slot)}'s delivery names schema version #{inspect(delivered)}, " <>
                "and the chart was compiled with #{inspect(compiled_with)}: a schema change " <>
                "recompiles (spec/14 §12.1) — compile again and carry/2 the state across"
    end
  end

  # The frame of a tick: realised over the sources, its viewport scale windowed. With the
  # window's upper end given — what a run passes every tick — the scale's domain is known
  # before the frame is built, so it is given rather than inferred over the window's rows
  # and then replaced (spec/14 §4.3, #409).
  defp realize(%{chart: chart, viewport: nil} = compiled, sources, _now) do
    {Frame.new(chart, realize_opts(compiled, sources)), nil}
  end

  defp realize(%{chart: chart, viewport: window} = compiled, sources, now) when now != nil do
    opts = [domains: Window.domains(window, now)] ++ realize_opts(compiled, sources)
    {Frame.new(chart, opts), now}
  end

  defp realize(%{chart: chart, viewport: window} = compiled, sources, now) do
    frame = Frame.new(chart, realize_opts(compiled, sources))
    hi = Window.hi(window, chart, frame, sources, now)
    {window_frame(window, chart, frame, sources, now), hi}
  end

  # The frame the tick gives, when it is not the one the chart was compiled with (spec/14
  # §12.5, #424): the frame is re-realised at it and every static region re-rendered from
  # that realisation, which is what a design animating through its *frame* — a `:geo`
  # projection's rotation, a scale whose range follows the tick — needs in order to move
  # on the canvas backends as it does on SVG.
  #
  # The regions, the targets and the defs are not recomputed: a region's status is
  # structural, a target reads the frame only for its `kind` (§12.3), and the defs are the
  # design's (§12.4). A frame whose *structure* moves is a different chart and the caller
  # compiles it again.
  defp retarget(compiled, nil, _sources), do: compiled

  defp retarget(%{chart: chart} = compiled, node, sources) do
    [{name, current}] = Enum.to_list(chart.frames)
    node = carried(node, current)

    if node == current do
      compiled
    else
      compiled = %{compiled | chart: %{chart | frames: %{name => node}}}
      frame = Frame.new(compiled.chart, realize_opts(compiled, sources))

      regions =
        Enum.map(compiled.regions, fn
          %{status: :static, build: build} = region ->
            %{region | static: build.(frame, sources, :css)}

          region ->
            region
        end)

      compiled = %{
        compiled
        | regions: regions,
          size: frame.size,
          margin: frame.margin,
          plot: frame.plot
      }

      drawn = drawn(compiled, frame, sources, nil, true)
      static = layer(compiled, drawn, :static, false)

      %{
        compiled
        | static: root(compiled, compiled.defs ++ static),
          backdrop: static_backdrop(compiled, drawn)
      }
    end
  end

  # A tick re-realises the frame, and must do it at the size the chart was compiled at
  # (spec/14 §4.2, #427): a design records none, so the compiled chart is where it lives.
  # Its force layouts start from the ones the chart carries (§12.5, D-132).
  defp realize_opts(%{theme: theme, system: system, size: size, forces: forces} = c, sources) do
    [
      sources: sources,
      schemas: c.schemas,
      theme: theme,
      system: system,
      size: {size.width, size.height},
      warm: forces,
      generated: c.generated
    ]
  end

  defp window_frame(nil, _chart, frame, _sources, _now), do: frame

  defp window_frame(window, chart, frame, sources, now) do
    Window.apply(window, frame, Window.hi(window, chart, frame, sources, now))
  end

  # Every region drawn for a tick: `%{region => %{svg: elements, canvas: elements}}`, and
  # a basemap's region its `backdrop` and `over` parts besides.
  # `canvas?` false draws a canvas-layer mark's SVG part alone, the geometry being the
  # scroll's to ask for (§12.5, #404).
  defp drawn(compiled, frame, sources, hi, canvas?, moved \\ %{})

  defp drawn(%{regions: regions} = compiled, frame, sources, hi, canvas?, moved) do
    Map.new(regions, fn region ->
      {name, output} = drawn_region(compiled, region, frame, sources, hi, canvas?, moved)
      {name, split_backdrop(compiled, name, output)}
    end)
  end

  # A basemap's region is drawn in two layers (spec/14 §12.3, #476, D-120): its images in
  # the backdrop beneath the canvas, its attribution — text to be read over the data — in
  # its group in the SVG layer. `svg` keeps the whole group for the one-string form.
  defp split_backdrop(%{chart: chart}, {:mark, i}, %{svg: svg} = output) do
    if Mark.tiles?(Enum.at(chart.marks, i)) do
      Map.merge(output, %{
        backdrop: Enum.map(svg, &children(&1, fn child -> child.type == :image end)),
        over: Enum.map(svg, &children(&1, fn child -> child.type != :image end))
      })
    else
      output
    end
  end

  defp split_backdrop(_compiled, _region, output), do: output

  defp children(%Element{children: children} = element, keep?),
    do: %{element | children: Enum.filter(children, keep?)}

  defp drawn_region(compiled, region, frame, sources, hi, canvas?, moved) do
    case region do
      %{region: region, status: :static, static: elements} ->
        {region, %{svg: elements, canvas: []}}

      %{region: {:mark, i} = region, build: build} ->
        mark = Enum.at(compiled.chart.marks, i)
        {target, _points} = Enum.at(compiled.targets, i)

        # A canvas mark whose geometry is the scroll's to ask for and which carries no
        # label draws nothing here, so its rows are not windowed either (#410).
        if not canvas? and target != :svg and not Map.has_key?(mark, :label) do
          {region, %{svg: [], canvas: []}}
        else
          sources = mark_sources(compiled, frame, mark, move(sources, moved, i), hi)
          {region, mark_output(target, mark, build, frame, sources, canvas?)}
        end

      %{region: region, build: build} ->
        {region, %{svg: build.(frame, sources, :css), canvas: []}}
    end
  end

  # The canvas marks over the rows under a strip and three neighbours each side (§12.5,
  # D-108): what an exposed region of the incremental canvas is drawn from. Every other
  # region draws nothing into a strip.
  defp drawn_strip(%{regions: regions, viewport: window} = compiled, frame, sources, hi, bounds) do
    Map.new(regions, fn
      %{region: {:mark, i} = region, build: build} ->
        mark = Enum.at(compiled.chart.marks, i)
        {target, _points} = Enum.at(compiled.targets, i)

        if target == :svg do
          {region, %{svg: [], canvas: []}}
        else
          sources = Window.strip(window, frame, mark, sources, hi, bounds)
          {region, %{mark_output(target, mark, build, frame, sources, true) | svg: []}}
        end

      %{region: region} ->
        {region, %{svg: [], canvas: []}}
    end)
  end

  # A mark that eases draws its own rows at their shown values (spec/14 §12.5, #417): the
  # substitution is per mark, so a source two marks share is not moved for both.
  defp move(sources, moved, index) do
    case moved do
      %{^index => {name, rows}} -> Map.put(sources, name, rows)
      _not_moving -> sources
    end
  end

  defp mark_sources(%{viewport: nil}, _frame, _mark, sources, _hi), do: sources

  defp mark_sources(%{viewport: window}, frame, mark, sources, hi),
    do: Window.sources(window, frame, mark, sources, hi)

  defp mark_output(:svg, _mark, build, frame, sources, _canvas?) do
    %{svg: build.(frame, sources, :css), canvas: []}
  end

  # A canvas-layer mark: its elements in literal style without text, and its inline
  # label as SVG text (spec/14 §12.3); the geometry only when it is wanted (#404).
  defp mark_output(_canvas_or_binary, mark, build, frame, sources, canvas?) do
    canvas =
      if canvas?,
        do: frame |> build.(sources, :literal) |> Enum.map(&strip_text/1),
        else: []

    svg =
      if Map.has_key?(mark, :label),
        do: frame |> build.(sources, :css) |> Enum.map(&only_text/1) |> Enum.reject(&is_nil/1),
        else: []

    %{svg: svg, canvas: canvas}
  end

  # One layer of a tick, in layout order: `:static` and `:dynamic_svg` split the SVG
  # regions by status, `:svg` takes them all (the one-string form), `:canvas` the canvas
  # elements; `:backdrop` the layer beneath the canvas, split by status as
  # `:static_backdrop` and `:dynamic_backdrop` (#476). The SVG layers hold a basemap's
  # group without its images, which are the backdrop's. A polar frame's centred group
  # wraps its inner regions, always in the one-string form and when it has anything
  # otherwise.
  defp layer(%{layout: layout, regions: regions, plot: plot}, drawn, which, always_centred?) do
    status = Map.new(regions, &{&1.region, &1.status})

    pick = fn region ->
      output = Map.fetch!(drawn, region)

      case {which, Map.fetch!(status, region)} do
        {:svg, _} -> output.svg
        {:canvas, _} -> output.canvas
        {:static, :static} -> Map.get(output, :over, output.svg)
        {:dynamic_svg, {:dynamic, _}} -> Map.get(output, :over, output.svg)
        {:backdrop, _} -> Map.get(output, :backdrop, [])
        {:static_backdrop, :static} -> Map.get(output, :backdrop, [])
        {:dynamic_backdrop, {:dynamic, _}} -> Map.get(output, :backdrop, [])
        _ -> []
      end
    end

    Enum.flat_map(layout, fn
      {:centered, inner} ->
        case Enum.flat_map(inner, pick) do
          [] when not always_centred? -> []
          elements -> [Furniture.centred(%{plot: plot}, elements)]
        end

      region ->
        pick.(region)
    end)
  end

  # The canvas layer of a tick: the whole layer per tick, or the incremental payload of a
  # viewport design with a binary layer (spec/14 §12.5).
  # `whole` is the whole window's canvas layer, a function: on the incremental path it is
  # called only by the full-redraw branch (§12.5, #404), and everywhere else at once.
  defp canvas(%{viewport: window} = compiled, frame, whole, strip, hi) do
    format = format(compiled)

    if window == nil or format != :binary_base64 do
      case whole.() do
        [] ->
          {"", nil, window && %{window | hi: hi}}

        elements ->
          string =
            Hybrid.render_dynamic(
              margin: compiled.margin,
              dynamic: elements,
              dynamic_style: %{},
              canvas_format: format
            )

          {string, nil, window && %{window | hi: hi}}
      end
    else
      {payload, window} =
        Window.scroll(window, frame, fn -> Element.group(whole.()) end, strip, hi, window.full)

      {"", payload, window}
    end
  end

  defp fragment(_compiled, []), do: ""
  defp fragment(compiled, elements), do: root(compiled, elements)

  # A page-ready document at the design's size, this frame's group translated by its box
  # and its margins (spec/14 §12.4, §4.2): the frames of a design stack, each transparent
  # where it draws nothing, and a design of one frame at `[0, 0, 1, 1]` is what it was.
  defp root(%{size: size, margin: margin, box: box}, elements) do
    Hybrid.render_static(
      width: size.width,
      height: size.height,
      margin: %{margin | left: margin.left + box.x, top: margin.top + box.y},
      static: moving(elements)
    )
  end

  # An SVG layer's motion as its classes and the one `<style>` they need (spec/14
  # §3.10–§3.12, D-176), as `Visualize.Chart.Frame.generate/2` writes a frame's; a layer
  # without motion is the elements it was.
  defp moving(elements) do
    {group, sheet} = FrameMotion.apply(Element.group(elements), :css)
    sheet ++ group.children
  end

  defp format(%{targets: targets}) do
    if Enum.any?(targets, &match?({:binary, _}, &1)), do: :binary_base64, else: :json
  end

  # -- compilation ----------------------------------------------------------------------

  defp ceiling!(ceiling) when is_integer(ceiling) and ceiling > 0, do: ceiling

  defp ceiling!(ceiling) do
    raise ArgumentError, "ceiling: a positive integer is needed, got: #{inspect(ceiling)}"
  end

  defp motion!(motion) when motion in [:full, :reduce], do: motion

  defp motion!(motion) do
    raise ArgumentError, "motion: :full or :reduce is needed, got: #{inspect(motion)}"
  end

  # The target of every mark (spec/14 §12.3): the override, else by the bound row count.
  defp targets(%Chart{marks: marks}, frame, sources, ceiling) do
    Enum.map(marks, fn mark ->
      points = length(Mark.rows(frame, mark, sources))

      case mark.type do
        :text -> {:svg, points}
        # A basemap draws images and text and no rows (§12.3, #475).
        :tiles -> {:svg, 0}
        _type -> {target(frame.kind, Map.get(mark, :render, :auto), points, ceiling), points}
      end
    end)
  end

  defp target(:facet, _render, _points, _ceiling), do: :svg
  defp target(_kind, render, _points, _ceiling) when render != :auto, do: render
  defp target(_kind, :auto, points, ceiling) when points <= ceiling, do: :svg

  defp target(_kind, :auto, _points, _ceiling),
    do: if(CanvasBinary.available?(), do: :binary, else: :canvas)

  # The scale kinds a window slides by a translation of its units (spec/14 §12.5, #416):
  # the only kinds a copy-shift is right for. An allowlist, not an exclusion, so a kind
  # added later redraws in full until it is shown to be one.
  @translations [:linear, :time]

  # Whether the canvas layer's old pixels go stale between ticks: the windowed scale is
  # not a translation, so no single dx moves the drawn pixels right, or a canvas mark
  # reads a scale other than the viewport's whose domain moves (spec/14 §12.5).
  defp stale?(chart, viewport, targets) do
    not translation?(chart, viewport) or moving_beside?(chart, viewport, targets)
  end

  # A scale adopted from another frame has no kind here to prove it one, so it fails safe.
  defp translation?(chart, viewport) do
    case get_in(chart.frames |> Map.values() |> hd(), [:scales, viewport]) do
      %{kind: kind} -> kind in @translations
      _adopted_or_absent -> false
    end
  end

  defp moving_beside?(chart, viewport, targets) do
    chart.marks
    |> Enum.zip(targets)
    |> Enum.any?(fn {mark, {target, _}} ->
      target != :svg and
        Enum.any?(
          Regions.mark_scales(chart, mark) -- [viewport],
          &Regions.moving?(chart, &1, viewport)
        )
    end)
  end

  # -- text and the canvas --------------------------------------------------------------

  # The canvas layer drops a labelled mark's labels group with its text (spec/14 §12.3,
  # #485), so the canvas draws the wrapper and the elements' group alone.
  defp strip_text(%Element{children: children} = element) do
    %{
      element
      | children:
          children
          |> Enum.reject(&(&1.type == :text or labels?(&1)))
          |> Enum.map(&strip_text/1)
    }
  end

  defp labels?(%Element{type: :group, style: %{class: "mark-labels"}}), do: true
  defp labels?(_element), do: false

  defp only_text(%Element{type: :text} = element), do: element

  defp only_text(%Element{type: :group, children: children} = element) do
    case children |> Enum.map(&only_text/1) |> Enum.reject(&is_nil/1) do
      [] -> nil
      kept -> %{element | children: kept}
    end
  end

  defp only_text(_element), do: nil
end
