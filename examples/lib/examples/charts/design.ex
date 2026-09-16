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
  - **The `<svg>` shell.** `Visualize.Chart.render/2` draws the frame's group, not a
    document, so the accessible root of spec/02 §2.1 is built here with
    `Visualize.IR.Element.root/3` and the group placed inside it (#131).
  - **The canvas.** The same applied chart through the binary canvas backend, which is what
    the gallery's backend selector pushes to `CanvasBinaryChart`.
  """

  alias Examples.ColorPalettes
  alias Visualize.Chart
  alias Visualize.IR.Element
  alias Visualize.Render

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
  The module's design drawn as the gallery's `<svg>` document.

  `Visualize.Chart.render/2` of the applied chart, inside the accessible root the module's
  `title/0` and `description/0` name.
  """
  @spec render(module(), keyword()) :: String.t()
  def render(module, opts) do
    applied = applied(module, opts)
    %{size: size} = applied.frame

    document(
      Chart.render(applied),
      size.width,
      size.height,
      module.title(),
      module.description()
    )
  end

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

  @doc "The plot area of a frame of `width` by `height` with `margin` (spec/14 §4.2)."
  @spec plot(number(), number(), map()) :: {number(), number()}
  def plot(width, height, margin) do
    {width - margin.left - margin.right, height - margin.top - margin.bottom}
  end

  @doc "The `palette` option as a `Visualize.Theme`, the default palette when absent."
  @spec theme(keyword()) :: Visualize.Theme.t()
  def theme(opts), do: ColorPalettes.theme(opts[:palette] || :default)

  # The `<svg>` around the frame's group. `Visualize.Chart.render/2` returns the group as a
  # string, so the root is rendered empty — its `role`, `<title>`, `<desc>` and
  # `aria-labelledby` are `Visualize.IR.Element.root/3`'s own (D-56) — and the group goes
  # in before the closing tag. A design that rendered its own document would not need this
  # (#131).
  defp document(group, width, height, title, description) do
    Element.root(width, height, title: title, description: description)
    |> Render.to_string()
    |> String.replace_suffix("</svg>", group <> "</svg>")
  end
end
