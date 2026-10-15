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
    alias Visualize.Chart.Builder.{Boards, Stack, Store}
    alias Visualize.Data.{Delivery, Schema, Table}

    # The events this module handles: `Visualize.Chart.Builder.handle_event/3` routes
    # each here.
    @events ~w(
      board_select board_place board_add board_remove board_cell board_cell_var board_edit
      board_var board_view board_edit_component board_return board_bind
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
          rect = Map.new(~w(x y w h)a, &{&1, integer(Map.get(params, Atom.to_string(&1)))})

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

    defp board_mode(%{board: %Board{} = board} = assigns, :board) do
      fetch = Stack.fetch(assigns.store)
      entries = if assigns.store, do: Store.list(assigns.store), else: []
      names = Map.new(entries, &{&1.id, &1.name})

      faults =
        case Board.validate(board, fetch) do
          :ok -> []
          {:error, errors} -> errors
        end

      binding = assigns.binding || Binding.new()
      required = required(assigns)
      sources = feed_sources(assigns)
      bind_faults = binding_faults(assigns, binding, required, sources)
      faults = faults ++ bind_faults
      faulty = MapSet.new(for {[:cells, cell | _], _reason} <- faults, do: cell)
      pools = Binding.pools(binding, sources)

      previews =
        Boards.preview(board, fetch,
          pools: pools,
          theme: assigns.theme,
          describe: describe(assigns, binding),
          refused: refused(bind_faults)
        )

      layout = Board.layout(board)

      view = fn name, rect ->
        cell = Map.fetch!(board.cells, name)

        Map.merge(rect, %{
          name: Atom.to_string(name),
          title: Map.get(cell, :title) || Atom.to_string(name),
          component: Map.get(names, cell.ref, Store.encode_id(cell.ref)),
          preview: Map.fetch!(previews, name),
          selected?: name == assigns.board_cell,
          faulty?: MapSet.member?(faulty, name)
        })
      end

      %{
        board: board,
        layout: layout,
        view: assigns.board_view,
        cells:
          for({name, rect} <- Board.arrange(board, layout.breakpoint), do: view.(name, rect)),
        stacked:
          for({name, rect} <- Board.arrange(board, layout.breakpoint - 1), do: view.(name, rect)),
        selected:
          selected(board, assigns.board_cell, fetch, names)
          |> with_slots(assigns.board_cell, binding, required, bind_faults),
        catalog?: is_map(assigns[:catalog]),
        feeds: for(feed <- feeds(assigns), do: {Boards.feed_key(feed), Boards.feed_key(feed)}),
        components: for(%{kind: :composite} = e <- entries, do: {e.name, Store.encode_id(e.id)}),
        vars: board_vars(board, fetch),
        window: window(board.window),
        faults: Enum.map(faults, &Board.format_error/1)
      }
    end

    defp board_mode(_assigns, _kind), do: nil

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
            name: Atom.to_string(slot),
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

    defp selected(_board, nil, _fetch, _names), do: nil

    defp selected(board, name, fetch, names) do
      case Map.fetch(board.cells, name) do
        {:ok, cell} ->
          vars = Map.get(cell, :vars, %{})

          %{
            name: Atom.to_string(name),
            title: Map.get(cell, :title),
            ref: Store.encode_id(cell.ref),
            listed?: Map.has_key?(names, cell.ref),
            sync: Map.get(cell, :sync, true),
            vars:
              for(
                var <- Boards.declared(cell.ref, fetch),
                do: {Atom.to_string(var), shown(Map.get(vars, var))}
              )
          }

        :error ->
          nil
      end
    end

    # Every variable a cell's component declares, and every one the board holds that none
    # does, so it can be emptied (§22.4).
    defp board_vars(board, fetch) do
      declared = board_var_names(board, fetch) -- Map.keys(board.vars)
      held = Map.keys(board.vars)
      by_cells = declared_by_cells(board, fetch)

      (declared ++ held)
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.map(fn name ->
        %{
          name: Atom.to_string(name),
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
          feed = Enum.find(feeds, &(Boards.feed_key(&1) == Atom.to_string(slot))),
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

      Enum.reduce(cells, %{}, fn {name, cell}, acc ->
        case Board.required_sources(%{board | cells: %{name => cell}}, fetch) do
          {:ok, required} -> Map.merge(acc, required)
          {:error, _errors} -> acc
        end
      end)
    end

    defp required(_assigns), do: %{}

    # The rows each bindable feed previews over (§22.6): the host's `sources` of its name,
    # else rows made from a catalog feed's schema.
    defp feed_sources(%{catalog: catalog} = assigns) when is_map(catalog) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      sources = assigns.sources || %{}

      Map.new(catalog, fn {feed, schema} ->
        rows = Map.get_lazy(sources, feed, fn -> Boards.sample(schema, now) end)
        {feed, Delivery.new(rows, schema: Schema.version(schema))}
      end)
    end

    defp feed_sources(assigns), do: pool(assigns)

    # A slot's schema for the preview: its bound feed's in the catalog (§22.6).
    defp describe(%{catalog: catalog}, binding) when is_map(catalog) do
      fn {cell, slot} ->
        with {:ok, feed} <- Binding.fetch(binding, cell, slot),
             {:ok, schema} <- Map.fetch(catalog, feed) do
          {:ok, schema}
        else
          :error -> {:error, :undescribed}
        end
      end
    end

    defp describe(_assigns, _binding), do: nil

    # The binding check (§22.8): every fault, but a stale binding of a cell whose component
    # did not resolve, which the board's own faults already name; and, since the preview
    # draws rows, the binding checked against what each feed's preview rows show (D-153).
    defp binding_faults(assigns, binding, required, sources) do
      schemas = if is_map(assigns[:catalog]), do: assigns.catalog, else: %{}
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

      (checked ++ row_types(sources, binding, required))
      |> Enum.uniq()
      |> Enum.sort_by(&elem(&1, 0))
    end

    defp row_types(sources, binding, required) do
      types =
        Map.new(sources, fn {feed, source} ->
          {feed, Table.column_types(rows(source))}
        end)

      case Binding.check_types(binding, required, types) do
        :ok -> []
        {:error, errors} -> errors
      end
    end

    defp rows(%Delivery{} = delivery), do: Delivery.source(delivery)
    defp rows(source), do: source

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
