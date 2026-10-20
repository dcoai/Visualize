defmodule Visualize.Hooks.TooltipShowTest do
  @moduledoc """
  #803, D-200: a mark's `tooltip` node with `show: false` delivers its events with nothing
  under the pointer. The cells of a 3 × 3 grid declare `event: :open` and
  `context_event: :flag`; drawn by `Visualize.Components.Chart` on SVG, the binary canvas
  and the JSON canvas and executed under the harness of spec/12 §6, a pointer over a cell
  shows no tooltip and no outline, and a click and a right-click still push their events.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Visualize.Chart
  alias Visualize.Components.Chart, as: Component
  alias Visualize.Event
  alias Visualize.JsHooks

  @tooltip %{show: false, template: "cell {row} {col}", event: :open, context_event: :flag}

  defp design(tooltip) do
    %{
      version: 3,
      sources: %{cells: %{fields: [:row, :col, :state]}},
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
          tooltip: tooltip
        }
      ]
    }
  end

  @cells for r <- 0..2, c <- 0..2, do: %{row: r, col: c, state: "hidden"}

  defp applied(tooltip \\ @tooltip) do
    {:ok, applied} = Chart.apply(design(tooltip), sources: %{cells: @cells}, size: {120, 120})
    applied
  end

  # Cell {column, row} = {1, 0}: the top row's middle, ordinal 1; its center on a chart
  # drawn at twice its size from (10, 20).
  @at {10 + 2 * (10 + 1.5 * 100 / 3), 20 + 2 * (10 + 0.5 * 100 / 3)}

  defp scenario(html, svg?) do
    {cx, cy} = @at

    """
    const el = #{JsHooks.markup(html)};
    const chart = el.querySelector('svg') || el.querySelector('canvas');
    chart.rect = {left: 10, top: 20, width: 240, height: 240};
    const tipEl = el.querySelector('[data-tooltip-drawn]');
    const cell = #{svg?} ? tipEl.querySelectorAll('[data-row]').filter((n) => n.getAttribute('data-row') === '1')[0] : chart;
    if (cell !== chart) cell.rect = {left: #{cx} - 10, top: #{cy} - 10, width: 20, height: 20};
    const hook = Stub.mount(TooltipHook, tipEl);
    const outlined = () => document.body.querySelectorAll('.vis-tooltip-hover')
      .filter((o) => o.style.display === 'block').length;
    Stub.fire(tipEl, 'mousemove', {target: cell, pageX: #{cx}, pageY: #{cy}, clientX: #{cx}, clientY: #{cy}});
    const report = {tip: hook.tip.style.display, text: hook.tip.textContent, outlined: outlined()};
    Stub.mark('click');
    Stub.fire(tipEl, 'click', {target: cell, clientX: #{cx}, clientY: #{cy}});
    Stub.mark('menu');
    let prevented = false;
    Stub.fire(tipEl, 'contextmenu', {target: cell, clientX: #{cx}, clientY: #{cy}, preventDefault: () => { prevented = true; }});
    report.prevented = prevented;
    Stub.done(report);
    """
  end

  defp pushes(log, mark) do
    for %{"kind" => "push"} = p <- JsHooks.after_mark(log, mark), do: p["payload"]
  end

  @backends [svg: [], binary: [backend: :canvas], json: [backend: :canvas, canvas_format: :json]]

  @tag :js
  test "nothing follows the pointer on every backend, and the click and the flag still push" do
    for {backend, opts} <- @backends do
      html = render_component(Component, [id: "grid", chart: applied()] ++ opts)
      label = inspect(backend)

      assert {:ok, %{"log" => log, "report" => report}} =
               JsHooks.run(scenario(html, backend == :svg)),
             label

      assert report["tip"] == "none", label
      assert report["outlined"] == 0, label
      assert [%{"event" => "open", "mark" => 0, "row" => 1} = click] = pushes(log, "click"), label
      assert [%{"event" => "flag", "row" => 1}] = pushes(log, "menu"), label
      assert report["prevented"] == true, label

      {:ok, decoded} = Event.decode(Map.delete(click, "drawn"))

      assert {:ok, %Event{event: "open", row: %{row: 0, col: 1}}} =
               Event.resolve(decoded, applied()),
             label
    end
  end

  @tag :js
  test "the same grid shown: the SVG's tooltip and outline follow the pointer" do
    html = render_component(Component, id: "grid", chart: applied(%{@tooltip | show: true}))
    assert {:ok, %{"report" => report}} = JsHooks.run(scenario(html, true))
    assert report["tip"] == "block"
    assert report["text"] == "cell 0 1"
    assert report["outlined"] == 1
  end

  test "show: false keys the elements, marks the group and writes only the named fields" do
    svg = Chart.render(applied())

    assert svg =~ ~s(data-tooltip-show="false")
    assert svg =~ ~s(data-tooltip-event="open")
    assert svg =~ ~s(data-tooltip-context-event="flag")
    assert svg =~ ~s(data-tooltip-template="cell {row} {col}")
    assert svg =~ ~s(data-frame="main" data-mark="0")
    assert svg =~ ~s(data-datum="" data-row="1")
    refute svg =~ "data-datum-"

    named = Chart.render(applied(Map.put(@tooltip, :fields, [:state])))
    assert named =~ ~s(data-datum="state" data-datum-state="hidden" data-row="1")
    refute named =~ "data-datum-row"
  end

  test "show: true, or no show, renders byte for byte as before" do
    without = Map.delete(@tooltip, :show)
    plain = Chart.render(applied(without))

    assert Chart.render(applied(%{@tooltip | show: true})) == plain
    refute plain =~ "data-tooltip-show"
    assert plain =~ ~s(data-datum="col row state")
  end

  test "the hit index of a canvas keys the hidden mark as it does a shown one" do
    shown = Visualize.Hooks.Tooltip.items(Chart.generate(applied(%{@tooltip | show: true})))
    assert Visualize.Hooks.Tooltip.items(Chart.generate(applied())) == shown
  end

  test "show is a boolean of the schema and round-trips through JSON" do
    chart = Chart.from_map!(design(@tooltip))
    assert {:ok, json} = Chart.to_json(chart)
    assert json =~ ~s("show":false)
    assert Chart.from_json(json) == {:ok, chart}

    assert {:error, [{[:marks, 0, :tooltip, :show], _reason}]} =
             Chart.from_map(design(%{@tooltip | show: "no"}))
  end
end
