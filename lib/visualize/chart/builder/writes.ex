if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Writes do
    @moduledoc false
    # The write path (spec/14 §18.15, §19.3). Every write of `Use.local` goes to the layer the
    # ownership rule names — the one that gives the key's value, else the node's owner, else
    # the selected layer — and a referenced site refuses it with the locked notice. With it,
    # the provenance it reads (`owned/3`), the composed design, the pool a chart binds while
    # designed, and a library entry linked into the stack.
    #
    # Split from `Visualize.Chart.Builder` by area (#568); compiled only with
    # `Phoenix.Component`, as the builder is (spec/10 §1.1, D-45, D-85).

    import Phoenix.Component, only: [assign: 2, assign: 3]

    # A frame's placement keys: where a chart shows the frame (#616).
    @placement [:box, :cell, :span, :z]

    alias Visualize.{Chart, Signals}
    alias Visualize.Chart.Builder.{Scales, Stack}
    alias Visualize.Chart.{Fragment, Use}

    # A composer opened on a kind takes only that kind; the workspace, a composite and a
    # design take anything (spec/14 §19.6).
    @doc false
    # A board is shown, never composed (spec/14 §22.1): no stack takes one.
    def admits(_open, %{kind: :board} = entry),
      do: {:refused, "#{entry.name} is a board; a board is opened, never composed into a chart"}

    def admits(nil, _entry), do: :ok
    def admits(%{kind: :composite}, _entry), do: :ok
    def admits(%{kind: kind}, %{kind: kind}), do: :ok

    def admits(%{kind: kind}, entry),
      do: {:refused, "a #{kind} composer takes a #{kind}; #{entry.name} is a #{entry.kind}"}

    @doc false
    def at(container, []), do: container

    def at(list, [index | rest]) when is_list(list) and is_integer(index),
      do: at(Enum.at(list, index), rest)

    def at(map, [key | rest]) when is_map(map), do: at(Map.get(map, key), rest)
    def at(_other, _path), do: nil

    # Which layer gave every value of the design and which owns every node (spec/14
    # §18.15): the provenance of the placed layers (§17.1), and for a node the highest
    # enabled layer with a value under its path — the one whose word the cascade keeps.
    @doc false
    def owned(%{uses: uses}, fetch, nodes) do
      placed = Stack.placed(uses, fetch)
      leaves = Chart.explain(placed)
      by_leaf = Map.new(leaves, &{&1.path, &1.layer})

      Enum.reduce(nodes, by_leaf, fn %{path: path}, acc ->
        case owner_of(leaves, placed, uses, path) do
          nil -> acc
          id -> Map.put(acc, path, id)
        end
      end)
    end

    # The provenance is of values, so a node with none yet — a site just keyed, a `%{}` —
    # is owned by the highest layer that carries it; a path through a list is a value's.
    @doc false
    def owner_of(_leaves, _placed, _uses, []), do: nil

    def owner_of(leaves, placed, uses, path) do
      # The tree's flat order (#380): an object inside a group stands where its row does.
      order = uses |> Stack.all() |> Map.new(&{&1.use.id, &1.index})

      carried =
        if Enum.all?(path, &is_atom/1),
          do: for({id, fragment} <- placed, at(fragment, path) != nil, do: id),
          else: []

      leaves
      |> Enum.filter(&List.starts_with?(&1.path, path))
      |> Enum.map(& &1.layer)
      |> Kernel.++(carried)
      |> Enum.max_by(&Map.get(order, &1, -1), fn -> nil end)
    end

    # An item appended to a list key in the layer the ownership rule names (§18.15).
    @doc false
    def appended(socket, path, key, item) do
      %{uses: uses, selected: selected, store: store} = socket.assigns
      fetch = Stack.fetch(store)

      case owner_for(uses, fetch, path, key) || Stack.get(uses, selected) do
        nil ->
          socket

        %Use{ref: ref} = use when ref != nil ->
          assign(socket, :notice, locked_notice(socket.assigns, use))

        use ->
          local = Stack.local_path(use, fetch, path)
          own = List.wrap(get_in(use.local, local ++ [key]) || [])

          assign(
            socket,
            :uses,
            Stack.update(uses, use.id, &Stack.write(&1, local, key, {:ok, own ++ [item]}))
          )
      end
    end

    # The scales the bound channels need and the frame lacks, declared through the
    # ownership rule (spec/14 §18.16, #370): after any binding — an edit, a placed mark.
    @doc false
    def derived_scales(socket) do
      design = composed(socket)
      types = Scales.pool_types(pool(socket.assigns))

      # Each frame's from the marks drawn in it, into that frame (#615).
      for frame <- frame_names(design),
          {name, node} <- Scales.derive(design, types, frame),
          reduce: socket do
        acc -> update_layer(acc, [:frames, frame, :scales], name, {:ok, node})
      end
    end

    # The frames a design declares, else the one a design with none is given.
    defp frame_names(design) do
      case Map.get(design, :frames) do
        frames when is_map(frames) and map_size(frames) > 0 -> Map.keys(frames)
        _none -> [Fragment.frame_name(design)]
      end
    end

    # A write goes to the use that owns what it writes — the one surface that writes
    # `Use.local` (spec/14 §19.3): the layer that gives the key's value, else the node's
    # owner, else the selected layer, which is where anything new is made (§18.15). A
    # declaration under a root — a source, a style, a def — is new unless a layer has it.
    @doc false
    def update_layer(socket, path, key, parsed) do
      %{uses: uses, selected: selected, store: store} = socket.assigns
      fetch = Stack.fetch(store)

      case owner_for(uses, fetch, path, key) || Stack.get(uses, selected) do
        nil ->
          socket

        # Where a chart shows a frame is the chart's, not the library's (#616, D-165): a
        # frame's placement is written into the site's own local even when the site is
        # linked, and the row reads *with local changes*.
        %Use{ref: ref} = use
        when ref != nil and key in @placement and length(path) == 2 and
               hd(path) == :frames ->
          local = Stack.local_path(use, fetch, path)
          assign(socket, :uses, Stack.update(uses, use.id, &Stack.write(&1, local, key, parsed)))

        # A referenced site is the library's word: nothing is written here (§18.15).
        %Use{ref: ref} = use when ref != nil ->
          assign(socket, :notice, locked_notice(socket.assigns, use))

        use ->
          local = Stack.local_path(use, fetch, path)
          assign(socket, :uses, Stack.update(uses, use.id, &Stack.write(&1, local, key, parsed)))
      end
    end

    # Every write an edit at a node means — `{key, parsed}`, a style's parts among them
    # (spec/14 §18.7) — each through the ownership rule, in order.
    @doc false
    def update_node(socket, path, writes) do
      Enum.reduce(writes, socket, fn {key, parsed}, acc ->
        update_layer(acc, path, key, parsed)
      end)
    end

    # The composed design, or `%{}` where the stack does not compose.
    @doc false
    def composed(socket) do
      %{uses: uses, store: store, stack_vars: vars} = socket.assigns

      case Stack.design(uses, vars, Stack.fetch(store)) do
        {:ok, design, _keyless} -> design
        {:error, _cycle} -> %{}
      end
    end

    @doc false
    def locked_notice(%{labels: labels}, use),
      do: "#{Stack.label(labels, use)} is from the library — open it to edit"

    @declaring [[:sources], [:styles], [:defs], [:vars]]

    # The owner of the key's value, else of the node, else of the nearest ancestor that a
    # layer gives — a scale derived under `frame.scales` goes to the frame's owner, not to
    # the selected mark site (#370) — and a declaration under a root is new (§18.15).
    defp owner_for(uses, fetch, path, key) do
      placed = Stack.placed(uses, fetch)
      leaves = Chart.explain(placed)

      candidates =
        if path in @declaring,
          do: [path ++ [key]],
          else: [path ++ [key], path | ancestors(path)]

      Enum.find_value(candidates, fn at ->
        case owner_of(leaves, placed, uses, at) do
          nil -> nil
          id -> Stack.get(uses, id)
        end
      end)
    end

    # The proper prefixes of a path, nearest first: `[:frames, :main, :scales]` →
    # `[[:frames, :main], [:frames]]`.
    defp ancestors(path) do
      for n <- (length(path) - 1)..1//-1, do: Enum.take(path, n)
    end

    # A use put where a drop target says; a target inside a referenced group is refused.
    defp dropped(uses, {:into, %Use{ref: nil, id: id}}, use),
      do: Stack.insert(uses, {:into, id}, use)

    defp dropped(uses, {:into, _locked_or_missing}, _use), do: uses
    defp dropped(uses, {:at, at}, use), do: Stack.insert_at(uses, at, use)
    defp dropped(uses, {:after, id}, use), do: Stack.insert(uses, id, use)

    # A link: the reference site of §19.3, for a layer that is to follow the library.
    # A drop into a referenced group is refused as any write into it is: its inside is
    # the library's (§18.8, #388).
    @doc false
    def linked(socket, _entry, {:into, %Use{ref: ref} = locked}) when ref != nil,
      do: assign(socket, :notice, locked_notice(socket.assigns, locked))

    def linked(socket, entry, at) do
      %{uses: uses, labels: labels} = socket.assigns
      use = Use.new(entry.id, uses)
      uses = dropped(uses, at, use)

      if Stack.get(uses, use.id) do
        assign(socket,
          uses: uses,
          labels: Map.put(labels, use.id, entry.name),
          selected: socket.assigns.selected || use.id,
          added: entry.id,
          notice: nil
        )
      else
        assign(socket, :notice, "#{entry.name} cannot go into a layer from the library")
      end
    end

    # The pool a chart binds while designed (spec/14 §19.10): the host's under the chart's
    # signals at the tick.
    @doc false
    def pool(%{sources: sources} = assigns) do
      Map.merge(
        sources,
        Signals.pool(Map.get(assigns, :signals, %{}), Map.get(assigns, :tick, 0))
      )
    end
  end
end
