if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Components.Chart do
    @moduledoc """
    A chart whose marks declare events, in LiveView (spec/10 §19, D-170).

    A `Phoenix.LiveComponent` over a `%Visualize.Chart.Applied{}`. It renders the chart's
    SVG inside `TooltipHook`, the datum under the pointer outlined as the palette's
    `:hover` (`Visualize.Hooks.Tooltip.attrs/1`), holds the drawing and a token for it, and
    resolves a click on a mark's datum to the row that was drawn. The page receives the
    click as one
    `Visualize.Event`:

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
      * `render` - options for `Visualize.Chart.render/2` — `title:`, `description:`,
        `responsive:` … — the SVG always a root (default `[]`)
      * `tooltip_class` - the hook's `data-tooltip-class` (default `"vis-tooltip"`)
    """

    use Phoenix.LiveComponent

    alias Visualize.Chart
    alias Visualize.Chart.Applied
    alias Visualize.Event
    alias Visualize.Hooks.Tooltip

    @impl true
    def mount(socket), do: {:ok, assign(socket, drawing: nil, drawn: nil, svg: nil, hover: %{})}

    @impl true
    def update(%{id: id, chart: %Applied{} = chart} = assigns, socket) do
      render_opts = Map.get(assigns, :render, [])

      socket =
        socket
        |> assign(id: id, tooltip_class: Map.get(assigns, :tooltip_class, "vis-tooltip"))
        |> draw({chart, render_opts})

      {:ok, socket}
    end

    # A new chart or new render options is a new drawing with a new token (spec/10 §19.3);
    # the same ones keep both, so an unrelated update does not drop a click in flight.
    defp draw(%{assigns: %{drawing: drawing}} = socket, drawing), do: socket

    defp draw(socket, {chart, render_opts} = drawing) do
      assign(socket,
        drawing: drawing,
        drawn: Integer.to_string(System.unique_integer([:positive, :monotonic])),
        svg: Chart.render(chart, [root: true] ++ render_opts),
        hover: Tooltip.attrs(chart.frame)
      )
    end

    @impl true
    def handle_event("visualize_event", params, socket) do
      %{id: id, drawing: {chart, _render_opts}, drawn: drawn} = socket.assigns

      with {:ok, click} <- Event.decode(params),
           {:ok, event} <- Event.resolve(click, chart, drawn: drawn) do
        send(self(), {:visualize_event, id, event})
      end

      {:noreply, socket}
    end

    def handle_event(_event, _params, socket), do: {:noreply, socket}

    @impl true
    def render(assigns) do
      ~H"""
      <div
        id={@id}
        phx-hook="TooltipHook"
        data-tooltip-target={@myself}
        data-tooltip-drawn={@drawn}
        data-tooltip-class={@tooltip_class}
        {@hover}
      >
        {Phoenix.HTML.raw(@svg)}
      </div>
      """
    end
  end
end
