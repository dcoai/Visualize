if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Events.Data do
    @moduledoc false
    # The data page (spec/14 §19.10, #372): sources added, renamed and removed, their
    # columns, types, generators and defaults, and the signals' play, pause and tick.
    #
    # Split from `Visualize.Chart.Builder` by area (#568); compiled only with
    # `Phoenix.Component`, as the builder is (spec/10 §1.1, D-45, D-85).

    import Phoenix.Component, only: [assign: 2, assign: 3, update: 3]
    import Visualize.Chart.Builder.Editing, only: [editing: 1]
    import Visualize.Chart.Builder.Workspace, only: [schedule: 1]
    import Visualize.Chart.Builder.Writes, only: [derived_scales: 1, update_layer: 4]

    alias Visualize.Chart.{Builder, Schema, Use}
    alias Visualize.Chart.Builder.{Editor, Sources, Stack}
    alias Visualize.Signals

    # The events this module handles: `Visualize.Chart.Builder.handle_event/3` routes
    # each here.
    @events ~w(
      add_source remove_source rename_source add_column rename_column remove_column
      set_column_type set_generator set_default_source edit_signal play pause tick_ms
    )

    @doc false
    def events, do: @events

    # -- the data page (spec/14 §19.10, #372) ---------------------------------------------

    # A source is two columns and a sine while designing, under one name, in the selected
    # layer; adding one opens the page.
    @doc false
    def handle_event("add_source", _params, socket) do
      %{design: design} = editing(socket.assigns)
      declared = design |> Map.get(:sources, %{}) |> Map.keys()
      taken = Enum.uniq(declared ++ Map.keys(socket.assigns.signals))

      name =
        1
        |> Stream.iterate(&(&1 + 1))
        |> Stream.map(&:"source_#{&1}")
        |> Enum.find(&(&1 not in taken))

      signal = Signals.new(:sine, [:t, :value])

      socket =
        socket
        |> update(:signals, &Map.put(&1, name, signal))
        |> assign(:notice, nil)
        |> declared_source(name, signal)

      Builder.handle_event("select_root", %{"root" => "sources"}, socket)
    end

    def handle_event("remove_source", %{"source" => name}, socket) do
      atom = String.to_atom(name)

      {:noreply,
       socket
       |> update(:signals, &Map.delete(&1, atom))
       |> update_layer([:sources], atom, :error)}
    end

    # A rename rewrites every reference across the chart's inline layers and moves the
    # signal; a name another source holds, or a source a library layer binds, is refused.
    def handle_event("rename_source", %{"source" => old, "name" => new}, socket) do
      new = String.trim(new)
      %{design: design} = editing(socket.assigns)
      sources = Map.get(design, :sources, %{})

      cond do
        new == "" or new == old ->
          {:noreply, socket}

        not Regex.match?(~r/^[a-z_][a-zA-Z0-9_]*$/, new) ->
          {:noreply, assign(socket, :notice, "#{new} is not a name a source can have")}

        Map.has_key?(sources, String.to_atom(new)) ->
          {:noreply, assign(socket, :notice, "a source is already named #{new}")}

        locked = binds_in_locked(socket.assigns, String.to_atom(old)) ->
          {:noreply, assign(socket, :notice, "#{old} is bound by #{locked} — from the library")}

        true ->
          {:noreply, renamed_source(socket, String.to_atom(old), String.to_atom(new))}
      end
    end

    def handle_event("add_column", %{"source" => name, "name" => column}, socket) do
      column = String.trim(column)

      if Regex.match?(~r/^[a-z_][a-zA-Z0-9_]*$/, column),
        do:
          {:noreply,
           columns_written(socket, String.to_atom(name), &(&1 ++ [String.to_atom(column)]))},
        else: {:noreply, socket}
    end

    def handle_event("rename_column", %{"source" => name, "column" => old, "name" => new}, socket) do
      new = String.trim(new)
      {source, old} = {String.to_atom(name), String.to_atom(old)}

      if new != "" and Regex.match?(~r/^[a-z_][a-zA-Z0-9_]*$/, new) and new != to_string(old) do
        atom = String.to_atom(new)
        %{design: design} = editing(socket.assigns)
        types = get_in(design, [:sources, source, :types]) || %{}

        socket =
          socket
          |> columns_written(source, fn fields ->
            Enum.map(fields, &if(&1 == old, do: atom, else: &1))
          end)
          |> types_written(
            source,
            types
            |> Map.delete(old)
            |> then(&if(types[old], do: Map.put(&1, atom, types[old]), else: &1))
          )

        {:noreply, socket}
      else
        {:noreply, socket}
      end
    end

    def handle_event("remove_column", %{"source" => name, "column" => column}, socket) do
      {source, column} = {String.to_atom(name), String.to_atom(column)}
      %{design: design} = editing(socket.assigns)
      types = get_in(design, [:sources, source, :types]) || %{}

      {:noreply,
       socket
       |> columns_written(source, &List.delete(&1, column))
       |> types_written(source, Map.delete(types, column))}
    end

    def handle_event(
          "set_column_type",
          %{"source" => name, "column" => column, "type" => type},
          socket
        ) do
      {source, column} = {String.to_atom(name), String.to_atom(column)}
      %{design: design} = editing(socket.assigns)
      types = get_in(design, [:sources, source, :types]) || %{}

      types =
        case Enum.find(Schema.column_types(), &(to_string(&1) == type)) do
          nil -> Map.delete(types, column)
          t -> Map.put(types, column, t)
        end

      {:noreply, socket |> types_written(source, types) |> derived_scales()}
    end

    # The generator is the signal under the source's name over the source's columns; a kind
    # keeps the numbers the signal had, none removes it.
    def handle_event("set_generator", %{"source" => name, "kind" => kind}, socket) do
      source = String.to_atom(name)
      %{design: design} = editing(socket.assigns)
      fields = for f <- get_in(design, [:sources, source, :fields]) || [], is_atom(f), do: f

      case Enum.find(Signals.kinds(), &(to_string(&1) == kind)) do
        nil ->
          {:noreply, update(socket, :signals, &Map.delete(&1, source))}

        _kind when fields == [] ->
          {:noreply, assign(socket, :notice, "#{name} needs a column before it can be generated")}

        kind ->
          {:noreply,
           update(socket, :signals, fn signals ->
             had = Map.get(signals, source) || %{}

             Map.put(
               signals,
               source,
               Signals.new(kind, fields, Map.take(had, [:window, :period, :min, :max, :seed]))
             )
           end)}
      end
    end

    # The pool entry that fills the source when the host binds none under its own name
    # (§2.3): a name typed, the pool's offered.
    def handle_event("set_default_source", %{"source" => name, "default" => default}, socket) do
      parsed =
        case String.trim(default) do
          "" -> :error
          typed -> Editor.parse(:name, typed)
        end

      {:noreply, update_layer(socket, [:sources, String.to_atom(name)], :default, parsed)}
    end

    def handle_event("edit_signal", %{"_target" => [target]} = params, socket) do
      case String.split(target, ".", parts: 2) do
        [name, key] ->
          atom = String.to_atom(name)

          {:noreply,
           update(socket, :signals, fn signals ->
             case Map.fetch(signals, atom) do
               {:ok, signal} ->
                 Map.put(signals, atom, Sources.edit(signal, key, params[target] || ""))

               :error ->
                 signals
             end
           end)}

        _other ->
          {:noreply, socket}
      end
    end

    def handle_event("play", _params, socket) do
      {:noreply, socket |> assign(:playing, true) |> schedule()}
    end

    def handle_event("pause", _params, socket) do
      {:noreply, assign(socket, :playing, false)}
    end

    def handle_event("tick_ms", %{"ms" => ms}, socket) do
      case Integer.parse(to_string(ms)) do
        {n, _} when n >= 50 -> {:noreply, assign(socket, :tick_ms, n)}
        _other -> {:noreply, socket}
      end
    end

    # The source's `fields` and, with it, its signal's, so the two never drift (#372).
    # A variable among the fields (§19.9) stays where it is; the signal reads the names.
    defp columns_written(socket, source, fun) do
      %{design: design} = editing(socket.assigns)
      fields = List.wrap(get_in(design, [:sources, source, :fields]) || [])
      fields = fields |> fun.() |> Enum.uniq()
      names = Enum.filter(fields, &is_atom/1)

      socket
      |> update_layer(
        [:sources, source],
        :fields,
        if(fields == [], do: :error, else: {:ok, fields})
      )
      |> update(:signals, fn signals ->
        case Map.get(signals, source) do
          nil -> signals
          _signal when names == [] -> Map.delete(signals, source)
          signal -> Map.put(signals, source, %{signal | fields: names})
        end
      end)
    end

    defp types_written(socket, source, types) do
      update_layer(
        socket,
        [:sources, source],
        :types,
        if(types == %{}, do: :error, else: {:ok, types})
      )
    end

    # Every reference to a source across the chart's inline layers, and its signal, renamed.
    defp renamed_source(socket, old, new) do
      %{uses: uses, signals: signals} = socket.assigns

      uses =
        Enum.map(uses, fn
          %Use{ref: nil, local: local, key: key} = use ->
            %{
              use
              | local: rename_source_in(local, old, new),
                key: if(key == old and Map.has_key?(local, :source), do: new, else: key)
            }

          use ->
            use
        end)

      signals =
        case Map.pop(signals, old) do
          {nil, signals} -> signals
          {signal, signals} -> Map.put(signals, new, signal)
        end

      assign(socket, uses: uses, signals: signals, notice: nil)
    end

    # A source's name wherever a fragment says it: the `sources` key, a mark's `data` (an
    # atom or a data node's `source`), a layout's `nodes`, another source's `default`.
    defp rename_source_in(%_{} = struct, _old, _new), do: struct

    defp rename_source_in(%{} = map, old, new) do
      map
      |> Map.new(fn
        {:sources, %{} = sources} ->
          {:sources,
           sources
           |> Map.new(fn {k, v} ->
             {if(k == old, do: new, else: k), rename_source_in(v, old, new)}
           end)}

        {key, ^old} when key in [:data, :source, :nodes, :default] ->
          {key, new}

        {key, value} ->
          {key, rename_source_in(value, old, new)}
      end)
    end

    defp rename_source_in(list, old, new) when is_list(list),
      do: Enum.map(list, &rename_source_in(&1, old, new))

    defp rename_source_in(other, _old, _new), do: other

    # The library layer, if any, whose fragment binds the source: nothing there is renamed.
    defp binds_in_locked(%{uses: uses, labels: labels, store: store}, source) do
      fetch = Stack.fetch(store)

      Enum.find_value(uses, fn use ->
        if Stack.locked?(use) do
          case fetch.(use.ref) do
            {:ok, fragment} -> if mentions_source?(fragment, source), do: Stack.label(labels, use)
            :error -> nil
          end
        end
      end)
    end

    defp mentions_source?(%_{} = _struct, _source), do: false

    defp mentions_source?(%{} = map, source) do
      Enum.any?(map, fn
        {key, ^source} when key in [:data, :source, :nodes] -> true
        {_key, value} -> mentions_source?(value, source)
      end)
    end

    defp mentions_source?(list, source) when is_list(list),
      do: Enum.any?(list, &mentions_source?(&1, source))

    defp mentions_source?(_other, _source), do: false

    # A signal's fields are all numbers — its time is its tick, an integer (spec/08 §8.2,
    # spec/14 §2.3, #369) — so a scale derived from them is linear, never a time scale
    # that the tick cannot take.
    defp declared_source(socket, name, %{fields: fields}) do
      %{design: design} = editing(socket.assigns)

      if Map.has_key?(Map.get(design, :sources, %{}), name) do
        socket
      else
        types = Map.new(fields, &{&1, :number})
        update_layer(socket, [:sources], name, {:ok, %{fields: fields, types: types}})
      end
    end
  end
end
