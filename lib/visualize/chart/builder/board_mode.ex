if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.BoardMode do
    @moduledoc false
    # The board mode (spec/14 §22, D-152), one of `Visualize.Chart.Builder.Modes`: its events
    # — a cell selected, placed, added, removed and written, the board written, the view,
    # Edit component and Back to board — and its render assigns. The pure writes and the
    # panel are `Visualize.Chart.Builder.Boards`; the grid is
    # `Visualize.Chart.Builder.BoardGrid`.
    #
    # A board chart holds its `%Visualize.Board{}` in the `board` assign and its selected
    # cell in `board_cell`, parked with the chart as its stack would be (§22.2). Every write
    # goes through `written/2`, which keeps the board only when it validates alone, so the
    # mode never holds a board that would not read.
    #
    # Compiled only with `Phoenix.Component`, as the builder is (spec/10 §1.1, D-45, D-85).

    import Phoenix.Component, only: [assign: 2, assign: 3]

    import Visualize.Chart.Builder.Workspace,
      only: [load: 2, opened_entry: 2, park: 1, structure: 1]

    import Visualize.Chart.Builder.Writes, only: [pool: 1]

    alias Visualize.Board
    alias Visualize.Board.Binding
    alias Visualize.Chart
    alias Visualize.Chart.Builder.{BoardKept, Boards, BoardSources, Stack, Store, Typed}

    # The events this module handles: `Visualize.Chart.Builder.handle_event/3` routes
    # each here.
    @events ~w(
      board_select board_place board_add board_remove board_cell board_cell_var board_edit
      board_var board_view board_edit_component board_return board_bind board_source
    )

    @doc false
    def events, do: @events

    # -- the cells (§22.3) -------------------------------------------------------------------

    @doc false
    def handle_event("board_select", %{"cell" => text}, socket) do
      case cell_named(socket, text) do
        nil -> {:noreply, socket}
        cell -> {:noreply, assign(socket, :board_cell, cell)}
      end
    end

    # The hook's rectangle (spec/10 §16.3): placed by the server or refused, never trusted.
    def handle_event("board_place", %{"cell" => text} = params, socket) do
      case cell_named(socket, text) do
        nil ->
          {:noreply, socket}

        cell ->
          rect = Map.new(~w(x y w h)a, &{&1, integer(Map.get(params, to_string(&1)))})

          {:noreply,
           socket
           |> assign(:board_cell, cell)
           |> written(&Boards.place(&1, cell, rect))}
      end
    end

    def handle_event("board_add", %{"ref" => submitted}, socket) do
      case Store.decode_id(submitted) do
        {:ok, ref} ->
          case Boards.added(socket.assigns.board, ref) do
            {:ok, board, cell} ->
              socket = assign(socket, board: board, board_cell: cell, notice: nil)
              {:noreply, bound(socket, by_name(socket.assigns, socket.assigns.binding, [cell]))}

            {:error, errors} ->
              {:noreply, refused(socket, errors)}
          end

        :error ->
          {:noreply, assign(socket, :notice, "#{submitted} is not a component of the library")}
      end
    end

    def handle_event("board_add", _params, socket) do
      {:noreply, assign(socket, :notice, "the library holds no composite to show")}
    end

    def handle_event("board_remove", %{"cell" => text}, socket) do
      case cell_named(socket, text) do
        nil ->
          {:noreply, socket}

        cell ->
          board = Boards.removed(socket.assigns.board, cell)
          next = board.cells |> Map.keys() |> Enum.min(fn -> nil end)
          binding = socket.assigns.binding || Binding.new()
          kept = for {{c, _slot}, _feed} = pair <- binding.slots, c != cell, into: %{}, do: pair

          {:noreply,
           socket
           |> assign(board: board, board_cell: next, notice: nil)
           |> bound(%{binding | slots: kept})}
      end
    end

    # -- the binding (§22.8) -------------------------------------------------------------------

    # A slot of the selected cell bound to a bindable feed, or unbound; a feed from the page
    # is one of the bindable feeds by its printed form, never a term of its own.
    def handle_event("board_bind", %{"_target" => ["slot." <> text = field]} = params, socket) do
      %{board_cell: cell} = socket.assigns
      slots = for {{^cell, slot}, _need} <- required(socket.assigns), do: slot

      case {cell, Boards.named(slots, text)} do
        {nil, _} ->
          {:noreply, socket}

        {_cell, nil} ->
          {:noreply, socket}

        {cell, slot} ->
          binding = socket.assigns.binding || Binding.new()

          binding =
            case Map.get(params, field, "") do
              "" ->
                %{binding | slots: Map.delete(binding.slots, {cell, slot})}

              key ->
                case Enum.find(feeds(socket.assigns), &(Boards.feed_key(&1) == key)) do
                  nil -> binding
                  feed -> Binding.put(binding, cell, slot, feed)
                end
            end

          {:noreply, bound(socket, binding)}
      end
    end

    def handle_event("board_bind", _params, socket), do: {:noreply, socket}

    # A virtual source's function written as text (§22.9): written and run when it holds,
    # else kept as a draft beside its faults, the board keeping the last that held.
    def handle_event("board_source", %{"source" => path, "elixir" => text}, socket) do
      %{board: board} = socket.assigns
      drafts = socket.assigns[:board_drafts] || %{}

      case BoardSources.write(board, path, text, source_schemas(socket.assigns, board)) do
        {:ok, edited} ->
          socket = written(socket, fn _board -> {:ok, edited} end)
          {:noreply, assign(socket, :board_drafts, Map.delete(drafts, path))}

        {:error, lines} ->
          draft = %{text: text, faults: lines}
          {:noreply, assign(socket, :board_drafts, Map.put(drafts, path, draft))}
      end
    end

    def handle_event("board_source", _params, socket), do: {:noreply, socket}

    # -- the forms (§22.4) ---------------------------------------------------------------------

    def handle_event("board_cell", %{"_target" => [field]} = params, socket) do
      value = Map.get(params, field, "")

      case socket.assigns.board_cell do
        nil ->
          {:noreply, socket}

        cell ->
          {:noreply,
           written(socket, fn board ->
             with {:ok, written} <-
                    Boards.cell_changed(Map.fetch!(board.cells, cell), field, value),
                  do: {:ok, %{board | cells: Map.put(board.cells, cell, written)}}
           end)}
      end
    end

    def handle_event("board_cell_var", %{"_target" => ["var." <> text = field]} = params, socket) do
      %{board: board, board_cell: cell} = socket.assigns

      with cell when cell != nil <- cell,
           ref = Map.fetch!(board.cells, cell).ref,
           name when name != nil <- Boards.named(Boards.declared(ref, fetch(socket)), text) do
        value = Map.get(params, field, "")

        {:noreply,
         written(socket, fn board ->
           cells =
             Map.update!(board.cells, cell, fn c ->
               vars = c |> Map.get(:vars, %{}) |> Boards.var_written(name, value)
               if vars == %{}, do: Map.delete(c, :vars), else: Map.put(c, :vars, vars)
             end)

           {:ok, %{board | cells: cells}}
         end)}
      else
        nil -> {:noreply, socket}
      end
    end

    def handle_event("board_cell_var", _params, socket), do: {:noreply, socket}
    def handle_event("board_cell", _params, socket), do: {:noreply, socket}

    def handle_event("board_edit", %{"_target" => [field]} = params, socket) do
      value = Map.get(params, field, "")
      {:noreply, written(socket, &Boards.changed(&1, field, value))}
    end

    def handle_event("board_edit", _params, socket), do: {:noreply, socket}

    def handle_event("board_var", %{"_target" => ["var." <> text = field]} = params, socket) do
      %{board: board} = socket.assigns

      case Boards.named(board_var_names(board, fetch(socket)), text) do
        nil ->
          {:noreply, socket}

        name ->
          value = Map.get(params, field, "")

          {:noreply,
           written(socket, &{:ok, %{&1 | vars: Boards.var_written(&1.vars, name, value)}})}
      end
    end

    def handle_event("board_var", _params, socket), do: {:noreply, socket}

    # The placement or the board below its breakpoint (§22.3): a view, never a write.
    def handle_event("board_view", %{"view" => "narrow"}, socket),
      do: {:noreply, assign(socket, :board_view, :narrow)}

    def handle_event("board_view", _params, socket),
      do: {:noreply, assign(socket, :board_view, :wide)}

    # -- Edit component and Back to board (§22.7) ----------------------------------------------

    def handle_event("board_edit_component", %{"cell" => text}, socket) do
      %{store: store, chart: board_chart} = socket.assigns

      with cell when cell != nil <- cell_named(socket, text),
           ref = Map.fetch!(socket.assigns.board.cells, cell).ref,
           {:ok, entry} <- if(store, do: Store.get(store, ref), else: :error) do
        socket = socket |> assign(:board_cell, cell) |> opened_entry(Map.put(entry, :id, ref))

        {:noreply,
         assign(socket, :return_to, %{
           chart: board_chart,
           cell: cell,
           opened: structure(socket.assigns)
         })}
      else
        nil ->
          {:noreply, socket}

        :error ->
          ref = Map.fetch!(socket.assigns.board.cells, cell_named(socket, text)).ref

          {:noreply,
           assign(socket, :notice, "the library no longer holds #{Store.encode_id(ref)}")}
      end
    end

    # The board's chart selected again; the component's chart closed when it holds no
    # unsaved change, and left open with a notice when it does (§22.7).
    def handle_event("board_return", _params, socket) do
      %{return_to: back, charts: charts, chart: here} = socket.assigns

      cond do
        back == nil ->
          {:noreply, socket}

        not Enum.any?(charts, &(&1.id == back.chart)) ->
          {:noreply, assign(socket, :notice, "the board this component came from is closed")}

        clean?(socket.assigns, back) ->
          {:noreply,
           socket
           |> park()
           |> assign(:charts, Enum.reject(charts, &(&1.id == here)))
           |> load(back.chart)
           |> assign(:notice, nil)}

        true ->
          name = socket.assigns.open && socket.assigns.open.name

          {:noreply,
           socket
           |> park()
           |> load(back.chart)
           |> assign(
             :notice,
             "#{name || "the component"} stays open in Charts: it has changes not saved to the library"
           )}
      end
    end

    # Unchanged since it was opened, or what the store now holds: nothing would be lost.
    defp clean?(%{open: open, store: store} = assigns, back) do
      current = structure(assigns)

      current == back.opened or
        (open != nil and open.id != nil and store != nil and
           match?({:ok, %{fragment: ^current}}, Store.get(store, open.id)))
    end

    # -- the render's assigns ------------------------------------------------------------------

    @doc false
    # The render's assigns for the mode (`Visualize.Chart.Builder.Modes`): `board_mode`.
    def assigns(assigns, kind, _errors), do: %{board_mode: board_mode(assigns, kind)}

    @doc false
    # The socket with what a pass over it draws and checks kept as `board_kept` (spec/14
    # §22.6, #723, D-191), for the render and the next event to read; `nil` off the mode.
    # `Visualize.Chart.Builder` calls it after every event and every `update/2`.
    def keep(socket) do
      case kept(socket.assigns) do
        nil -> if socket.assigns[:board_kept], do: assign(socket, :board_kept, nil), else: socket
        {kept, _computed} -> assign(socket, :board_kept, kept)
      end
    end

    @doc false
    # What a pass over the assigns keeps, and what it had to compute for it: `{kept,
    # %{facts: computed?, required: cells read, previews: cells drawn}}`, or `nil` off the
    # mode.
    def kept(assigns) do
      case board_kept(assigns) do
        nil -> nil
        {_mode, kept, computed} -> {kept, computed}
      end
    end

    defp board_mode(assigns, kind) do
      case kind == :board && board_kept(assigns) do
        {mode, _kept, _computed} -> mode
        _off -> nil
      end
    end

    defp board_kept(%{board: %Board{} = board, open: %{kind: :board}} = assigns),
      do: pass(assigns, board)

    defp board_kept(_assigns), do: nil

    defp pass(assigns, %Board{} = board) do
      fetch = Stack.fetch(assigns.store)
      entries = if assigns.store, do: Store.list(assigns.store), else: []
      names = Map.new(entries, &{&1.id, &1.name})
      kept = Map.get(assigns, :board_kept) || %{}

      # The facts are a function of the board and of what the store says of its
      # components, flattened (§22.5): kept while both are what they were.
      flat = flat(board, fetch)

      {facts, facts_entry, facts?} =
        BoardKept.facts(kept[:facts], {board, flat}, fn -> facts(board, fetch, flat) end)

      # A cell's slots are its component's, read alone (§22.8): kept by the cell and what
      # the store says of its component.
      {per_cell, required_entries, read} =
        BoardKept.each(
          kept[:required],
          Map.new(board.cells, fn {name, cell} -> {name, {cell, Map.get(flat, cell.ref)}} end),
          fn stale -> Map.new(stale, &{&1, required_of(board, &1, fetch)}) end
        )

      required = per_cell |> Map.values() |> Enum.reduce(%{}, &Map.merge(&2, &1))
      binding = assigns.binding || Binding.new()
      sources = feed_sources(assigns)

      # The board's virtual sources run over the preview's data (§22.9), kept by what they
      # are a function of.
      {virtual, virtual_entry, virtual?} =
        BoardKept.facts(
          kept[:virtual],
          {board.virtual_sources, cell_sources(board), binding, sources, assigns[:catalog],
           assigns[:virtual_sources]},
          fn ->
            BoardSources.run(
              board,
              binding,
              sources,
              assigns[:catalog],
              assigns[:virtual_sources] || []
            )
          end
        )

      bind_faults = binding_faults(assigns, binding, required, sources, virtual.feed_schemas)
      faults = facts.faults ++ bind_faults
      faulty = MapSet.new(for {[:cells, cell | _], _reason} <- faults, do: cell)
      pools = virtual.pools
      refused = refused(bind_faults)

      # Each preview is a function of these, and is drawn again only when one moved (§22.6).
      shared = %{board | cells: %{}}

      keys =
        Map.new(board.cells, fn {name, cell} ->
          {name,
           {cell, shared, Map.get(flat, cell.ref), Map.get(pools, name), assigns.theme,
            assigns[:catalog], for({{^name, _slot}, _feed} = pair <- binding.slots, do: pair),
            Map.get(refused, name)}}
        end)

      {previews, preview_entries, drawn} =
        BoardKept.each(kept[:previews], keys, fn stale ->
          Boards.preview(%{board | cells: Map.take(board.cells, stale)}, fetch,
            pools: pools,
            theme: assigns.theme,
            describe: describe(assigns, binding, virtual.slot_schemas),
            refused: refused
          )
        end)

      layout = Board.layout(board)

      view = fn name, rect ->
        cell = Map.fetch!(board.cells, name)

        Map.merge(rect, %{
          name: to_string(name),
          title: Map.get(cell, :title) || to_string(name),
          component: Map.get(names, cell.ref, Store.encode_id(cell.ref)),
          preview: Map.fetch!(previews, name),
          selected?: name == assigns.board_cell,
          faulty?: MapSet.member?(faulty, name)
        })
      end

      mode = %{
        board: board,
        layout: layout,
        view: assigns.board_view,
        cells:
          for({name, rect} <- Board.arrange(board, layout.breakpoint), do: view.(name, rect)),
        stacked:
          for({name, rect} <- Board.arrange(board, layout.breakpoint - 1), do: view.(name, rect)),
        selected:
          selected(board, assigns.board_cell, flat, names)
          |> with_slots(assigns.board_cell, binding, required, bind_faults),
        catalog?: is_map(assigns[:catalog]),
        feeds: for(feed <- feeds(assigns), do: {Boards.feed_key(feed), Boards.feed_key(feed)}),
        components: for(%{kind: :composite} = e <- entries, do: {e.name, Store.encode_id(e.id)}),
        vars: facts.vars,
        window: window(board.window),
        faults: Enum.map(faults, &Board.format_error/1),
        sources: Boards.sources(%{run: virtual, drafts: assigns[:board_drafts] || %{}}),
        source_errors: virtual.errors
      }

      {mode,
       %{
         facts: facts_entry,
         required: required_entries,
         previews: preview_entries,
         virtual: virtual_entry
       }, %{facts: facts?, required: read, previews: drawn, virtual: virtual?}}
    end

    # What a source's inputs may name, with their schemas: the catalog's feeds and the
    # board's sources by id.
    defp source_schemas(assigns, board) do
      own =
        for {path, source} <- Board.virtual_sources(board),
            into: %{},
            do: {List.last(path), source.schema}

      Map.merge(own, assigns[:catalog] || %{})
    end

    defp cell_sources(board),
      do: for({name, %{virtual_sources: s}} <- board.cells, into: %{}, do: {name, s})

    # Each component the board's cells name, flattened through the store (spec/14 §19.8):
    # what the store says of it, nested references and all, by ref.
    defp flat(board, fetch) do
      board.cells
      |> Map.values()
      |> Enum.map(& &1.ref)
      |> Enum.uniq()
      |> Map.new(fn ref ->
        {ref, with({:ok, fragment} <- fetch.(ref), do: Chart.flatten(fragment, fetch))}
      end)
    end

    # The board's faults given the store (§22.5) and the variables it shows (§22.4): one
    # reading of the board and its components.
    defp facts(board, fetch, flat) do
      faults =
        case Board.validate(board, fetch) do
          :ok -> []
          {:error, errors} -> errors
        end

      %{faults: faults, vars: board_vars(board, flat)}
    end

    # The variables a component declares, from its flattened design.
    defp declared(flat, ref) do
      case Map.get(flat, ref) do
        {:ok, design, _report} -> design |> Map.get(:vars, %{}) |> Map.keys() |> Enum.sort()
        _none -> []
      end
    end

    # The selected cell's slots, each with the feed it is bound to and its own faults (§22.8).
    defp with_slots(nil, _cell, _binding, _required, _faults), do: nil

    defp with_slots(selected, cell, binding, required, faults) do
      slots =
        for {{^cell, slot}, _need} <- Enum.sort(required) do
          feed =
            case Binding.fetch(binding, cell, slot) do
              {:ok, feed} -> Boards.feed_key(feed)
              :error -> nil
            end

          %{
            name: to_string(slot),
            feed: feed,
            faults: for(fault <- faults, slot?(fault, cell, slot), do: Board.format_error(fault))
          }
        end

      Map.put(selected, :slots, slots)
    end

    # A fault of a cell's slot: at the slot's path, or a type fault naming it (D-153).
    defp slot?({[:cells, cell, :sources, slot | _], _reason}, cell, slot), do: true
    defp slot?({[:cells, cell | _], {:type_mismatch, slot, _, _, _}}, cell, slot), do: true
    defp slot?(_fault, _cell, _slot), do: false

    defp selected(_board, nil, _flat, _names), do: nil

    defp selected(board, name, flat, names) do
      case Map.fetch(board.cells, name) do
        {:ok, cell} ->
          vars = Map.get(cell, :vars, %{})

          %{
            name: to_string(name),
            title: Map.get(cell, :title),
            ref: Store.encode_id(cell.ref),
            listed?: Map.has_key?(names, cell.ref),
            sync: Map.get(cell, :sync, true),
            vars:
              for(
                var <- declared(flat, cell.ref),
                do: {to_string(var), shown(Map.get(vars, var))}
              )
          }

        :error ->
          nil
      end
    end

    # Every variable a cell's component declares, and every one the board holds that none
    # does, so it can be emptied (§22.4).
    defp board_vars(board, flat) do
      by_cells =
        board.cells
        |> Map.values()
        |> Enum.flat_map(&declared(flat, &1.ref))
        |> Enum.uniq()

      held = Map.keys(board.vars)
      declared = Enum.uniq(by_cells ++ held) -- held

      (declared ++ held)
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.map(fn name ->
        %{
          name: to_string(name),
          value: shown(Map.get(board.vars, name)),
          declared?: name in by_cells
        }
      end)
    end

    defp board_var_names(board, fetch),
      do: Enum.uniq(declared_by_cells(board, fetch) ++ Map.keys(board.vars))

    defp declared_by_cells(board, fetch) do
      board.cells
      |> Map.values()
      |> Enum.map(& &1.ref)
      |> Enum.uniq()
      |> Enum.flat_map(&Boards.declared(&1, fetch))
      |> Enum.uniq()
    end

    defp window(nil), do: %{kind: "none", last: nil, from: "", to: ""}
    defp window(%{last: last}), do: %{kind: "last", last: last, from: "", to: ""}

    defp window(%{from: from, to: to}),
      do: %{kind: "fixed", last: nil, from: Boards.local(from), to: Boards.local(to)}

    defp shown(nil), do: ""
    defp shown(value) when is_binary(value), do: value
    defp shown(value), do: to_string(value)

    # -- the binding's parts (§22.8) -----------------------------------------------------------

    @doc false
    # The binding a board opens with: the host's for its id, else every slot bound by name.
    def started(assigns, %Board{} = board, id) do
      case Map.get(assigns[:board_bindings] || %{}, id) do
        %Binding{} = binding ->
          binding

        _none ->
          by_name(Map.put(assigns, :board, board), Binding.new(), Map.keys(board.cells))
      end
    end

    # Each unbound slot of the cells bound to the bindable feed of its own name, if any.
    defp by_name(assigns, binding, cells) do
      binding = binding || Binding.new()
      feeds = feeds(assigns)

      for {{cell, slot}, _need} <- required(assigns),
          cell in cells,
          Binding.fetch(binding, cell, slot) == :error,
          feed = Enum.find(feeds, &(Boards.feed_key(&1) == to_string(slot))),
          feed != nil,
          reduce: binding do
        binding -> Binding.put(binding, cell, slot, feed)
      end
    end

    # The binding kept on the chart and, when it changed, sent to the host (§22.8).
    defp bound(socket, binding) do
      if binding == socket.assigns.binding do
        socket
      else
        %{id: id, open: open} = socket.assigns
        tag = Map.get(socket.assigns, :on_bind, :visualize_board_bound)
        send(self(), {tag, id, open && open.id, binding})
        assign(socket, :binding, binding)
      end
    end

    # The bindable feeds: the catalog's, else the sample pool's names (§22.8).
    defp feeds(%{catalog: catalog}) when is_map(catalog),
      do: catalog |> Map.keys() |> Enum.sort_by(&Boards.feed_key/1)

    defp feeds(assigns), do: assigns |> pool() |> Map.keys() |> Enum.sort_by(&Boards.feed_key/1)

    # Every cell's slots, each cell read alone, so one that does not resolve leaves the
    # others' listed (§22.8).
    defp required(%{board: %Board{cells: cells} = board, store: store}) do
      fetch = Stack.fetch(store)

      Enum.reduce(cells, %{}, fn {name, _cell}, acc ->
        Map.merge(acc, required_of(board, name, fetch))
      end)
    end

    defp required(_assigns), do: %{}

    # One cell's slots, its component read alone; none when it does not resolve.
    defp required_of(%Board{cells: cells} = board, name, fetch) do
      case Board.required_sources(%{board | cells: Map.take(cells, [name])}, fetch) do
        {:ok, required} -> required
        {:error, _errors} -> %{}
      end
    end

    # The rows each bindable feed previews over (§22.6): the host's `sources` of its name,
    # else rows made from a catalog feed's schema.
    defp feed_sources(%{catalog: catalog} = assigns) when is_map(catalog),
      do: Typed.samples(assigns)

    defp feed_sources(assigns), do: pool(assigns)

    # A slot's schema for the preview: its bound feed's in the catalog (§22.6).
    # A slot read through the board's virtual sources is described with what they answer
    # and join (§22.9).
    defp describe(%{catalog: catalog}, binding, slot_schemas) when is_map(catalog) do
      fn {cell, slot} ->
        with :error <- Map.fetch(slot_schemas, {cell, slot}),
             {:ok, feed} <- Binding.fetch(binding, cell, slot),
             {:ok, schema} <- Map.fetch(catalog, feed) do
          {:ok, schema}
        else
          {:ok, schema} -> {:ok, schema}
          :error -> {:error, :undescribed}
        end
      end
    end

    defp describe(_assigns, _binding, _slot_schemas), do: nil

    # The binding check (§22.8): every fault, but a stale binding of a cell whose component
    # did not resolve, which the board's own faults already name; and, since the preview
    # draws rows, the binding checked against what each feed's preview rows show (D-153).
    defp binding_faults(assigns, binding, required, sources, feed_schemas) do
      schemas = if is_map(assigns[:catalog]), do: feed_schemas, else: %{}
      resolved = MapSet.new(for {{cell, _slot}, _need} <- required, do: cell)

      checked =
        case Binding.check(binding, required, schemas) do
          :ok ->
            []

          {:error, errors} ->
            Enum.reject(errors, fn {[:cells, cell | _], reason} ->
              reason == :not_required and cell in Map.keys(assigns.board.cells) and
                cell not in resolved
            end)
        end

      (checked ++ row_types(Typed.feeds(assigns), sources, binding, required))
      |> Enum.uniq()
      |> Enum.sort_by(&elem(&1, 0))
    end

    # Each feed's types as `update/2` read them from its preview rows (D-189), for the feeds
    # the preview binds.
    defp row_types(typed, sources, binding, required) do
      types = Map.take(typed, Map.keys(sources))

      case Binding.check_types(binding, required, types) do
        :ok -> []
        {:error, errors} -> errors
      end
    end

    # The cells a type fault keeps from being realized (§22.6, D-153), with their faults.
    defp refused(faults) do
      for {[:cells, cell | _], {:type_mismatch, _, _, _, _}} = fault <- faults, reduce: %{} do
        refused -> Map.update(refused, cell, [fault], &(&1 ++ [fault]))
      end
    end

    # -- writing ---------------------------------------------------------------------------------

    # One write of the board: kept when the board it makes validates alone, refused with the
    # board's own words when it does not, and nothing for a value that does not read (§22.2).
    defp written(socket, fun) do
      case fun.(socket.assigns.board) do
        {:ok, board} ->
          case Board.validate(board) do
            :ok -> assign(socket, board: board, notice: nil)
            {:error, errors} -> refused(socket, errors)
          end

        {:error, errors} ->
          refused(socket, errors)

        :error ->
          socket
      end
    end

    defp refused(socket, errors) do
      assign(socket, :notice, "refused: " <> Enum.map_join(errors, "; ", &Board.format_error/1))
    end

    # A cell's name from the page as one the board has, or `nil`: no atom is made of it.
    defp cell_named(%{assigns: %{board: %Board{cells: cells}}}, text),
      do: Boards.named(Map.keys(cells), text)

    defp cell_named(_socket, _text), do: nil

    defp fetch(socket), do: Stack.fetch(socket.assigns.store)

    defp integer(value) when is_integer(value), do: value

    defp integer(value) when is_binary(value) do
      case Integer.parse(value) do
        {n, ""} -> n
        _other -> value
      end
    end

    defp integer(value), do: value
  end
end
