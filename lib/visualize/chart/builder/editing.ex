if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Editing do
    @moduledoc false
    # What is being edited (spec/14 §18.13, §18.15, §19.10). `editing/1` derives, from the
    # builder's assigns, everything the render reads: the resolved layers, the composed
    # design, the open node and its page, the strip, the context panels, the tree's rows and
    # each mode's assigns (`Visualize.Chart.Builder.Modes`). Events read it for the node they
    # write.
    #
    # Split from `Visualize.Chart.Builder` by area (#568); compiled only with
    # `Phoenix.Component`, as the builder is (spec/10 §1.1, D-45, D-85).

    import Visualize.Chart.Builder.Tree,
      only: [
        chosen_index: 1,
        disabled: 1,
        expanded_index: 1,
        hidden_index: 1,
        layer_masks: 1,
        placed_layers: 1,
        tree_rows: 1
      ]

    import Visualize.Chart.Builder.Workspace, only: [chart_rows: 1]
    import Visualize.Chart.Builder.Writes, only: [at: 2, owned: 3, pool: 1]

    alias Visualize.{Chart, Theme}
    alias Visualize.Chart.{Fragment, Schema, Use, Validator}

    alias Visualize.Chart.Builder.{
      Axes,
      Editor,
      Modes,
      Palette,
      Preview,
      Scales,
      Sources,
      Stack,
      Steps,
      Store,
      Themes,
      Variables
    }

    # What the editor is looking at: the resolved layers, the design they stand for, the
    # target's nodes, the open one and its value, and the faults application reports.
    @doc false
    def editing(assigns) do
      fetch = Stack.fetch(assigns.store)
      {layers, missing} = Stack.resolve(assigns.uses, assigns.labels, fetch)

      {design, cycle, keyless} =
        case Stack.design(assigns.uses, assigns.stack_vars, fetch) do
          {:ok, design, %{keyless: keyless}} -> {design, nil, keyless}
          {:error, {:cycle, chain}} -> {%{}, chain, []}
        end

      kind = (assigns.open && assigns.open.kind) || :composite
      # The page is the chart's (spec/14 §18.15): the nodes are walked over the composed
      # design, and each is owned by the highest layer that gives a value under it. A
      # selected site that gives the design nothing — keyless, disabled, empty — has no
      # node there, so its page is its own fragment, as every layer's once was.
      chart_nodes = Editor.nodes(design)
      owned = owned(assigns, fetch, chart_nodes)
      selected_use = Stack.get(assigns.uses, assigns.selected)
      mine = for {path, id} <- owned, selected_use && id == selected_use.id, do: path

      {nodes, layer} =
        if selected_use == nil or mine != [] do
          {chart_nodes, design}
        else
          fragment = target_fragment(assigns)
          {Editor.nodes(fragment), fragment}
        end

      # The design root itself is not a place to edit: its keys are Deploy's (`version`)
      # or sites of their own (§19.8), so a layer opens on its first real node — the
      # first the selected layer owns, where it owns one.
      entry =
        case assigns.node_label do
          "design" ->
            first_node(nodes, mine)

          label ->
            Enum.find(nodes, &(&1.label == label)) || implied(label) || first_node(nodes, mine)
        end

      preview_theme = preview_theme(assigns, design)
      errors = faults(kind, design, Map.put(assigns, :theme, preview_theme), cycle)
      {tabs, children} = strip(nodes, entry, design, errors, layer == design, assigns.context)

      %{
        layers: layers,
        missing: missing,
        design: design,
        nodes: nodes,
        entry: entry,
        tabs: tabs,
        variables_tab: variables_tab(layers, design, assigns.bindings, assigns.context),
        chips: chips(children, entry, assigns.facet),
        page: page(nodes, entry, layer, errors, owned, assigns),
        needs: needs(errors),
        style_site: style_site(entry, at(layer, entry.path)),
        open_style: open_style(entry),
        variables: variables(layers, design),
        sites: Stack.sites(assigns.uses, assigns.labels, fetch),
        find_hit: find_hit(assigns.find),
        site: site(assigns, fetch),
        refs: refs(design, assigns.store),
        colour: colour(assigns, entry, at(layer, entry.path), design),
        defs: Map.get(design, :defs, %{}),
        pool: assigns |> pool() |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort(),
        bound_pool: pool(assigns),
        columns: columns(pool(assigns)),
        source_name: source_name(assigns, fetch),
        channel_columns: Scales.columns(design, pool(assigns)),
        data_page?: root(entry.label) == "sources" and kind == :composite,
        axes_rows:
          if(kind == :composite, do: axes_rows(design, entry, at(layer, entry.path)), else: []),
        steps: if(kind == :composite, do: Steps.steps(design), else: []),
        data_rows: data_rows(design, assigns, owned),
        editing: at(layer, entry.path),
        errors: errors,
        chart?: layer == design,
        keyless: keyless,
        unplaced: Enum.map(keyless, &Stack.label(assigns.labels, Stack.get(assigns.uses, &1))),
        kind: kind,
        preview?: kind == :composite,
        preview_theme: preview_theme,
        chart_rows: chart_rows(assigns),
        selected_index: Stack.index_of(assigns.uses, assigns.selected),
        chosen_index: chosen_index(assigns),
        disabled: disabled(assigns.uses),
        expanded_index: expanded_index(assigns),
        placed_layers: placed_layers(assigns),
        layer_masks: layer_masks(assigns),
        tree_rows: tree_rows(assigns),
        hidden_index: hidden_index(assigns)
      }
      # Each mode's own assigns, `nil` under its key while it is off (spec/14 §20).
      |> Map.merge(Modes.assigns(assigns, kind, errors))
    end

    # The selected site for its context: what it contributes before its mask, and what it
    # still needs (spec/14 §19.10).
    defp site(%{uses: uses, labels: labels, selected: selected}, fetch) do
      case Stack.get(uses, selected) do
        nil ->
          nil

        use ->
          free =
            case Stack.sites([use], labels, fetch) do
              [%{free: free}] -> free
              [] -> []
            end

          %{
            use: use,
            label: Stack.label(labels, use),
            fragment: Stack.unmasked(use, fetch),
            free: free
          }
      end
    end

    # A reference may be a local name or a library id of the kind (spec/14 §19.10).
    defp refs(design, store) do
      entries = if store, do: Store.list(store), else: []
      ids = fn kind -> for %{kind: ^kind, id: id} <- entries, do: id end

      %{
        style: Palette.names(design) ++ ids.(:style),
        scale:
          Map.keys(get_in(design, Fragment.frame_path(design) ++ [:scales]) || %{}) ++
            ids.(:scale),
        source: Map.keys(Map.get(design, :sources, %{})) ++ ids.(:source)
      }
    end

    # The colour chooser (spec/14 §19.10): the selected colour field, if the selected field
    # is one, with the theme's slots in their colours and the literals the design already
    # uses; the theme itself is what every well shows its colour through.
    defp colour(%{field: field}, entry, node, design) do
      theme = design |> Map.get(:theme, :default) |> theme()

      spec =
        field &&
          Enum.find(
            Schema.describe(entry.kind),
            &(to_string(&1.key) == field and &1.type == :colour)
          )

      # A stop well of a fill's gradient (§18.6): the chooser writes `fill.stop.<i>`.
      stop = field && stop_colour(field, node, design)

      %{
        theme: theme,
        key: (spec && spec.key) || (stop && field),
        spec: spec || %{type: :colour, range: nil},
        value: if(spec && is_map(node), do: Map.get(node, spec.key), else: stop && stop.colour),
        swatches:
          Enum.map(
            Theme.colour_slots(theme),
            &{to_string(&1), Theme.resolve(theme, &1, :literal)}
          ),
        recent: recent_colours(design)
      }
    end

    # The colour of a gradient stop the selected field names, from the fill of the node
    # being edited (§18.6); nil when the field is not a stop well.
    defp stop_colour("fill.stop." <> i, node, design) do
      with {index, ""} <- Integer.parse(i),
           {:paint, name} <- is_map(node) && Map.get(node, :fill),
           %{stops: stops} when is_list(stops) <- get_in(design, [:defs, name]),
           %{colour: colour} <- Enum.at(stops, index) do
        %{colour: colour}
      else
        _other -> nil
      end
    end

    defp stop_colour(_field, _node, _design), do: nil

    # Every "#rrggbb" the design's styles carry, once each, in order of first use.
    defp recent_colours(design) do
      design
      |> Map.get(:styles, %{})
      |> Map.values()
      |> Enum.flat_map(fn style -> if is_map(style), do: Map.values(style), else: [] end)
      |> Enum.filter(&(is_binary(&1) and String.starts_with?(&1, "#")))
      |> Enum.uniq()
    end

    # The theme the wells show colours through, built unchecked: a theme being edited may
    # break a contract for a moment, and the editor says so rather than the render raising
    # (spec/14 §20.4).
    defp theme(value), do: Themes.effective(value, nil)

    # The find box names a variable exactly to highlight its fields; a partial match
    # filters the list only.
    defp find_hit(find) do
      case String.trim(find || "") do
        "" -> nil
        name -> name
      end
    end

    # The theme the preview draws in: the host's when it gives one; else, for a design that
    # names a theme that is not built-in, the store's theme of that name — the `theme:` of
    # application supplied by the library, so a host ships a theme as a value (spec/14 §2.5,
    # §9.3, D-139); else the design's own, `nil`.
    defp preview_theme(%{theme: %Theme{} = theme}, _design), do: theme

    defp preview_theme(%{store: store}, %{theme: name})
         when store != nil and is_atom(name) and name != nil do
      with nil <- Theme.builtin(name),
           {:ok, theme} <- Store.theme(store, name) do
        theme
      else
        _builtin_or_none -> nil
      end
    end

    defp preview_theme(_assigns, _design), do: nil

    # A composite or a design is applied, so its faults are the design's; any other kind is
    # validated as that kind — per-kind validity (spec/14 §19.8).
    defp faults(_kind, _design, _assigns, [_ | _] = chain), do: [{[], {:cycle, chain}}]

    # The layer's faults, and the builder's own: a position channel bound through no scale
    # that nothing could type (spec/14 §18.16, #370).
    defp faults(:composite, design, %{bindings: vars, theme: theme} = assigns, nil) do
      pool = pool(assigns)

      # A binding of the wrong type is a fault, never applied (spec/14 §18.4, D-153).
      layer =
        with [] <- Preview.type_faults(design, pool, assigns[:catalog]) do
          case Chart.apply(design, sources: pool, vars: vars, theme: theme) do
            {:ok, _applied} -> []
            {:error, errors} -> errors
          end
        end

      layer ++ Scales.unscaled(design, Scales.pool_types(pool))
    end

    # A board chart has no design: the board mode validates the board itself, alone on every
    # write and given the store in its validity section (spec/14 §22.2, §22.5).
    defp faults(:board, _design, _assigns, nil), do: []

    # The design of a non-composite chart is stamped with the version as every design the
    # stack makes is (§9.1); per-kind validity reads the fragment, which carries none.
    defp faults(kind, design, _assigns, nil) do
      case Validator.validate(Map.delete(design, :version), kind) do
        :ok -> []
        {:error, errors} -> errors
      end
    end

    # The strip: every root the stacked design declares, in the schema's order — none of
    # them open while the variables panel is up, since the tab that ends the row is (spec/14
    # §18.13, #363) — and the open root's children and the node's facets as one row of chips.
    defp strip(nodes, entry, design, errors, chart?, context) do
      open_root = if context == :variables, do: nil, else: root(entry.label)
      here = nodes |> Enum.map(&root(&1.label)) |> Enum.uniq()
      needs = needs(errors)

      tabs =
        for root <- roots(design, here) do
          count = Map.get(needs, root, 0)

          %{
            label: root,
            word: root_word(root),
            open: root == open_root,
            elsewhere: root not in here,
            needs: count,
            class: tab_class(root == open_root, root in here, count),
            title: tab_title(root_word(root), root in here, chart?, count)
          }
        end

      children =
        for node <- nodes, root(node.label) == open_root, node.label != open_root do
          %{
            label: leaf(node.label, open_root),
            node: node.label,
            open: node.label == entry.label,
            needs: Map.get(needs, node.label, 0)
          }
        end

      {tabs, children}
    end

    # What the design still needs, by the node that holds it (spec/14 §18.13): every fault
    # counted under its root and under each node on its path, so a tab and a chip can say
    # how many things under them are still needed.
    defp needs(errors) do
      errors
      |> Enum.flat_map(fn {path, _reason} -> owners(path) end)
      |> Enum.frequencies()
    end

    # The labels of every node above a fault's path: `marks[0].channels.x` is owed by
    # `marks`, `marks[0]` and `marks[0].channels`.
    defp owners(path) do
      path
      |> Enum.scan([], fn key, acc -> acc ++ [key] end)
      |> Enum.map(&Editor.label/1)
      |> Enum.uniq()
      |> Enum.reject(&(&1 == "design"))
    end

    # Every root but the design's own, the frame first (spec/14 §18.13): design is the
    # deployed tier, not a node to edit, and a chart starts from its frame.
    defp roots(design, here) do
      declared = design |> Editor.nodes() |> Enum.map(&root(&1.label)) |> Enum.uniq()
      # Neither the design's own root nor `vars` is a tab: a declaration is the variable
      # panel's (§19.10), where it is made, defaulted and bound in one place.
      # `meta` is not a tab either: the frame's page opens with the design's name (§18.15).
      roots =
        Enum.reject(
          declared ++ Enum.reject(here, &(&1 in declared)),
          &(&1 in ["design", "vars", "meta"])
        )

      Enum.filter(roots, &(&1 == "frames")) ++ Enum.reject(roots, &(&1 == "frames"))
    end

    # A node the layer does not carry yet but a page shows a form for — the frame's meta
    # (§18.15) — is implied by its label: writing to it creates it.
    defp implied("meta"), do: %{path: [:meta], kind: :meta, label: "meta"}
    defp implied(_label), do: nil

    defp first_node(nodes, mine) do
      Enum.find(nodes, &(&1.label != "design" and &1.path in mine)) ||
        Enum.find(nodes, &(&1.label != "design")) || hd(nodes)
    end

    # The selected use, resolved: the page of a site the design has no node of.
    defp target_fragment(%{uses: uses, labels: labels, selected: selected, store: store}) do
      case Stack.get(uses, selected) do
        nil ->
          %{}

        use ->
          {[{_label, fragment}], _missing} = Stack.resolve([use], labels, Stack.fetch(store))
          fragment
      end
    end

    defp tab_class(open?, here?, count) do
      ["vis-builder-node"]
      |> then(&if open?, do: &1 ++ ["vis-builder-node-open"], else: &1)
      |> then(&if here?, do: &1, else: &1 ++ ["vis-builder-node-elsewhere"])
      |> then(&if count > 0, do: &1 ++ ["vis-builder-node-needs"], else: &1)
      |> Enum.join(" ")
    end

    # The tab that ends the row (spec/14 §18.13, #363): open while the panel is up, badged
    # with the variables that have neither a default nor a binding.
    defp variables_tab(layers, design, bindings, context) do
      count = length(Variables.unbound(layers, design, bindings))
      open? = context == :variables

      %{
        open: open?,
        needs: count,
        class: tab_class(open?, true, count) <> " vis-builder-node-variables",
        title: tab_title("variables", true, false, count) |> String.replace(" of this site", "")
      }
    end

    # The word a root wears: `sources` is *data* to a person (#372); the design key and the
    # event value stay the key.
    @doc false
    def root_word("sources"), do: "data"
    # A design holds its frames by name (#383); the tab is still the word a person reads.
    def root_word("frames"), do: "frame"
    def root_word(root), do: root

    defp tab_title(root, here?, chart?, count) do
      base =
        cond do
          chart? -> "#{root} of the chart"
          here? -> "#{root} of this site"
          true -> "#{root} — this site declares none; opens the layer that does"
        end

      case count do
        0 -> base
        1 -> base <> " — 1 thing still needed"
        n -> base <> " — #{n} things still needed"
      end
    end

    defp chips(children, entry, facet) do
      facets = Editor.facets(entry.kind)
      open = if facet in facets, do: facet, else: List.first(facets)

      nodes =
        for child <- children do
          %{
            label: child.label,
            node: child.node,
            facet: nil,
            event: "select_node",
            class:
              chip(child.open, nil) <>
                if(child.needs > 0, do: " vis-builder-chip-needs", else: "")
          }
        end

      case facets do
        [_single] ->
          nodes

        many ->
          nodes ++
            for {one, index} <- Enum.with_index(many) do
              %{
                label: to_string(one),
                node: nil,
                facet: one,
                event: "facet",
                class: chip(one == open, index == 0 and nodes != [])
              }
            end
      end
    end

    defp chip(open?, first_facet?) do
      ["vis-builder-chip"]
      |> then(&if open?, do: &1 ++ ["vis-builder-chip-open"], else: &1)
      |> then(&if first_facet?, do: &1 ++ ["vis-builder-chip-divided"], else: &1)
      |> Enum.join(" ")
    end

    defp style_site(entry, node) do
      case Schema.key(entry.kind, :style) do
        nil ->
          nil

        %{default: fallback} ->
          value = is_map(node) && Map.get(node, :style)
          %{value: value, fallback: fallback, stack: current_stack(value || nil, fallback)}
      end
    end

    defp variables(layers, design) do
      declared = design |> Map.get(:vars, %{}) |> Map.keys()
      used = layers |> Chart.free_vars() |> Enum.map(& &1.name)
      (declared ++ used) |> Enum.uniq() |> Enum.sort() |> Enum.map(&to_string/1)
    end

    defp open_style(%{path: [:styles, name]}), do: name
    defp open_style(_entry), do: nil

    @doc false
    def root(label), do: label |> String.split(~r/[.\[]/, parts: 2) |> hd()

    defp leaf(label, root) do
      label |> String.replace_prefix(root, "") |> String.replace_prefix(".", "")
    end

    # A signal added is a source of the chart (spec/14 §19.10): declared under its name in
    # the selected layer with the signal's fields, unless the chart declares one already.
    # The data page's rows (spec/14 §19.10, #372): every source of the composed design with
    # its columns, types, generator and host rows, the declaring layer's label beside it.
    defp data_rows(design, assigns, owned) do
      pool = pool(assigns)
      %{uses: uses, labels: labels} = assigns

      owners =
        for {[:sources, name], id} <- owned, into: %{} do
          {name, Stack.label(labels, Stack.get(uses, id))}
        end

      Sources.rows(design, assigns.signals, pool, Scales.pool_types(pool), owners)
    end

    # The inspect tab's page (spec/14 §18.15): the nodes at the top of the open root — the
    # root itself when it is one node, else its members — each a page of sections; the
    # frame's opens with the design's meta.
    defp page(nodes, entry, layer, errors, owned, %{uses: uses, labels: labels} = assigns) do
      open_root = root(entry.label)
      under = Enum.filter(nodes, &(root(&1.label) == open_root and &1.label != "design"))
      needs = needs(errors)

      owners =
        Map.new(owned, fn {path, id} -> {path, Stack.label(labels, Stack.get(uses, id))} end)

      selected = Stack.get(uses, assigns.selected)
      layer_label = selected && Stack.label(labels, selected)
      # The labels of the library's sites, anywhere in the tree, each with its row — the
      # index unlock takes: read-only in the chart (§18.8, §18.15, #381).
      locked =
        for %{use: use, index: index} <- Stack.all(uses),
            Stack.locked?(use),
            into: %{},
            do: {Stack.label(labels, use), index}

      tops =
        case Enum.find(under, &(length(&1.path) == 1)) do
          nil -> Enum.filter(under, &(length(&1.path) == 2))
          single -> [single]
        end

      tops =
        for node <- tops do
          name = leaf(node.label, open_root)

          %{
            kind: node.kind,
            node: at(layer, node.path) || %{},
            path: node.path,
            label: node.label,
            name: if(name == "", do: node.label, else: name),
            slug: node.label |> String.replace(~r/[^A-Za-z0-9]+/, "-") |> String.trim("-"),
            needs: Map.get(needs, node.label, 0),
            layer: Map.get(owners, node.path),
            other?: Map.get(owners, node.path) not in [nil, layer_label],
            before: if(node.kind == :frame, do: [meta_form(layer)], else: [])
          }
        end

      page = %{owners: owners, layer: layer_label, locked: locked}

      case tops do
        [one] when length(one.path) == 1 ->
          Map.merge(page, %{sections?: false, single: one, tops: []})

        # The one frame of a design holds the root by itself (#383): its page is the frame's,
        # as it was when a design had a single `frame` key. Several frames are several
        # sections, one per frame, like the styles or the sources.
        [%{kind: :frame} = one] ->
          Map.merge(page, %{sections?: false, single: one, tops: []})

        many ->
          Map.merge(page, %{sections?: true, single: nil, tops: many})
      end
    end

    # The columns the pool's rows have, by name (spec/14 §18.6): the first row's keys.
    defp columns(pool) do
      Map.new(pool, fn {name, rows} ->
        case Visualize.Data.Table.rows(rows) do
          [first | _] when is_map(first) ->
            {name, first |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort()}

          _none ->
            {name, []}
        end
      end)
    end

    # The name a keyed source site is declared under, for its fields' columns.
    defp source_name(%{uses: uses, selected: selected}, _fetch) do
      case Stack.get(uses, selected) do
        %Use{local: %{source: _}, key: key} -> key
        _other -> nil
      end
    end

    # The design's name and description open the frame's page (spec/14 §18.15).
    defp meta_form(layer) do
      %{kind: :meta, node: Map.get(layer, :meta) || %{}, path: [:meta], label: "meta", only: nil}
    end

    # The axes section's rows for the open node (#373): a mark's position scales, or a
    # position scale's own row; nothing elsewhere.
    defp axes_rows(design, %{kind: :mark}, mark) when is_map(mark),
      do: Axes.rows(design, Scales.position_scales(design, mark))

    defp axes_rows(design, %{kind: :scale, path: [:frames, _frame, :scales, name]}, _node)
         when name in [:x, :y, :angle, :r],
         do: Axes.rows(design, [name])

    defp axes_rows(_design, _entry, _node), do: []

    @doc false
    def current_stack(nil, nil), do: []
    def current_stack(nil, fallback), do: [fallback]
    def current_stack(false, fallback), do: current_stack(nil, fallback)
    def current_stack(value, _fallback) when is_list(value), do: value
    def current_stack(value, _fallback), do: [value]
  end
end
