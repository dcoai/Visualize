defmodule Examples.Charts.Design do
  @moduledoc """
  What a gallery chart written as a design shares (#124).

  A converted chart module is a *design plus its data*: `design/1` returns the design map —
  folded from `Visualize.Chart.Build` fragments through `Visualize.Chart.compose/1` — and
  the rows its sources bind to, and `render/1` is `render/2` of this module over the two.
  Nothing here draws: the drawing is `Visualize.Chart.render/2`.

  Three things the gallery needs that a design does not carry, each in one place rather than
  in twenty-nine modules:

  - **The palette is the theme.** The gallery's `palette` option becomes the `theme:` of
    `Visualize.Chart.apply/2` (`Examples.ColorPalettes.theme/1`), so a mark that names no
    colour paints in the palette's series slots and a palette swap recolours every chart.
  - **The `<svg>` shell** is the library's: `Visualize.Chart.render/2` with `root: true`
    draws the accessible root of spec/02 §2.1 around the frame, titled from the design's
    `meta` (#131).
  - **The canvas.** The same applied chart through the binary canvas backend, which is what
    the gallery's backend selector pushes to `CanvasBinaryChart`.
  """

  alias Examples.ColorPalettes
  alias Visualize.Chart

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

  @doc """
  True when `module` is a chart written as a design rather than an imperative one.

  The module is loaded first: `function_exported?/3` answers for a module that is not yet
  loaded with `false`, and in a release-less app nothing has loaded it before the first call.
  """
  @spec design?(module()) :: boolean()
  def design?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :design, 1)
  end

  @doc "The module's design applied over its rows, with the `palette` option as the theme."
  @spec applied(module(), keyword()) :: Chart.Applied.t()
  def applied(module, opts) do
    {design, sources} = module.design(opts)
    {:ok, applied} = Chart.apply(design, sources: sources, theme: theme(opts))
    applied
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
  compiled chart's static SVG and every mark of more than a point on the binary canvas —
  `canvas` base64 for the `CanvasBinaryChart` hook, `""` when no mark goes there — with
  the frame's size, for the page to layer the two.
  """
  @spec hybrid(module(), keyword()) :: %{
          static: String.t(),
          canvas: String.t(),
          dynamic_svg: String.t(),
          width: number(),
          height: number()
        }
  def hybrid(module, opts) do
    applied = applied(module, opts)
    {:ok, compiled} = Chart.compile(applied, ceiling: 1)
    {payload, _compiled} = Visualize.Chart.Compiled.tick(compiled, applied.sources)

    %{
      static: Visualize.Chart.Compiled.static(compiled),
      canvas: payload.canvas,
      dynamic_svg: payload.svg,
      width: applied.frame.size.width,
      height: applied.frame.size.height
    }
  end

  @doc """
  The columns of `nodes/1`'s rows: what a hierarchy chart's source declares.
  """
  @spec hierarchy_fields() :: [atom()]
  def hierarchy_fields, do: @hierarchy_fields

  @doc """
  A nested `%{name, value, children}` map as the flat node list a hierarchy transform reads
  (spec/14 §5.4.2): one row per node in pre-order — the dotted position as `id`, its
  parent's, the node's `name` and `value` (`0` when absent), and `branch`, the index of
  the root's child it descends from, which is what a hierarchy's colour scale reads (D-46;
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

  @doc "The `palette` option as a `Visualize.Theme`, the default palette when absent."
  @spec theme(keyword()) :: Visualize.Theme.t()
  def theme(opts), do: ColorPalettes.theme(opts[:palette] || :default)
end
