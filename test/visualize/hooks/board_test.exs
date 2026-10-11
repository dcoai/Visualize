defmodule Visualize.Hooks.BoardTest do
  @moduledoc """
  A live board's hooks executed under node (spec/10 §18, §6.2, spec/15 §9, #575): the
  container's width pushed to its component, focus moved across the cells carrying
  `data-vis-cell` and into a cell's chart, and a cell's brush pushing to the board's
  component and keeping its overlay through a redraw.
  """
  use ExUnit.Case, async: true

  import Visualize.JsHooks, only: [run: 1]

  @moduletag :js

  defp pushes(log), do: for(%{"kind" => "push"} = p <- log, do: Map.delete(p, "kind"))

  # Three cells as `Visualize.Components.Board` renders them, the middle one holding a
  # chart's keyboard container, inside the board's container.
  @board_prelude """
  const keys = Stub.markup('div', {id: 'b-keys', tabindex: '-1', 'data-keyboard-points': '[]'}, []);
  const cell = (name, children) =>
    Stub.markup('article', {id: 'ops-' + name, 'data-vis-cell': name, tabindex: '0'}, children);
  const a = cell('a', []), b = cell('b', [keys]), c = cell('c', []);
  const grid = Stub.markup('div', {class: 'vis-board-grid'}, [a, b, c]);
  const el = Stub.markup('section', {id: 'ops', 'data-board-event': 'resize'}, [grid]);
  el.rect = {left: 0, top: 0, width: 1288.4, height: 600};
  // The push names the container itself; logged by its id.
  el.toJSON = () => "ops";
  const key = (target, k) => {
    let prevented = false;
    el.fire('keydown', {key: k, target, preventDefault: () => { prevented = true; }});
    return prevented;
  };
  const active = () => document.activeElement && document.activeElement.getAttribute('id');
  """

  test "BoardHook pushes the board's width to its component, once per settled change" do
    assert {:ok, %{"log" => log, "report" => report}} =
             run("""
             #{@board_prelude}
             const hook = Stub.mount(BoardHook, el);
             el.rect.width = 700;
             hook.measure();
             Stub.advance(100);
             el.rect.width = 640;
             hook.measure();
             const early = hook.last;
             Stub.advance(150);
             hook.measure();
             Stub.advance(150);
             Stub.done({early});
             """)

    # Mounted at 1288; the two quick changes settle once, at the last; a repeat is not pushed.
    assert pushes(log) == [
             %{
               "on" => "live",
               "name" => "resize",
               "payload" => %{"width" => 1288},
               "target" => "ops"
             },
             %{
               "on" => "live",
               "name" => "resize",
               "payload" => %{"width" => 640},
               "target" => "ops"
             }
           ]

    assert report["early"] == 1288
  end

  test "BoardHook moves focus across the cells and into a cell's chart; a chart's own keys are its own" do
    assert {:ok, %{"report" => report}} =
             run("""
             #{@board_prelude}
             Stub.mount(BoardHook, el);
             const report = {};
             a.focus();
             report.right = [key(a, 'ArrowRight'), active()];
             report.down = [key(b, 'ArrowDown'), active()];
             report.pastEnd = [key(c, 'ArrowRight'), active()];
             report.home = [key(c, 'Home'), active()];
             report.end = [key(a, 'End'), active()];
             report.up = [key(c, 'ArrowUp'), active()];
             report.enter = [key(b, 'Enter'), active()];
             // An arrow pressed in the chart bubbles up with the chart as its target.
             report.inChart = [key(keys, 'ArrowRight'), active()];
             report.tab = [key(b, 'Tab'), active()];
             Stub.done(report);
             """)

    assert report["right"] == [true, "ops-b"]
    assert report["down"] == [true, "ops-c"]
    assert report["pastEnd"] == [true, "ops-c"]
    assert report["home"] == [true, "ops-a"]
    assert report["end"] == [true, "ops-c"]
    assert report["up"] == [true, "ops-b"]
    assert report["enter"] == [true, "b-keys"]
    assert report["inChart"] == [false, "b-keys"]
    assert report["tab"] == [false, "b-keys"]
  end

  test "Escape in a cell's chart hands focus back to the cell" do
    assert {:ok, %{"report" => report}} =
             run("""
             #{@board_prelude}
             Stub.mount(BoardHook, el);
             const chart = Stub.mount(KeyboardHook, keys);
             key(b, 'Enter');
             keys.fire('keydown', {key: 'Escape', preventDefault() {}});
             Stub.done({active: active()});
             """)

    assert report["active"] == "ops-b"
  end

  test "a cell's brush pushes to the board's component and keeps its overlay through a redraw" do
    assert {:ok, %{"log" => log, "report" => report}} =
             run("""
             const frame = (x) => {
               const g = Stub.markup('g', {'data-vis-brush': 'x', 'data-vis-brush-x': x,
                                           'data-vis-brush-extent': '40,20,580,180'});
               const svg = Stub.markup('svg', {viewBox: '0 0 600 200'}, [g]);
               svg.rect = {left: 0, top: 0, width: 600, height: 200};
               return svg;
             };
             const first = frame('0,100,40,580,600');
             const el = Stub.markup('div', {'data-brush-event': 'brush', 'data-brush-target': '7'}, [first]);
             const hook = Stub.mount(BrushHook, el);
             const drag = (from, to) => {
               Stub.fire(hook.captureRect, 'mousedown', {button: 0, clientX: from, clientY: 100, preventDefault() {}});
               Stub.fire(document, 'mousemove', {clientX: to, clientY: 100, preventDefault() {}});
               Stub.fire(document, 'mouseup', {});
             };
             drag(148, 310);

             // The server redraws the chart: a new <svg> replaces the old one in the container.
             el.removeChild(first);
             const second = frame('100,200,40,580,600');
             el.appendChild(second);
             hook.updated();
             const report = {kept: second.contains(hook.overlay), gone: first.contains(hook.overlay)};
             drag(148, 310);
             Stub.fire(hook.captureRect, 'dblclick', {});
             Stub.done(report);
             """)

    assert report == %{"kept" => true, "gone" => false}

    assert [
             %{"name" => "brush", "target" => "7", "payload" => %{"domain" => [20, 50]}},
             %{"name" => "brush", "target" => "7", "payload" => %{"domain" => [120, 150]}},
             %{"name" => "brush_clear", "target" => "7", "payload" => %{}}
           ] = pushes(log)
  end
end
