defmodule Visualize.Hooks.CanvasClickTest do
  @moduledoc """
  #764, D-197: a click on a canvas is the click on the SVG. `Visualize.Components.Chart`
  draws one chart as SVG, on the JSON canvas and on the binary canvas; `TooltipHook`,
  executed under the harness of spec/12 §6 over each drawing as the component renders
  it, is clicked at the same points. On the SVG the click lands on the element drawn there;
  on a canvas, which draws none, the hook finds it in the drawing's hit index. Every
  backend pushes the same `visualize_event`, and each resolves to the same
  `Visualize.Event`.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Visualize.Chart
  alias Visualize.Components.Chart, as: Component
  alias Visualize.Event
  alias Visualize.Hooks.Tooltip.Items
  alias Visualize.JsHooks

  # A 3 × 3 grid of cells in a 10-pixel margin, 100 pixels a side, and a dot over the
  # middle cell: the dot is drawn last, so it is on top there.
  @design %{
    version: 3,
    sources: %{cells: %{fields: [:row, :col]}, dots: %{fields: [:row, :col]}},
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
        style: %{stroke: %{color: "#ffffff", width: 2}},
        tooltip: %{fields: [:row, :col], event: :cell_click}
      },
      %{
        type: :circle,
        data: :dots,
        channels: %{x: :col, y: :row},
        options: %{radius: 6},
        tooltip: %{fields: [:row, :col], event: :dot_click}
      }
    ]
  }

  @cells for r <- 0..2, c <- 0..2, do: %{row: r, col: c}

  defp applied do
    {:ok, applied} =
      Chart.apply(@design,
        sources: %{cells: @cells, dots: [%{row: 1, col: 1}]},
        size: {120, 120}
      )

    applied
  end

  # The point at the middle of cell `{r, c}`, a cell 100/3 wide, row 0 at the top.
  defp center({r, c}), do: {10 + (c + 0.5) * 100 / 3, 10 + (r + 0.5) * 100 / 3}

  # The clicks, each a point in the chart's units and the element drawn on top there — the
  # mark's position and the row's ordinal — or nothing.
  @clicks [
    {{0, 0}, {0, 0}},
    {{2, 1}, {0, 7}},
    {{1, 2}, {0, 5}},
    # The dot over the middle cell, and the middle cell beside the dot.
    {{1, 1}, {1, 0}},
    {:beside_dot, {0, 4}},
    # The margin: nothing is drawn there.
    {:margin, nil}
  ]

  defp point({r, c}), do: center({r, c})
  defp point(:beside_dot), do: {60 + 12, 60}
  defp point(:margin), do: {4, 60}

  defp html(opts), do: render_component(Component, [id: "grid", chart: applied()] ++ opts)

  @backends [svg: [], json: [backend: :canvas, canvas_format: :json], binary: [backend: :canvas]]

  # The scenario: the drawing mounted under TooltipHook, its chart — the <svg> or the
  # <canvas> — at twice its size 10 and 20 pixels in, and one click per point: on the SVG
  # with the element drawn there as its target, on a canvas with only the position.
  defp scenario(html, backend) do
    clicks =
      Enum.map_join(@clicks, "\n", fn {at, target} ->
        {x, y} = point(at)
        selector = if target, do: target_selector(target), else: "null"

        """
        Stub.mark(#{Jason.encode!(inspect(at))});
        {
          const node = #{if backend == :svg and target, do: "pick(#{selector})", else: "null"};
          Stub.fire(el, 'click', {target: node || chart, clientX: #{10 + 2 * x}, clientY: #{20 + 2 * y}, shiftKey: true});
        }
        """
      end)

    """
    const el = #{JsHooks.markup(html)};
    const chart = el.querySelector('svg') || el.querySelector('canvas');
    chart.rect = {left: 10, top: 20, width: 240, height: 240};
    const pick = ([mark, row]) => el.querySelectorAll('[data-mark]')
      .filter((g) => g.getAttribute('data-mark') === String(mark))[0]
      .querySelectorAll('[data-row]').filter((n) => n.getAttribute('data-row') === String(row))[0];
    Stub.mount(TooltipHook, el);
    #{clicks}
    Stub.done({});
    """
  end

  defp target_selector({mark, row}), do: "[#{mark}, #{row}]"

  defp pushes(log, at) do
    for %{"kind" => "push"} = p <- JsHooks.after_mark(log, inspect(at)),
        do: Map.delete(p["payload"], "drawn")
  end

  @tag :js
  test "the same point clicked on SVG, the JSON canvas and the binary canvas is one event" do
    runs =
      for {backend, opts} <- @backends, into: %{} do
        assert {:ok, %{"log" => log}} = JsHooks.run(scenario(html(opts), backend)), "#{backend}"
        {backend, log}
      end

    applied = applied()

    for {at, target} <- @clicks do
      [svg, json, binary] = for b <- [:svg, :json, :binary], do: pushes(runs[b], at)
      assert svg == json, inspect({at, svg, json})
      assert svg == binary, inspect({at, svg, binary})

      case target do
        nil ->
          assert svg == []

        {mark, row} ->
          assert [%{"mark" => ^mark, "row" => ^row, "modifiers" => ["shift"]} = payload] = svg
          {x, y} = point(at)
          assert_in_delta payload["at"]["x"], x, 1.0e-6
          assert_in_delta payload["at"]["y"], y, 1.0e-6

          # Resolved by the server, every backend's push is one Visualize.Event.
          events =
            for b <- [:svg, :json, :binary] do
              [push] = pushes(runs[b], at)
              {:ok, click} = Event.decode(push)
              {:ok, event} = Event.resolve(click, applied)
              event
            end

          assert [event, event, event] = events
          assert event.modifiers == [:shift]
          # The row drawn at the point: a cell's, by its ordinal, or the dot's.
          expected = if mark == 0, do: Enum.at(@cells, row), else: %{row: 1, col: 1}
          assert event.row == expected
      end
    end
  end

  test "a canvas drawing carries the hit index and the size beside its stream" do
    for {format, hook, attr} <-
          [
            binary: ["CanvasBinaryChart", "data-binary"],
            json: ["CanvasChart", "data-commands"]
          ]
          |> Enum.map(fn {f, [h, a]} -> {f, h, a} end) do
      html = html(backend: :canvas, canvas_format: format)
      assert html =~ ~s(data-size="120,120")
      assert html =~ ~s(data-vis-items="[{&quot;event&quot;:&quot;cell_click&quot;)
      assert html =~ ~s(phx-hook="#{hook}")
      assert html =~ attr <> "="
      refute html =~ "<rect"
    end

    # The SVG carries no index: its elements are the keys.
    refute html([]) =~ "data-vis-items"
  end

  test "the index: cells padded by their stroke, the dot a disc, in drawing order" do
    [cells, dots] = Items.entries(Chart.generate(applied(), resolve: :literal))

    assert %{event: "cell_click", frame: "main", mark: 0} = cells
    assert length(cells.items) == 9
    assert [0, "r", x, y, w, h] = hd(cells.items)
    assert {x, y} == {9, 9}
    assert_in_delta w, 100 / 3 + 2, 1.0e-9
    assert_in_delta h, 100 / 3 + 2, 1.0e-9

    assert %{event: "dot_click", mark: 1, items: [[0, "c", cx, cy, r]]} = dots
    assert {cx, cy, r} == {60.0, 60.0, 6.0}
  end

  test "the index follows transforms: a rotated rect and a path are paths, with their boxes" do
    alias Visualize.IR.{Element, Path, Transform}

    key = &Element.put_attr(&1, "data-row", &2)
    rotated = Element.rect(0, 0, 10, 10) |> key.("0")
    triangle = %Path{commands: [{:M, 0, 0}, {:L, 10, 0}, {:L, 0, 10}, :Z]}
    stroked = Element.path(triangle, %{fill: :none, stroke: "#000", stroke_width: 2}) |> key.("1")

    mark =
      Element.group([rotated, stroked],
        attrs: %{"data-tooltip-event" => "pick", "data-frame" => "main", "data-mark" => "0"}
      )

    tree = %{
      Element.group([%{mark | transform: Transform.new() |> Transform.rotate(90)}])
      | transform: Transform.translate(100, 50)
    }

    [%{items: [[0, "p" | rect], [1, "p" | path]]}] = Items.entries(tree)

    # Turned a quarter about the origin, then moved: the box of x in -10..0 and y in 0..10.
    [x, y, w, h, d, matrix, 1, 0] = rect
    assert_in_delta x, 90, 1.0e-9
    assert_in_delta y, 50, 1.0e-9
    assert {w, h} |> then(fn {w, h} -> {Float.round(w, 9), Float.round(h, 9)} end) == {10.0, 10.0}
    assert d =~ "M0,0"

    assert [a, b, c, dd, 100, 50] =
             Enum.map(matrix, &if(is_float(&1), do: Float.round(&1, 9), else: &1))

    assert {a, b, c, dd} == {0.0, 1.0, -1.0, 0.0}

    # An unfilled path takes the pointer on its stroke only, its box grown by half of it.
    [x, y, _w, _h, _d, _m, 0, 2] = path
    assert_in_delta x, 89, 1.0e-9
    assert_in_delta y, 49, 1.0e-9
  end

  test "a canvas chart that draws text lays it over the binary stream, not over the JSON" do
    {:ok, applied} =
      @design
      |> Map.put(:labels, [%{anchor: :title, text: ["Cells"]}])
      |> Chart.apply(sources: %{cells: @cells, dots: []}, size: {120, 120})

    binary = render_component(Component, id: "g", chart: applied, backend: :canvas)

    json =
      render_component(Component, id: "g", chart: applied, backend: :canvas, canvas_format: :json)

    assert binary =~ ~r/class="vis-chart-text"[^>]*>\s*<svg[^>]*aria-hidden="true"/
    assert binary =~ ">Cells</text>"
    refute json =~ "vis-chart-text"
  end

  test "a backend the component does not draw is refused by name" do
    assert_raise ArgumentError, ~r/backend: :svg or :canvas/, fn -> html(backend: :webgl) end
  end
end
