defmodule ExamplesWeb.BoardLifecycleTest do
  @moduledoc """
  The board outside its process on `/board` (spec/15 §10–§12, spec/08 §12, #781, work item
  #822): a snapshot reopened from its JSON with no feed, the board carried in a bundle to a
  second library under new ids, and the conformance kit run over the board's feeds.
  """
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  alias ExamplesWeb.BoardLive
  alias ExamplesWeb.BoardLive.Lifecycle

  @endpoint ExamplesWeb.Endpoint

  defp snapshot_json do
    build_conn() |> post("/board/export/snapshot") |> response(200)
  end

  test "an exported snapshot reopens with no feed, every cell drawn" do
    assert {:ok, shown} = Lifecycle.reopen(snapshot_json())
    assert shown.cells == map_size(Examples.BoardDemo.value().cells)
    assert %DateTime{} = shown.now
    assert shown.svg =~ ~s(data-vis-cell="offline" data-vis-state="down")
    assert shown.svg =~ ~s(data-vis-cell="links")
  end

  test "a document the reader refuses is its faults, worded" do
    assert {:error, [fault]} = Lifecycle.reopen("{\"$version\": 99}")
    assert fault =~ "needs schema v99"

    assert {:error, [_ | _]} = Lifecycle.reopen("not json")
  end

  test "the running board frozen now reopens the same way" do
    {:ok, board} = Examples.BoardDemo.board()
    assert {:ok, %{cells: cells}} = Lifecycle.freeze(board)
    assert cells == map_size(Examples.BoardDemo.value().cells)
  end

  test "the board carried in a bundle arrives under ids the receiving library issues" do
    assert {:ok, carried} = Lifecycle.carry()
    # It traveled as the file another host receives: stamped, and read back from the text.
    assert %{"$version" => _, "provenance" => %{"store" => "examples /board"}, "board" => _} =
             Jason.decode!(carried.file)

    assert carried.bytes > 0
    # The receiving library held two designs of its own; every carried one is new.
    assert length(carried.before) == 2
    assert length(carried.after) == 2 + length(carried.carried)
    assert carried.outside == []

    for {old, new} <- carried.ids,
        do: assert(new not in Enum.map(carried.before, &elem(&1, 0)), inspect(old))

    table = Map.new(carried.ids)
    for {_cell, old, new} <- carried.refs, do: assert(table[old] == new)

    assert {"links", "links", fields} = List.keyfind(carried.needs, "links", 0)
    assert "iface" in Enum.map(fields, &to_string/1)
  end

  test "the conformance kit passes every feed but the unreachable and the over-delivering one" do
    rows = Lifecycle.conformance()

    assert Enum.map(rows, &elem(&1, 0)) ==
             Enum.sort(Enum.map(Map.keys(Examples.BoardDemo.feeds()), &to_string/1))

    for {feed, checks} <- rows,
        feed not in ["offline", "over_budget"],
        {check, findings} <- checks,
        do: assert(findings == [], "#{feed} #{check}: #{inspect(findings)}")

    {"offline", checks} = List.keyfind(rows, "offline", 0)
    assert [_ | _] = Keyword.fetch!(checks, :deliveries)

    # Serving more than the budget it names, on purpose (D-227): the kit says so.
    {"over_budget", checks} = List.keyfind(rows, "over_budget", 0)
    assert [_ | _] = overruns = Keyword.fetch!(checks, :supports)
    assert Enum.all?(overruns, &(&1 =~ "the feed names :budget and served 6000"))
  end

  test "the page renders the panel, and its buttons are the page's own events" do
    html = build_conn() |> get("/board") |> html_response(200)
    assert html =~ ~s(id="panel-lifecycle")
    assert html =~ ~s(id="board-reopen")
    assert html =~ ~s(phx-click="carry")
    assert html =~ ~s(phx-click="conformance")

    {:ok, socket} = BoardLive.mount(%{}, %{}, %Phoenix.LiveView.Socket{})
    assert socket.assigns.reopened == nil

    {:noreply, socket} = BoardLive.handle_event("freeze", %{}, socket)
    assert {:ok, %{cells: _}} = socket.assigns.reopened

    {:noreply, socket} = BoardLive.handle_event("carry", %{}, socket)
    assert {:ok, _carried} = socket.assigns.bundle

    # The kit's report arrives as the page's async result.
    {:noreply, socket} = BoardLive.handle_async(:conformance, {:ok, [{"wave", []}]}, socket)
    assert socket.assigns.conformance == [{"wave", []}]

    shown =
      Phoenix.LiveViewTest.rendered_to_string(
        Lifecycle.panel(%{
          uploads: socket.assigns.uploads,
          reopened: socket.assigns.reopened,
          bundle: socket.assigns.bundle,
          conformance: socket.assigns.conformance,
          __changed__: nil
        })
      )

    assert shown =~ "Reopened:"
    assert shown =~ "designs carried at schema v"
    assert shown =~ "The bundle as a file"
    assert shown =~ ~s(data-feed="wave")
  end
end
