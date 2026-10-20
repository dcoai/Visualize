if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Components.Chart do
    @moduledoc """
    A chart whose marks declare events, in LiveView (spec/10 §19, D-170).

    A `Phoenix.LiveComponent` over a `%Visualize.Chart.Applied{}`. It draws the chart —
    as SVG by default, or on a canvas — inside `TooltipHook`, the datum under the pointer
    outlined as the palette's `:hover` (`Visualize.Hooks.Tooltip.attrs/1`), holds the
    drawing and a token for it, and resolves a click on a mark's datum to the row that was
    drawn. The page receives the click as one `Visualize.Event`, the same on every backend
    (D-197):

        <.live_component module={Visualize.Components.Chart} id="sales" chart={@applied} />

        def handle_info({:visualize_event, "sales", %Visualize.Event{event: "point_click", row: row}}, socket) do
          {:noreply, assign(socket, picked: row)}
        end

    A click is dropped, never forwarded with partial data, when it was made on a drawing
    the component no longer holds, names an event its mark does not declare, or names a row
    the drawing does not have. A chart whose marks declare no event needs no component.

    ## Assigns

      * `id` - the component's id, its hook element's DOM id, and the `id` of the events it
        sends (required)
      * `chart` - the `%Visualize.Chart.Applied{}` drawn (required)
      * `backend` - `:svg` (default) or `:canvas`: on a canvas the drawing carries its hit
        index, `Visualize.Hooks.Tooltip.items/1`, so a click resolves as on the SVG
      * `canvas_format` - `:binary` (default) for `CanvasBinaryChart`, or `:json` for
        `CanvasChart`; the binary stream draws no text, so its text is laid over the canvas
        as an SVG layer
      * `render` - options for `Visualize.Chart.render/2` — `title:`, `description:`,
        `responsive:` … — the SVG always a root (default `[]`)
      * `tooltip_class` - the hook's `data-tooltip-class` (default `"vis-tooltip"`)
    """

    use Phoenix.LiveComponent

    alias Visualize.Chart
    alias Visualize.Chart.{Applied, Summary}
    alias Visualize.Event
    alias Visualize.Hooks.{Keyboard, Tooltip}
    alias Visualize.IR.Element

    @impl true
    def mount(socket) do
      {:ok,
       assign(socket,
         drawing: nil,
         drawn: nil,
         svg: nil,
         canvas: nil,
         hover: %{},
         keyboard: %{},
         motion: false
       )}
    end

    @impl true
    def update(%{id: id, chart: %Applied{} = chart} = assigns, socket) do
      render_opts = Map.get(assigns, :render, [])

      backend =
        backend!(Map.get(assigns, :backend, :svg), Map.get(assigns, :canvas_format, :binary))

      socket =
        socket
        |> assign(id: id, tooltip_class: Map.get(assigns, :tooltip_class, "vis-tooltip"))
        |> draw({chart, render_opts, backend})

      {:ok, socket}
    end

    defp backend!(:svg, _format), do: :svg
    defp backend!(:canvas, format) when format in [:binary, :json], do: {:canvas, format}

    defp backend!(backend, format) do
      raise ArgumentError,
            "backend: :svg or :canvas with canvas_format: :binary or :json is needed, " <>
              "got: #{inspect({backend, format})}"
    end

    # A new chart, new render options or a new backend is a new drawing with a new token
    # (spec/10 §19.3); the same ones keep both, so an unrelated update does not drop a
    # click in flight.
    defp draw(%{assigns: %{drawing: drawing}} = socket, drawing), do: socket

    defp draw(socket, {chart, render_opts, backend} = drawing) do
      assign(socket,
        drawing: drawing,
        drawn: Integer.to_string(System.unique_integer([:positive, :monotonic])),
        hover: Tooltip.attrs(chart.frame),
        # Every point and every keyed item reached from the keyboard (spec/10 §17, D-198).
        keyboard: Keyboard.attrs(chart)
      )
      |> assign(drawn_as(backend, chart, render_opts))
    end

    defp drawn_as(:svg, chart, render_opts) do
      svg = Chart.render(chart, [root: true] ++ render_opts)
      # A drawing that names identities plays its exits and enters (spec/10 §19.3, §20).
      %{svg: svg, canvas: nil, motion: String.contains?(svg, "data-vis-id")}
    end

    # On a canvas (spec/10 §19.3, D-197): the stream, the hit index and the size from one
    # generated tree in literal colors, and on the binary stream the text it cannot carry.
    defp drawn_as({:canvas, format}, chart, render_opts) do
      tree = Chart.generate(chart, resolve: :literal)
      %{width: width, height: height} = chart.frame.size
      summary = Summary.new(chart)
      title = Keyword.get(render_opts, :title, summary.name)

      canvas = %{
        format: format,
        width: width,
        height: height,
        stream: stream(tree, format),
        text: if(format == :binary, do: text_layer(tree, width, height)),
        items: Tooltip.items(tree),
        summary: %{summary | name: title}
      }

      %{svg: nil, canvas: canvas, motion: false}
    end

    defp stream(tree, :binary),
      do: Visualize.Render.to_string(tree, backend: :canvas, format: :binary_base64)

    defp stream(tree, :json),
      do: Visualize.Render.to_string(tree, backend: :canvas, format: :json)

    # The chart's text as an SVG over the canvas, `aria-hidden` and taking no pointer: one
    # picture with the canvas, which names it. `nil` for a chart that draws no text.
    defp text_layer(tree, width, height) do
      case only_text(tree) do
        nil ->
          nil

        text ->
          Element.root(width, height, hidden: true, children: [text])
          |> Visualize.Render.to_string(backend: :svg)
      end
    end

    defp only_text(%Element{type: :text} = element), do: element

    defp only_text(%Element{type: :group, children: children} = element) do
      case children |> Enum.map(&only_text/1) |> Enum.reject(&is_nil/1) do
        [] -> nil
        kept -> %{element | children: kept}
      end
    end

    defp only_text(_element), do: nil

    @impl true
    def handle_event("visualize_event", params, socket) do
      %{id: id, drawing: {chart, _render_opts, _backend}, drawn: drawn} = socket.assigns

      with {:ok, click} <- Event.decode(params),
           {:ok, event} <- Event.resolve(click, chart, drawn: drawn) do
        send(self(), {:visualize_event, id, event})
      end

      {:noreply, socket}
    end

    def handle_event(_event, _params, socket), do: {:noreply, socket}

    @impl true
    def render(%{canvas: nil} = assigns) do
      ~H"""
      <div id={"#{@id}-keys"} phx-hook="KeyboardHook" {@keyboard}>
        <div
          id={@id}
          phx-hook="TooltipHook"
          data-tooltip-target={@myself}
          data-tooltip-drawn={@drawn}
          data-tooltip-class={@tooltip_class}
          {@hover}
        >
          <div :if={@motion} id={"#{@id}-motion"} phx-hook="MotionHook">{Phoenix.HTML.raw(@svg)}</div>
          {if @motion, do: nil, else: Phoenix.HTML.raw(@svg)}
        </div>
      </div>
      """
    end

    def render(assigns) do
      ~H"""
      <div id={"#{@id}-keys"} phx-hook="KeyboardHook" {@keyboard}>
      <div
        id={@id}
        phx-hook="TooltipHook"
        data-tooltip-target={@myself}
        data-tooltip-drawn={@drawn}
        data-tooltip-class={@tooltip_class}
        data-vis-items={@canvas.items}
        data-size={"#{@canvas.width},#{@canvas.height}"}
        {@hover}
      >
        <div
          class="vis-chart-layers"
          style={"position: relative; width: #{@canvas.width}px; height: #{@canvas.height}px;"}
          {Summary.attrs(@canvas.summary, "#{@id}-access")}
        >
          {Phoenix.HTML.raw(Summary.description(@canvas.summary, "#{@id}-access"))}
          <div
            :if={@canvas.format == :binary}
            id={"#{@id}-canvas"}
            phx-hook="CanvasBinaryChart"
            phx-update="ignore"
            data-binary={@canvas.stream}
            data-width={@canvas.width}
            data-height={@canvas.height}
          >
            <canvas width={@canvas.width} height={@canvas.height} style="display: block;"></canvas>
          </div>
          <div
            :if={@canvas.format == :json}
            id={"#{@id}-canvas"}
            phx-hook="CanvasChart"
            phx-update="ignore"
            data-commands={@canvas.stream}
            data-width={@canvas.width}
            data-height={@canvas.height}
          >
            <canvas width={@canvas.width} height={@canvas.height} style="display: block;"></canvas>
          </div>
          <div
            :if={@canvas.text}
            class="vis-chart-text"
            style="position: absolute; top: 0; left: 0; pointer-events: none;"
          >
            {Phoenix.HTML.raw(@canvas.text)}
          </div>
        </div>
      </div>
      </div>
      """
    end
  end
end
