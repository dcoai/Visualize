if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Events.Graph do
    @moduledoc false
    # The graph (spec/14 §18.16, #379): a drawn node's menu, its copy and its override, a
    # palette component or a library entry placed where it was dropped, and a drawn node
    # moved.
    #
    # Split from `Visualize.Chart.Builder` by area (#568); compiled only with
    # `Phoenix.Component`, as the builder is (spec/10 §1.1, D-45, D-85).

    import Phoenix.Component, only: [assign: 2, assign: 3, update: 3]
    import Visualize.Chart.Builder.Editing, only: [root: 1]
    import Visualize.Chart.Builder.Selection, only: [opened: 2, row_use: 2]
    import Visualize.Chart.Builder.Tree, only: [site_items: 3, site_kind: 1]
    import Visualize.Chart.Builder.Workspace, only: [fetch: 2]

    import Visualize.Chart.Builder.Writes,
      only: [
        admits: 2,
        at: 2,
        composed: 1,
        derived_scales: 1,
        linked: 3,
        owned: 3,
        update_layer: 4
      ]

    alias Visualize.Chart.Builder.{Editor, Place, Stack}
    alias Visualize.Chart.{Fragment, Frame, Use}

    # The events this module handles: `Visualize.Chart.Builder.handle_event/3` routes
    # each here.
    @events ~w(
      menu menu_close copy_node override_node component_key place move graph_size frame_box
    )

    # The smallest side, in pixels, the graph is drawn at (spec/14 §18.4).
    @smallest 100

    @doc false
    def events, do: @events

    # -- copy and override, and the menu that offers them (spec/14 §18.16, #379) ----------

    # A right-click on a drawn node, or on a layer row: the menu at the point, for the
    # node or for the row's nodes.
    @doc false
    def handle_event("menu", %{"node" => label} = params, socket) do
      {:noreply,
       assign(socket, :menu, %{nodes: [label], x: number(params["x"]), y: number(params["y"])})}
    end

    def handle_event("menu", %{"layer" => index} = params, socket) do
      case row_use(socket.assigns.uses, index) do
        nil ->
          {:noreply, socket}

        use ->
          labels = nodes_of(socket, use.id)

          {:noreply,
           assign(socket, :menu, %{
             nodes: labels,
             site: site_items(socket.assigns, use, index),
             x: number(params["x"]),
             y: number(params["y"])
           })}
      end
    end

    def handle_event("menu_close", _params, socket),
      do: {:noreply, assign(socket, menu: nil, reverting: nil)}

    def handle_event("copy_node", %{"node" => label}, socket),
      do: {:noreply, socket |> assign(:menu, nil) |> lifted(:copy, label)}

    def handle_event("override_node", %{"node" => label}, socket),
      do: {:noreply, socket |> assign(:menu, nil) |> lifted(:override, label)}

    # -- the palette, and a drop on the graph (spec/14 §18.16) ------------------------------

    # A palette row from the keyboard: Insert places it in its home region.
    def handle_event("component_key", %{"key" => key, "component" => word}, socket) do
      case {key, Place.component(word)} do
        {insert, {:ok, component}} when insert in ["Insert", "i", "Enter", " "] ->
          {:noreply, placed(socket, component, Place.home(component), {0, 0})}

        _other ->
          {:noreply, socket}
      end
    end

    # A drop on the graph: a component, or a library entry, placed where it landed — by
    # the point in chart coordinates, or by the region the keyboard twin names.
    def handle_event("place", %{"component" => word} = params, socket) do
      case Place.component(word) do
        {:ok, component} ->
          {region, point} = where(socket, params, component)
          {:noreply, placed(socket, component, region, point)}

        :error ->
          {:noreply, assign(socket, :notice, "#{word} is not a component")}
      end
    end

    def handle_event("place", %{"name" => submitted}, socket) do
      case fetch(socket.assigns.store, submitted) do
        {:ok, entry} ->
          case admits(socket.assigns.open, entry) do
            # Linked, as every drop is (#381): the entry's placement is the library's, so
            # nothing is snapped; unlock it to move it.
            :ok ->
              {:noreply, linked(socket, entry, {:after, socket.assigns.selected})}

            {:refused, notice} ->
              {:noreply, assign(socket, :notice, notice)}
          end

        :error ->
          {:noreply, assign(socket, :notice, "no fragment is stored under #{submitted}")}
      end
    end

    # A drawn node moved on the graph (spec/14 §18.16): its placement key rewritten in the
    # layer that owns it, by the region the point falls in or the region given; a move into
    # the region it already occupies, or of a node with no placement, is nothing.
    def handle_event("move", %{"node" => label} = params, socket) do
      design = composed(socket)

      case Enum.find(Editor.nodes(design), &(&1.label == label)) do
        %{kind: kind, path: path} = node when kind in [:axis, :legend, :label] ->
          {region, point} = where(socket, params, nil)
          body = at(design, path) || %{}

          case Place.moved(kind, body, region, point, design) do
            {:ok, moved} ->
              {:noreply, socket |> rewritten(path, kind, body, moved) |> opened(node.label)}

            # The axis's new orientation reads a scale the design lacks: brought beneath
            # the axis's owner, as a drop brings it (§18.16).
            {:ok, moved, sites} ->
              {:noreply,
               socket
               |> brought(path, sites)
               |> rewritten(path, kind, body, moved)
               |> opened(node.label)}

            _same_or_unmovable ->
              {:noreply, socket}
          end

        _other ->
          {:noreply, socket}
      end
    end

    # The graph is the box (spec/14 §18.4): its measured size is what the preview draws the
    # design at. A size too small to draw in — a hidden or collapsed graph measures zero —
    # keeps the last one, so a chart never redraws into nothing.
    def handle_event("graph_size", %{"width" => width, "height" => height}, socket) do
      case {integer(width), integer(height)} do
        {w, h} when w >= @smallest and h >= @smallest ->
          {:noreply, assign(socket, :graph_size, {w, h})}

        _too_small ->
          {:noreply, socket}
      end
    end

    # A frame dragged or resized on the graph, or nudged from the keyboard (spec/14 §18.16,
    # #614): its box as fractions, which the hook snapped and the server only checks —
    # kept inside the box and at least a twentieth on a side, rounded to four places — and
    # writes through the ownership rule. A box given is the frame's placement, so a `cell`
    # and `span` it said are taken away: both is a fault (§4.2).
    def handle_event("frame_box", %{"frame" => name, "box" => box}, socket) do
      design = composed(socket)

      with {:ok, frame} <- frame_named(design, name),
           {:ok, box} <- fractions(box) do
        path = [:frames, frame]
        node = at(design, path)
        socket = socket |> assign(:notice, nil) |> update_layer(path, :box, {:ok, box})

        socket =
          if socket.assigns.notice == nil,
            do: Enum.reduce(placement_by_cell(node), socket, &update_layer(&2, path, &1, :error)),
            else: socket

        {:noreply, opened(socket, Editor.label(path))}
      else
        _not_a_frame_or_box -> {:noreply, socket}
      end
    end

    # -- placing a component (spec/14 §18.16) ------------------------------------------------

    # The keys a move changed, written through the ownership rule: the placement key, and
    # an axis's scale when its orientation changed.
    defp rewritten(socket, path, kind, before, moved) do
      [placement_key(kind), :scale]
      |> Enum.filter(&(Map.has_key?(moved, &1) and Map.get(moved, &1) != Map.get(before, &1)))
      |> Enum.reduce(socket, fn key, acc ->
        update_layer(acc, path, key, {:ok, Map.fetch!(moved, key)})
      end)
    end

    defp placement_key(:axis), do: :side
    defp placement_key(:legend), do: :position
    defp placement_key(:label), do: :anchor

    # Scale sites brought by a move, inserted beneath the moved node's owner — or the
    # selected layer when nothing owns it — so the axis reads them.
    defp brought(socket, path, sites) do
      %{uses: uses, labels: labels, selected: selected, store: store} = socket.assigns
      fetch = Stack.fetch(store)

      owner =
        case owned(socket.assigns, fetch, [%{path: path}]) |> Map.get(path) do
          nil -> Stack.index_of(uses, selected) || 0
          id -> Stack.index_of(uses, id) || 0
        end

      # Beneath the owner: each before the row that stands at its position (#380).
      {uses, issued} =
        Enum.reduce(sites, {uses, []}, fn site, {uses, issued} ->
          use = %{Use.new(nil, uses) | ref: nil, local: %{site.kind => site.body}, key: site.key}
          {Stack.insert_at(uses, owner + length(issued), use), issued ++ [use]}
        end)

      assign(socket,
        uses: uses,
        labels: Enum.reduce(issued, labels, &Map.put(&2, &1.id, "new #{site_kind(&1)}"))
      )
    end

    # The region a drop names: its point classified against the frame the preview drew, or
    # the region given outright; absent both, the component's home.
    # A point is read in the frame under it at the size the graph was measured at (§18.4),
    # so the region is that frame's band or its plot.
    defp where(socket, params, component) do
      point = {number(Map.get(params, "x")), number(Map.get(params, "y"))}

      case Map.get(params, "region") do
        given when given in ~w(plot top bottom left right) ->
          {String.to_existing_atom(given), point}

        _none when is_map_key(params, "x") ->
          spot = Place.spot(composed(socket), graph_size(socket), point)
          {Place.region(spot.point, spot.geometry), spot}

        _none ->
          {if(component, do: Place.home(component), else: :plot), point}
      end
    end

    # The size the graph was last measured at, else the render's default (spec/14 §18.4).
    defp graph_size(socket), do: socket.assigns[:graph_size] || Frame.default_size()

    defp number(value) when is_number(value), do: value

    defp number(value) when is_binary(value) do
      case Float.parse(value) do
        {n, _} -> n
        :error -> 0
      end
    end

    defp number(_none), do: 0

    defp integer(value) when is_integer(value), do: value
    defp integer(value) when is_float(value), do: round(value)

    defp integer(value) when is_binary(value) do
      case Integer.parse(value) do
        {n, _} -> n
        :error -> 0
      end
    end

    defp integer(_none), do: 0

    # The frame of the composed design a pushed name names, never a new atom.
    defp frame_named(design, name) when is_binary(name) do
      case Map.get(design, :frames) do
        frames when is_map(frames) ->
          case Enum.find(Map.keys(frames), &(to_string(&1) == name)) do
            nil -> :error
            frame -> {:ok, frame}
          end

        _none ->
          :error
      end
    end

    defp frame_named(_design, _name), do: :error

    # The smallest side of a frame, as a fraction of the box (spec/14 §18.16).
    @thinnest 0.05

    # A pushed box as fractions inside the whole: `[x, y, w, h]`, each side at least the
    # thinnest, the box kept inside, every number rounded to four places.
    defp fractions([x, y, w, h]) do
      case Enum.map([x, y, w, h], &number_or_nil/1) do
        [x, y, w, h] when is_number(x) and is_number(y) and is_number(w) and is_number(h) ->
          w = w |> max(@thinnest) |> min(1)
          h = h |> max(@thinnest) |> min(1)
          x = x |> max(0) |> min(1 - w)
          y = y |> max(0) |> min(1 - h)
          {:ok, Enum.map([x, y, w, h], &rounded/1)}

        _other ->
          :error
      end
    end

    defp fractions(_box), do: :error

    defp number_or_nil(value) when is_number(value), do: value

    defp number_or_nil(value) when is_binary(value) do
      case Float.parse(value) do
        {n, ""} -> n
        _other -> nil
      end
    end

    defp number_or_nil(_other), do: nil

    # Four places, and a whole number written as one: `[0, 0, 0.5, 1]`, as a person would.
    defp rounded(value) do
      r = Float.round(value * 1.0, 4)
      if r == trunc(r), do: trunc(r), else: r
    end

    # The keys that placed a frame by the layout's grid, which a box replaces.
    defp placement_by_cell(node) when is_map(node),
      do: Enum.filter([:cell, :span], &Map.has_key?(node, &1))

    defp placement_by_cell(_node), do: []

    # A component placed: its sites inserted above the selected layer — or above the layer
    # whose axis of the same identity it replaces, so the drop is what draws (§8.2) —
    # lowest first, the last one selected and its node opened; a legend written through
    # the ownership rule.
    defp placed(socket, component, region, point) do
      design = composed(socket)

      case Place.node(component, region, design, point) do
        {:sites, sites} ->
          %{uses: uses, labels: labels, selected: selected} = socket.assigns
          # After the selected site, or after the layer whose axis the drop replaces when
          # that stands higher (§8.2); each issued site after the one before it (#380).
          after_id = highest_of(uses, [selected | replaced_owners(socket, design, sites)])

          {uses, issued} =
            Enum.reduce(sites, {uses, []}, fn site, {uses, issued} ->
              use = %{
                Use.new(nil, uses)
                | ref: nil,
                  local: %{site.kind => site.body},
                  key: site.key
              }

              previous = if issued == [], do: after_id, else: List.last(issued).id
              {Stack.insert(uses, previous, use), issued ++ [use]}
            end)

          last = List.last(issued)

          socket
          |> assign(
            uses: uses,
            labels: Enum.reduce(issued, labels, &Map.put(&2, &1.id, "new #{site_kind(&1)}")),
            selected: last.id,
            notice: nil
          )
          |> opened_placed(component, last)
          |> derived_scales()

        {:legend, node} ->
          path = Fragment.frame_path(composed(socket))

          socket
          |> update_layer(path, :legend, {:ok, node})
          |> assign(notice: nil)
          |> opened(Editor.label(path ++ [:legend]))

        {:error, :no_scale} ->
          assign(socket, notice: "a legend needs a colour scale")
      end
    end

    # The gap above the layer that owns an axis the placed one replaces — its `{scale,
    # side}` is an axis's identity in the cascade — or 0 when nothing is replaced.
    # The owners of the axes a placed axis replaces — the same scale and side (§8.2).
    defp replaced_owners(socket, design, sites) do
      %{store: store} = socket.assigns
      axes = design |> Editor.nodes() |> Enum.filter(&(&1.kind == :axis))
      owners = owned(socket.assigns, Stack.fetch(store), axes)

      sites
      |> Enum.filter(&(&1.kind == :axis))
      |> Enum.flat_map(fn %{body: %{scale: scale, side: side}} ->
        for node <- axes,
            match?(%{scale: ^scale, side: ^side}, at(design, node.path)),
            owner = Map.get(owners, node.path),
            owner != nil,
            do: owner
      end)
    end

    # The id standing highest in the tree's flat order, or nil for none.
    defp highest_of(uses, ids) do
      ids
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&{Stack.index_of(uses, &1), &1})
      |> Enum.reject(fn {index, _} -> index == nil end)
      |> Enum.max_by(&elem(&1, 0), fn -> {nil, nil} end)
      |> elem(1)
    end

    # The placed node opened: the composed design's node of the site's kind that the site
    # owns (§18.15) — an axis that replaced one of its identity owns that one's node.
    # The top-level nodes a use gives the chart, for a row's menu (spec/14 §18.17, #379).
    defp nodes_of(socket, id) do
      design = composed(socket)

      nodes =
        design |> Editor.nodes() |> Enum.filter(&(length(&1.path) <= 2 and &1.label != "design"))

      owners = owned(socket.assigns, Stack.fetch(socket.assigns.store), nodes)

      nodes
      |> Enum.filter(&(Map.get(owners, &1.path) == id))
      |> Enum.reject(fn node ->
        Enum.any?(
          nodes,
          &(&1.label != node.label and String.starts_with?(node.label, &1.label <> ".") and
              Map.get(owners, &1.path) == id)
        )
      end)
      |> Enum.map(& &1.label)
    end

    # A copy or an override of a node (spec/14 §18.16, #379): the inline site
    # `Stack.lifted/5` gives, inserted directly above the layer that owns the node, the
    # owner masked where the site says, the new site selected and its node open.
    defp lifted(socket, mode, label) do
      %{uses: uses, labels: labels, store: store} = socket.assigns
      fetch = Stack.fetch(store)
      design = composed(socket)

      with %{} = node <- Enum.find(Editor.nodes(design), &(&1.label == label)),
           %{path: path} = node,
           id when id != nil <- owned(socket.assigns, fetch, [node]) |> Map.get(path),
           %Use{} = owner <- Stack.get(uses, id),
           %{local: local, key: key, mask: mask, lifted: count} <-
             Stack.lifted(
               mode,
               owner,
               fetch,
               Map.put(node, :body, at(design, path)),
               taken(design, path)
             ) do
        use = %{Use.new(nil, uses) | ref: nil, local: local, key: key}

        uses =
          uses
          |> Stack.insert(owner.id, use)
          |> then(fn uses ->
            if mask,
              do: Stack.update(uses, owner.id, &%{&1 | mask: List.wrap(&1.mask) ++ [mask]}),
              else: uses
          end)

        word =
          case {mode, count} do
            {:copy, _} -> "copy of #{label}"
            {:override, 1} -> "override of #{label}"
            {:override, n} -> "override of #{Stack.label(labels, owner)}: #{root(label)} (#{n})"
          end

        socket
        |> assign(
          uses: uses,
          labels: Map.put(labels, use.id, word),
          selected: use.id,
          notice: nil
        )
        |> opened_own(use, node)
      else
        _other -> assign(socket, :notice, "#{label} is not a node of the chart")
      end
    end

    # The names a copy must not take: every mark id and every declared key of the kind.
    defp taken(design, [:marks, _i]),
      do: for(%{id: id} <- List.wrap(Map.get(design, :marks, [])), is_atom(id), do: id)

    defp taken(design, [:styles, _]), do: Map.keys(Map.get(design, :styles, %{}))
    defp taken(design, [:sources, _]), do: Map.keys(Map.get(design, :sources, %{}))
    defp taken(design, [:vars, _]), do: Map.keys(Map.get(design, :vars, %{}))

    defp taken(design, [:frames, _frame, :scales, _]),
      do: Map.keys(get_in(design, Fragment.frame_path(design) ++ [:scales]) || %{})

    defp taken(_design, _path), do: []

    # The copied node opened: the node of the same kind the new site owns, else the one it
    # was copied from.
    defp opened_own(socket, %Use{id: id}, %{kind: kind, label: was}) do
      design = composed(socket)
      nodes = design |> Editor.nodes() |> Enum.filter(&(&1.kind == kind))
      owners = owned(socket.assigns, Stack.fetch(socket.assigns.store), nodes)

      case Enum.find(nodes, &(Map.get(owners, &1.path) == id)) do
        nil -> opened(socket, was)
        node -> opened(socket, node.label)
      end
    end

    defp opened_placed(socket, _component, %Use{id: id, local: local}) do
      [{kind, body}] = Map.to_list(local)
      design = composed(socket)
      nodes = design |> Editor.nodes() |> Enum.filter(&(&1.kind == kind))
      owners = owned(socket.assigns, Stack.fetch(socket.assigns.store), nodes)

      label =
        case Enum.find(nodes, &(Map.get(owners, &1.path) == id)) do
          nil -> root_of(kind)
          node -> node.label
        end

      socket |> guessed(label, kind, body) |> opened(label)
    end

    # A placed mark's guessed channels are marked as guesses (§18.16) until edited.
    defp guessed(socket, label, :mark, %{channels: channels}) when map_size(channels) > 0 do
      update(socket, :guessed, fn set ->
        Enum.reduce(channels, set, fn {key, _}, acc ->
          MapSet.put(acc, "#{label}.channels.#{key}")
        end)
      end)
    end

    defp guessed(socket, _label, _kind, _body), do: socket

    defp root_of(:axis), do: "frame"
    defp root_of(:mark), do: "marks"
    defp root_of(:label), do: "labels"
    defp root_of(:scale), do: "frame"
    defp root_of(_kind), do: "design"
  end
end
