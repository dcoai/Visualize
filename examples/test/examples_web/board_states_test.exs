defmodule ExamplesWeb.BoardStatesTest do
  @moduledoc """
  `/board` shows every cell state and a composite selection (spec/15 §8.4, §13.2, D-167,
  #781, work item #821, #865, D-227): five cells over feeds made to be stale, empty,
  capped, wrongly typed and over the board's ceiling, and a cell whose feed names a link by two fields, picked and selected as a map,
  kept in the page's URL.
  """
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  alias ExamplesWeb.BoardLive
  alias Visualize.Board.Server
  alias Visualize.Event

  @endpoint ExamplesWeb.Endpoint

  test "the page renders the new cells and says what each shows" do
    html = build_conn() |> get("/board") |> html_response(200)

    for cell <- ~w(links stale no_data capped invalid over_budget),
        do: assert(html =~ ~s(data-vis-cell="#{cell}"), cell)

    assert html =~ ~s(phx-click="select_link")
    assert html =~ "stale_after: 30"
  end

  test "each state cell is drawn in its state" do
    {:ok, board} = Examples.BoardDemo.board()
    {:ok, _info} = Server.subscribe(board)
    :ok = Server.tick(board)
    views = views(%{}, [:stale, :no_data, :capped, :invalid, :over_budget])
    Server.unsubscribe(board, self())

    assert {:stale, age} = views.stale.state
    assert age > 30
    # A stale chart is still drawn, under its banner.
    assert views.stale.svg =~ ~s(class="mark mark-)

    assert views.no_data.state == :no_data
    assert views.no_data.svg == nil

    assert views.capped.state == :capped
    assert views.capped.svg =~ ~s(class="mark mark-)

    assert {:invalid, [_ | _] = errors} = views.invalid.state
    assert inspect(errors) =~ "type_mismatch"

    # Over the board's ceiling: the rows are never handed to the cell, and its panel says so.
    assert views.over_budget.state == {:over_budget, 6000, 5000}
    assert views.over_budget.svg == nil
    assert views.over_budget.note =~ ~s(data-vis-state="over_budget")
    assert views.over_budget.note =~ "Over budget: 6,000 rows, ceiling 5,000"
  end

  test "a link's pick is its composite identity, which the board selects as a map" do
    {:ok, board} = Examples.BoardDemo.board()
    {:ok, _info} = Server.subscribe(board)
    :ok = Server.tick(board)
    _views = views(%{}, [:links])

    assert {:ok, %{identity: %{"host" => host, "iface" => iface}}} =
             Server.pick(board, "links", 0, 3)

    assert {host, iface} == {"h2", "eth1"}

    :ok = Server.select(board, %{"host" => "h2", "iface" => "eth1"})
    assert Server.info(board).selection == %{"host" => "h2", "iface" => "eth1"}

    # The one bar selected, the other seven muted.
    svg = dimmed(board, "links", 7)
    assert length(Regex.scan(~r/opacity="0.25"/, svg)) == 7

    # A host picked on Hosts is the pair, and selects both of that host's links.
    assert {:ok, %{identity: {"host", "h2"}}} = Server.pick(board, "hosts", 0, 1)
    :ok = Server.select(board, {"host", "h2"})
    assert length(Regex.scan(~r/opacity="0.25"/, dimmed(board, "links", 6))) == 6

    :ok = Server.select(board, nil)
    Server.unsubscribe(board, self())
  end

  test "the page keeps a composite selection in its URL and reads it back, no atom made" do
    {:ok, socket} = BoardLive.mount(%{}, %{}, %Phoenix.LiveView.Socket{})
    link = %{"host" => "h2", "iface" => "eth1"}
    selected = %Event{event: :select, value: %{identity: link}}

    {:noreply, patched} =
      BoardLive.handle_info({:visualize_event, "demo-board", selected}, socket)

    assert {:live, :patch, %{to: to}} = patched.redirected
    assert URI.decode_query(URI.parse(to).query) == %{"select" => "host:h2,iface:eth1"}

    {:noreply, _same} =
      BoardLive.handle_params(%{"select" => "host:h2,iface:eth1"}, "/board", socket)

    {:ok, board} = Examples.BoardDemo.board()
    assert Server.info(board).selection == link

    {:noreply, clicked} = BoardLive.handle_event("select_link", %{}, socket)
    assert {:live, :patch, %{to: ^to}} = clicked.redirected

    # A field the board does not select by is no selection, and no atom.
    word = "no_field_#{System.unique_integer([:positive])}"
    :ok = Server.select(board, nil)

    {:noreply, _same} =
      BoardLive.handle_params(%{"select" => "host:h2,#{word}:x"}, "/board", socket)

    assert Server.info(board).selection == nil
    assert_raise ArgumentError, fn -> String.to_existing_atom(word) end
  end

  # The first view of each cell that is no longer loading.
  defp views(seen, []), do: seen

  defp views(seen, waiting) do
    receive do
      {:visualize_board, _board, {:cell, cell, %{state: state} = view}} when state != :loading ->
        case Enum.find(waiting, &(to_string(&1) == cell)) do
          nil -> views(seen, waiting)
          asked -> views(Map.put(seen, asked, view), List.delete(waiting, asked))
        end

      {:visualize_board, _board, _other} ->
        views(seen, waiting)
    end
  end

  # The first drawing of a cell that dims `n` things.
  defp dimmed(board, cell, n) do
    receive do
      {:visualize_board, ^board, {:cell, ^cell, %{svg: svg}}} when is_binary(svg) ->
        if length(Regex.scan(~r/opacity="0.25"/, svg)) == n, do: svg, else: dimmed(board, cell, n)

      {:visualize_board, _board, _other} ->
        dimmed(board, cell, n)
    end
  end
end
