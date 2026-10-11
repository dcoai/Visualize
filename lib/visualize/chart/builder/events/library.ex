if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Events.Library do
    @moduledoc false
    # The library and the message (spec/14 §18.2, §19.6–§19.8): save, deploy, save to the
    # library, a new fragment, import, the library panel's folds and views, and a library
    # entry dropped — into the stack, onto a style stack or onto a reference field.
    #
    # Split from `Visualize.Chart.Builder` by area (#568); compiled only with
    # `Phoenix.Component`, as the builder is (spec/10 §1.1, D-45, D-85).

    import Phoenix.Component, only: [assign: 2, assign: 3, update: 3]
    import Visualize.Chart.Builder.Editing, only: [editing: 1]
    import Visualize.Chart.Builder.Events.Form, only: [clamp: 2, restacked: 2]
    import Visualize.Chart.Builder.Selection, only: [aimed: 2, decode_id: 1, position: 1]

    import Visualize.Chart.Builder.Workspace,
      only: [fetch: 2, opened_entry: 2, saved: 3, structure: 1]

    import Visualize.Chart.Builder.Writes, only: [admits: 2, linked: 3, update_layer: 4]

    alias Visualize.Chart
    alias Visualize.Chart.Builder.{Document, Stack, Store}
    alias Visualize.Chart.{Composite, Fragment, Schema, Validator}

    # The events this module handles: `Visualize.Chart.Builder.handle_event/3` routes
    # each here.
    @events ~w(
      save add_layer deploy new_fragment put_design library_fold library_toggle
      library_view fragment_key insert import
    )

    @doc false
    def events, do: @events

    # -- the message, and the library ----------------------------------------------------

    # Save sends structure, never the flattened result (spec/14 §19.6, D-103).
    @doc false
    def handle_event("save", _params, socket) do
      %{on_save: tag, id: id} = socket.assigns
      send(self(), {tag, id, structure(socket.assigns)})
      {:noreply, assign(socket, :notice, nil)}
    end

    # Click opens; only drag composes (spec/14 §19.8).
    def handle_event("add_layer", %{"name" => submitted}, socket) do
      case fetch(socket.assigns.store, submitted) do
        {:ok, entry} -> {:noreply, opened_entry(socket, entry)}
        :error -> {:noreply, assign(socket, :notice, "no fragment is stored under #{submitted}")}
      end
    end

    # Deploy is the other verb: the structure flattened through the store, and the flat
    # design sent — never while a non-composite kind is open (spec/14 §19.6, D-103).
    def handle_event("deploy", _params, socket) do
      %{on_deploy: tag, id: id, store: store, open: open} = socket.assigns

      if open != nil and open.kind != :composite do
        {:noreply, assign(socket, :notice, "deploy a composite; a #{open.kind} is not a chart")}
      else
        case Chart.flatten(structure(socket.assigns), Stack.fetch(store)) do
          {:ok, _design, %{keyless: [_ | _] = keyless}} ->
            names =
              Enum.map_join(
                keyless,
                ", ",
                &Stack.label(socket.assigns.labels, Stack.get(socket.assigns.uses, &1))
              )

            {:noreply,
             assign(socket, :notice, "not deployed: #{names} need a key to be declared under")}

          {:ok, design, %{missing: missing}} ->
            send(self(), {tag, id, design})
            {:noreply, assign(socket, :notice, showed_through(missing))}

          {:error, {:cycle, chain}} ->
            {:noreply,
             assign(
               socket,
               :notice,
               "not deployed: the stack refers to itself through #{inspect(chain)}"
             )}
        end
      end
    end

    # A new fragment of a kind starts empty and valid (spec/14 §19.8); a design is the
    # deployed tier and is not one to start (§19.6).
    def handle_event("new_fragment", %{"kind" => "design"}, socket) do
      {:noreply,
       assign(socket, :notice, "a design is what Deploy makes; start a composite instead")}
    end

    def handle_event("new_fragment", %{"kind" => submitted}, socket) do
      case Enum.find(Stack.kinds(), &(to_string(&1) == submitted)) do
        nil ->
          {:noreply, assign(socket, :notice, "#{submitted} is not a kind of fragment")}

        kind ->
          entry = %{id: nil, name: nil, kind: kind, fragment: Stack.empty(kind)}
          {:noreply, opened_entry(socket, entry)}
      end
    end

    # Saving names the entry, never the body. The workspace and a composite are saved as
    # structure; any other kind is saved as the lowest tier that holds it — one bare inline
    # site is its body, anything more is structure — and is refused if what it flattens to
    # is no longer that kind, or is not valid as one (spec/14 §19.6, §19.8).
    def handle_event("put_design", %{"name" => name}, socket) do
      %{store: store} = socket.assigns
      trimmed = String.trim(name)

      cond do
        is_nil(store) ->
          {:noreply, assign(socket, :notice, "no store is configured")}

        trimmed == "" ->
          {:noreply, assign(socket, :notice, "a saved fragment needs a name")}

        true ->
          {:noreply, put(socket, kept(socket.assigns), trimmed)}
      end
    end

    # The library folds to a rail and unfolds (spec/14 §18.16).
    def handle_event("library_fold", _params, socket) do
      {:noreply, update(socket, :library_open, &(not &1))}
    end

    # A top-level header of the library folded or unfolded, by name (spec/14 §18.16, #355).
    def handle_event("library_toggle", %{"name" => name}, socket) do
      toggle = fn set ->
        if MapSet.member?(set, name), do: MapSet.delete(set, name), else: MapSet.put(set, name)
      end

      {:noreply, update(socket, :library_folded, toggle)}
    end

    # Two views over one store; group is the default because it is the one a person
    # authored deliberately (spec/14 §19.8).
    def handle_event("library_view", %{"view" => "kind"}, socket),
      do: {:noreply, assign(socket, :library_view, :kind)}

    def handle_event("library_view", %{"view" => _group}, socket),
      do: {:noreply, assign(socket, :library_view, :group)}

    # A library item from the keyboard: Enter opens, Insert adds above the selected layer.
    def handle_event("fragment_key", %{"key" => key, "name" => name}, socket) do
      case key do
        enter when enter in ["Enter", " "] ->
          handle_event("add_layer", %{"name" => name}, socket)

        # Insert, `i` and `I` all insert it linked, as a drop does (spec/14 §18.17, #381).
        insert when insert in ["Insert", "i", "I"] ->
          handle_event("insert", %{"name" => name}, socket)

        _other ->
          {:noreply, socket}
      end
    end

    # A style fragment dropped on a site's stack: its id goes into the stack where it was
    # dropped, and nothing is merged or copied (spec/14 §18.20, §19.6).
    def handle_event("insert", %{"scope" => "style", "name" => submitted, "at" => at}, socket) do
      case fetch(socket.assigns.store, submitted) do
        {:ok, %{kind: :style} = entry} ->
          {:noreply,
           socket
           |> restacked(fn stack ->
             List.insert_at(stack, clamp(position(at), stack), entry.id)
           end)
           |> assign(added: entry.id, notice: nil)}

        {:ok, entry} ->
          {:noreply,
           assign(
             socket,
             :notice,
             "#{entry.name} is a #{entry.kind}, and a style site takes a style"
           )}

        :error ->
          {:noreply, assign(socket, :notice, "no fragment is stored under #{submitted}")}
      end
    end

    # A library entry dropped on a reference field writes its id there — the same write the
    # field's select makes — and an entry of another kind is refused by name (spec/14
    # §19.10). A style field is a stack, so a style goes onto it as a drop on the stack does.
    def handle_event(
          "insert",
          %{"scope" => "ref", "field" => field, "name" => submitted} = params,
          socket
        ) do
      socket = aimed(socket, params)
      %{entry: entry} = editing(socket.assigns)

      with {:ok, stored} <- fetch(socket.assigns.store, submitted),
           %{key: key, type: type} <-
             Enum.find(Schema.describe(entry.kind), &(to_string(&1.key) == field)),
           kind when kind != nil <- ref_kind(type) do
        cond do
          stored.kind != kind ->
            {:noreply,
             assign(
               socket,
               :notice,
               "a #{kind} field takes a #{kind}; #{stored.name} is a #{stored.kind}"
             )}

          kind == :style ->
            handle_event("insert", %{"scope" => "style", "name" => submitted, "at" => 99}, socket)

          true ->
            {:noreply,
             socket |> update_layer(entry.path, key, {:ok, stored.id}) |> assign(:notice, nil)}
        end
      else
        :error -> {:noreply, assign(socket, :notice, "no fragment is stored under #{submitted}")}
        _other -> {:noreply, assign(socket, :notice, "#{field} is not a reference field")}
      end
    end

    # A library entry into the stack (spec/14 §18.17, #381): a use referring to it, linked
    # and locked; at the gap given, into the container's row, or above the selected layer.
    def handle_event("insert", %{"name" => submitted} = params, socket) do
      at = drop_target(socket, params)

      case fetch(socket.assigns.store, submitted) do
        {:ok, entry} ->
          case admits(socket.assigns.open, entry) do
            :ok -> {:noreply, linked(socket, entry, at)}
            {:refused, notice} -> {:noreply, assign(socket, :notice, notice)}
          end

        :error ->
          {:noreply, assign(socket, :notice, "no fragment is stored under #{submitted}")}
      end
    end

    def handle_event("import", %{"document" => document}, socket) do
      case Chart.from_json(document) do
        {:ok, chart} -> {:noreply, imported(socket, Chart.to_map(chart))}
        {:error, reason} -> {:noreply, assign(socket, :notice, notice(reason))}
      end
    end

    # -- what a save keeps ---------------------------------------------------------------

    defp kept(%{open: open, uses: uses, stack_vars: vars})
         when open == nil or open.kind == :composite,
         do: {:ok, :composite, Stack.structure(uses, vars)}

    # A board is kept as its map form under the wrapper, checked by its own reader
    # (spec/14 §22.1, D-152); the mode keeps it valid alone, so this refuses only a board a
    # later edit of the reader would.
    defp kept(%{open: %{kind: :board}, board: board}) do
      fragment = %{board: Visualize.Board.to_map(board)}

      case Validator.validate(fragment, :board) do
        :ok -> {:ok, :board, fragment}
        {:error, errors} -> {:error, "not a valid board: " <> faults_notice(errors)}
      end
    end

    defp kept(%{open: %{kind: kind}, uses: uses, stack_vars: vars, store: store}) do
      fragment = Stack.body(uses, vars)

      case Composite.flatten(fragment, Stack.fetch(store)) do
        {:error, {:cycle, _chain}} ->
          {:error, "the stack refers to itself, and cannot be saved until it does not"}

        {:ok, flat, _report} ->
          case {Fragment.kind(flat), Validator.validate(flat, kind)} do
            {^kind, :ok} ->
              {:ok, kind, fragment}

            {^kind, {:error, errors}} ->
              {:error, "not a valid #{kind}: " <> faults_notice(errors)}

            {other, _} ->
              {:error, drifted(kind, other)}
          end
      end
    end

    defp put(socket, {:error, notice}, _name), do: assign(socket, :notice, notice)

    defp put(socket, {:ok, kind, fragment}, name) do
      %{store: store, open: open} = socket.assigns
      entry = %{id: open && open.id, name: name, kind: kind, fragment: fragment}

      saved(socket, Store.put(store, entry), fn s, id ->
        if open, do: assign(s, :open, %{open | id: id, name: name}), else: s
      end)
    end

    defp faults_notice(errors), do: Enum.map_join(errors, "; ", &Validator.format/1)

    defp showed_through([]), do: nil

    defp showed_through(missing) do
      refs = Enum.map_join(missing, ", ", fn {_site, ref} -> Store.encode_id(ref) end)
      "deployed with #{length(missing)} reference(s) showing through: #{refs}"
    end

    # The kind a field refers to, when it is a reference field at all.
    defp ref_kind({:ref, kind}), do: kind
    defp ref_kind(_type), do: nil

    defp drifted(kind, nil) do
      "this was opened as a #{kind} and is now many things at once; a saved #{kind} must still be one"
    end

    defp drifted(kind, other) do
      "this was opened as a #{kind} and is now a #{other}; a saved #{kind} must still be one"
    end

    # A document is a whole design, so it replaces the stack rather than joining it (D-88),
    # as its sites: one kind each, keyed where the document keyed them (spec/14 §18.12).
    defp imported(socket, design) do
      {uses, labels} = Composite.decompose(design)

      assign(socket,
        uses: uses,
        labels: labels,
        selected: uses |> List.first() |> then(&(&1 && &1.id)),
        open: nil,
        board: nil,
        board_cell: nil,
        return_to: nil,
        stash: nil,
        stack_vars: %{},
        bindings: %{},
        node_label: "design",
        facet: nil,
        notice: nil
      )
    end

    # A use referring to the entry, at the position it was dropped at; the label is the
    # entry's name (spec/14 §19.3).
    # Where a drop lands in the tree (spec/14 §18.17, #380): inside a group's row, before
    # the row at a flat position, or after the selected site when the drop said nothing.
    defp drop_target(socket, params) do
      cond do
        into = Map.get(params, "into") -> {:into, Stack.get(socket.assigns.uses, decode_id(into))}
        (at = Map.get(params, "at")) != nil -> {:at, position(at)}
        true -> {:after, socket.assigns.selected}
      end
    end

    defp notice(reason), do: Enum.join(Document.faults(reason), "; ")
  end
end
