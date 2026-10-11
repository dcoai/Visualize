if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Workspace do
    @moduledoc false
    # The workspace of charts (spec/14 §19.9) and the store as the builder reaches it. The
    # live assigns are the selected chart's, parked back to its row when another is selected;
    # an entry opened from the library opens as a new chart (§19.9); the signals' tick is
    # scheduled here (§18.2).
    #
    # Split from `Visualize.Chart.Builder` by area (#568); compiled only with
    # `Phoenix.Component`, as the builder is (spec/10 §1.1, D-45, D-85).

    import Phoenix.Component, only: [assign: 2, assign: 3, update: 3]

    alias Visualize.Chart.Builder.{Stack, Store}

    # A selection that names a use the seeded stack has is kept — a host may seed one, and
    # the person's place survives a replaced list of the same shape — else the first use.
    @doc false
    def selection(selected, uses) do
      case Stack.get(uses, selected) do
        nil -> uses |> List.first() |> then(&(&1 && &1.id))
        use -> use.id
      end
    end

    # The Charts panel's rows (spec/14 §18.8): every chart of the workspace, the selected
    # one's layers drawn by the stack panel, another's as names to select.
    @doc false
    def chart_rows(%{charts: charts, chart: selected} = assigns) do
      for chart <- charts do
        live? = chart.id == selected
        state = if live?, do: assigns, else: chart
        kind = state.open && state.open.kind != :composite && state.open.kind

        %{
          id: chart.id,
          name: chart.name,
          kind: kind,
          title: if(kind, do: "a #{kind} opened from the library", else: "a chart"),
          selected?: live?,
          expanded: chart.expanded,
          layers:
            if(live?,
              do: [],
              else:
                state.uses
                |> Enum.with_index()
                |> Enum.map(fn {use, i} -> {Stack.label(state.labels, use), i} end)
            )
        }
      end
    end

    # Opening an entry opens it as a new chart — a composite's sites, or the body as one
    # inline site — selected, the entry recorded on it so Save as writes the entry
    # (spec/14 §19.9).
    @doc false
    # A board entry opens as a board chart (spec/14 §22.2): the board read back by its own
    # reader, and an entry that does not read is not opened.
    def opened_entry(socket, %{kind: :board} = entry) do
      case Visualize.Board.from_map(Map.get(entry.fragment, :board)) do
        {:ok, board} ->
          socket
          |> opened(entry, [], %{}, %{}, %{})
          |> assign(
            board: board,
            binding: Visualize.Chart.Builder.BoardMode.started(socket.assigns, board, entry.id),
            board_cell: board.cells |> Map.keys() |> Enum.min(fn -> nil end)
          )
          |> added_chart(entry.name || "new board", "chart #{socket.assigns.next_chart}")

        {:error, errors} ->
          assign(
            socket,
            :notice,
            "#{entry.name || "the board"} does not open: " <>
              Enum.map_join(errors, "; ", &Visualize.Board.format_error/1)
          )
      end
    end

    def opened_entry(socket, entry) do
      {uses, labels, vars, signals} = Stack.open(entry, names(socket.assigns.store))
      n = socket.assigns.next_chart

      socket
      |> opened(entry, uses, labels, vars, signals)
      |> added_chart(entry.name || "new #{entry.kind}", "chart #{n}")
    end

    defp opened(socket, entry, uses, labels, vars, signals) do
      socket
      |> park()
      |> assign(
        open: %{id: entry.id, name: entry.name, kind: entry.kind},
        board: nil,
        board_cell: nil,
        binding: nil,
        return_to: nil,
        uses: uses,
        labels: labels,
        stack_vars: vars,
        signals: signals,
        selected: uses |> List.first() |> then(&(&1 && &1.id)),
        node_label: "design",
        facet: nil,
        style_entry: nil,
        field: nil,
        context: :inspect,
        added: nil,
        notice: nil
      )
    end

    # The live assigns are the selected chart's; parking writes them back to its row.
    # A board chart holds its board, its selected cell and the host's binding of it, and a component opened from a
    # board the chart it returns to (spec/14 §22.2, §22.7).
    @chart_state [
      :uses,
      :labels,
      :stack_vars,
      :selected,
      :open,
      :signals,
      :board,
      :board_cell,
      :binding,
      :return_to
    ]

    @doc false
    def park(%{assigns: %{chart: nil}} = socket), do: socket

    def park(%{assigns: assigns} = socket) do
      state = Map.take(assigns, @chart_state)

      update(socket, :charts, fn charts ->
        Enum.map(charts, &if(&1.id == assigns.chart, do: Map.merge(&1, state), else: &1))
      end)
    end

    @doc false
    def load(socket, id) do
      case Enum.find(socket.assigns.charts, &(&1.id == id)) do
        nil ->
          socket

        chart ->
          socket
          |> assign(Map.take(chart, @chart_state))
          |> assign(
            chart: id,
            selection: MapSet.new(),
            node_label: "design",
            facet: nil,
            style_entry: nil,
            field: nil
          )
          |> update(:charts, fn charts ->
            Enum.map(charts, &if(&1.id == id, do: %{&1 | expanded: true}, else: &1))
          end)
      end
    end

    # The live assigns become a new, selected, expanded chart of the workspace.
    @doc false
    def added_chart(socket, name, fallback \\ nil) do
      %{next_chart: id} = socket.assigns
      state = Map.take(socket.assigns, @chart_state)
      chart = Map.merge(state, %{id: id, name: name || fallback, expanded: true})

      assign(socket,
        charts: socket.assigns.charts ++ [chart],
        chart: id,
        next_chart: id + 1
      )
    end

    # The store's names, for the labels of an opened composite's sites.
    @doc false
    def names(nil), do: fn _id -> nil end

    def names(store) do
      fn id ->
        case Store.get(store, id) do
          {:ok, entry} -> entry.name
          :error -> nil
        end
      end
    end

    # The tick goes to the host's process, which forwards it (spec/14 §18.2).
    @doc false
    def schedule(socket) do
      Process.send_after(
        self(),
        {:visualize_chart_tick, socket.assigns.id},
        socket.assigns.tick_ms
      )

      socket
    end

    @doc false
    def saved(socket, {:ok, id}, then), do: socket |> assign(:notice, nil) |> then.(id)

    def saved(socket, {:error, reason}, _then),
      do: assign(socket, :notice, "the store refused the design: #{inspect(reason)}")

    @doc false
    def fetch(nil, _submitted), do: :error

    def fetch(store, submitted) do
      case Store.decode_id(submitted) do
        {:ok, id} -> Store.get(store, id)
        :error -> :error
      end
    end

    # The stack as a composite: what saving sends (spec/14 §19.6).
    @doc false
    def structure(%{uses: uses, stack_vars: vars} = assigns),
      do: Stack.structure(uses, vars, Map.get(assigns, :signals, %{}))
  end
end
