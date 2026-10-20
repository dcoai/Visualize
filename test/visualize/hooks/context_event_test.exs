defmodule Visualize.Hooks.ContextEventTest do
  @moduledoc """
  #767, D-199: a mark's secondary action. The cells of a 3 × 3 grid declare `event:
  :open` and `context_event: :flag`; a dot over the middle cell declares only a click.
  Drawn by `Visualize.Components.Chart` on SVG and on the binary canvas and executed under
  the harness of spec/12 §6, a right-click, a long-press and the Menu key or Shift+F10 on
  the focused cell all push the same `flag` event, which resolves to one
  `Visualize.Event`; and the browser's menu is suppressed only over an item whose mark
  declares a context event.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Visualize.Chart
  alias Visualize.Components.Chart, as: Component
  alias Visualize.Data.{Delivery, Schema}
  alias Visualize.Event
  alias Visualize.JsHooks

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
        tooltip: %{fields: [:row, :col], event: :open, context_event: :flag}
      },
      %{
        type: :circle,
        data: :dots,
        channels: %{x: :col, y: :row},
        options: %{radius: 6},
        tooltip: %{fields: [:row, :col], event: :dot}
      }
    ]
  }

  @cells for r <- 0..2, c <- 0..2, do: %{row: r, col: c}

  # The cells are identities (D-167), so the keyboard reaches them (D-198).
  @schema Schema.new!(%{
            row: %{type: :category, identity: true},
            col: %{type: :category, identity: true}
          })

  defp applied(design \\ @design, dots \\ [%{row: 1, col: 1}]) do
    {:ok, applied} =
      Chart.apply(design,
        sources: %{cells: Delivery.new(@cells, schema: Schema.version(@schema)), dots: dots},
        schemas: Schema.Cache.new([{:cells, @schema}]),
        size: {120, 120}
      )

    applied
  end

  # Cell {column, row} = {1, 0}: the top row's middle, ordinal 1; its center.
  @cell {10 + 1.5 * 100 / 3, 10 + 0.5 * 100 / 3}

  defp scenario(html, backend) do
    {x, y} = @cell
    {cx, cy} = {10 + 2 * x, 20 + 2 * y}

    """
    const el = #{JsHooks.markup(html)};
    const chart = el.querySelector('svg') || el.querySelector('canvas');
    chart.rect = {left: 10, top: 20, width: 240, height: 240};
    const tipEl = el.querySelector('[data-tooltip-drawn]');
    const cellEl = (mark, row) => el.querySelectorAll('[data-mark]')
      .filter((g) => g.getAttribute('data-mark') === String(mark))[0]
      .querySelectorAll('[data-row]').filter((n) => n.getAttribute('data-row') === String(row))[0];
    const svg = #{backend == :svg};
    const under = (mark, row) => (svg ? cellEl(mark, row) : chart);
    // The element under a point, as the browser answers it: the cell's on an SVG.
    document.elementFromPoint = () => under(0, 1);
    Stub.mount(TooltipHook, tipEl);
    const kb = Stub.mount(KeyboardHook, el);
    const menu = (target, x, y) => {
      let prevented = false;
      tipEl.fire('contextmenu', {target, clientX: x, clientY: y, preventDefault: () => { prevented = true; }});
      return prevented;
    };
    const report = {};

    Stub.mark('right-click');
    report.cell = menu(under(0, 1), #{cx}, #{cy});

    Stub.mark('long-press');
    const before = Stub.log.filter((e) => e.kind === 'push').length;
    tipEl.fire('touchstart', {target: under(0, 1), touches: [{clientX: #{cx}, clientY: #{cy}}]});
    Stub.advance(499);
    report.early = Stub.log.filter((e) => e.kind === 'push').length - before;
    Stub.advance(1);
    // The menu and the click a browser fires after a long-press are swallowed.
    report.after = menu(under(0, 1), #{cx}, #{cy});
    tipEl.fire('click', {target: under(0, 1), clientX: #{cx}, clientY: #{cy}, preventDefault: () => {}});
    Stub.advance(1000);

    Stub.mark('moved');
    tipEl.fire('touchstart', {target: under(0, 1), touches: [{clientX: #{cx}, clientY: #{cy}}]});
    tipEl.fire('touchmove', {target: under(0, 1), touches: [{clientX: #{cx + 30}, clientY: #{cy}, pageX: 0, pageY: 0}]});
    Stub.advance(600);

    Stub.mark('menu-key');
    el.fire('focus', {});
    ['ArrowRight', 'ArrowRight'].forEach((k) => el.fire('keydown', {target: el, key: k, preventDefault: () => {}}));
    el.fire('keydown', {target: el, key: 'ContextMenu', preventDefault: () => {}});

    Stub.mark('shift-f10');
    el.fire('keydown', {target: el, key: 'F10', shiftKey: true, preventDefault: () => {}});

    Stub.mark('plain-f10');
    el.fire('keydown', {target: el, key: 'F10', preventDefault: () => {}});

    Stub.mark('no-context');
    // The dot declares a click and no context event; the margin holds nothing.
    report.dot = menu(under(1, 0), 130, 140);
    report.margin = menu(chart, 14, 140);

    Stub.done(report);
    """
  end

  defp pushes(log, mark) do
    for %{"kind" => "push"} = p <- JsHooks.after_mark(log, mark),
        do: Map.delete(p["payload"], "drawn")
  end

  @tag :js
  test "right-click, long-press and the Menu key or Shift+F10 are one event, on SVG and a canvas" do
    applied = applied()

    for {backend, opts} <- [svg: [], binary: [backend: :canvas]] do
      html = render_component(Component, [id: "grid", chart: applied] ++ opts)
      assert {:ok, %{"log" => log, "report" => report}} = JsHooks.run(scenario(html, backend))
      label = inspect(backend)

      assert [right] = pushes(log, "right-click"), label
      assert [pressed] = pushes(log, "long-press"), label
      assert [keyed] = pushes(log, "menu-key"), label
      assert [shifted] = pushes(log, "shift-f10"), label
      assert pushes(log, "moved") == [], label
      assert pushes(log, "plain-f10") == [], label
      assert pushes(log, "no-context") == [], label

      assert %{"event" => "flag", "frame" => "main", "mark" => 0, "row" => 1, "modifiers" => []} =
               right

      for other <- [pressed, keyed, shifted] do
        assert Map.delete(other, "at") == Map.delete(right, "at"), inspect({backend, other})
        assert_in_delta other["at"]["x"], right["at"]["x"], 1.0e-4
        assert_in_delta other["at"]["y"], right["at"]["y"], 1.0e-4
      end

      # The menu yields only over an item whose mark declares a context event, and the
      # menu after a long-press is the press's.
      assert report["cell"] == true
      assert report["early"] == 0
      assert report["after"] == true
      assert report["dot"] == false
      assert report["margin"] == false

      # Every gesture's push resolves to the one Visualize.Event.
      events =
        for push <- [right, pressed, keyed, shifted] do
          {:ok, click} = Event.decode(push)
          {:ok, event} = Event.resolve(click, applied)
          %{event | at: nil}
        end

      assert [%Event{event: "flag", row: %{row: 0, col: 1}} = event, event, event, event] = events
    end
  end

  test "a context name is declared beside the event, keys the elements and resolves" do
    html = render_component(Component, id: "grid", chart: applied())
    assert html =~ ~s(data-tooltip-context-event="flag")
    assert Event.declared(applied()) == ["dot", "flag", "open"]

    click = %{event: "flag", frame: "main", mark: 0, row: 4, drawn: nil, at: nil, modifiers: []}
    assert {:ok, %Event{event: "flag", row: %{row: 1, col: 1}}} = Event.resolve(click, applied())
    assert :error = Event.resolve(%{click | mark: 1}, applied())
  end

  test "a mark with only a context event keys its elements; one name for both is refused" do
    only =
      put_in(@design, [:marks, Access.at(0), :tooltip], %{fields: [:row], context_event: :flag})

    svg = Chart.render(applied(only, []))
    assert svg =~ ~s(data-frame="main" data-mark="0" data-tooltip-context-event="flag")
    assert svg =~ ~s(data-row="8")
    refute svg =~ ~s(data-mark="0" data-tooltip-event)

    same = put_in(@design, [:marks, Access.at(0), :tooltip, :context_event], "open")

    assert {:error, [{[:marks, 0, :tooltip, :context_event], {:same_name, :event}}]} =
             Chart.from_map(same)
  end
end
