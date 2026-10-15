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
        update_layer: 4
      ]

    alias Visualize.Chart
    alias Visualize.Chart.Builder.{Editor, Fills, FormSchema, Params, Stack}
    alias Visualize.Chart.{Fragment, Use, Var}

    # The events this module handles: `Visualize.Chart.Builder.handle_event/3` routes
    # each here.
    @events ~w(
      toggle_axis toggle_grid add_style_entry remove_style_entry select_style_entry
      edit_style add_style select_style edit submitted set_var set_key list_add
      list_remove
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

    # Every edit at a site lands in its local style, never in a named entry (§18.19, D-98).
    def handle_event("edit_style", %{"_target" => [target]} = params, socket) do
      if Fills.control?(target) do
        {:noreply, filled(socket, target, params[target], &styled(&1, &2))}
      else
        {:noreply, Enum.reduce(Editor.changes(:style, params), socket, &styled(&2, &1))}
      end
    end

    def handle_event("edit_style", _params, socket), do: {:noreply, socket}

    def handle_event("add_style", %{"name" => submitted}, socket) do
      case Editor.parse({:ref, :style}, String.trim(submitted)) do
        {:ok, name} ->
          socket
          |> update_layer([:styles], name, {:ok, %{}})
          |> opened("styles." <> to_string(name))
          |> assign(:notice, nil)
          |> then(&{:noreply, &1})

        :error ->
          {:noreply, assign(socket, :notice, "a style needs a name")}
      end
    end

    def handle_event("select_style", %{"name" => submitted}, socket) do
      %{layers: layers} = editing(socket.assigns)

      case declaring(layers, submitted) do
        nil -> {:noreply, socket}
        index -> {:noreply, socket |> select(index) |> opened("styles." <> submitted)}
      end
    end

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

      with %{key: key, type: {:list, scalar}} <-
             Enum.find(FormSchema.describe(entry.kind), &(to_string(&1.key) == field)),
           {:ok, item} <- Editor.parse(scalar, typed) do
        list = if(is_map(node), do: Map.get(node, key, []), else: []) ++ [item]
        {:noreply, socket |> update_layer(entry.path, key, {:ok, list}) |> assign(:notice, nil)}
      else
        _other -> {:noreply, socket}
      end
    end

    def handle_event("list_remove", %{"field" => field, "index" => index} = params, socket) do
      socket = aimed(socket, params)
      %{entry: entry, editing: node} = editing(socket.assigns)

      with %{key: key, type: {:list, _}} <-
             Enum.find(FormSchema.describe(entry.kind), &(to_string(&1.key) == field)),
           list when is_list(list) <- is_map(node) && Map.get(node, key) do
        rest = List.delete_at(list, position(index))
        write = if rest == [], do: :error, else: {:ok, rest}
        {:noreply, update_layer(socket, entry.path, key, write)}
      else
        _other -> {:noreply, socket}
      end
    end

    # The fill group's controls (spec/14 §18.6): `fill_style` writes the fill and may declare
    # the gradient named for the style; the `fill.…` controls edit that gradient where it is
    # declared. `write` is how this form writes the fill itself — the node's or the panel's.
    defp filled(socket, target, submitted, write) do
      %{entry: entry, editing: node, design: design} = editing(socket.assigns)
      value = if(is_map(node), do: Map.get(node, :fill))
      defs = Map.get(design, :defs, %{})
      name = Fills.name(entry.path)

      target
      |> Fills.writes(submitted, value, defs, name, nil)
      |> Enum.reduce(socket, fn
        {:fill, parsed}, acc -> write.(acc, {:fill, parsed})
        {:declare, name, gradient}, acc -> declare_gradient(acc, name, gradient)
        {:gradient, name, fun}, acc -> update_gradient(acc, name, fun)
      end)
      |> assign(:notice, nil)
    end

    # A gradient is declared where the selected site can hold it: under the site's own
    # `defs` when the site is a design-level layer, else as a gradient site of its own,
    # keyed by name, just below (spec/14 §18.6, §19.3).
    defp declare_gradient(socket, name, gradient) do
      %{uses: uses, labels: labels, selected: selected} = socket.assigns

      case Stack.get(uses, selected) do
        nil ->
          socket

        %Use{local: local} = use ->
          cond do
            declares_gradient?(use, name) ->
              update_gradient(socket, name, fn _old -> gradient end)

            is_map(local) and Fragment.wrapped(local) == nil ->
              update_layer(socket, [:defs], name, {:ok, gradient})

            true ->
              site = %{Use.new(nil, uses) | ref: nil, local: %{gradient: gradient}, key: name}

              assign(socket,
                uses: Stack.insert(uses, selected, site),
                labels: Map.put(labels, site.id, "gradient #{name}")
              )
          end
      end
    end

    # The gradient is edited in the site that declares it — as a keyed gradient site, or
    # under a layer's `defs`; one declared only through a library reference is left alone.
    defp update_gradient(socket, name, fun) do
      %{uses: uses} = socket.assigns

      case Enum.find(uses, &declares_gradient?(&1, name)) do
        nil ->
          assign(socket, :notice, "gradient #{name} is not declared in this stack")

        %Use{ref: ref} = use when ref != nil ->
          assign(socket, :notice, locked_notice(socket.assigns, use))

        %Use{id: id, local: %{gradient: body}} ->
          assign(socket, :uses, Stack.update(uses, id, &%{&1 | local: %{gradient: fun.(body)}}))

        %Use{id: id} ->
          assign(
            socket,
            :uses,
            Stack.update(uses, id, fn use ->
              Stack.write(use, [:defs], name, {:ok, fun.(get_in(use.local, [:defs, name]))})
            end)
          )
      end
    end

    defp declares_gradient?(%Use{local: %{gradient: body}, key: key}, name) when is_map(body),
      do: key == name

    defp declares_gradient?(%Use{local: local}, name) when is_map(local),
      do: is_map(local[:defs]) and Map.has_key?(local[:defs], name)

    defp declares_gradient?(_use, _name), do: false

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

      case Enum.find(FormSchema.describe(entry.kind), &(to_string(&1.key) == field)) do
        %{key: key, type: {:list, _}} ->
          ticked =
            params |> Map.get(field <> ".pick", []) |> List.wrap() |> Enum.map(&String.to_atom/1)

          vars = for %Var{} = v <- (is_map(node) && Map.get(node, key, [])) || [], do: v
          parsed = if ticked ++ vars == [], do: :error, else: {:ok, ticked ++ vars}
          socket |> update_layer(entry.path, key, parsed) |> assign(:notice, nil)

        _other ->
          socket
      end
    end

    defp edit_field(socket, entry, target, params) do
      if Fills.control?(target) do
        {:noreply, filled(socket, target, params[target], &edited(&1, entry, &2))}
      else
        {:noreply,
         Editor.changes(entry.kind, params)
         |> Enum.reduce(socket, &edited(&2, entry, &1))
         |> derived_scales()}
      end
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

    defp styled(socket, nil), do: socket
    defp styled(socket, {key, parsed}), do: restacked(socket, &local(&1, key, parsed))

    defp local(stack, key, parsed) do
      case List.last(stack) do
        node when is_map(node) -> List.replace_at(stack, -1, write_key(node, key, parsed))
        _none -> stack ++ [write_key(%{}, key, parsed)]
      end
    end

    defp write_key(node, key, {:ok, value}), do: Map.put(node, key, value)
    defp write_key(node, key, :error), do: Map.delete(node, key)

    # A change to the open node's stack, written back in whatever shape it came in: a stack
    # of one that names a style stays a bare reference (spec/14 §3.6).
    @doc false
    def restacked(socket, change) do
      %{entry: entry, editing: node} = editing(socket.assigns)

      case FormSchema.key(entry.kind, :style) do
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
