defmodule Visualize.Chart.Frame do
  @moduledoc """
  The realised frame of a chart: its scales, built once, and the static furniture —
  grid, axes, legend and labels — rendered from them (spec/14 §4, D-60).

  `new/2` takes a `Visualize.Chart` and the sources its marks are bound to, realises every
  `:scale` node through the existing scale modules — a `domain: :auto` inferred from the
  whole column of every mark channel that names the scale, a `range: :auto` from the plot
  area by the scale's name — and caches the structs on the frame. `scales/1` reads them,
  the escape hatch for annotations, brush conversion and custom marks; `put_scale/3`
  replaces one. `generate/2` is the furniture as one `Visualize.IR.Element` group with
  the margins applied and every theme slot resolved through `Visualize.Theme.resolve/3`;
  `render/2` is the same as a string. Given `sources:`, both also draw every mark of the
  design between the grid and the axes through `Visualize.Chart.Mark.generate/3`
  (spec/14 §5.6); without them a frame renders the furniture alone, over its unit
  domains, which is what the static split of a compiled chart needs (spec/14 §12).

  ## Examples

      iex> chart =
      ...>   Visualize.Chart.from_map!(%{
      ...>     version: 2,
      ...>     sources: %{primary: %{fields: [:t, :v]}},
      ...>     frames: %{main: %{
      ...>       kind: :cartesian,
      ...>       scales: %{x: %{kind: :linear}, y: %{kind: :linear, domain: [0, :auto]}},
      ...>       axes: [%{scale: :x, side: :bottom}, %{scale: :y, side: :left, grid: true}]
      ...>     }},
      ...>     marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v}}]
      ...>   })
      iex> frame = Visualize.Chart.Frame.new(chart, sources: %{primary: %{t: [1, 2, 3], v: [4, 9, 2]}}, size: {300, 200})
      iex> Visualize.Chart.Frame.scale(frame, :x).domain
      [1, 3]
      iex> Visualize.Chart.Frame.scale(frame, :y).domain
      [0, 9]
      iex> frame.plot
      %{width: 240, height: 150}

  """

  alias Visualize.{Chart, Theme}
  alias Visualize.Chart.Frame.{Defs, Furniture, Labels, Legend, Lines, Scales}
  alias Visualize.Chart.{Mark, Schema, Style, Validator, Var}
  alias Visualize.Geo.Projection
  alias Visualize.IR.{Element, Transform}

  defstruct kind: :cartesian,
            size: %{width: 600, height: 400},
            margin: %{top: 20, right: 20, bottom: 30, left: 40},
            plot: %{width: 540, height: 350},
            scales: %{},
            projection: nil,
            panels: [],
            facet: nil,
            axes: [],
            legend: nil,
            labels: [],
            marks: [],
            theme: nil,
            styles: %{},
            design_styles: %{},
            defs: %{},
            now: nil,
            name: nil,
            domains: %{},
            mark_paths: [],
            label_paths: [],
            box: [0, 0, 1, 1],
            z: 0,
            background: nil

  @typedoc "A frame kind of spec/14 §4.1."
  @type kind :: :cartesian | :polar | :geo | :facet

  @type t :: %__MODULE__{
          kind: kind(),
          size: %{width: number(), height: number()},
          margin: %{top: number(), right: number(), bottom: number(), left: number()},
          plot: %{width: number(), height: number()},
          scales: %{atom() => struct()},
          projection: Projection.t() | nil,
          panels: [term()],
          facet: %{by: atom(), columns: pos_integer()} | nil,
          axes: [map()],
          legend: map() | nil,
          labels: [map()],
          marks: [map()],
          theme: Theme.t(),
          styles: %{atom() => map()},
          design_styles: %{atom() => map()},
          defs: %{atom() => map()},
          now: term() | nil,
          name: atom() | nil,
          domains: %{atom() => term()},
          mark_paths: [non_neg_integer()],
          label_paths: [non_neg_integer()],
          box: [number()],
          z: integer(),
          background: term() | nil
        }

  # The size a frame is realised at when the caller gives none (spec/14 §4.2): a static
  # render still works, and a design never carries one.
  @default_size {600, 400}

  @doc "The size a frame is realised at when no `size:` is given (spec/14 §4.2)."
  @spec default_size() :: {number(), number()}
  def default_size, do: @default_size

  @doc """
  The frame of a chart, every scale realised and the theme resolved (spec/14 §4.7).

  ## Options

    * `:sources` - a map from source name to anything `Visualize.Data.Table.rows/1`
      reads; the columns `:auto` domains are inferred from (default `%{}`)
    * `:theme` - a `%Visualize.Theme{}`; taken for any theme name the design gives, and
      required for one that is neither built-in nor inline
    * `:size` - the `{width, height}` the frame is realised at (default `{600, 400}`,
      spec/14 §4.2); a design records none
    * `:now` - the instant a `:window` step measures its durations back from (spec/14
      §5.4.1); without it each such step takes the newest reading of its own column

  Raises `ArgumentError` for an unresolved variable, a theme name it cannot resolve, a
  bound value a scale cannot take, or a legend in a margin that cannot hold it (spec/14
  §4.5).
  """
  @spec new(Chart.t(), keyword()) :: t()
  def new(%Chart{} = chart, opts \\ []) do
    sources = Keyword.get(opts, :sources, %{})
    {name, node} = frame_node(chart, Keyword.get(opts, :frame))
    kind = node.kind
    size = size(Keyword.get(opts, :size, @default_size))
    margin = margin(Map.get(node, :margin, Schema.default(:frame, :margin)))

    # The frame's own pixel box is its fractions of the render's (spec/14 §4.2, #383), and
    # its plot is that less its margins: `size` stays the design's, which is the root's.
    [_bx, _by, bw, bh] = box = box(node)

    plot = %{
      width: bw * size.width - margin.left - margin.right,
      height: bh * size.height - margin.top - margin.bottom
    }

    now = Keyword.get(opts, :now)
    theme = theme(chart.theme, Keyword.get(opts, :theme))
    styles = Style.all(chart.styles)
    projection = projection(kind, node, plot)
    panels = panels(kind, node, chart, sources, context(plot, projection, now))
    facet = facet(kind, node, panels)
    scale_plot = if facet, do: panel_plot(plot, facet.columns, panels), else: plot
    ctx = context(scale_plot, projection, now)

    scales =
      Scales.realise(
        chart,
        node,
        mine(chart.marks, name, chart),
        kind,
        scale_plot,
        theme,
        sources,
        styles,
        ctx,
        Keyword.get(opts, :domains, %{})
      )

    legend = Map.get(node, :legend)
    # A legend in a margin that cannot hold it is a fault here, not a clipped drawing (§4.5).
    Legend.check!(legend, scales, margin, styles, theme)

    %__MODULE__{
      kind: kind,
      size: size,
      margin: margin,
      plot: plot,
      scales: scales,
      projection: projection,
      panels: panels,
      facet: facet,
      axes: Map.get(node, :axes, []),
      legend: legend,
      labels: mine(chart.labels, name, chart),
      marks: mine(chart.marks, name, chart),
      name: name,
      domains: Keyword.get(opts, :domains, %{}),
      mark_paths: paths_of(chart.marks, name, chart),
      label_paths: paths_of(chart.labels, name, chart),
      box: box,
      z: Map.get(node, :z, Schema.default(:frame, :z)),
      background: Map.get(node, :background),
      theme: theme,
      styles: styles,
      design_styles: chart.styles,
      defs: chart.defs,
      now: now
    }
  end

  @doc "The realised scales by name: the escape hatch (spec/14 §4.3)."
  @spec scales(t()) :: %{atom() => struct()}
  def scales(%__MODULE__{scales: scales}), do: scales

  @doc "One realised scale; `ArgumentError` when the frame declares no such scale."
  @spec scale(t(), atom()) :: struct()
  def scale(%__MODULE__{scales: scales}, name) do
    Map.get(scales, name) ||
      raise ArgumentError,
            "the frame declares no scale #{inspect(name)}; it has #{inspect(Map.keys(scales))}"
  end

  @doc "The frame with the realised scale replaced: the override of spec/14 §4.3."
  @spec put_scale(t(), atom(), struct()) :: t()
  def put_scale(%__MODULE__{scales: scales} = frame, name, scale)
      when is_atom(name) and is_struct(scale) do
    %{frame | scales: Map.put(scales, name, scale)}
  end

  @doc "The projection of a `:geo` frame (spec/14 §4.6), `nil` for any other kind."
  @spec projection(t()) :: Projection.t() | nil
  def projection(%__MODULE__{projection: projection}), do: projection

  @doc "As `generate/2` with `resolve: :css`."
  @spec generate(t()) :: Element.t()
  def generate(%__MODULE__{} = frame), do: generate(frame, [])

  @doc """
  The frame as one `Visualize.IR.Element` group (spec/14 §4.7): the static furniture,
  and every mark of the design between the grid and the axes when sources are given.

  ## Options

    * `:resolve` - how the theme's slots render: `:css` (default) for references a
      stylesheet can override, `:literal` for the plain values a canvas needs
    * `:sources` - a map from source name to anything `Visualize.Data.Table.rows/1`
      reads, as `new/2` takes; when given, the marks are drawn from them (spec/14 §5.6)
    * `:paths` - `true` for every design node's element to carry `data-node` with the
      node's path as `Visualize.Chart.Validator.format_path/1` spells it — `frame`,
      `marks[0]`, `frames.main.axes[0]`, `frames.main.legend`, `labels[0]` — for a caller that must
      name what it drew, as the builder's graph does (spec/14 §4.7, D-105); `false`
      (default) leaves the markup as it is

  ## Examples

      iex> chart = Visualize.Chart.from_map!(%{version: 2, sources: %{s: %{fields: [:x, :y]}},
      ...>   frames: %{main: %{kind: :cartesian, scales: %{x: %{kind: :linear}, y: %{kind: :linear}}}},
      ...>   marks: [%{type: :line, data: :s, channels: %{x: :x, y: :y}}]})
      iex> rows = [%{x: 0, y: 1}, %{x: 1, y: 2}]
      iex> group = Visualize.Chart.Frame.new(chart, sources: %{s: rows}) |> Visualize.Chart.Frame.generate(sources: %{s: rows}, paths: true)
      iex> {group.attrs["data-node"], Enum.map(group.children, & &1.attrs["data-node"])}
      {"frames.main", ["marks[0]"]}
  """
  @spec generate(t(), keyword()) :: Element.t()
  def generate(%__MODULE__{} = frame, opts) do
    mode = Keyword.get(opts, :resolve, :css)
    sources = Keyword.get(opts, :sources)
    paths? = Keyword.get(opts, :paths, false)

    children =
      background(frame, mode) ++
        furniture(frame, mode, sources, paths?) ++
        Legend.generate(frame, mode, paths?) ++ Labels.generate(frame, mode, paths?)

    group =
      Element.group(children,
        style: %{class: "frame"},
        transform: Transform.translate(frame.margin.left, frame.margin.top)
      )
      |> stamp([:frames, frame.name], paths?)
      |> Defs.resolve(frame, mode)
      |> Lines.split()

    # The defs come first (spec/14 §2.7): the paints declared, the filters the tree uses.
    %{group | children: Defs.defs(frame, mode, group) ++ group.children}
  end

  # The frame's own box painted under its contents, `[]` when it declares no `background`
  # (spec/14 §4.2, #383): the group is translated by the margins, so the rect starts back
  # at the box's corner, and its colour resolves through the theme as any other does.
  defp background(%__MODULE__{background: nil}, _mode), do: []

  defp background(%__MODULE__{} = frame, mode) do
    [_x, _y, w, h] = frame.box
    margin = frame.margin

    [
      Element.new(:rect,
        attrs: %{
          x: -margin.left,
          y: -margin.top,
          width: w * frame.size.width,
          height: h * frame.size.height
        },
        style: %{fill: Style.colour(frame.background, frame.theme, mode)}
      )
    ]
  end

  @doc "As `render/2` with `[]` options."
  @spec render(t()) :: String.t()
  def render(%__MODULE__{} = frame), do: render(frame, [])

  @doc """
  `generate/2` rendered through `Visualize.Render.to_string/2`.

  ## Options

    * `:backend` - `:svg`, `:canvas`, or a module; defaults to the configured backend
    * `:resolve` - the theme mode of `generate/2`; defaults to `Visualize.Theme.mode/1`
      of the backend
    * `:sources` and `:paths` - as `generate/2` takes them
  """
  @spec render(t(), keyword()) :: String.t()
  def render(%__MODULE__{} = frame, opts) do
    {mode, opts} = Keyword.pop_lazy(opts, :resolve, fn -> Theme.mode(opts[:backend]) end)
    {sources, opts} = Keyword.pop(opts, :sources)
    {paths?, opts} = Keyword.pop(opts, :paths, false)

    frame
    |> generate(resolve: mode, sources: sources, paths: paths?)
    |> Visualize.Render.to_string(opts)
  end

  @doc false
  # The element a design node renders, tagged with the node's path when the frame draws
  # with `paths: true` (spec/14 §4.7, D-105): the frame stamps what it places, so a
  # generator's element is tagged at the position the frame drew it and no generator
  # knows its path.
  @spec stamp(Element.t(), Validator.path(), boolean()) :: Element.t()
  def stamp(element, path, true),
    do: Element.put_attr(element, "data-node", Validator.format_path(path))

  def stamp(element, _path, false), do: element

  # -- construction ---------------------------------------------------------------------

  # What a mark's pipeline sees of the frame (spec/14 §5.4).
  defp context(plot, projection, now),
    do: %{size: [plot.width, plot.height], projection: projection, now: now}

  # Which frame `new/2` realises: the one `frame:` names, else the design's only one — a
  # design with several and no name given is an authoring error, not a default (spec/14
  # §4.1, #383).
  defp frame_node(%Chart{frames: frames}, nil) when map_size(frames) == 1 do
    frames |> Enum.to_list() |> hd()
  end

  defp frame_node(%Chart{frames: frames}, nil) do
    raise ArgumentError,
          "this design has #{map_size(frames)} frames (#{inspect(Map.keys(frames))}); " <>
            "say which with frame: (spec/14 §4.1)"
  end

  defp frame_node(%Chart{frames: frames}, name) do
    case Map.fetch(frames, name) do
      {:ok, node} ->
        {name, node}

      :error ->
        raise ArgumentError, "the design declares no frame #{inspect(name)} (spec/14 §4.1)"
    end
  end

  # A mark or a label belongs to the frame it names, and to the only frame when it names
  # none (spec/14 §5.1, §6.1).
  defp mine(nodes, name, %Chart{frames: frames}) do
    if map_size(frames) == 1 do
      nodes
    else
      Enum.filter(nodes, &(Map.get(&1, :frame) == name))
    end
  end

  # The design positions of the nodes this frame draws, so an element carries the path the
  # design gives it and not the position within the frame (spec/14 §4.7, D-105).
  defp paths_of(nodes, name, chart) do
    mine = mine(nodes, name, chart)
    for {node, i} <- Enum.with_index(nodes), node in mine, do: i
  end

  # A frame's pixel box is its fractions of the render's (spec/14 §4.2).
  defp box(node) do
    case Map.get(node, :box, Schema.default(:frame, :box)) do
      [x, y, w, h] when is_number(x) and is_number(y) and is_number(w) and is_number(h) ->
        [x, y, w, h]

      other ->
        raise ArgumentError, "box: is [x, y, w, h] in fractions, got #{inspect(other)}"
    end
  end

  defp size({width, height}) when is_number(width) and is_number(height),
    do: %{width: width, height: height}

  defp size(%{width: width, height: height}), do: %{width: width, height: height}

  defp size(other) do
    raise ArgumentError,
          "size: is {width, height} in pixels, got #{inspect(other)} (spec/14 §4.2)"
  end

  defp margin(%Var{name: name}), do: Style.unresolved!(name)

  defp margin(node) do
    Map.new([:top, :right, :bottom, :left], &{&1, Map.get(node, &1, Schema.default(:margin, &1))})
  end

  defp theme(_design, %Theme{} = given), do: given
  defp theme(:default, nil), do: Theme.default()
  defp theme(:dark, nil), do: Theme.dark()
  defp theme(%Var{name: name}, nil), do: Style.unresolved!(name)

  defp theme(node, nil) when is_map(node) do
    Enum.each(node, fn {_, v} -> match?(%Var{}, v) and Style.unresolved!(v.name) end)
    Theme.new(node)
  end

  defp theme(name, nil) do
    raise ArgumentError,
          "theme #{inspect(name)} is neither built-in nor inline; pass it as the :theme " <>
            "option of Visualize.Chart.Frame.new/2"
  end

  defp projection(:geo, node, plot) do
    spec = Map.get(node, :projection, %{})
    type = Map.get(spec, :type, :mercator)
    centre = [plot.width / 2, plot.height / 2]
    [tx, ty] = Map.get(spec, :translate, centre)

    type
    |> Projection.new()
    |> Projection.translate(tx, ty)
    |> maybe(spec, :scale, &Projection.scale/2)
    |> maybe(spec, :center, fn p, [lon, lat] -> Projection.center(p, lon, lat) end)
    |> maybe(spec, :rotate, &rotate/2)
    |> maybe(spec, :parallels, fn p, [a, b] -> Projection.parallels(p, a, b) end)
    |> maybe(spec, :clip_angle, &Projection.clip_angle/2)
  end

  defp projection(_kind, _node, _plot), do: nil

  defp maybe(projection, spec, key, setter) do
    case Map.get(spec, key) do
      nil -> projection
      value -> setter.(projection, value)
    end
  end

  defp rotate(projection, [lambda, phi]), do: Projection.rotate(projection, lambda, phi)

  defp rotate(projection, [lambda, phi, gamma]),
    do: Projection.rotate(projection, lambda, phi, gamma)

  # The facet's panels: the distinct values of `by` over every bound source, in order of
  # first appearance; one panel with no value when nothing is bound (spec/14 §4.6).
  defp panels(:facet, %{facet: %{by: by}}, chart, sources, ctx) do
    values =
      chart.marks
      |> Enum.flat_map(&Scales.mark_rows(&1, sources, ctx))
      |> Enum.map(&Visualize.Data.Table.get(&1, by))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if values == [], do: [nil], else: values
  end

  defp panels(_kind, _node, _chart, _sources, _ctx), do: []

  # The facet with its effective column count: `columns` as given, else one row.
  defp facet(:facet, %{facet: %{by: by} = spec}, panels) do
    %{by: by, columns: Map.get(spec, :columns) || length(panels)}
  end

  defp facet(_kind, _node, _panels), do: nil

  defp panel_plot(plot, columns, panels) do
    rows = div(length(panels) + columns - 1, columns)
    %{width: plot.width / columns, height: plot.height / rows}
  end

  # -- furniture by kind ----------------------------------------------------------------

  defp furniture(%{kind: :polar} = frame, mode, sources, paths?) do
    Furniture.polar(frame, mode, marks(frame, mode, sources, paths?, []), paths?)
  end

  defp furniture(%{kind: :facet} = frame, mode, sources, paths?),
    do: panels(frame, mode, sources, paths?)

  defp furniture(frame, mode, sources, paths?) do
    Furniture.cartesian(frame, mode, marks(frame, mode, sources, paths?, []), paths?)
  end

  @doc false
  # The panels of a facet frame (spec/14 §4.6): one `class="panel"` group per panel
  # value, translated to its cell, holding the grid, the marks drawn from the rows whose
  # `by` is the value, the axes and the value as a title. Every panel's copy of a mark or
  # an axis carries the one node's path when `paths?` (§4.7).
  @spec panels(t(), Theme.mode(), map() | nil, boolean()) :: [Element.t()]
  def panels(frame, mode, sources, paths? \\ false)

  def panels(%__MODULE__{kind: :facet, facet: %{columns: columns}} = frame, mode, sources, paths?) do
    panel = panel_plot(frame.plot, columns, frame.panels)
    inner = %{frame | plot: panel}
    style = Style.resolve(Style.node(frame.styles, :label), frame.theme, mode)

    Enum.with_index(frame.panels, fn value, i ->
      x = rem(i, columns) * panel.width
      y = div(i, columns) * panel.height
      title = if value == nil, do: [], else: [panel_title(value, style)]
      marks = marks(inner, mode, sources, paths?, panel: value)

      Element.group(Furniture.cartesian(inner, mode, marks, paths?) ++ title,
        style: %{class: "panel"},
        transform: Transform.translate(x, y)
      )
    end)
  end

  # Every mark of the design at its one-based position, or nothing without sources; each
  # stamped with its path at the position the frame drew it (§4.7).
  defp marks(_frame, _mode, nil, _paths?, _opts), do: []

  defp marks(frame, mode, sources, paths?, opts) do
    Enum.with_index(frame.marks, fn mark, i ->
      frame
      |> Mark.generate(mark, [sources: sources, resolve: mode, index: i + 1] ++ opts)
      |> stamp([:marks, Enum.at(frame.mark_paths, i, i)], paths?)
    end)
  end

  defp panel_title(value, style) do
    Element.new(:text,
      attrs: %{x: 4, y: 4, dy: "0.71em"},
      style: Map.merge(%{class: "label", text_anchor: :start}, style),
      content: to_string(value)
    )
  end
end
