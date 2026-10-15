if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Events.Inspect do
    @moduledoc false
    # The strip and the inspector (spec/14 §18.13, §18.15, §19.10): a node, a root, a facet
    # or a field selected, a section folded, a drawn node picked, and which context panel is
    # open and how wide.
    #
    # Split from `Visualize.Chart.Builder` by area (#568); compiled only with
    # `Phoenix.Component`, as the builder is (spec/10 §1.1, D-45, D-85).

    import Phoenix.Component, only: [assign: 2, assign: 3, update: 3]
    import Visualize.Chart.Builder.Editing, only: [editing: 1, root: 1]
    import Visualize.Chart.Builder.Selection, only: [aimed: 2, opened: 2, position: 1, select: 2]
    import Visualize.Chart.Builder.Writes, only: [owned: 3]

    alias Visualize.Chart.Builder.{Editor, Stack}

    # The events this module handles: `Visualize.Chart.Builder.handle_event/3` routes
    # each here.
    @events ~w(
      select_node pick select_field toggle_section context_width context select_root facet
      inspect
    )

    @doc false
    def events, do: @events

    # The context's panels, one open at a time (spec/14 §19.10): inspect by every selection,
    # color by its toggle and variables by its tab at the end of the node row (§18.13).
    @panels [:inspect, :color, :variables]

    # -- the strip -----------------------------------------------------------------------

    @doc false
    def handle_event("select_node", %{"node" => label}, socket) do
      {:noreply, assign(socket, node_label: label, facet: nil, field: nil, context: :inspect)}
    end

    # A click on the graph (spec/14 §18.16): the node the element draws is opened in the
    # layer that owns it — the highest enabled layer with a value under its path, the
    # provenance every write follows (§18.15) — selected first, then opened. A label the
    # composed design has no node for is a no-op.
    def handle_event("pick", %{"node" => label}, socket) do
      socket = assign(socket, :menu, nil)
      %{uses: uses, store: store, stack_vars: vars} = socket.assigns
      fetch = Stack.fetch(store)

      design =
        case Stack.design(uses, vars, fetch) do
          {:ok, design, _keyless} -> design
          {:error, _cycle} -> %{}
        end

      case Enum.find(Editor.nodes(design), &(&1.label == label)) do
        nil ->
          {:noreply, socket}

        node ->
          owner = socket.assigns |> owned(fetch, [node]) |> Map.get(node.path)
          at = Stack.index_of(uses, owner)
          socket = if at, do: select(socket, at), else: socket
          {:noreply, opened(socket, label)}
      end
    end

    # Clicking into a field selects it, and the context panel becomes its picker
    # (spec/14 §19.10); the same click on the field already selected leaves it.
    def handle_event("select_field", %{"field" => key} = params, socket) do
      socket = aimed(socket, params)
      {:noreply, assign(socket, field: key, context: context_for(socket, key))}
    end

    # A section of the inspector folds and unfolds (spec/14 §18.15).
    def handle_event("toggle_section", %{"section" => key}, socket) do
      {:noreply,
       update(socket, :collapsed, fn set ->
         if MapSet.member?(set, key), do: MapSet.delete(set, key), else: MapSet.put(set, key)
       end)}
    end

    # The inspector's width, dragged at its edge and kept within reason (spec/14 §18.16).
    def handle_event("context_width", %{"width" => width}, socket) do
      case Integer.parse(to_string(width)) do
        {n, _} -> {:noreply, assign(socket, :context_width, n |> max(300) |> min(800))}
        :error -> {:noreply, socket}
      end
    end

    # The color toggle and the variables tab: which of the context's panels is open
    # (spec/14 §19.10, §18.13).
    def handle_event("context", %{"panel" => panel}, socket) do
      case Enum.find(@panels, &(to_string(&1) == panel)) do
        nil -> {:noreply, socket}
        p -> {:noreply, assign(socket, :context, p)}
      end
    end

    # A root opens as the chart declares it, whatever layer is selected (spec/14 §18.13,
    # §18.15). From the page of a site the design has no node of, a root of the design
    # takes the person to the highest layer that declares it, as the inspector does.
    def handle_event("select_root", %{"root" => root}, socket) do
      %{design: design, chart?: chart?, layers: layers, nodes: nodes} = editing(socket.assigns)
      label = if chart?, do: first_under(design, root), else: first_under_nodes(nodes, root)

      cond do
        label ->
          {:noreply, assign(socket, node_label: label, facet: nil, context: :inspect)}

        first_under(design, root) ->
          layers
          |> Enum.with_index()
          |> Enum.reverse()
          |> Enum.find(fn {{_label, fragment}, _index} -> first_under(fragment, root) end)
          |> case do
            nil ->
              {:noreply, socket}

            {{_label, _fragment}, index} ->
              {:noreply, socket |> select(index) |> opened(first_under(design, root))}
          end

        true ->
          {:noreply, socket}
      end
    end

    def handle_event("facet", %{"facet" => facet}, socket) do
      %{entry: entry} = editing(socket.assigns)
      facets = Editor.facets(entry.kind)
      {:noreply, assign(socket, facet: Enum.find(facets, &(to_string(&1) == facet)), field: nil)}
    end

    def handle_event("inspect", %{"path" => path, "layer" => layer}, socket) do
      {:noreply, socket |> select(position(layer)) |> opened(path)}
    end

    # A color field opens the color panel; any other field leaves the panel where it is —
    # a font key is a style's, and the font panel is under the styles root the form is in.
    defp context_for(socket, key) do
      %{entry: entry} = editing(socket.assigns)

      # A part's key by its path — `stroke.color`, `fill.stops.0.color` (§18.7).
      case Editor.locate(entry.kind, key) do
        %{spec: %{type: :color}} -> :color
        _other -> socket.assigns.context
      end
    end

    defp first_under(fragment, root) when is_map(fragment) do
      fragment
      |> Editor.nodes()
      |> Enum.find(&(root(&1.label) == root))
      |> case do
        nil -> nil
        node -> node.label
      end
    end

    defp first_under(_other, _root), do: nil

    defp first_under_nodes(nodes, root) do
      case Enum.find(nodes, &(root(&1.label) == root)) do
        nil -> nil
        node -> node.label
      end
    end
  end
end
