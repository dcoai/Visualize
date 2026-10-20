defmodule Visualize.Hooks.KeyboardGridTest do
  @moduledoc """
  #765, D-198: a grid of states reached from the keyboard. A 3 × 3 band grid whose cells
  declare a click event, drawn by `Visualize.Components.Chart` and executed under the
  harness of spec/12 §6 — `KeyboardHook` around `TooltipHook`, as the component renders
  them, on SVG and on the binary canvas: the arrows move in the grid's two dimensions and
  stop at its edges, Enter sends the event a click at the cell's center sends, and one
  click yields one event even with a pick event set, as a board's cell sets one.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Visualize.Chart
  alias Visualize.Chart.Summary
  alias Visualize.Components.Chart, as: Component
  alias Visualize.Data.{Delivery, Schema}
  alias Visualize.JsHooks

  @design %{
    version: 3,
    sources: %{
      cells: %{fields: [:row, :col, :state], requires: %{row: [:identity], col: [:identity]}}
    },
    frames: %{
      main: %{
        kind: :cartesian,
        margin: %{top: 10, right: 10, bottom: 10, left: 10},
        scales: %{
          x: %{kind: :band, domain: [0, 1, 2], padding: 0},
          y: %{kind: :band, domain: [2, 1, 0], padding: 0}
        }
      }
    },
    marks: [
      %{
        type: :rect,
        data: :cells,
        channels: %{x0: :col, x1: :col, y0: :row, y1: :row},
        tooltip: %{fields: [:state], template: "{state}", event: :cell_click}
      }
    ]
  }

  @schema Schema.new!(%{
            row: %{type: :category, identity: true},
            col: %{type: :category, identity: true},
            state: %{type: :category}
          })

  defp applied do
    rows =
      for r <- 0..2, c <- 0..2, do: %{row: r, col: c, state: if(r == c, do: "open", else: "shut")}

    {:ok, applied} =
      Chart.apply(@design,
        sources: %{cells: Delivery.new(rows, schema: Schema.version(@schema))},
        schemas: Schema.Cache.new([{:cells, @schema}]),
        size: {120, 120}
      )

    applied
  end

  # The middle of cell {column, row}, a cell 100/3 wide, row 0 at the top.
  defp center({c, r}), do: {10 + (c + 0.5) * 100 / 3, 10 + (r + 0.5) * 100 / 3}

  test "the cells are one grid series: centers, cells, keys and readouts" do
    assert [%{name: "cells", grid: true, points: points}] = Summary.points(applied())
    assert length(points) == 9

    for {point, ordinal} <- Enum.with_index(points) do
      {r, c} = {div(ordinal, 3), rem(ordinal, 3)}
      assert point.cell == {c, r}
      {x, y} = center({c, r})
      assert_in_delta point.x, x, 1.0e-9
      assert_in_delta point.y, y, 1.0e-9
      assert point.key == %{event: "cell_click", frame: "main", mark: 0, row: ordinal}
    end

    assert hd(points).text == "cells, 1 of 9: col 0, row 0, open"
    assert Enum.at(points, 1).text == "cells, 2 of 9: col 1, row 0, shut"
  end

  # The scenario over a drawing: both hooks mounted as the page mounts them, the chart at
  # twice its size, then the keys, Enter, and clicks fired on both hooks' elements — the
  # stub does not bubble, so a click reaches each as the browser's would.
  defp scenario(html, backend) do
    """
    const el = #{JsHooks.markup(html)};
    el.setAttribute('data-keyboard-pick-event', 'pick');
    el.dataset.keyboardPickEvent = 'pick';
    const chart = el.querySelector('svg') || el.querySelector('canvas');
    chart.rect = {left: 10, top: 20, width: 240, height: 240};
    const tipEl = el.querySelector('[data-tooltip-drawn]');
    const tip = Stub.mount(TooltipHook, tipEl);
    const kb = Stub.mount(KeyboardHook, el);
    const cell = (row) => el.querySelectorAll('[data-row]').filter((n) => n.getAttribute('data-row') === String(row))[0];
    const at = [];
    const key = (k) => { el.fire('keydown', {target: el, key: k, preventDefault: () => {}}); at.push(kb.at ? kb.at.index : null); };
    const click = (x, y, row) => {
      const ev = {target: #{if backend == :svg, do: "row === null ? chart : cell(row)", else: "chart"}, clientX: 10 + 2 * x, clientY: 20 + 2 * y};
      tipEl.fire('click', ev);
      el.fire('mousedown', ev);
      el.fire('click', ev);
    };
    el.fire('focus', {});
    ['ArrowRight', 'ArrowRight', 'ArrowRight', 'ArrowRight', 'ArrowDown', 'ArrowLeft', 'ArrowUp', 'ArrowUp', 'End', 'ArrowDown', 'ArrowDown', 'ArrowDown'].forEach(key);
    Stub.mark('enter');
    // Back to the cell in the middle of the top row, then Enter.
    ['Home', 'ArrowRight'].forEach(key);
    el.fire('keydown', {target: el, key: 'Enter', preventDefault: () => {}});
    Stub.mark('click');
    click(#{elem(center({1, 0}), 0)}, #{elem(center({1, 0}), 1)}, 1);
    Stub.mark('margin');
    click(4, 60, null);
    Stub.done({at});
    """
  end

  defp pushes(log, mark) do
    for %{"kind" => "push"} = p <- JsHooks.after_mark(log, mark),
        do: {p["name"], Map.delete(p["payload"], "drawn")}
  end

  @tag :js
  test "arrows move in two dimensions, Enter is a click, and a click is one event" do
    for {backend, opts} <- [svg: [], binary: [backend: :canvas]] do
      html = render_component(Component, [id: "grid", chart: applied()] ++ opts)

      assert {:ok, %{"log" => log, "report" => %{"at" => at}}} =
               JsHooks.run(scenario(html, backend))

      # Right along the top row to its end and no further, down a row, left, up twice to
      # the top and no further; End is the last cell, and down stops at the bottom.
      assert at == [0, 1, 2, 2, 5, 4, 1, 1, 8, 8, 8, 8, 0, 1], inspect({backend, at})

      # Enter on the top row's middle cell sends what a click at its center sends.
      assert [{"visualize_event", entered}] = pushes(log, "enter")
      assert [{"visualize_event", clicked}] = pushes(log, "click"), inspect(backend)
      # The same key and keys held; the point as the readout's four decimals give it.
      assert Map.delete(entered, "at") == Map.delete(clicked, "at")
      assert_in_delta entered["at"]["x"], clicked["at"]["x"], 1.0e-4
      assert_in_delta entered["at"]["y"], clicked["at"]["y"], 1.0e-4
      assert %{"event" => "cell_click", "frame" => "main", "mark" => 0, "row" => 1} = entered

      # A click on no keyed item is the keyboard's pick of the nearest point, alone.
      assert [{"pick", %{"series" => 0, "index" => _}}] = pushes(log, "margin")
    end
  end

  test "the component wraps its drawing in KeyboardHook with the grid's points" do
    html = render_component(Component, id: "grid", chart: applied())
    assert html =~ ~s(<div id="grid-keys" phx-hook="KeyboardHook")
    assert html =~ ~s(&quot;grid&quot;:true)
    assert html =~ ~s(<div id="grid" phx-hook="TooltipHook")
  end
end
