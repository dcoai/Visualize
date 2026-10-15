if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Events.Form do
    @moduledoc false
    # The form (spec/14 §18.6, §18.7, §18.18–§18.20): a field edited, a list's items, a
    # site's key, a parameter's value, a style stack and its entries, a fill and its gradient,
    # and the axes ticked where their scale is.
    #
    # Split from `Visualize.Chart.Builder` by area (#568); compiled only with
    # `Phoenix.Component`, as the builder is (spec/10 §1.1, D-45, D-85).

    import Phoenix.Component, only: [assign: 2, assign: 3, update: 3]
    import Visualize.Chart.Builder.Editing, only: [current_stack: 2, editing: 1]
    import Visualize.Chart.Builder.Selection, only: [aimed: 2, opened: 2, position: 1, select: 2]
    import Visualize.Chart.Builder.Workspace, only: [selection: 2]

    import Visualize.Chart.Builder.Writes,
      only: [
        appended: 4,
        derived_scales: 1,
        locked_notice: 2,
        owner_of: 4,
        pool: 1,
        update_layer: 4,
        update_node: 3
      ]

    alias Visualize.Chart
    alias Visualize.Chart.Builder.{Editor, Params, Stack, StyleForm, StyleStack}
    alias Visualize.Chart.{Fragment, Schema, Use, Var}
    alias Visualize.Theme

    # The events this module handles: `Visualize.Chart.Builder.handle_event/3` routes
    # each here.
    @events ~w(
      toggle_axis toggle_grid add_style_entry remove_style_entry select_style_entry
      edit_style add_style select_style edit submitted set_var set_key list_add
      list_remove style_item edit_defaults choose_palette_style override_style
    )

    @doc false
    def events, do: @events

    # -- axes ticked where their scale is (spec/14 §18.16, #373) --------------------------

    # A side ticked adds `%{scale, side}` to the frame's axes in the frame's layer, the
    # scale declared first when the frame lacks it; unticked, that axis leaves its layer.
    @doc false
    def handle_event("toggle_axis", %{"scale" => scale, "side" => side} = params, socket) do
      scale = String.to_atom(scale)
      side = String.to_atom(side)
      %{design: design} = editing(socket.assigns)
      # The frame the row is of — the mark's or the scale's own (#615).
      frame_path = [:frames, ticked_frame(design, params)]

      axes =
        design
        |> get_in(frame_path ++ [:axes])
        |> List.wrap()
        |> Enum.with_index()

      case Enum.find(axes, fn {axis, _i} -> axis[:scale] == scale and axis[:side] == side end) do
        {axis, index} ->
          {:noreply, axis_removed(socket, frame_path, axis, index)}

        nil ->
          socket =
            if Map.has_key?(get_in(design, frame_path ++ [:scales]) || %{}, scale),
              do: socket,
              else:
                update_layer(
                  socket,
                  frame_path ++ [:scales],
                  scale,
                  {:ok, %{kind: :linear, domain: :auto}}
                )

          {:noreply, appended(socket, frame_path, :axes, %{scale: scale, side: side})}
      end
    end

    def handle_event("toggle_grid", %{"scale" => scale} = params, socket) do
      scale = String.to_atom(scale)
      %{design: design} = editing(socket.assigns)
      frame_path = [:frames, ticked_frame(design, params)]

      axes =
        design
        |> get_in(frame_path ++ [:axes])
        |> List.wrap()
        |> Enum.with_index()

      case Enum.find(axes, fn {axis, _i} -> axis[:scale] == scale end) do
        nil ->
          {:noreply, socket}

        {axis, index} ->
          on? = Map.get(axis, :grid, false) == true
          parsed = if on?, do: :error, else: {:ok, true}
          path = frame_path ++ [:axes, index]
          {:noreply, update_layer(socket, path, :grid, parsed)}
      end
    end

    # -- style stacks and the palette ----------------------------------------------------

    def handle_event("add_style_entry", %{"name" => submitted}, socket) do
      case Editor.parse({:ref, :style}, String.trim(submitted)) do
        {:ok, name} -> {:noreply, restacked(socket, &(&1 ++ [name]))}
        :error -> {:noreply, assign(socket, :notice, "a style entry needs a name")}
      end
    end

    def handle_event("remove_style_entry", %{"index" => index}, socket) do
      at = position(index)
      {:noreply, restacked(socket, &List.delete_at(&1, at))}
    end

    def handle_event("select_style_entry", %{"index" => index}, socket) do
      {:noreply, assign(socket, :style_entry, position(index))}
    end

    # Every edit at a site lands in its local style, never in a named entry (§18.19, D-98),
    # and writes only the key changed, in its part (§18.7, D-178): the local style is the
    # node the write lands in, the site's resolved style what a type change starts from.
    def handle_event("edit_style", %{"_target" => [_target]} = params, socket) do
      {:noreply, styled(socket, &Editor.changes(:style, params, &1, &2))}
    end

    def handle_event("edit_style", _params, socket), do: {:noreply, socket}

    # A created style is declared in the design, never in a layer (§18.14, §19.11, D-178):
    # a style site keyed by its name at the chart's top level, selected and opened. A name
    # the design declares already is opened, not declared twice.
    def handle_event("add_style", %{"name" => submitted}, socket) do
      %{design: design} = editing(socket.assigns)

      case Editor.parse({:ref, :style}, String.trim(submitted)) do
        {:ok, name} when is_atom(name) ->
          if Map.has_key?(Map.get(design, :styles) || %{}, name) do
            socket
            |> opened_style(name)
            |> assign(:notice, "#{name} is declared already — opened it")
            |> then(&{:noreply, &1})
          else
            {:noreply, declared_style(socket, name)}
          end

        _error_or_id ->
          {:noreply, assign(socket, :notice, "a style needs a name")}
      end
    end

    # A theme palette entry chosen in the palette panel: marked, and offered for override
    # (spec/14 §18.14, #685).
    def handle_event("choose_palette_style", %{"name" => submitted}, socket) do
      {:noreply, assign(socket, :palette_chosen, palette_name(socket, submitted))}
    end

    # The theme's entry declared in the design as a style site of its name, holding the
    # entry to change (§18.14, D-178); a name the design declares is opened instead.
    def handle_event("override_style", %{"name" => submitted}, socket) do
      %{design: design, palette_theme: theme} = editing(socket.assigns)

      case palette_name(socket, submitted) do
        nil ->
          {:noreply, socket}

        name ->
          socket = assign(socket, :palette_chosen, nil)

          if Map.has_key?(Map.get(design, :styles) || %{}, name),
            do: {:noreply, opened_style(socket, name)},
            else: {:noreply, declared_style(socket, name, Theme.style(theme, name))}
      end
    end

    def handle_event("select_style", %{"name" => submitted}, socket) do
      %{layers: layers} = editing(socket.assigns)

      case declaring(layers, submitted) do
        nil -> {:noreply, socket}
        index -> {:noreply, socket |> select(index) |> opened("styles." <> submitted)}
      end
    end

    # A list of nodes in a style — a gradient's stops — gains an item or loses one (§18.6),
    # in the node the form edits or, at a site, the local style (`edit`).
    def handle_event("style_item", %{"field" => field, "op" => op} = params, socket) do
      change =
        case {op, Integer.parse(Map.get(params, "index", ""))} do
          {"add", _index} -> :add
          {"remove", {i, ""}} -> {:remove, i}
          {"drop", _index} -> :drop
          _other -> nil
        end

      socket = aimed(socket, params)

      case {change, Map.get(params, "edit")} do
        {nil, _edit} ->
          {:noreply, socket}

        {change, "edit_style"} ->
          {:noreply, styled(socket, &items(:style, field, change, &1, &2))}

        {change, "edit_defaults"} ->
          {:noreply, site_defaults(socket, &items(:defaults, field, change, &1, &1))}

        {change, _edit} ->
          %{entry: entry, editing: node} = editing(socket.assigns)
          writes = items(entry.kind, field, change, node, node)
          {:noreply, update_node(socket, entry.path, writes)}
      end
    end

    # A layer's or a group's own defaults, from the site's context (spec/14 §18.7, #684):
    # written into the composite's `defaults`, never into what it holds.
    def handle_event("edit_defaults", %{"_target" => [_target]} = params, socket) do
      {:noreply, site_defaults(socket, &Editor.changes(:defaults, params, &1))}
    end

    def handle_event("edit_defaults", _params, socket), do: {:noreply, socket}

    # -- the form, the parameters, the document ------------------------------------------

    def handle_event("edit", %{"_target" => [target]} = params, socket) do
      socket = aimed(socket, params)
      %{entry: entry} = editing(socket.assigns)

      if String.ends_with?(target, ".pick") do
        {:noreply, picked(socket, entry, String.trim_trailing(target, ".pick"), params)}
      else
        edit_field(socket, entry, target, params)
      end
    end

    def handle_event("edit", _params, socket), do: {:noreply, socket}

    # A form's submit is intercepted so Enter in a box never navigates (spec/14 §18.7,
    # #274); the change event already wrote every field, so there is nothing to do.
    def handle_event("submitted", _params, socket), do: {:noreply, socket}

    def handle_event("set_var", %{"_target" => [name]} = params, socket) do
      %{layers: layers} = editing(socket.assigns)
      free = Enum.find(Chart.free_vars(layers), &(to_string(&1.name) == name))
      {:noreply, bound(socket, free, params[name])}
    end

    # The key a name-keyed site is declared under, from the context panel (spec/14 §19.3):
    # the one surface that writes `Use.key`; blank removes it.
    def handle_event("set_key", params, socket) do
      %{selected: selected} = socket.assigns
      pool = pool(socket.assigns)

      # The pool list writes `key`; the box beneath it, a name the pool lacks, `key.other`
      # (spec/14 §19.10) — whichever changed.
      submitted =
        case params do
          %{"_target" => ["key.other"]} -> Map.get(params, "key.other")
          _other -> Map.get(params, "key")
        end

      key =
        case Editor.parse(:name, submitted) do
          {:ok, name} -> name
          :error -> nil
        end

      # A source chosen from the pool takes the pool's fields when it declares none
      # (spec/14 §19.10): one pick, and it previews.
      # The key is the site's own and is always written; the fields are the body's, and a
      # locked site keeps the entry's (§18.15).
      {:noreply,
       update(socket, :uses, fn uses ->
         Stack.update(uses, selected, fn u ->
           if Stack.locked?(u),
             do: %{u | key: key},
             else: %{u | key: key, local: filled(u.local, key, pool)}
         end)
       end)}
    end

    # A list of scalars as items (spec/14 §18.6): Enter in the + box appends one read by the
    # element's type; × removes by index. Both write the whole list, as the schema says.
    def handle_event("list_add", %{"field" => field} = params, socket) do
      socket = aimed(socket, params)
      %{entry: entry, editing: node} = editing(socket.assigns)
      typed = Map.get(params, "value") || Map.get(params, "#{field}.add") || ""

      with %{path: at, spec: %{type: {:list, scalar}}} <- Editor.locate(entry.kind, field),
           {:ok, item} <- Editor.parse(scalar, typed) do
        list = List.wrap(Editor.value_at(entry.kind, node, at)) ++ [item]

        {:noreply,
         socket
         |> update_node(entry.path, Editor.write(entry.kind, node, at, {:ok, list}))
         |> assign(:notice, nil)}
      else
        _other -> {:noreply, socket}
      end
    end

    def handle_event("list_remove", %{"field" => field, "index" => index} = params, socket) do
      socket = aimed(socket, params)
      %{entry: entry, editing: node} = editing(socket.assigns)

      with %{path: at, spec: %{type: {:list, _}}} <- Editor.locate(entry.kind, field),
           list when is_list(list) <- Editor.value_at(entry.kind, node, at) do
        rest = List.delete_at(list, position(index))
        write = if rest == [], do: :error, else: {:ok, rest}
        {:noreply, update_node(socket, entry.path, Editor.write(entry.kind, node, at, write))}
      else
        _other -> {:noreply, socket}
      end
    end

    # A source chosen from the pool takes the pool's fields when it declares none (§19.10).
    defp filled(%{source: body} = local, key, pool) when is_map(body) and key != nil do
      case {Map.get(body, :fields, []), Map.get(pool, key)} do
        {[], rows} when rows != nil ->
          case Visualize.Data.Table.rows(rows) do
            [first | _] when is_map(first) ->
              %{local | source: Map.put(body, :fields, first |> Map.keys() |> Enum.sort())}

            _none ->
              local
          end

        _other ->
          local
      end
    end

    defp filled(local, _key, _pool), do: local

    # A list ticked from the columns the rows have (spec/14 §18.6): the ticked names in
    # the list's order, the variable items kept.
    defp picked(socket, entry, field, params) do
      %{editing: node} = editing(socket.assigns)

      case Editor.locate(entry.kind, field) do
        %{path: [key], spec: %{type: {:list, _}}} ->
          ticked =
            params |> Map.get(field <> ".pick", []) |> List.wrap() |> Enum.map(&String.to_atom/1)

          vars = for %Var{} = v <- (is_map(node) && Map.get(node, key, [])) || [], do: v
          parsed = if ticked ++ vars == [], do: :error, else: {:ok, ticked ++ vars}
          socket |> update_layer(entry.path, key, parsed) |> assign(:notice, nil)

        _other ->
          socket
      end
    end

    # A form's change, in the node the editor is on: a key's write, or a style's parts
    # (§18.7, D-178); the scales a bound channel needs follow.
    defp edit_field(socket, entry, _target, params) do
      %{editing: node} = editing(socket.assigns)

      {:noreply,
       entry.kind
       |> Editor.changes(params, node)
       |> Enum.reduce(socket, &edited(&2, entry, &1))
       |> derived_scales()}
    end

    # A composed axis taken out of the layer that gives it: an axis site leaves the stack;
    # an entry of a layer's `frame.axes` leaves the list.
    defp axis_removed(socket, frame_path, axis, index) do
      %{uses: uses, store: store} = socket.assigns
      fetch = Stack.fetch(store)
      placed = Stack.placed(uses, fetch)
      leaves = Chart.explain(placed)

      case owner_of(leaves, placed, uses, frame_path ++ [:axes, index]) do
        nil ->
          socket

        id ->
          case Stack.get(uses, id) do
            %Use{ref: ref} = use when ref != nil ->
              assign(socket, :notice, locked_notice(socket.assigns, use))

            %Use{local: %{axis: _}} = use ->
              closed_site(socket, use)

            use ->
              local = Stack.local_path(use, fetch, frame_path)
              own = List.wrap(get_in(use.local, local ++ [:axes]) || [])
              rest = List.delete(own, axis)
              parsed = if rest == [], do: :error, else: {:ok, rest}

              assign(
                socket,
                :uses,
                Stack.update(uses, use.id, &Stack.write(&1, local, :axes, parsed))
              )
          end
      end
    end

    # The frame an axes row names, when the composed design has it; else the design's.
    defp ticked_frame(design, %{"frame" => name}) when is_binary(name) do
      frames = Map.get(design, :frames)
      frames = if is_map(frames), do: Map.keys(frames), else: []
      Enum.find(frames, &(to_string(&1) == name)) || Fragment.frame_of(design, nil)
    end

    defp ticked_frame(design, _params), do: Fragment.frame_of(design, nil)

    # An axis site unticked leaves the stack; the selection falls back to the first layer.
    defp closed_site(socket, %Use{id: id}) do
      uses = Enum.reject(socket.assigns.uses, &(&1.id == id))

      assign(socket,
        uses: uses,
        labels: Map.delete(socket.assigns.labels, id),
        selected: selection(socket.assigns.selected, uses)
      )
    end

    defp edited(socket, _entry, nil), do: socket

    defp edited(socket, entry, {key, parsed}),
      do: socket |> update_layer(entry.path, key, parsed) |> unguessed(entry, key)

    # An edited field is no longer a guess; a mark's data changed clears its channels' (§18.16).
    defp unguessed(socket, entry, key) do
      prefix = if key == :data and entry.kind == :mark, do: entry.label <> ".channels.", else: nil
      own = entry.label <> "." <> to_string(key)

      update(socket, :guessed, fn guessed ->
        guessed
        |> MapSet.delete(own)
        |> MapSet.reject(&(prefix != nil and String.starts_with?(&1, prefix)))
      end)
    end

    # The writes `writes.(local, resolved)` means, laid in the site's local style: the last
    # entry when it is a node, else a new one (D-98). `resolved` is the site's stack in its
    # parts, which a paint's type change and a list's rows start from (§18.19).
    defp styled(socket, writes) do
      %{design: design, style_site: site, palette_theme: theme} = editing(socket.assigns)
      stack = (site && site.stack) || []
      resolved = StyleStack.resolved(design, stack, theme)

      local =
        case List.last(stack) do
          node when is_map(node) and not is_struct(node) -> node
          _none -> %{}
        end

      case writes.(local, resolved) do
        [] -> socket
        changes -> restacked(socket, &local(&1, changes))
      end
    end

    defp local(stack, changes) do
      case List.last(stack) do
        node when is_map(node) and not is_struct(node) ->
          List.replace_at(stack, -1, Enum.reduce(changes, node, &write_key(&2, &1)))

        _none ->
          stack ++ [Enum.reduce(changes, %{}, &write_key(&2, &1))]
      end
    end

    defp write_key(node, {key, {:ok, value}}), do: Map.put(node, key, value)
    defp write_key(node, {key, :error}), do: Map.delete(node, key)

    # The writes `writes.(own)` means, laid in the selected group's own `defaults`; a site
    # that is no inline group has none to write (§18.7, #684).
    defp site_defaults(socket, writes) do
      %{uses: uses, selected: selected} = socket.assigns

      case Stack.get(uses, selected) do
        %Use{} = use ->
          if Stack.group?(use) do
            own = get_in(use.local, [:composite, :defaults]) || %{}
            updated = Enum.reduce(writes.(own), own, &write_key(&2, &1))

            composite =
              if updated == %{},
                do: Map.delete(use.local.composite, :defaults),
                else: Map.put(use.local.composite, :defaults, updated)

            uses =
              Stack.update(uses, use.id, &%{&1 | local: Map.put(&1.local, :composite, composite)})

            assign(socket, uses: uses, notice: nil)
          else
            socket
          end

        nil ->
          socket
      end
    end

    # An item added to or removed from a style's list of nodes at a field's path.
    defp items(kind, field, change, node, resolved) do
      case StyleForm.kind?(kind) && StyleForm.locate(kind, field) do
        %{path: path, spec: %{type: {:list, {:node, _}}}, suffix: nil} when change != :drop ->
          StyleForm.item(node, path, change, resolved)

        # A defaults node's entry for a mark kind dropped (§18.7, #684).
        %{path: path, spec: %{type: {:node, :kind_defaults}}, suffix: nil} when change == :drop ->
          StyleForm.item(node, path, :drop, resolved)

        _other ->
          []
      end
    end

    # A change to the open node's stack, written back in whatever shape it came in: a stack
    # of one that names a style stays a bare reference (spec/14 §3.6).
    @doc false
    def restacked(socket, change) do
      %{entry: entry, editing: node} = editing(socket.assigns)

      case Schema.key(entry.kind, :style) do
        nil ->
          socket

        %{default: fallback} ->
          current = current_stack(is_map(node) && Map.get(node, :style), fallback)

          socket
          |> update_layer(entry.path, :style, {:ok, shaped(change.(current))})
          |> assign(:style_entry, nil)
      end
    end

    defp shaped(stack) do
      case Enum.reject(stack, &(is_map(&1) and map_size(&1) == 0)) do
        [only] when not is_map(only) -> only
        pruned -> pruned
      end
    end

    @doc false
    def clamp(at, list), do: at |> max(0) |> min(length(list))

    # A variable takes the type of its first use (spec/14 §18.11); a blank control removes
    # the binding and the default returns.
    defp bound(socket, nil, _value), do: socket

    defp bound(socket, free, value) do
      case Editor.submitted(Params.expects(free), value) do
        {:ok, parsed} -> update(socket, :bindings, &Map.put(&1, free.name, parsed))
        :error -> update(socket, :bindings, &Map.delete(&1, free.name))
      end
    end

    # A style site keyed by the name, appended at the chart's top level, selected and its
    # node opened (§18.14, D-178).
    defp declared_style(socket, name, body \\ %{}) do
      %{uses: uses, labels: labels} = socket.assigns
      site = %{Use.new(nil, uses) | ref: nil, local: %{style: body}, key: name}

      socket
      |> assign(
        uses: uses ++ [site],
        labels: Map.put(labels, site.id, "style #{name}"),
        selected: site.id,
        notice: nil
      )
      |> opened("styles." <> to_string(name))
    end

    # A name of the theme's palette, read without making an atom (§18.14).
    defp palette_name(socket, submitted) do
      %{palette_theme: theme} = editing(socket.assigns)
      Enum.find(Theme.style_names(theme), &(to_string(&1) == submitted))
    end

    # A declared style opened where the highest layer declaring it is.
    defp opened_style(socket, name) do
      %{layers: layers} = editing(socket.assigns)

      case declaring(layers, to_string(name)) do
        nil -> opened(socket, "styles." <> to_string(name))
        index -> socket |> select(index) |> opened("styles." <> to_string(name))
      end
    end

    # The highest layer whose fragment declares a style of that name, or `nil`.
    defp declaring(layers, name) do
      layers
      |> Enum.with_index()
      |> Enum.filter(fn {{_label, fragment}, _index} ->
        fragment
        |> Map.get(:styles)
        |> then(&(is_map(&1) and Enum.any?(Map.keys(&1), fn key -> to_string(key) == name end)))
      end)
      |> List.last()
      |> case do
        {_layer, index} -> index
        nil -> nil
      end
    end
  end
end
