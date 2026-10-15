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
  alias Visualize.Chart.Style.{Defaults, Parts}
  alias Visualize.Chart.Transform.Force
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
            defaults: [],
            defs: %{},
            now: nil,
            schemas: %{},
            system: :as_posted,
            name: nil,
            domains: %{},
            mark_paths: [],
            label_paths: [],
            box: [0, 0, 1, 1],
            z: 0,
            background: nil,
            sync: nil,
            brush: nil,
            forces: %{}

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
          defaults: [map() | nil],
          defs: %{atom() => map()},
          now: term() | nil,
          schemas: %{atom() => Visualize.Data.Schema.t()},
          system: Visualize.Quantity.system(),
          name: atom() | nil,
          domains: %{atom() => term()},
          mark_paths: [non_neg_integer()],
          label_paths: [non_neg_integer()],
          box: [number()],
          z: integer(),
          background: term() | nil,
          sync: String.t() | nil,
          brush: :x | nil,
          forces: map()
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
    * `:schemas` - the schema of each slot by name, whose declared identity a `:window`
      step's `latest` reads (spec/14 §5.4.1, D-168); `Visualize.Chart.apply/2` passes the
      applied chart's (default `%{}`)
    * `:system` - the unit system every axis shows its measure in, `:metric`, `:us`, `:uk`
      or `:as_posted` (default): the viewer's, never the design's (spec/14 §4.4, D-156)
    * `:warm` - the force layouts a compiled chart carries between ticks (spec/14 §12.5,
      D-132); every `:force` step is cold without it (default `%{}`)

  Each distinct `:force` step of the frame's marks is laid out once, before any domain is
  inferred, and held in `forces`: every pipeline that reaches the step reads that layout
  (spec/14 §5.4.3).

  Raises `ArgumentError` for an unresolved variable, a theme name it cannot resolve, a
  `system:` not of `Visualize.Quantity.systems/0`, a bound value a scale cannot take, a legend in a side margin that cannot hold it, a top or
  bottom legend with a row or a single entry wider than the plot, or a `max_label` below 1
  (spec/14 §4.5). A top or bottom legend in a margin too small for its rows grows that
  margin, and the plot is that much shorter (D-169).
  """
  @spec new(Chart.t(), keyword()) :: t()
  def new(%Chart{} = chart, opts \\ []) do
    {name, node} = frame_node(chart, Keyword.get(opts, :frame))
    size = size(Keyword.get(opts, :size, @default_size))
    margin = margin(Map.get(node, :margin, Schema.default(:frame, :margin)))
    frame = realise(chart, opts, name, node, size, margin)

    # A legend in a margin that cannot hold it is a fault here, not a clipped drawing; a top
    # or bottom one grows its margin instead, and the frame is realised over the smaller plot
    # (§4.5, D-169). The rows depend on the plot's width, which that leaves alone.
    case Legend.fit!(frame, margin) do
      ^margin -> frame
      grown -> realise(chart, opts, name, node, size, grown)
    end
  end

  # The frame over one margin: its plot, projection, forces, panels and scales.
  defp realise(chart, opts, name, node, size, margin) do
    sources = Keyword.get(opts, :sources, %{})
    kind = node.kind

    # The frame's own pixel box is its fractions of the render's (spec/14 §4.2, #383), and
    # its plot is that less its margins: `size` stays the design's, which is the root's.
    [_bx, _by, bw, bh] = box = box_of(node, chart.layout, size)

    plot = %{
      width: bw * size.width - margin.left - margin.right,
      height: bh * size.height - margin.top - margin.bottom
    }

    now = Keyword.get(opts, :now)
    schemas = Keyword.get(opts, :schemas, %{})
    system = system(Keyword.get(opts, :system, :as_posted))
    theme = theme(chart.theme, Keyword.get(opts, :theme))
    styles = Style.all(chart.styles, theme)
    projection = projection(kind, node, plot, sources)
    marks = mine(chart.marks, name, chart)

    # Each graph laid out once, before anything reads its rows (spec/14 §5.4.3, D-132).
    forces =
      Force.layouts(
        marks,
        sources,
        context(kind, plot, projection, now, schemas, %{}),
        Keyword.get(opts, :warm, %{})
      )

    panels =
      panels(kind, node, chart, sources, context(kind, plot, projection, now, schemas, forces))

    facet = facet(kind, node, panels)
    scale_plot = if facet, do: panel_plot(plot, facet.columns, panels), else: plot
    ctx = context(kind, scale_plot, projection, now, schemas, forces)

    scales =
      Scales.realise(
        chart,
        node,
        marks,
        kind,
        scale_plot,
        theme,
        sources,
        styles,
        ctx,
        Keyword.get(opts, :domains, %{})
      )

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
      legend: Map.get(node, :legend),
      labels: mine(chart.labels, name, chart),
      marks: marks,
      name: name,
      domains: Keyword.get(opts, :domains, %{}),
      mark_paths: paths_of(chart.marks, name, chart),
      label_paths: paths_of(chart.labels, name, chart),
      box: box,
      z: Map.get(node, :z, Schema.default(:frame, :z)),
      background: Map.get(node, :background),
      sync: sync_group(chart, name),
      brush: brush(chart, name),
      theme: theme,
      styles: styles,
      design_styles: chart.styles,
      defaults: [theme.defaults, chart.defaults, Map.get(node, :defaults)],
      defs: Map.merge(chart.defs, inline_paints(chart, styles, theme)),
      now: now,
      schemas: schemas,
      system: system,
      forces: forces
    }
  end

  # The gradients the design's styles write inline (spec/14 §3.2, D-172), held beside the
  # declared paints so the frame draws both alike: the named styles, the palette among
  # them, every style node written at a site — a mark's and its label's, a label's, an
  # axis's and a legend's — and every defaults node (spec/14 §3.8).
  defp inline_paints(chart, styles, theme) do
    sites =
      Enum.flat_map(chart.marks, fn mark ->
        stack(mark) ++ stack(Map.get(mark, :label))
      end) ++
        Enum.flat_map(chart.labels, &stack/1) ++
        Enum.flat_map(Map.values(chart.frames || %{}), fn frame ->
          Enum.flat_map(List.wrap(Map.get(frame, :axes)), &stack/1) ++
            stack(Map.get(frame, :legend))
        end)

    defaults =
      Defaults.nodes(
        [theme.defaults, chart.defaults] ++
          Enum.map(chart.marks ++ chart.labels, &Map.get(&1, :defaults)) ++
          Enum.flat_map(Map.values(chart.frames || %{}), fn frame ->
            [Map.get(frame, :defaults) | Enum.map(List.wrap(Map.get(frame, :axes)), &defaults/1)]
          end)
      )

    Parts.inline_paints(Map.values(styles) ++ sites ++ defaults)
  end

  defp stack(%{style: stack}) when is_map(stack) or is_list(stack), do: List.wrap(stack)
  defp stack(_node), do: []

  defp defaults(node) when is_map(node), do: Map.get(node, :defaults)
  defp defaults(_node), do: nil

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

  @doc """
  The box the frame's legend is laid out in, `%{width: w, height: h}` in user units, not
  counting the 8 between it and the plot (spec/14 §4.5, D-169): the widest row and
  (rows − 1) × 16 + 12 for a top or bottom legend, the estimated width and
  (entries − 1) × 16 + 12 for a stacked one, the title counted as an entry. A frame with
  no legend is `%{width: 0, height: 0}`. A host laying out around a chart asks it rather
  than repeating the text estimate.
  """
  @spec legend_extent(t()) :: %{width: number(), height: number()}
  def legend_extent(%__MODULE__{} = frame), do: Legend.extent(frame)

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
        attrs: Map.merge(sync_attrs(frame), brush_attrs(frame)),
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

  @doc """
  The attributes of a sync group for the frame it reads (spec/14 §2.9, D-116):
  `data-vis-sync`, the group, and `data-vis-sync-x`, `d0,d1,x0,x1,width` — the `x`
  scale's domain (milliseconds since the Unix epoch for a time scale), the chart pixels of
  its ends and the chart's width — which is all the hooks need to map a shared x through
  this frame's own scale. `%{}` for a frame that is no group's.

      iex> chart = Visualize.Chart.from_map!(%{version: 2,
      ...>   interaction: %{sync: "dash"},
      ...>   frames: %{main: %{kind: :cartesian, scales: %{x: %{kind: :linear, domain: [0, 100]}}}}})
      iex> Visualize.Chart.Frame.new(chart, size: {300, 200}) |> Visualize.Chart.Frame.sync_attrs()
      %{"data-vis-sync" => "dash", "data-vis-sync-x" => "0,100,40,280,300"}
  """
  @spec sync_attrs(t()) :: %{String.t() => String.t()}
  def sync_attrs(%__MODULE__{sync: nil}), do: %{}

  def sync_attrs(%__MODULE__{sync: group} = frame) do
    %{"data-vis-sync" => group, "data-vis-sync-x" => numbers(x_mapping(frame))}
  end

  @doc """
  The attributes of the design's brush for the frame it brushes (spec/14 §2.9, D-143):
  `data-vis-brush`, its kind; `data-vis-brush-x`, the `x` mapping exactly as
  `sync_attrs/1` gives it; and `data-vis-brush-extent`, `x0,y0,x1,y1`, the plot area in
  the chart's coordinates — what `BrushHook` captures over and turns into a window in
  domain units (spec/10 §6.5). `%{}` for a frame the design does not brush.

      iex> chart = Visualize.Chart.from_map!(%{version: 2,
      ...>   interaction: %{brush: :x},
      ...>   frames: %{main: %{kind: :cartesian, scales: %{x: %{kind: :linear, domain: [0, 100]}}}}})
      iex> Visualize.Chart.Frame.new(chart, size: {300, 200}) |> Visualize.Chart.Frame.brush_attrs()
      %{"data-vis-brush" => "x", "data-vis-brush-extent" => "40,20,280,170", "data-vis-brush-x" => "0,100,40,280,300"}
  """
  @spec brush_attrs(t()) :: %{String.t() => String.t()}
  def brush_attrs(%__MODULE__{brush: nil}), do: %{}

  def brush_attrs(%__MODULE__{brush: kind} = frame) do
    [bx, by | _] = frame.box
    left = bx * frame.size.width + frame.margin.left
    top = by * frame.size.height + frame.margin.top
    extent = [left, top, left + frame.plot.width, top + frame.plot.height]

    %{
      "data-vis-brush" => Atom.to_string(kind),
      "data-vis-brush-x" => numbers(x_mapping(frame)),
      "data-vis-brush-extent" => numbers(extent)
    }
  end

  # The `x` scale as the hooks map it: `d0,d1,x0,x1,width` — its domain in the bus's unit,
  # the chart pixels of its ends and the chart's width (spec/14 §2.9).
  defp x_mapping(frame) do
    %{domain: [d0, d1], range: [r0, r1]} = scale(frame, :x)
    [bx | _] = frame.box
    offset = bx * frame.size.width + frame.margin.left
    [domain_unit(d0), domain_unit(d1), r0 + offset, r1 + offset, frame.size.width]
  end

  defp numbers(numbers), do: Enum.map_join(numbers, ",", &Visualize.IR.Path.format_number/1)

  # The design's brush when this frame is the one it reads — the sync frame's rule: the
  # frame `interaction.frame` names, else the design's first by name (spec/14 §2.9).
  defp brush(%Chart{interaction: %{brush: kind} = interaction, frames: frames}, name)
       when kind != nil do
    if (Map.get(interaction, :frame) || frames |> Map.keys() |> Enum.min()) == name, do: kind
  end

  defp brush(_chart, _name), do: nil

  # A value of the x domain in the bus's unit: a number as it is, a time in milliseconds
  # since the Unix epoch, JavaScript's own unit (D-116).
  defp domain_unit(%DateTime{} = t), do: DateTime.to_unix(t, :millisecond)

  defp domain_unit(%NaiveDateTime{} = t),
    do: t |> DateTime.from_naive!("Etc/UTC") |> domain_unit()

  defp domain_unit(%Date{} = d), do: Date.diff(d, ~D[1970-01-01]) * 86_400_000
  defp domain_unit(n) when is_number(n), do: n

  # The group when this frame is the one it reads: the frame `interaction.frame` names, else
  # the design's first by name (spec/14 §2.9).
  defp sync_group(%Chart{interaction: interaction, frames: frames}, name) do
    case interaction do
      %{sync: group} when is_binary(group) ->
        if (Map.get(interaction, :frame) || frames |> Map.keys() |> Enum.min()) == name,
          do: group

      _none ->
        nil
    end
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

  @doc false
  # The point a centred mark is about, in the coordinates its group is drawn in (spec/14
  # §5.6, #488): the plot's middle, or the origin of a `:polar` frame's centred group,
  # which already sits there. An `:arc` mark is translated to it and a `:chord` step's
  # paths are drawn about it, so the ring and its ribbons share one centre.
  @spec centre(kind(), %{width: number(), height: number()}) :: [number()]
  def centre(:polar, _plot), do: [0, 0]
  def centre(_kind, plot), do: [plot.width / 2, plot.height / 2]

  # What a mark's pipeline sees of the frame (spec/14 §5.4).
  defp context(kind, plot, projection, now, schemas, forces) do
    %{
      size: [plot.width, plot.height],
      centre: centre(kind, plot),
      projection: projection,
      now: now,
      schemas: schemas,
      forces: forces
    }
  end

  # The viewer's unit system (spec/14 §4.4, D-156): one of the four, else a fault here.
  defp system(system) do
    if system in Visualize.Quantity.systems(),
      do: system,
      else:
        raise(
          ArgumentError,
          "system: must be one of #{inspect(Visualize.Quantity.systems())}, got #{inspect(system)}"
        )
  end

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

  @doc """
  A frame node's box as fractions of the render's size (spec/14 §4.2): its `box`, or the
  share of the design's `layout` its `cell` and `span` take (§2.8). This is the one place
  a cell resolves; `new/2` reads it, and so does a tool that must know where a frame is
  drawn without realising it (§18.16). `size` is `{width, height}` or `%{width, height}`,
  which the gap is taken out of. Raises `ArgumentError` for a malformed box or cell, as
  `new/2` does.

      iex> Visualize.Chart.Frame.box_of(%{box: [0.5, 0, 0.5, 1]}, nil, {600, 400})
      [0.5, 0, 0.5, 1]

      iex> Visualize.Chart.Frame.box_of(%{cell: [1, 0]}, %{columns: [3, 1]}, {600, 400})
      [0.75, 0.0, 0.25, 1.0]
  """
  @spec box_of(map(), map() | nil, {number(), number()} | map()) :: [number()]
  def box_of(node, layout, size), do: box(node, layout, size(size))

  # A frame's pixel box is its fractions of the render's (spec/14 §4.2).
  defp box(node, layout, size) do
    case {Map.get(node, :cell), Map.get(node, :box, Schema.default(:frame, :box))} do
      {cell, _box} when is_list(cell) ->
        cell(cell, Map.get(node, :span) || [1, 1], layout || %{}, size)

      {_none, [x, y, w, h]}
      when is_number(x) and is_number(y) and is_number(w) and is_number(h) ->
        [x, y, w, h]

      {_none, other} ->
        raise ArgumentError, "box: is [x, y, w, h] in fractions, got #{inspect(other)}"
    end
  end

  # A cell of the design's grid as a box (spec/14 §2.8, #384): the weights are normalised
  # over their sum, so `[4, 3, 2, 1]` and `[8, 6, 4, 2]` are one layout, and the `gap`
  # comes out of the cells — half at each edge a cell shares with another — rather than
  # out of the grid's outer edges.
  defp cell([column, row], [across, down], layout, size)
       when is_integer(column) and is_integer(row) and is_integer(across) and is_integer(down) do
    columns = weights(layout, :columns)
    rows = weights(layout, :rows)
    gap = Map.get(layout, :gap, Schema.default(:layout, :gap)) || 0

    {x, w} = share(columns, column, across, gap / size.width)
    {y, h} = share(rows, row, down, gap / size.height)
    [x, y, w, h]
  end

  defp cell(cell, span, _layout, _size) do
    raise ArgumentError,
          "cell: is [column, row] with span [across, down], got #{inspect({cell, span})} " <>
            "(spec/14 §2.8)"
  end

  defp weights(layout, key) do
    case Map.get(layout, key, Schema.default(:layout, key)) do
      weights when is_list(weights) and weights != [] -> weights
      _other -> [1]
    end
  end

  # The share of the box the cells `at … at + count - 1` take, less half the gap at each
  # edge they share with a neighbour: `{offset, size}` in fractions.
  defp share(weights, at, count, gap) do
    total = Enum.sum(weights)
    before = weights |> Enum.take(at) |> Enum.sum()
    taken = weights |> Enum.slice(at, count) |> Enum.sum()

    lead = if at == 0, do: 0.0, else: gap / 2
    trail = if at + count >= length(weights), do: 0.0, else: gap / 2

    {before / total + lead, taken / total - lead - trail}
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
  defp theme(%Var{name: name}, nil), do: Style.unresolved!(name)

  defp theme(node, nil) when is_map(node) do
    Enum.each(node, fn {_, v} -> match?(%Var{}, v) and Style.unresolved!(v.name) end)
    Theme.new(node)
  end

  defp theme(name, nil) do
    Theme.builtin(name) || unknown_theme!(name)
  end

  defp unknown_theme!(name) do
    raise ArgumentError,
          "theme #{inspect(name)} is neither built-in nor inline; pass it as the :theme " <>
            "option of Visualize.Chart.Frame.new/2"
  end

  defp projection(:geo, node, plot, sources) do
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
    |> fit(Map.get(spec, :fit), plot, sources)
  end

  defp projection(_kind, _node, _plot, _sources), do: nil

  # The view fitted to a source (spec/14 §4.6, #475): every point of its rows — before any
  # mark's transforms — fills the plot inset by the padding, through
  # `Visualize.Geo.Projection.fit/3`, which keeps `center` and `rotate` and so keeps a
  # Mercator projection tile-aligned. An unbound source, or one with no point, fits nothing.
  defp fit(projection, nil, _plot, _sources), do: projection
  defp fit(_projection, %Var{name: name}, _plot, _sources), do: Style.unresolved!(name)

  defp fit(projection, %{data: name} = node, plot, sources) do
    case Map.fetch(sources, name) do
      {:ok, source} ->
        points = source |> Visualize.Data.Table.rows() |> Enum.flat_map(&fit_points(&1, node))
        pad = Map.get(node, :padding, Schema.default(:fit, :padding))
        box = [[pad, pad], [plot.width - pad, plot.height - pad]]
        Projection.fit(projection, box, points)

      :error ->
        projection
    end
  end

  defp fit_points(row, %{field: field}) when is_map(row),
    do: positions(Visualize.Data.Table.get(row, field))

  defp fit_points(row, %{fields: [lon, lat]}) when is_map(row),
    do: positions([Visualize.Data.Table.get(row, lon), Visualize.Data.Table.get(row, lat)])

  defp fit_points(_row, _node), do: []

  # Every position of a GeoJSON value at any depth: a position is a list whose first two
  # members are numbers; a geometry's `coordinates`, a collection's `geometries`, a
  # feature's `geometry` and a feature collection's `features` are walked.
  defp positions([lon, lat | _]) when is_number(lon) and is_number(lat), do: [{lon, lat}]
  defp positions(list) when is_list(list), do: Enum.flat_map(list, &positions/1)

  defp positions(%{} = geo) when not is_struct(geo) do
    keys =
      [coordinates: "coordinates", geometries: "geometries"] ++
        [geometry: "geometry", features: "features"]

    Enum.flat_map(keys, fn {atom, string} ->
      positions(Map.get(geo, string) || Map.get(geo, atom))
    end)
  end

  defp positions(_other), do: []

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
    base = Defaults.at(frame, nil, :text)
    style = Style.resolve(Style.over(base, frame.styles, :label), frame.theme, mode)

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

  # A basemap's `:tiles` marks are drawn first, beneath every other mark whatever the
  # design's order (spec/14 §5.2, D-119); each keeps its own position for its paint and
  # its path.
  defp marks(frame, mode, sources, paths?, opts) do
    frame.marks
    |> Enum.with_index(fn mark, i -> {mark, i} end)
    |> Mark.drawing_order()
    |> Enum.map(fn {mark, i} ->
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
