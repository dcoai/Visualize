if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Events.Tree do
    @moduledoc false
    # The layer tree (spec/14 §18.8, §18.17, §19.3, #380–#382): rows selected, grouped,
    # copied, saved, reordered, added, unlocked, locked, reverted, opened, folded and masked,
    # from the pointer and from the keyboard.
    #
    # Split from `Visualize.Chart.Builder` by area (#568); compiled only with
    # `Phoenix.Component`, as the builder is (spec/10 §1.1, D-45, D-85).

    import Phoenix.Component, only: [assign: 2, assign: 3, update: 3]
    import Phoenix.LiveView, only: [push_event: 3]
    import Visualize.Chart.Builder.Events.Form, only: [restacked: 2]

    import Visualize.Chart.Builder.Selection,
      only: [decode_id: 1, position: 1, row_name: 2, row_use: 2, select: 2]

    import Visualize.Chart.Builder.Tree,
      only: [chosen: 1, edited: 1, expanded_index: 1, revertable?: 1]

    import Visualize.Chart.Builder.Workspace, only: [names: 1, opened_entry: 2, saved: 3]
    import Visualize.Chart.Builder.Writes, only: [locked_notice: 2]

    alias Visualize.Chart.{Builder, Use}
    alias Visualize.Chart.Builder.{Masks, Stack, Store}

    # The events this module handles: `Visualize.Chart.Builder.handle_event/3` routes
    # each here.
    @events ~w(
      unlock_site lock_site revert_site select_layer group_sites ungroup_site copy_site
      save_site_as save_site layer_key open_layer toggle_layer_mask toggle_layer_detail
      open_declared toggle_layer reorder new_layer toggle_site mask
    )

    @doc false
    def events, do: @events

    # -- linked, unlocked, locked again, reverted (spec/14 §18.8, §19.3, #381) -----------

    # Unlock: the entry's body copied into the site's local, the ref remembered as its
    # origin, the site's form open; a composite becomes a group of copies of its sites.
    @doc false
    def handle_event("unlock_site", %{"index" => index}, socket) do
      %{uses: uses, labels: labels, store: store, signals: signals} = socket.assigns

      with %Use{ref: ref} = use when ref != nil <- row_use(uses, index),
           {:ok, entry} <- Store.get(store, ref) do
        {unlocked, inner, entry_signals} =
          Stack.unlocked(use, entry, Stack.fetch(store), names(store))

        {issued, _among} =
          Enum.map_reduce(inner, uses, fn {site, name}, among ->
            issued = %{site | id: Use.new(nil, among).id}
            {{issued, name}, among ++ [issued]}
          end)

        unlocked =
          case issued do
            [] -> unlocked
            _ -> put_in(unlocked.local.composite.uses, Enum.map(issued, &elem(&1, 0)))
          end

        socket
        |> assign(
          uses: Stack.update(uses, use.id, fn _ -> unlocked end),
          labels:
            Enum.reduce(issued, labels, fn {site, name}, acc -> Map.put(acc, site.id, name) end),
          signals: Map.merge(entry_signals, signals),
          menu: nil,
          reverting: nil,
          notice: nil
        )
        |> select(index)
        |> then(&{:noreply, &1})
      else
        %Use{} ->
          {:noreply, assign(socket, :notice, "#{row_name(socket, index)} is not linked")}

        :error ->
          {:noreply, assign(socket, :notice, "#{row_name(socket, index)}'s entry is gone")}

        nil ->
          {:noreply, socket}
      end
    end

    # Lock again: the ref restored from the origin, the local kept over it.
    def handle_event("lock_site", %{"index" => index}, socket) do
      case row_use(socket.assigns.uses, index) do
        %Use{origin: origin} = use when origin != nil ->
          {:noreply,
           assign(socket,
             uses: Stack.update(socket.assigns.uses, use.id, &Stack.locked/1),
             menu: nil,
             reverting: nil,
             notice: nil
           )}

        %Use{} ->
          {:noreply, assign(socket, :notice, "#{row_name(socket, index)} has nothing to link to")}

        nil ->
          {:noreply, socket}
      end
    end

    # Revert: armed by the first click, done by the second (§18.8).
    def handle_event("revert_site", %{"index" => index}, socket) do
      case row_use(socket.assigns.uses, index) do
        %Use{} = use ->
          cond do
            not revertable?(use) ->
              {:noreply,
               assign(socket, :notice, "#{row_name(socket, index)} is as the library has it")}

            socket.assigns.reverting == use.id ->
              {:noreply,
               assign(socket,
                 uses: Stack.update(socket.assigns.uses, use.id, &Stack.reverted/1),
                 menu: nil,
                 reverting: nil,
                 notice: nil
               )}

            true ->
              {:noreply,
               assign(socket,
                 reverting: use.id,
                 notice:
                   "revert #{row_name(socket, index)}? again — discards #{edited(use)} edited keys"
               )}
          end

        nil ->
          {:noreply, socket}
      end
    end

    # -- the stack -----------------------------------------------------------------------

    # A Shift-click extends the selection to the row, a Ctrl-click toggles it — within
    # the anchor's container (spec/14 §18.8, #382); a plain click makes it the one row.
    def handle_event("select_layer", %{"index" => index, "extend" => how}, socket)
        when how in ["range", "toggle"] do
      {:noreply, extended(socket, position(index), how)}
    end

    def handle_event("select_layer", %{"index" => index}, socket) do
      {:noreply, select(socket, position(index))}
    end

    # -- many rows: group, ungroup, copy a group, save a group (spec/14 §18.8, #382) ------

    # The selection — or the row alone, when it is not among the selected — wrapped in a
    # new group at the first one's position, expanded and selected.
    def handle_event("group_sites", %{"index" => index}, socket) do
      %{uses: uses, labels: labels} = socket.assigns

      case row_use(uses, index) do
        nil ->
          {:noreply, socket}

        %Use{id: id} ->
          chosen = chosen(socket.assigns)
          ids = if MapSet.member?(chosen, id), do: MapSet.to_list(chosen), else: [id]
          group = %{Use.new(nil, uses) | ref: nil, local: Stack.group()}
          n = uses |> Stack.all() |> Enum.count(&Stack.group?(&1.use)) |> Kernel.+(1)

          case Stack.grouped(uses, ids, group) do
            {:ok, grouped} ->
              {:noreply,
               socket
               |> assign(
                 uses: grouped,
                 labels: Map.put(labels, group.id, "group #{n}"),
                 expanded_sites: MapSet.put(socket.assigns.expanded_sites, group.id),
                 menu: nil,
                 notice: nil
               )
               |> select(Stack.index_of(grouped, group.id))}

            :error ->
              {:noreply, assign(socket, menu: nil, notice: "select within one layer or group")}
          end
      end
    end

    # A group's sites spliced back at its position, selected; a referenced group is the
    # library's inside and is refused.
    def handle_event("ungroup_site", %{"index" => index}, socket) do
      %{uses: uses, labels: labels} = socket.assigns

      case row_use(uses, index) do
        %Use{ref: nil} = use ->
          if Stack.group?(use) do
            inner = Stack.children(use)
            spliced = Stack.ungrouped(uses, use.id)

            socket =
              assign(socket,
                uses: spliced,
                labels: Map.delete(labels, use.id),
                expanded_sites: MapSet.delete(socket.assigns.expanded_sites, use.id),
                menu: nil,
                notice: nil
              )

            case inner do
              [] ->
                {:noreply, select(socket, position(index))}

              [first | _] ->
                {:noreply,
                 socket
                 |> select(Stack.index_of(spliced, first.id))
                 |> assign(:selection, MapSet.new(Enum.map(inner, & &1.id)))}
            end
          else
            {:noreply,
             assign(socket, menu: nil, notice: "#{row_name(socket, index)} is not a group")}
          end

        %Use{} ->
          {:noreply, assign(socket, menu: nil, notice: "unlock #{row_name(socket, index)} first")}

        nil ->
          {:noreply, socket}
      end
    end

    # A copy of a group and everything in it, fresh ids throughout, directly after it.
    def handle_event("copy_site", %{"index" => index}, socket) do
      %{uses: uses, labels: labels} = socket.assigns

      case row_use(uses, index) do
        nil ->
          {:noreply, socket}

        %Use{} = use ->
          {copy, pairs} = Stack.duplicated(uses, use)
          inserted = Stack.insert(uses, use.id, copy)

          labels =
            Enum.reduce(pairs, labels, fn {new, old}, acc ->
              case Map.fetch(acc, old) do
                {:ok, name} when new == copy.id -> Map.put(acc, new, "copy of #{name}")
                {:ok, name} -> Map.put(acc, new, name)
                :error -> acc
              end
            end)

          {:noreply,
           socket
           |> assign(uses: inserted, labels: labels, menu: nil, notice: nil)
           |> select(Stack.index_of(inserted, copy.id))}
      end
    end

    # *Save as …* on the menu: the row selected, and the context panel's name field focused.
    def handle_event("save_site_as", %{"index" => index}, socket) do
      {:noreply,
       socket
       |> assign(:menu, nil)
       |> select(position(index))
       |> push_event("vis:focus", %{id: "#{socket.assigns.id}-masks-save-name"})}
    end

    # A group's structure written to the store as a composite entry of the name, and the
    # row made a reference to it (spec/14 §18.8, §19.6, #382).
    def handle_event("save_site", %{"index" => index, "name" => name}, socket) do
      %{uses: uses, labels: labels, store: store} = socket.assigns
      trimmed = String.trim(name)

      case row_use(uses, index) do
        %Use{ref: nil, local: %{composite: composite}} = use when is_map(composite) ->
          cond do
            is_nil(store) ->
              {:noreply, assign(socket, :notice, "no store is configured")}

            trimmed == "" ->
              {:noreply, assign(socket, :notice, "a saved group needs a name")}

            true ->
              fragment = %{
                composite: %{uses: Stack.children(use), vars: Map.get(composite, :vars, %{})}
              }

              entry = %{id: nil, name: trimmed, kind: :composite, fragment: fragment}

              saved(socket, Store.put(store, entry), fn s, id ->
                inner = for %{use: held} <- Stack.all(Stack.children(use)), do: held.id

                assign(s,
                  uses: Stack.update(uses, use.id, &%{&1 | ref: id, local: %{}}),
                  labels: labels |> Map.drop(inner) |> Map.put(use.id, trimmed),
                  expanded_sites: MapSet.delete(s.assigns.expanded_sites, use.id),
                  selection: MapSet.new()
                )
              end)
              |> then(&{:noreply, &1})
          end

        %Use{} ->
          {:noreply, assign(socket, :notice, "#{row_name(socket, index)} is not a group")}

        nil ->
          {:noreply, socket}
      end
    end

    # The keyboard has every gesture the pointer has (spec/14 §18.17): Enter and Space
    # select, the arrows move and focus follows the row to where the layer went.
    def handle_event("layer_key", %{"key" => key, "index" => index, "shift" => true}, socket)
        when key in ["ArrowUp", "ArrowDown"] do
      {:noreply, extended_by_key(socket, position(index), key)}
    end

    def handle_event("layer_key", %{"key" => key, "index" => index}, socket) do
      at = position(index)
      count = length(Stack.all(socket.assigns.uses))

      case key do
        enter when enter in ["Enter", " "] ->
          {:noreply, select(socket, at)}

        "ArrowUp" when at > 0 ->
          {:noreply, moved_by_key(socket, at, at - 1)}

        "ArrowDown" when at < count - 1 ->
          {:noreply, moved_by_key(socket, at, at + 1)}

        # A library layer opens, so the entry is edited where it lives (§18.8).
        "o" ->
          handle_event("open_layer", %{"index" => index}, socket)

        # `l` unlocks a linked site or locks an unlocked one; `r` arms and reverts (#381).
        "l" ->
          case row_use(socket.assigns.uses, index) do
            %Use{ref: nil, origin: nil} -> {:noreply, socket}
            %Use{ref: nil} -> handle_event("lock_site", %{"index" => index}, socket)
            _linked -> handle_event("unlock_site", %{"index" => index}, socket)
          end

        "r" ->
          handle_event("revert_site", %{"index" => index}, socket)

        # Right and Left open and close what the row declares, as a tree's do (§18.8).
        "ArrowRight" ->
          if at in expanded_index(socket.assigns),
            do: {:noreply, socket},
            else: handle_event("toggle_layer_detail", %{"index" => index}, socket)

        "ArrowLeft" ->
          if at in expanded_index(socket.assigns),
            do: handle_event("toggle_layer_detail", %{"index" => index}, socket),
            else: {:noreply, socket}

        _other ->
          {:noreply, socket}
      end
    end

    # The lock on a library layer (spec/14 §18.8): the entry it references opens at the
    # chart level, as the library click opens it, and saving it reaches every chart that
    # references it. A layer with no reference has nothing to open.
    def handle_event("open_layer", %{"index" => index}, socket) do
      case row_use(socket.assigns.uses, index) do
        %Use{ref: ref} when ref != nil ->
          case Store.get(socket.assigns.store, ref) do
            {:ok, entry} ->
              {:noreply, opened_entry(socket, entry)}

            :error ->
              {:noreply, assign(socket, :notice, "the library no longer holds this entry")}
          end

        _inline ->
          {:noreply, socket}
      end
    end

    # A row opens or closes on what its layer declares (spec/14 §18.8).
    def handle_event("toggle_layer_mask", %{"index" => index}, socket) do
      case row_use(socket.assigns.uses, index) do
        nil ->
          {:noreply, socket}

        use ->
          {:noreply,
           update(socket, :mask_layers, fn open ->
             if MapSet.member?(open, use.id),
               do: MapSet.delete(open, use.id),
               else: MapSet.put(open, use.id)
           end)}
      end
    end

    def handle_event("toggle_layer_detail", %{"index" => index}, socket) do
      case row_use(socket.assigns.uses, index) do
        nil ->
          {:noreply, socket}

        use ->
          {:noreply,
           update(socket, :expanded_layers, fn open ->
             if MapSet.member?(open, use.id),
               do: MapSet.delete(open, use.id),
               else: MapSet.put(open, use.id)
           end)}
      end
    end

    # A kind a layer declares: the layer selected, the kind's page opened in the inspector
    # (spec/14 §18.8) — the frame's page for the frame and what it holds, a root's own for
    # the rest, the variables panel for vars.
    def handle_event("open_declared", %{"index" => index, "kind" => kind}, socket) do
      case row_use(socket.assigns.uses, index) do
        nil ->
          {:noreply, socket}

        _use ->
          socket = select(socket, position(index))

          # A kind opens as its root tab does (§18.13): the frame's tab holds the frame's parts,
          # the scales and the axes; vars are the variables panel.
          case kind do
            "vars" ->
              {:noreply, assign(socket, context: :variables)}

            k when k in ~w(meta frame frames scales axes) ->
              Builder.handle_event("select_root", %{"root" => "frames"}, socket)

            k when k in ~w(sources styles defs marks labels theme) ->
              Builder.handle_event("select_root", %{"root" => k}, socket)

            _other ->
              {:noreply, socket}
          end
      end
    end

    def handle_event("toggle_layer", %{"index" => index}, socket) do
      case row_use(socket.assigns.uses, index) do
        nil ->
          {:noreply, socket}

        use ->
          {:noreply,
           update(socket, :uses, &Stack.update(&1, use.id, fn u -> Stack.toggle(u) end))}
      end
    end

    def handle_event("reorder", %{"scope" => "style", "from" => from, "to" => to}, socket) do
      {:noreply, restacked(socket, &shift(&1, position(from), position(to)))}
    end

    # A row dropped on a group's row moves into it, at the end; never into itself or what
    # it holds, never into a referenced group (spec/14 §18.17, #380).
    def handle_event("reorder", %{"from" => from, "into" => into}, socket) do
      %{uses: uses} = socket.assigns

      case {row_use(uses, from), Stack.get(uses, decode_id(into))} do
        {%Use{id: id} = moved, %Use{ref: nil, id: group}} ->
          if id == group or under?(uses, group, id) do
            {:noreply, socket}
          else
            {:noreply,
             assign(
               socket,
               :uses,
               uses |> Stack.remove(id) |> Stack.insert({:into, group}, moved)
             )}
          end

        # A referenced group's inside is the library's (§18.8, #388): refused as any
        # write into it is.
        {%Use{}, %Use{ref: ref} = locked} when ref != nil ->
          {:noreply, assign(socket, :notice, locked_notice(socket.assigns, locked))}

        _other ->
          {:noreply, socket}
      end
    end

    def handle_event("reorder", %{"from" => from, "to" => to}, socket) do
      {:noreply, update(socket, :uses, &Stack.move(&1, position(from), position(to)))}
    end

    # The + on the Layers title: a menu of the single kinds, and an empty inline site of the
    # chosen one directly below the selected layer, selected and opened (spec/14 §18.8).
    # A + on the selected chart's row adds an empty layer (spec/14 §18.8, #380): a group
    # with no objects, after the selected site's layer, selected; nothing asks for a kind.
    def handle_event("new_layer", _params, socket) do
      %{uses: uses, labels: labels, selected: selected} = socket.assigns
      use = %{Use.new(nil, uses) | ref: nil, local: Stack.group()}
      top = top_of(uses, selected)
      n = uses |> Stack.all() |> Enum.count(&Stack.group?(&1.use)) |> Kernel.+(1)

      {:noreply,
       assign(socket,
         uses: Stack.insert(uses, top, use),
         labels: Map.put(labels, use.id, "layer #{n}"),
         selected: use.id,
         expanded_sites: MapSet.put(socket.assigns.expanded_sites, use.id),
         node_label: "design",
         facet: nil,
         field: nil,
         context: :inspect,
         notice: nil
       )}
    end

    # A group's row opens or closes on what it holds (spec/14 §18.8).
    def handle_event("toggle_site", %{"index" => index}, socket) do
      case row_use(socket.assigns.uses, index) do
        nil ->
          {:noreply, socket}

        %Use{id: id} ->
          {:noreply,
           update(socket, :expanded_sites, fn open ->
             if MapSet.member?(open, id), do: MapSet.delete(open, id), else: MapSet.put(open, id)
           end)}
      end
    end

    # A mask checkbox: the path joins or leaves the selected site's mask (spec/14 §19.5).
    # An unchecked box submits nothing, which is the path leaving.
    # A mask checkbox under a layer's row (§18.8): the form names the layer's position, and
    # the write is the site's own, so a locked layer's mask is written like any other's.
    def handle_event("mask", %{"_target" => [name]} = params, socket) do
      %{uses: uses} = socket.assigns

      at =
        case Map.fetch(params, "_index") do
          {:ok, index} -> row_use(uses, index) |> then(&(&1 && &1.id))
          :error -> socket.assigns.selected
        end

      case at && Stack.get(uses, at) do
        nil ->
          {:noreply, socket}

        _use ->
          checked = Map.get(params, name) == "true"

          {:noreply,
           update(
             socket,
             :uses,
             &Stack.update(&1, at, fn u -> Masks.toggle(u, name, checked) end)
           )}
      end
    end

    defp moved_by_key(socket, from, to) do
      socket
      |> update(:uses, &Stack.move(&1, from, to))
      |> push_event("vis:focus", %{id: "#{socket.assigns.id}-layers-row-#{to}"})
    end

    # The selection extended to a row — the range from the anchor, or the row toggled —
    # within the anchor's container; a row elsewhere is refused (§18.8, #382).
    defp extended(socket, at, how) do
      %{uses: uses, selected: selected} = socket.assigns

      case {row_use(uses, at), Stack.get(uses, selected)} do
        {nil, _} ->
          socket

        {use, nil} ->
          select(socket, at) |> assign(:selection, MapSet.new([use.id]))

        {use, anchor} ->
          case {how, Stack.between(uses, anchor.id, use.id)} do
            {"range", {:ok, ids}} ->
              assign(socket, selection: MapSet.new(ids), notice: nil)

            {"toggle", {:ok, _ids}} ->
              chosen = chosen(socket.assigns)

              toggled =
                if MapSet.member?(chosen, use.id) and use.id != anchor.id,
                  do: MapSet.delete(chosen, use.id),
                  else: MapSet.put(chosen, use.id)

              assign(socket, selection: toggled, notice: nil)

            {_how, :error} ->
              assign(socket, :notice, "select within one layer or group")
          end
      end
    end

    # Shift+Arrow: the range grown by one row at the edge away from the anchor.
    defp extended_by_key(socket, at, key) do
      %{uses: uses, selected: selected} = socket.assigns
      rows = Stack.all(uses)

      case Stack.get(uses, selected) do
        nil ->
          socket

        anchor ->
          chosen = chosen(socket.assigns)
          indexes = for row <- rows, MapSet.member?(chosen, row.use.id), do: row.index
          anchor_at = Stack.index_of(uses, anchor.id)

          edge =
            case key do
              "ArrowUp" -> min(Enum.min(indexes, fn -> anchor_at end), at) - 1
              "ArrowDown" -> max(Enum.max(indexes, fn -> anchor_at end), at) + 1
            end

          case Enum.at(rows, edge) do
            nil ->
              socket

            _row when edge < 0 ->
              socket

            row ->
              extended(socket, row.index, "range")
              |> push_event("vis:focus", %{id: "#{socket.assigns.id}-layers-row-#{edge}"})
          end
      end
    end

    # Whether a site stands under another, at any depth.
    defp under?(uses, ancestor, id) do
      case Stack.parent_of(uses, ancestor) do
        nil -> false
        ^id -> true
        parent -> under?(uses, parent, id)
      end
    end

    defp shift(list, from, to) do
      {value, rest} = List.pop_at(list, from)
      List.insert_at(rest, to, value)
    end

    # The top-level site holding a site — the layer a selection stands in — or nil.
    defp top_of(_uses, nil), do: nil

    defp top_of(uses, id) do
      case Stack.parent_of(uses, id) do
        nil -> if Stack.get(uses, id), do: id
        parent -> top_of(uses, parent)
      end
    end
  end
end
