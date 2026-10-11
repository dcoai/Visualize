if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Tree do
    @moduledoc false
    # The layer tree's rows (spec/14 §18.8, #380–#382): every site by flat position with its
    # depth, the rows selected beside the anchor, the rows hidden under a closed group, the
    # open rows' masks and contributions, and a row's menu items.
    #
    # Split from `Visualize.Chart.Builder` by area (#568); compiled only with
    # `Phoenix.Component`, as the builder is (spec/10 §1.1, D-45, D-85).

    import Visualize.Chart.Builder.Selection, only: [position: 1]
    import Visualize.Chart.Builder.Workspace, only: [names: 1]

    alias Visualize.Chart.Builder.{Masks, Stack}
    alias Visualize.Chart.Use

    # The mask rows of every layer whose › Mask item is open, by position (spec/14 §18.8,
    # #316): over what the site contributes before its mask, the entry's body included, so
    # a locked layer's mask is as editable as any — it is the site's, not the entry's.
    @doc false
    def layer_masks(%{uses: uses, mask_layers: open, store: store}) do
      fetch = Stack.fetch(store)

      for %{use: use, index: index} <- Stack.all(uses), MapSet.member?(open, use.id), into: %{} do
        {index, %{rows: Masks.rows(Stack.unmasked(use, fetch), use), all?: use.mask == :all}}
      end
    end

    # The positions whose rows are open on what they declare (spec/14 §18.8).
    @doc false
    def expanded_index(%{uses: uses, expanded_layers: open}) do
      for %{use: use, index: index} <- Stack.all(uses),
          MapSet.member?(open, use.id),
          into: MapSet.new(),
          do: index
    end

    # The rows of the tree (spec/14 §18.8, #380): every site by flat position with its
    # depth, its name, whether it is a group and what it holds, whether it is open.
    # A referenced group (#388) is a container too: its count is its entry's sites, and
    # its `inside` the rows of that entry, drawn in its row since they have no flat
    # position of their own — every gesture on one is the group's.
    @doc false
    def tree_rows(%{uses: uses, labels: labels, expanded_sites: open, store: store}) do
      fetch = Stack.fetch(store)
      name_of = names(store)
      rows = Stack.all(uses, fetch)
      held = rows |> Enum.reject(&(&1.owner == nil)) |> Enum.group_by(& &1.owner)

      for %{use: use, depth: depth, parent: parent, owner: nil} <- rows do
        referenced = Stack.inside(use, fetch)
        label = Stack.label(labels, use)
        entry = (use.ref && name_of.(use.ref)) || label

        %{
          name: label,
          depth: depth,
          parent: parent,
          group?: Stack.group?(use) or referenced != nil,
          count: length(referenced || Stack.children(use)),
          open?: MapSet.member?(open, use.id),
          kind: site_kind(use),
          id: use.id,
          state: Stack.linkage(use),
          inside:
            for row <- Map.get(held, use.id, []) do
              %{
                name: Stack.inner_label(row.use, name_of, entry),
                depth: row.depth,
                group?: Stack.group?(row.use) or Stack.inside(row.use, fetch) != nil,
                kind: site_kind(row.use),
                tag: entry
              }
            end
        }
      end
    end

    # The site's own items of the row's menu (§18.8, #381): what its linkage allows.
    @doc false
    def site_items(assigns, %Use{} = use, index) do
      lock =
        case Stack.linkage(use) do
          :inline -> []
          :unlocked -> [{"lock_site", "Lock"}]
          _linked -> [{"unlock_site", "Unlock"}]
        end

      revert =
        cond do
          not revertable?(use) ->
            []

          assigns.reverting == use.id ->
            [{"revert_site", "revert — discards #{edited(use)} edited keys"}]

          true ->
            [{"revert_site", "Revert to original"}]
        end

      chosen = chosen(assigns)

      grouping =
        cond do
          Stack.group?(use) ->
            [
              {"group_sites", "Group"},
              {"ungroup_site", "Ungroup"},
              {"copy_site", "Copy"},
              {"save_site_as", "Save as …"}
            ]

          use.ref != nil and match?({:composite, _}, use.ref) ->
            [{"group_sites", "Group"}, {"copy_site", "Copy"}]

          true ->
            [{"group_sites", "Group"}]
        end

      grouping =
        if MapSet.size(chosen) > 1 and MapSet.member?(chosen, use.id),
          do:
            Enum.map(grouping, fn
              {"group_sites", _} -> {"group_sites", "Group #{MapSet.size(chosen)} selected"}
              item -> item
            end),
          else: grouping

      %{index: position(index), items: grouping ++ lock ++ revert}
    end

    # The flat positions of the rows selected beside the anchor, for the panel.
    @doc false
    def chosen_index(assigns) do
      chosen = chosen(assigns)

      for %{use: use, index: index} <- Stack.all(assigns.uses),
          MapSet.member?(chosen, use.id),
          use.id != assigns.selected,
          into: MapSet.new(),
          do: index
    end

    # The rows selected (spec/14 §18.8, #382): the ids still in the tree, the anchor among
    # them whatever the set says, so a stale id is never a selection.
    @doc false
    def chosen(%{uses: uses, selected: selected, selection: selection}) do
      ids = for %{use: use} <- Stack.all(uses), into: MapSet.new(), do: use.id

      selection
      |> MapSet.intersection(ids)
      |> then(&if selected, do: MapSet.put(&1, selected), else: &1)
    end

    # A site is reverted when it has an origin, or a ref with a local (§18.8).
    @doc false
    def revertable?(%Use{origin: origin}) when origin != nil, do: true
    def revertable?(%Use{ref: ref, local: local}), do: ref != nil and map_size(local) > 0

    # The keys a revert discards: those of the site's local.
    @doc false
    def edited(%Use{local: local}), do: map_size(local)

    # A row of a group hides its rows while the group is closed: the flat positions of
    # every site under a closed group.
    @doc false
    def hidden_index(%{uses: uses, expanded_sites: open}) do
      rows = Stack.all(uses)

      closed =
        for %{use: use} <- rows, Stack.group?(use), not MapSet.member?(open, use.id), do: use.id

      hidden = fn row, hidden ->
        row.parent != nil and (row.parent in closed or MapSet.member?(hidden, row.parent))
      end

      rows
      |> Enum.reduce(MapSet.new(), fn row, acc ->
        if hidden.(row, acc), do: MapSet.put(acc, row.use.id), else: acc
      end)
      |> then(fn ids ->
        for %{use: use, index: index} <- rows,
            MapSet.member?(ids, use.id),
            into: MapSet.new(),
            do: index
      end)
    end

    # Each layer's own contribution placed where the design keeps its kind, by position,
    # disabled ones included — what its row lists when opened (§18.8); a reference to a
    # composite is what it flattens to, as the stack reads it (#283).
    @doc false
    def placed_layers(%{uses: uses, store: store}) do
      fetch = Stack.fetch(store)
      for %{use: use} <- Stack.all(uses), do: Stack.contribution(use, fetch)
    end

    @doc false
    def disabled(uses) do
      for %{use: use, index: index} <- Stack.all(uses),
          not Stack.enabled?(use),
          into: MapSet.new(),
          do: index
    end

    @doc false
    def site_kind(%Use{ref: {kind, _n}}) when is_atom(kind), do: kind
    def site_kind(%Use{local: local}), do: local |> Map.keys() |> List.first()
  end
end
