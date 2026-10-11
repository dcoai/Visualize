if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Events.Charts do
    @moduledoc false
    # The charts of the workspace (spec/14 §18.8, §19.9): added, selected, folded and
    # closed.
    #
    # Split from `Visualize.Chart.Builder` by area (#568); compiled only with
    # `Phoenix.Component`, as the builder is (spec/10 §1.1, D-45, D-85).

    import Phoenix.Component, only: [assign: 2, assign: 3, update: 3]
    import Visualize.Chart.Builder.Selection, only: [position: 1, select: 2]
    import Visualize.Chart.Builder.Workspace, only: [added_chart: 2, load: 2, park: 1]

    alias Visualize.Chart.Use

    # The events this module handles: `Visualize.Chart.Builder.handle_event/3` routes
    # each here.
    @events ~w(
      add_chart select_chart toggle_chart select_chart_layer close_chart close
    )

    @doc false
    def events, do: @events

    # -- the charts (spec/14 §18.8, §19.9) ------------------------------------------------

    # A new chart is one frame layer: a chart minimally is a frame.
    # A new chart is one cartesian frame: valid from its first moment (§18.8, #374).
    @doc false
    def handle_event("add_chart", _params, socket) do
      use = %{Use.new(nil, []) | ref: nil, local: %{frames: %{main: %{kind: :cartesian}}}}
      n = socket.assigns.next_chart

      {:noreply,
       socket
       |> park()
       |> assign(
         uses: [use],
         labels: %{use.id => "new frame"},
         stack_vars: %{},
         signals: %{},
         selected: use.id,
         open: nil,
         board: nil,
         board_cell: nil,
         binding: nil,
         return_to: nil,
         node_label: "design",
         facet: nil,
         style_entry: nil,
         field: nil,
         context: :inspect,
         notice: nil
       )
       |> added_chart("chart #{n}")}
    end

    def handle_event("select_chart", %{"chart" => id}, socket) do
      {:noreply, socket |> park() |> load(String.to_integer(id))}
    end

    def handle_event("toggle_chart", %{"chart" => id}, socket) do
      id = String.to_integer(id)

      {:noreply,
       update(socket, :charts, fn charts ->
         Enum.map(charts, &if(&1.id == id, do: %{&1 | expanded: not &1.expanded}, else: &1))
       end)}
    end

    # A layer of another chart is selected by selecting its chart first.
    def handle_event("select_chart_layer", %{"chart" => id, "index" => index}, socket) do
      {:noreply, socket |> park() |> load(String.to_integer(id)) |> select(position(index))}
    end

    # Closing a chart removes it and selects its neighbour; the last chart stays.
    def handle_event("close_chart", %{"chart" => id}, socket) do
      id = String.to_integer(id)
      %{charts: charts} = socket.assigns

      case charts do
        [_only] ->
          {:noreply,
           assign(socket, :notice, "the last chart stays; add another to close this one")}

        _many ->
          socket = park(socket)
          index = Enum.find_index(charts, &(&1.id == id))
          remaining = Enum.reject(socket.assigns.charts, &(&1.id == id))
          neighbour = Enum.at(remaining, min(index, length(remaining) - 1))

          socket
          |> assign(:charts, remaining)
          |> then(&if(socket.assigns.chart == id, do: load(&1, neighbour.id), else: &1))
          |> then(&{:noreply, &1})
      end
    end

    # The first draft's close: the selected chart closes.
    def handle_event("close", _params, socket) do
      handle_event("close_chart", %{"chart" => to_string(socket.assigns.chart)}, socket)
    end
  end
end
