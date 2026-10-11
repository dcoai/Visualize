defmodule Visualize.Backend.Hybrid do
  @moduledoc """
  Hybrid SVG/Canvas backend for optimized rendering.

  Renders static elements (axes, labels, grids) as SVG and dynamic
  data (lines, points, areas) as Canvas commands. This provides the
  best of both worlds:

  - SVG for crisp, accessible static elements (rendered once)
  - Canvas for efficient high-frequency data updates

  ## Usage

      # Build your chart elements
      axis_elements = build_axes(scales)
      data_path = Shape.Line.generate_path(line, data)

      # Render hybrid output
      output = Visualize.Backend.Hybrid.render(
        static: axis_elements,
        dynamic: data_path,
        width: 800,
        height: 600,
        margin: %{top: 20, right: 20, bottom: 30, left: 40}
      )

      # Returns %{svg: "...", canvas_commands: "...", container: "..."}

  ## In LiveView

      <div class="hybrid-chart" style="position: relative;">
        <!-- Static SVG background (render once or on resize) -->
        <%= Phoenix.HTML.raw(@chart.svg) %>

        <!-- Dynamic Canvas overlay (updates frequently) -->
        <div
          id="chart-canvas"
          phx-hook="CanvasChart"
          data-commands={@chart.canvas_commands}
          data-width={@width}
          data-height={@height}
          style="position: absolute; top: 0; left: 0;"
        >
          <canvas width={@width} height={@height}></canvas>
        </div>
      </div>

  """

  alias Visualize.Backend.{Canvas, SVG}
  alias Visualize.IR.{Element, Path, Transform}

  @doc """
  Renders a hybrid chart with SVG static elements and Canvas dynamic data.

  ## Options

    * `:static` - List of IR.Element for static rendering (axes, labels, grid)
    * `:dynamic` - IR.Path or IR.Element for dynamic data
    * `:dynamic_style` - Style map for the dynamic element (stroke, fill, etc.)
    * `:width` - Chart width
    * `:height` - Chart height
    * `:margin` - Margin map with :top, :right, :bottom, :left
    * `:canvas_format` - Canvas output format: `:json` (default), `:js` or `:commands`;
      the container's `CanvasChart` hook (`Visualize.Hooks.Canvas`) replays `:json` from
      `data-commands` and `:js` from `data-script`
    * `:title`, `:description` - the chart's accessible name and description (spec/14
      §21.4, D-142), put on the `<canvas>` of `html` as `Visualize.Backend.Canvas`'s root
      wrapper puts them; `Visualize.Chart.Summary`'s name and text
    * `:canvas_id` - the prefix of the description's id (default
      `"visualize-hybrid-canvas"`), unique per chart on a page

  The SVG layer is `aria-hidden`: it is one layer of a picture the canvas names.

  ## Returns

    * `%{svg: String.t(), canvas: String.t(), html: String.t()}`

  """
  @spec render(keyword()) :: %{svg: String.t(), canvas: String.t(), html: String.t()}
  def render(opts) do
    width = Keyword.fetch!(opts, :width)
    height = Keyword.fetch!(opts, :height)
    margin = Keyword.get(opts, :margin, %{top: 20, right: 20, bottom: 30, left: 40})
    static = Keyword.get(opts, :static, [])
    dynamic = Keyword.get(opts, :dynamic)

    dynamic_style =
      Keyword.get(opts, :dynamic_style, %{stroke: "#4e79a7", fill: :none, stroke_width: 2})

    canvas_format = Keyword.get(opts, :canvas_format, :json)

    # Render static SVG (axes, labels, grid)
    svg = render_static_svg(static, width, height, margin)

    # Render dynamic Canvas commands (data)
    canvas = render_dynamic_canvas(dynamic, dynamic_style, margin, canvas_format)

    # Generate combined HTML container
    named =
      {Keyword.get(opts, :canvas_id, "visualize-hybrid-canvas"), Keyword.get(opts, :title),
       Keyword.get(opts, :description)}

    html = generate_html(svg, canvas, width, height, canvas_format, named)

    %{
      svg: svg,
      canvas: canvas,
      html: html
    }
  end

  @doc """
  Renders only the static SVG portion (for initial render or resize): an `aria-hidden`
  root, one layer of a picture another element names (spec/14 §21.4).
  """
  @spec render_static(keyword()) :: String.t()
  def render_static(opts) do
    width = Keyword.fetch!(opts, :width)
    height = Keyword.fetch!(opts, :height)
    margin = Keyword.get(opts, :margin, %{top: 20, right: 20, bottom: 30, left: 40})
    static = Keyword.get(opts, :static, [])

    render_static_svg(static, width, height, margin)
  end

  @doc """
  Renders only the dynamic Canvas portion (for data updates).
  """
  @spec render_dynamic(keyword()) :: String.t()
  def render_dynamic(opts) do
    margin = Keyword.get(opts, :margin, %{top: 20, right: 20, bottom: 30, left: 40})
    dynamic = Keyword.get(opts, :dynamic)

    dynamic_style =
      Keyword.get(opts, :dynamic_style, %{stroke: "#4e79a7", fill: :none, stroke_width: 2})

    canvas_format = Keyword.get(opts, :canvas_format, :json)

    render_dynamic_canvas(dynamic, dynamic_style, margin, canvas_format)
  end

  # Private functions

  defp render_static_svg(static_elements, width, height, margin) do
    # Wrap static elements in a group with margin transform
    static_group =
      Element.group(List.wrap(static_elements),
        transform: Transform.translate(margin.left, margin.top)
      )

    # Create SVG root with transparent background (so canvas shows through)
    root = Element.root(width, height, hidden: true, children: [static_group])

    SVG.render_element(root, [])
    |> IO.iodata_to_binary()
  end

  defp render_dynamic_canvas(nil, _style, _margin, _format), do: ""

  defp render_dynamic_canvas(%Path{} = path, style, margin, format) do
    # Create element from path with style
    element =
      Element.path(path, style)
      |> Element.set_transform(Transform.translate(margin.left, margin.top))

    Canvas.render_element(element, format: format)
    |> IO.iodata_to_binary()
  end

  defp render_dynamic_canvas(%Element{} = element, _style, margin, format) do
    # Apply margin transform to element
    element = Element.set_transform(element, Transform.translate(margin.left, margin.top))

    Canvas.render_element(element, format: format)
    |> IO.iodata_to_binary()
  end

  defp render_dynamic_canvas(elements, style, margin, format) when is_list(elements) do
    # Wrap multiple elements in a group
    group =
      Element.group(elements, style: style)
      |> Element.set_transform(Transform.translate(margin.left, margin.top))

    Canvas.render_element(group, format: format)
    |> IO.iodata_to_binary()
  end

  defp generate_html(svg, canvas, width, height, format, {id, title, description}) do
    # Escape the canvas commands for HTML attribute
    escaped_canvas =
      canvas
      |> String.replace("\"", "&quot;")
      |> String.replace("<", "&lt;")
      |> String.replace(">", "&gt;")

    data_attr = if format == :json, do: "data-commands", else: "data-script"

    """
    <div class="hybrid-chart" style="position: relative; width: #{width}px; height: #{height}px;">
      <div class="hybrid-svg" style="position: absolute; top: 0; left: 0; pointer-events: none;">
        #{svg}
      </div>
      <div
        class="hybrid-canvas"
        phx-hook="CanvasChart"
        #{data_attr}="#{escaped_canvas}"
        data-width="#{width}"
        data-height="#{height}"
        style="position: absolute; top: 0; left: 0;"
      >
        <canvas width="#{width}" height="#{height}" style="display: block;"#{Canvas.named_canvas(id, title, description)}</canvas>
      </div>
    </div>
    """
  end
end
