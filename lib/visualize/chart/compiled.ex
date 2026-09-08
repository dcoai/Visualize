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
  added for the SVG layer's moving part; `static/1` is the static SVG string; `tick/3` is
  the per-tick payload, and for a design with a viewport it slides the canvas layer
  through `Visualize.Incremental`, whose state the struct carries. `svg/2` is the
  one-string form, the frame's own group, equal to `Visualize.Chart.Frame.render/2` when
  every mark targets `:svg`.

  ## Examples

      iex> design = %{
      ...>   version: 1,
      ...>   sources: %{primary: %{fields: [:t, :v]}},
      ...>   frame: %{
      ...>     kind: :cartesian,
      ...>     scales: %{x: %{kind: :linear, domain: [0, 10]}, y: %{kind: :linear}},
      ...>     axes: [%{scale: :x, side: :bottom}, %{scale: :y, side: :left, grid: true}]
      ...>   },
      ...>   marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v}}]
      ...> }
      iex> {:ok, compiled} = Visualize.Chart.compile(design, sources: %{primary: %{t: [1, 2], v: [3, 9]}})
      iex> Visualize.Chart.Compiled.dynamic_regions(compiled)
      [{:grid, {:inferred, [:y]}}, {{:mark, 0}, :data}, {{:axis, 1}, {:inferred, [:y]}}]
      iex> Visualize.Chart.Compiled.targets(compiled)
      [{:svg, 2}]

  """

  alias Visualize.Backend.{CanvasBinary, Hybrid}
  alias Visualize.{Chart, Render, Theme}
  alias Visualize.Chart.{Applied, Frame, Mark}
  alias Visualize.Chart.Compiled.{Regions, Window}
  alias Visualize.Chart.Frame.Furniture
  alias Visualize.IR.{Element, Transform}

  @default_ceiling 1000

  @enforce_keys [:chart, :theme, :sources, :layout, :regions, :targets, :ceiling]
  defstruct [
    :chart,
    :theme,
    :sources,
    :layout,
    :regions,
    :targets,
    :ceiling,
    :static,
    :size,
    :margin,
    :plot,
    :viewport
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
  @type layout :: [region() | {:centred, [region()]}]

  @typedoc "The per-tick payload of spec/14 §12.4."
  @type payload :: %{
          svg: String.t(),
          canvas: String.t(),
          canvas_format: :binary_base64 | :json,
          incremental: map() | nil,
          bytes: non_neg_integer()
        }

  @type t :: %__MODULE__{
          chart: Chart.t(),
          theme: Theme.t(),
          sources: %{atom() => term()},
          layout: layout(),
          regions: [map()],
          targets: [{target(), non_neg_integer()}],
          ceiling: pos_integer(),
          static: String.t(),
          size: %{width: number(), height: number()},
          margin: %{top: number(), right: number(), bottom: number(), left: number()},
          plot: %{width: number(), height: number()},
          viewport: map() | nil
        }

  @doc false
  # The compiled chart of an applied one (spec/14 §12.1); `Visualize.Chart.compile/2`.
  @spec new(Applied.t(), keyword()) :: t()
  def new(%Applied{chart: chart, sources: sources, frame: frame}, opts) do
    ceiling = ceiling!(Keyword.get(opts, :ceiling, @default_ceiling))
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
      sources: sources,
      layout: layout,
      regions: regions,
      targets: targets,
      ceiling: ceiling,
      size: frame.size,
      margin: frame.margin,
      plot: frame.plot,
      viewport: window && Map.put(window, :full, stale?(chart, window.scale, targets))
    }

    static = layer(compiled, drawn(compiled, frame, sources, nil), :static, false)
    %{compiled | static: root(compiled, static)}
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

  @doc "The static SVG string, rendered once at compilation (spec/14 §12.4)."
  @spec static(t()) :: String.t()
  def static(%__MODULE__{static: static}), do: static

  @doc """
  The hybrid chart map over the sources by slot name (spec/14 §12.4): `width`, `height`,
  `margin`, `static`, `dynamic`, `dynamic_style`, `canvas_format` and `dynamic_svg`.

  Raises `ArgumentError` as `Visualize.Chart.Frame.new/2` does for a value a scale
  cannot take.
  """
  @spec render(t(), map()) :: map()
  def render(%__MODULE__{} = compiled, sources) when is_map(sources) do
    {frame, hi} = realise(compiled, sources, nil)
    drawn = drawn(compiled, frame, sources, hi)
    canvas = layer(compiled, drawn, :canvas, false)

    %{
      width: compiled.size.width,
      height: compiled.size.height,
      margin: compiled.margin,
      static: layer(compiled, drawn, :static, false),
      dynamic: if(canvas == [], do: nil, else: canvas),
      dynamic_style: %{},
      canvas_format: format(compiled),
      dynamic_svg: layer(compiled, drawn, :dynamic_svg, false)
    }
  end

  @doc """
  The one-string form (spec/14 §12.4): the frame's group with the static and the dynamic
  regions in the frame's own order, as SVG; equal to `Visualize.Chart.Frame.render/2`
  when every mark targets `:svg`.
  """
  @spec svg(t(), map()) :: String.t()
  def svg(%__MODULE__{margin: margin} = compiled, sources) when is_map(sources) do
    {frame, hi} = realise(compiled, sources, nil)
    children = layer(compiled, drawn(compiled, frame, sources, hi), :svg, true)

    Element.group(children,
      style: %{class: "frame"},
      transform: Transform.translate(margin.left, margin.top)
    )
    |> Render.to_string(backend: :svg)
  end

  @doc "As `tick/3` with `[]` options."
  @spec tick(t(), map()) :: {payload(), t()}
  def tick(%__MODULE__{} = compiled, sources), do: tick(compiled, sources, [])

  @doc """
  The per-tick payload and the compiled chart holding the tick's state (spec/14 §12.4).

  `svg` is the SVG layer's dynamic regions as one SVG root of the shape of `static/1`
  (`""` when there are none); `canvas` the canvas layer through
  `Visualize.Backend.Hybrid.render_dynamic/1` (`""` when there is none, or when the
  layer streams incrementally); `incremental` the `canvas_incremental` payload of
  `Visualize.Incremental` for a design with a viewport and a binary canvas layer
  (spec/14 §12.5), else `nil`; `bytes` the byte size of what the tick transmits.

  ## Options

    * `:now` - the window's upper end for a viewport design; by default the newest
      value the marks bind to the viewport scale
  """
  @spec tick(t(), map(), keyword()) :: {payload(), t()}
  def tick(%__MODULE__{} = compiled, sources, opts) when is_map(sources) do
    {frame, hi} = realise(compiled, sources, Keyword.get(opts, :now))
    drawn = drawn(compiled, frame, sources, hi)
    svg = fragment(compiled, layer(compiled, drawn, :dynamic_svg, false))
    format = format(compiled)

    {canvas, incremental, window} =
      canvas(compiled, frame, layer(compiled, drawn, :canvas, false), hi)

    bytes =
      byte_size(svg) + byte_size(canvas) +
        if(incremental, do: byte_size(incremental.binary), else: 0)

    payload = %{
      svg: svg,
      canvas: canvas,
      canvas_format: format,
      incremental: incremental,
      bytes: bytes
    }

    {payload, %{compiled | sources: sources, viewport: window}}
  end

  # -- per tick -------------------------------------------------------------------------

  # The frame of a tick: realised over the sources, its viewport scale windowed.
  defp realise(%{chart: chart, theme: theme, viewport: window}, sources, now) do
    frame = Frame.new(chart, sources: sources, theme: theme)

    case window do
      nil ->
        {frame, nil}

      window ->
        {window_frame(window, chart, frame, sources, now),
         Window.hi(window, chart, frame, sources, now)}
    end
  end

  defp window_frame(nil, _chart, frame, _sources, _now), do: frame

  defp window_frame(window, chart, frame, sources, now) do
    Window.apply(window, frame, Window.hi(window, chart, frame, sources, now))
  end

  # Every region drawn for a tick: `%{region => %{svg: elements, canvas: elements}}`.
  defp drawn(%{regions: regions} = compiled, frame, sources, hi) do
    Map.new(regions, fn
      %{region: region, status: :static, static: elements} ->
        {region, %{svg: elements, canvas: []}}

      %{region: {:mark, i} = region, build: build} ->
        mark = Enum.at(compiled.chart.marks, i)
        {target, _points} = Enum.at(compiled.targets, i)
        sources = mark_sources(compiled, frame, mark, sources, hi)
        {region, mark_output(target, mark, build, frame, sources)}

      %{region: region, build: build} ->
        {region, %{svg: build.(frame, sources, :css), canvas: []}}
    end)
  end

  defp mark_sources(%{viewport: nil}, _frame, _mark, sources, _hi), do: sources

  defp mark_sources(%{viewport: window}, frame, mark, sources, hi),
    do: Window.sources(window, frame, mark, sources, hi)

  defp mark_output(:svg, _mark, build, frame, sources) do
    %{svg: build.(frame, sources, :css), canvas: []}
  end

  # A canvas-layer mark: its elements in literal style without text, and its inline
  # label as SVG text (spec/14 §12.3).
  defp mark_output(_canvas_or_binary, mark, build, frame, sources) do
    canvas = frame |> build.(sources, :literal) |> Enum.map(&strip_text/1)

    svg =
      if Map.has_key?(mark, :label),
        do: frame |> build.(sources, :css) |> Enum.map(&only_text/1) |> Enum.reject(&is_nil/1),
        else: []

    %{svg: svg, canvas: canvas}
  end

  # One layer of a tick, in layout order: `:static` and `:dynamic_svg` split the SVG
  # regions by status, `:svg` takes them all (the one-string form), `:canvas` the canvas
  # elements. A polar frame's centred group wraps its inner regions, always in the
  # one-string form and when it has anything otherwise.
  defp layer(%{layout: layout, regions: regions, plot: plot}, drawn, which, always_centred?) do
    status = Map.new(regions, &{&1.region, &1.status})

    pick = fn region ->
      output = Map.fetch!(drawn, region)

      case {which, Map.fetch!(status, region)} do
        {:svg, _} -> output.svg
        {:canvas, _} -> output.canvas
        {:static, :static} -> output.svg
        {:dynamic_svg, {:dynamic, _}} -> output.svg
        _ -> []
      end
    end

    Enum.flat_map(layout, fn
      {:centred, inner} ->
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
  defp canvas(%{viewport: nil}, _frame, [], _hi), do: {"", nil, nil}
  defp canvas(%{viewport: window}, _frame, [], hi), do: {"", nil, %{window | hi: hi}}

  defp canvas(%{viewport: window} = compiled, frame, elements, hi) do
    format = format(compiled)

    if window == nil or format != :binary_base64 do
      string =
        Hybrid.render_dynamic(
          margin: compiled.margin,
          dynamic: elements,
          dynamic_style: %{},
          canvas_format: format
        )

      {string, nil, window && %{window | hi: hi}}
    else
      {payload, window} = Window.scroll(window, frame, Element.group(elements), hi, window.full)
      {"", payload, window}
    end
  end

  defp fragment(_compiled, []), do: ""
  defp fragment(compiled, elements), do: root(compiled, elements)

  defp root(%{size: size, margin: margin}, elements) do
    Hybrid.render_static(width: size.width, height: size.height, margin: margin, static: elements)
  end

  defp format(%{targets: targets}) do
    if Enum.any?(targets, &match?({:binary, _}, &1)), do: :binary_base64, else: :json
  end

  # -- compilation ----------------------------------------------------------------------

  defp ceiling!(ceiling) when is_integer(ceiling) and ceiling > 0, do: ceiling

  defp ceiling!(ceiling) do
    raise ArgumentError, "ceiling: a positive integer is needed, got: #{inspect(ceiling)}"
  end

  # The target of every mark (spec/14 §12.3): the override, else by the bound row count.
  defp targets(%Chart{marks: marks}, frame, sources, ceiling) do
    Enum.map(marks, fn mark ->
      points = length(Mark.rows(frame, mark, sources))
      {target(frame.kind, Map.get(mark, :render, :auto), points, ceiling), points}
    end)
  end

  defp target(:facet, _render, _points, _ceiling), do: :svg
  defp target(_kind, render, _points, _ceiling) when render != :auto, do: render
  defp target(_kind, :auto, points, ceiling) when points <= ceiling, do: :svg

  defp target(_kind, :auto, _points, _ceiling),
    do: if(CanvasBinary.available?(), do: :binary, else: :canvas)

  # Whether the canvas layer's old pixels go stale between ticks: a canvas mark reads a
  # scale other than the viewport's whose domain moves (spec/14 §12.5).
  defp stale?(chart, viewport, targets) do
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

  defp strip_text(%Element{children: children} = element) do
    %{element | children: children |> Enum.reject(&(&1.type == :text)) |> Enum.map(&strip_text/1)}
  end

  defp only_text(%Element{type: :text} = element), do: element

  defp only_text(%Element{type: :group, children: children} = element) do
    case children |> Enum.map(&only_text/1) |> Enum.reject(&is_nil/1) do
      [] -> nil
      kept -> %{element | children: kept}
    end
  end

  defp only_text(_element), do: nil
end
