defmodule Visualize.Hooks.ExecutedBoardBuilderHookTest do
  @moduledoc """
  `BuilderHook` in scope `board` executed under node against the recording DOM stub
  (spec/12 §6, spec/10 §16.3): the board mode's grid, its cells built from the attributes
  the builder renders (spec/14 §22.3).

  A pointer's travel is read as squares of the grid and pushed as `board_place` on
  release; each push is handed back to the builder, so the test holds where the cell
  lands — or that the server refuses it — and not only the numbers sent.
  """
  use ExUnit.Case, async: true

  import Visualize.JsHooks, only: [run: 1]

  alias Visualize.BuilderFixture
  alias Visualize.Chart.Builder

  @moduletag :js

  # The grid laid out 1192 px wide with an 8 px gap: a column's pitch is (1192 + 8) / 12 =
  # 100 px, and a row's 80 + 8 = 88 px.
  @width 1192
  @col 100
  @row 88

  # A board of two cells over the fixture library's baseline composite: `wide` across the
  # top left, `tall` beside it.
  defp board do
    s = BuilderFixture.socket(BuilderFixture.layers(), store: BuilderFixture.Library)
    {:noreply, s} = Builder.handle_event("new_fragment", %{"kind" => "board"}, s)
    {:noreply, s} = Builder.handle_event("board_add", %{"ref" => "composite:1"}, s)
    {:noreply, s} = Builder.handle_event("board_add", %{"ref" => "composite:1"}, s)
    s
  end

  # The grid's cells as the builder rendered them: each `<article>`'s data attributes.
  defp cells(s) do
    html = BuilderFixture.render(s)
    [grid] = Regex.run(~r/<div id="b-board"[^>]*>/, html)
    assert grid =~ ~s(data-builder-scope="board")
    assert grid =~ ~s(data-board-gap="8")

    for [tag] <- Regex.scan(~r/<article[^>]*data-board-cell[^>]*>/, html) do
      for [_, name, value] <- Regex.scan(~r/([\w-]+)="([^"]*)"/, tag),
          String.starts_with?(name, "data-board-"),
          into: %{},
          do: {name, value}
    end
  end

  # The grid built from the rendered cells, the hook mounted on it, and `steps` run: each a
  # line of JavaScript over `grid`, `cell(name)` and `hook`. What the hook pushed is returned.
  defp scenario(cells, steps) do
    source = """
    const cells = #{Jason.encode!(cells)}.map((attributes) => Stub.markup('article', attributes, [
      Stub.markup('header', {class: 'vis-builder-board-cell-head'}),
      Stub.markup('span', {'data-board-handle': 'e'}),
      Stub.markup('span', {'data-board-handle': 's'}),
      Stub.markup('span', {'data-board-handle': 'se'})
    ]));
    const grid = Stub.markup('div', {'data-builder-scope': 'board', 'data-builder-target': '1', 'data-board-gap': '8', 'data-board-row-height': '80'}, cells);
    grid.rect = {left: 0, top: 0, width: #{@width}, height: 600};
    const hook = Stub.mount(BuilderHook, grid);
    const cell = (name) => cells.find((c) => c.getAttribute('data-board-cell') === name);
    const handle = (name, edge) => cell(name).children.find((c) => c.getAttribute('data-board-handle') === edge);
    const down = (target, x, y) => hook.handlePointerDown({target, button: 0, clientX: x, clientY: y});
    const move = (x, y) => grid.fire('pointermove', {clientX: x, clientY: y});
    const up = () => grid.fire('pointerup', {});
    #{Enum.join(steps, "\n")}
    Stub.done({});
    """

    assert {:ok, %{"log" => log}} = run(source)
    for %{"kind" => "push", "name" => name, "payload" => p} <- log, do: {name, p}
  end

  defp rect(s, cell), do: Map.take(s.assigns.board.cells[cell], [:x, :y, :w, :h])

  defp placed(s, {"board_place", payload}) do
    {:noreply, s} = Builder.handle_event("board_place", payload, s)
    s
  end

  test "a cell dragged by its body is pushed at the squares the pointer traveled, and placed" do
    s = board()
    assert rect(s, :cell_1) == %{x: 0, y: 0, w: 4, h: 2}
    assert rect(s, :cell_2) == %{x: 4, y: 0, w: 4, h: 2}

    # Two columns and three rows, a few pixels short of each: the travel rounds.
    pushes =
      scenario(cells(s), [
        "down(cell('cell_1').children[0], 50, 40);",
        "move(50 + #{@col}, 40);",
        "move(50 + #{2 * @col - 6}, 40 + #{3 * @row - 10});",
        "up();"
      ])

    assert [{"board_place", payload}] = pushes

    assert payload == %{
             "cell" => "cell_1",
             "x" => 2,
             "y" => 3,
             "w" => 4,
             "h" => 2,
             "scope" => "board"
           }

    s = placed(s, hd(pushes))
    assert rect(s, :cell_1) == %{x: 2, y: 3, w: 4, h: 2}
    assert s.assigns.notice == nil
  end

  test "a drag onto another cell is pushed, and the server refuses it" do
    s = board()

    pushes =
      scenario(cells(s), [
        "down(cell('cell_1').children[0], 50, 40);",
        "move(50 + #{2 * @col}, 40);",
        "up();"
      ])

    assert [{"board_place", %{"x" => 2, "y" => 0}} = push] = pushes
    s = placed(s, push)
    assert rect(s, :cell_1) == %{x: 0, y: 0, w: 4, h: 2}
    assert s.assigns.notice =~ "overlaps"
  end

  test "a cell is resized by its corner and its edges, clamped to the grid" do
    s = board()

    pushes =
      scenario(cells(s), [
        "down(handle('cell_2', 'se'), 800, 170);",
        "move(800 + #{9 * @col}, 170 + #{2 * @row});",
        "up();",
        "down(handle('cell_1', 's'), 200, 170);",
        "move(200 + #{3 * @col}, 170 + #{@row});",
        "up();",
        "down(handle('cell_1', 'e'), 400, 100);",
        "move(400 - #{9 * @col}, 100);",
        "up();"
      ])

    assert [
             {"board_place", %{"cell" => "cell_2", "x" => 4, "y" => 0, "w" => 8, "h" => 4}},
             {"board_place", %{"cell" => "cell_1", "x" => 0, "y" => 0, "w" => 4, "h" => 3}},
             {"board_place", %{"cell" => "cell_1", "x" => 0, "y" => 0, "w" => 1, "h" => 2}}
           ] = pushes

    s = placed(s, Enum.at(pushes, 0))
    assert rect(s, :cell_2) == %{x: 4, y: 0, w: 8, h: 4}
  end

  test "a drag past the edge is shown and pushed clamped to the grid" do
    pushes =
      scenario(cells(board()), [
        "down(cell('cell_2').children[0], 500, 40);",
        "move(500 + #{20 * @col}, 40 - #{5 * @row});",
        "up();"
      ])

    assert [{"board_place", %{"cell" => "cell_2", "x" => 8, "y" => 0, "w" => 4, "h" => 2}}] =
             pushes
  end

  test "a press that does not travel a square pushes nothing, so the click selects" do
    assert scenario(cells(board()), [
             "down(cell('cell_1').children[0], 50, 40);",
             "move(70, 50);",
             "up();"
           ]) == []
  end

  test "while it moves the cell is marked and drawn where it would go; release restores it" do
    source_steps = [
      "down(cell('cell_1').children[0], 50, 40);",
      "move(50, 40 + #{3 * @row});",
      "Stub.mark('moving');",
      "if (!cell('cell_1').classList.contains('vis-builder-board-dragging')) throw new Error('not marked');",
      "if (cell('cell_1').style.gridRow !== '4 / span 2') throw new Error('row ' + cell('cell_1').style.gridRow);",
      "up();",
      "if (cell('cell_1').classList.contains('vis-builder-board-dragging')) throw new Error('still marked');",
      "if (cell('cell_1').style.gridRow !== '1 / span 2') throw new Error('not restored');"
    ]

    assert [{"board_place", %{"y" => 3}}] = scenario(cells(board()), source_steps)
  end

  test "an arrow moves the focused cell one square, and Shift with an arrow resizes it" do
    s = board()

    pushes =
      scenario(cells(s), [
        "hook.handleKeyDown({target: cell('cell_1'), key: 'ArrowDown', preventDefault() {}});",
        "hook.handleKeyDown({target: cell('cell_2'), key: 'ArrowRight', shiftKey: true, preventDefault() {}});",
        "hook.handleKeyDown({target: cell('cell_1'), key: 'ArrowLeft', preventDefault() {}});",
        "hook.handleKeyDown({target: cell('cell_1'), key: 'a', preventDefault() {}});"
      ])

    assert [
             {"board_place", %{"cell" => "cell_1", "x" => 0, "y" => 1, "w" => 4, "h" => 2}},
             {"board_place", %{"cell" => "cell_2", "x" => 4, "y" => 0, "w" => 5, "h" => 2}}
           ] = pushes

    s = Enum.reduce(pushes, s, &placed(&2, &1))
    assert rect(s, :cell_1) == %{x: 0, y: 1, w: 4, h: 2}
    assert rect(s, :cell_2) == %{x: 4, y: 0, w: 5, h: 2}
  end
end
