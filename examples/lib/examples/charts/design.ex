defmodule Examples.Charts.Design do
  @moduledoc """
  What a gallery chart written as a design shares (#124).

  A converted chart module is a *design plus its data*: `design/1` returns the design map —
  folded from `Visualize.Chart.Build` fragments through `Visualize.Chart.compose/1` — and
  the rows its sources bind to, and `render/1` is `render/2` of this module over the two.
  Nothing here draws: the drawing is `Visualize.Chart.render/2`.

  Three things the gallery needs that a design does not carry, each in one place rather than
  in twenty-nine modules:

  - **The theme is the picker's.** The gallery's `theme` option, a key of
    `Examples.Themes.list/0`, becomes the `theme:` of `Visualize.Chart.apply/2`
    (`Examples.Themes.theme/1`), so a mark that names no color paints in the theme's series
    slots and a theme swap recolors every chart.
  - **The `<svg>` shell** is the library's: `Visualize.Chart.render/2` with `root: true`
    draws the accessible root of spec/02 §2.1 around the frame, titled from the design's
    `meta` (#131).
  - **The canvas.** The same applied chart through the binary canvas backend, which is what
    the gallery's backend selector pushes to `CanvasBinaryChart`.
  """

  alias Examples.Themes
  alias Visualize.Chart
  alias Visualize.Chart.Frame

  @hierarchy_fields [:id, :parent, :name, :value, :branch]

  @doc """
  The fragments folded into a design (spec/14 §16.1).

  A chart writes no design node of its own, so a fault here is a fault of
  `Visualize.Chart.compose/2` rather than of the chart.
  """
  @spec fold([map()]) :: map()
  def fold(fragments) do
    {:ok, design} = Chart.compose(fragments)
    design
  end

  # A polar label's inset from the rim, and every corner label's from the plot's edge
  # (spec/14 §5.5, §6.3).
  @inset 4

  @doc """
  The outer radius of a ring whose labels sit outside it (spec/14 §5.5, #489): half the
  plot's smaller side, less the room the longest label takes on its spoke — the label's
  inset and `dr` from the rim, its estimated width (`Visualize.Chart.Text.width/2`) at
  `font_size`, and the inset from the plot's edge — so no ring label leaves the plot.
  `plot` is the plot area's `{width, height}`.

      iex> Examples.Charts.Design.ring_radius({400, 400}, ["Wednesday", "Friday"], 11, 11)
      121.6
  """
  @spec ring_radius({number(), number()}, [String.t()], number(), number()) :: float()
  def ring_radius({width, height}, labels, font_size, dr) do
    longest = labels |> Enum.map(&Chart.Text.width(&1, font_size)) |> Enum.max(fn -> 0.0 end)
    Float.round(min(width, height) / 2 - (@inset + dr + longest + @inset), 6)
  end

  @doc """
  True when `module` is a chart written as a design rather than an imperative one.

  The module is loaded first: `function_exported?/3` answers for a module that is not yet
  loaded with `false`, and in a release-less app nothing has loaded it before the first call.
  """
  @spec design?(module()) :: boolean()
  def design?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :design, 1)
  end

  @doc """
  Whether the module's design eases anything — a `transition` on a scale (spec/14 §4.3,
  #360) or on a mark (§5.1, #417) — so a run of it keeps a compiled chart on SVG too, the
  easing having nowhere else to live.
  """
  @spec transitions?(module()) :: boolean()
  def transitions?(module) do
    {design, _sources} = module.design([])

    frame = get_in(design, Visualize.Chart.Fragment.frame_path(design)) || %{}

    Enum.any?(Map.get(frame, :scales, %{}), fn {_name, scale} ->
      Map.has_key?(scale, :transition)
    end) or Enum.any?(Map.get(design, :marks, []), &Map.has_key?(&1, :transition))
  end

  @doc """
  Whether a run of the module's design carries state from one tick to the next, so it
  keeps a compiled chart on SVG too: it eases (`transitions?/1`), or a mark lays out a
  graph with a `:force` step, whose layout a compiled chart keeps warm (spec/14 §12.5,
  #527, D-132).
  """
  @spec stateful?(module()) :: boolean()
  def stateful?(module), do: transitions?(module) or force?(module)

  defp force?(module) do
    {design, _sources} = module.design([])

    Enum.any?(Map.get(design, :marks, []), fn mark ->
      case Map.get(mark, :data) do
        %{transforms: steps} when is_list(steps) -> Enum.any?(steps, &match?(%{op: :force}, &1))
        _source -> false
      end
    end)
  end

  @doc """
  One SVG frame of a design's compiled charts at their eased scales, as the gallery's
  document, and the compiled charts after it (spec/14 §12.5, #360, #432):
  `Visualize.Chart.Compiled.step/3` per frame — each group already placed at its box
  (§12.1) — inside the accessible root the module's title and description name, the
  description followed by the `summary:` of the opts (spec/14 §21.1) when they carry one.

  `compiled` is the `{name, compiled}` list `Examples.Frames.prepare/3` keeps, in the
  order the frames draw; `opts` are the tick's, `now:` and `at:` among them.
  """
  @spec step(module(), [{atom(), Chart.Compiled.t()}], map(), map(), keyword()) ::
          {String.t(), [{atom(), Chart.Compiled.t()}]}
  def step(module, compiled, design, sources, opts) do
    tick = Keyword.take(opts, [:now, :at, :motion])

    {groups, stepped} =
      Enum.map_reduce(compiled, [], fn {name, one}, acc ->
        node = get_in(design, [:frames, name])
        {group, one} = Chart.Compiled.step(one, sources, [frame: node] ++ tick)
        {group, [{name, one} | acc]}
      end)

    [{_name, first} | _] = compiled

    # The summary of the chart as it was prepared (spec/14 §21.1): applying the design
    # again on every frame to say it would cost the run what it measures.
    description =
      case Keyword.get(opts, :summary) do
        nil -> module.description()
        summary -> module.description() <> ". " <> summary
      end

    svg =
      Visualize.IR.Element.root(first.size.width, first.size.height,
        title: module.title(),
        description: description,
        children: groups
      )
      |> Visualize.Render.to_string()

    {svg, Enum.reverse(stepped)}
  end

  @doc "The module's design applied over its rows, with the `theme` option's theme."
  @spec applied(module(), keyword()) :: Chart.Applied.t()
  def applied(module, opts) do
    {design, sources} = module.design(opts)

    {:ok, applied} =
      Chart.apply(design, sources: sources, theme: theme(opts), size: size(module, opts))

    applied
  end

  @doc """
  The size a chart is drawn at: the caller's `width`/`height` where it gives them, else
  the module's own `size/0` where it has one, else the render's default (spec/14 §4.2,
  #427). A design records no size, so this is where the number comes from.
  """
  @spec size(module(), keyword()) :: {number(), number()}
  def size(module, opts) do
    {width, height} =
      if Code.ensure_loaded?(module) and function_exported?(module, :size, 0),
        do: module.size(),
        else: Frame.default_size()

    {opts[:width] || width, opts[:height] || height}
  end

  @doc """
  The size the gallery draws a chart at in a container `width` wide: that width, capped at
  the module's design width, and the height at the design's aspect (spec/10 §10.2, #457).
  A narrow container shrinks a chart; a wide one never grows it past its design.
  """
  @spec fitted(module(), pos_integer()) :: {pos_integer(), pos_integer()}
  def fitted(module, width) when is_integer(width) and width > 0 do
    {design_w, design_h} = size(module, [])
    capped = min(width, design_w)
    {capped, round(capped * design_h / design_w)}
  end

  @doc """
  The module's design drawn as the gallery's `<svg>` document: `Visualize.Chart.render/2`
  with `root: true`, the accessible root titled from the design's own `meta` (#131).
  """
  @spec render(module(), keyword()) :: String.t()
  def render(module, opts), do: Chart.render(applied(module, opts), root: true)

  @doc "The module's design through the binary canvas backend, base64 for the hook."
  @spec canvas(module(), keyword()) :: String.t()
  def canvas(module, opts) do
    module
    |> applied(opts)
    |> Chart.render(backend: :canvas, format: :binary_base64)
  end

  @doc """
  The module's design as the hybrid split of spec/14 §12 (#268): the furniture as the
  compiled charts' static SVG and every mark of more than a point on the binary canvas —
  `canvas` base64 for the `CanvasBinaryChart` hook, `""` when no mark goes there — with
  the design's size, for the page to layer the two.

  A design of several frames has one plot per frame (§12.1, #432), and `plots` carries
  them in drawing order with the geometry each canvas is placed by; `static` is the
  frames' documents stacked and `canvas` the first plot's, so a page that draws one
  canvas reads what it always did. `backdrop` is what goes beneath the canvases: every
  plot's static backdrop and its tick's, stacked — a basemap's tiles (§12.4, #476).
  """
  @spec hybrid(module(), keyword()) :: %{
          static: String.t(),
          canvas: String.t(),
          dynamic_svg: String.t(),
          backdrop: String.t(),
          plots: [map()],
          width: number(),
          height: number()
        }
  def hybrid(module, opts) do
    applied = applied(module, opts)
    {:ok, frames} = Chart.compile(applied, ceiling: 1)

    plots =
      for {name, _realized} <- ordered(applied) do
        compiled = Map.fetch!(frames, name)
        {payload, _compiled} = Visualize.Chart.Compiled.tick(compiled, applied.sources)

        %{
          name: name,
          static: Visualize.Chart.Compiled.static(compiled),
          canvas: payload.canvas,
          dynamic_svg: payload.svg,
          backdrop: Visualize.Chart.Compiled.backdrop(compiled) <> payload.backdrop,
          box: compiled.box,
          plot: compiled.plot,
          margin: compiled.margin
        }
      end

    %{
      static: Enum.map_join(plots, "", & &1.static),
      canvas: plots |> hd() |> Map.fetch!(:canvas),
      dynamic_svg: Enum.map_join(plots, "", & &1.dynamic_svg),
      backdrop: Enum.map_join(plots, "", & &1.backdrop),
      plots: plots,
      width: applied.frame.size.width,
      height: applied.frame.size.height
    }
  end

  # The design's frames in the order they draw: `z`, ties by name (spec/14 §4.2).
  defp ordered(applied),
    do: Enum.sort_by(applied.frames, fn {name, f} -> {f.z, to_string(name)} end)

  @doc """
  The columns of `nodes/1`'s rows: what a hierarchy chart's source declares.
  """
  @spec hierarchy_fields() :: [atom()]
  def hierarchy_fields, do: @hierarchy_fields

  @doc """
  A nested `%{name, value, children}` map as the flat node list a hierarchy transform reads
  (spec/14 §5.4.2): one row per node in pre-order — the dotted position as `id`, its
  parent's, the node's `name` and `value` (`0` when absent), and `branch`, the index of
  the root's child it descends from, which is what a hierarchy's color scale reads (D-46;
  `nil` for the root). The mapping `Visualize.Chart.Presets.sources/2` applies to a
  component's tree, for the gallery's own trees.
  """
  @spec nodes(map()) :: [map()]
  def nodes(tree), do: flatten(tree, "0", nil, nil)

  defp flatten(node, id, parent, branch) do
    row = %{id: id, parent: parent, name: node[:name], value: node[:value] || 0, branch: branch}

    children =
      (node[:children] || [])
      |> Enum.with_index()
      |> Enum.flat_map(fn {child, i} -> flatten(child, "#{id}.#{i}", id, branch || i) end)

    [row | children]
  end

  @doc "The plot area of a frame of `width` by `height` with `margin` (spec/14 §4.2)."
  @spec plot(number(), number(), map()) :: {number(), number()}
  def plot(width, height, margin) do
    {width - margin.left - margin.right, height - margin.top - margin.bottom}
  end

  @doc """
  The `theme` option as a `Visualize.Theme`: a key looked up in `Examples.Themes.list/0`,
  the gallery's Default when absent or unlisted, or a theme itself — what
  `Examples.Themes.Changes` draws a chart under to learn what it draws.
  """
  @spec theme(keyword()) :: Visualize.Theme.t()
  def theme(opts) do
    case opts[:theme] do
      %Visualize.Theme{} = theme -> theme
      key -> Themes.theme(key)
    end
  end
end
