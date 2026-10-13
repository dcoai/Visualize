defmodule Visualize.Hooks.ExecutedBuilderFramesHookTest do
  @moduledoc """
  `BuilderHook` in scope `graph` executed under node against the recording DOM stub
  (spec/12 §6, spec/10 §16.3), over the chart's `<svg>` exactly as the builder renders it
  for a design of several frames (spec/14 §18.4, §18.16, #386).

  The hook reads a point in the frame under it from `data-builder-frames`; each push is
  handed back to the builder, so the test holds what the drop became, not only the numbers
  sent.
  """
  use ExUnit.Case, async: true

  import Visualize.JsHooks, only: [run: 1]

  alias Visualize.BuilderFixture
  alias Visualize.Chart.Builder
  alias Visualize.Chart.Builder.Writes

  @moduletag :js

  # The builder over two frames side by side, measured at 800 × 400.
  defp measured do
    s = BuilderFixture.socket(BuilderFixture.two_frames())
    {:noreply, s} = Builder.handle_event("graph_size", %{"width" => 800, "height" => 400}, s)
    s
  end

  # The chart's `<svg>` attributes as the builder rendered them.
  defp svg(s) do
    [tag] = Regex.run(~r/<svg class="vis-builder-chart"[^>]*>/, BuilderFixture.render(s))

    for [_, name, value] <- Regex.scan(~r/([\w-]+)="([^"]*)"/, tag),
        into: %{},
        do: {name, value}
  end

  # The graph built around the rendered `<svg>`, drawn at its own size from (0, 0), the
  # hook mounted on it, and `steps` run over `graph`, `svg` and `hook`. The log's pushes and
  # the scenario's report are returned.
  defp scenario(svg, steps) do
    source = """
    const svg = Stub.markup('svg', #{Jason.encode!(svg)});
    svg.rect = {left: 0, top: 0, width: #{svg["width"]}, height: #{svg["height"]}};
    const graph = Stub.markup('div', {'data-builder-scope': 'graph', 'data-builder-target': '1'}, [svg]);
    const hook = Stub.mount(BuilderHook, graph);
    const component = (word) => ({types: ['application/x-visualize-component'], getData: (t) => t === 'application/x-visualize-component' ? word : ''});
    const over = (x, y, word) => hook.handleDragOver({target: svg, clientX: x, clientY: y, dataTransfer: component(word), preventDefault() {}});
    const drop = (x, y, word) => hook.handleDrop({target: svg, clientX: x, clientY: y, dataTransfer: component(word), preventDefault() {}});
    const region = () => ['top', 'bottom', 'left', 'right', 'plot'].find((r) => graph.classList.contains('vis-builder-region-' + r)) || null;
    const report = {};
    #{Enum.join(steps, "\n")}
    Stub.done(report);
    """

    assert {:ok, %{"log" => log, "report" => report}} = run(source)
    {for(%{"kind" => "push", "name" => name, "payload" => p} <- log, do: {name, p}), report}
  end

  test "a point is read in the frame under it: the second frame's own margin is its left band" do
    s = measured()
    attrs = svg(s)

    assert attrs["data-builder-frames"] ==
             "history 0 0 400 400 20 20 30 40;now 400 0 400 400 20 20 30 40"

    {pushes, report} =
      scenario(attrs, [
        # 10 px into `now`: inside its 40 px left margin.
        "over(410, 200, 'axis'); report.inside_now = region();",
        # Far into `now`'s plot.
        "over(600, 200, 'axis'); report.plot = region();",
        # Inside `history`'s right margin, just short of the shared edge.
        "over(390, 200, 'axis'); report.history_right = region();",
        "drop(410, 200, 'axis'); report.after = region();"
      ])

    assert report == %{
             "inside_now" => "left",
             "plot" => "plot",
             "history_right" => "right",
             "after" => nil
           }

    assert [{"place", %{"component" => "axis", "x" => 410, "y" => 200} = payload}] = pushes

    # Handed back: the server reads the same point in the same frame, a y axis on the left.
    {:noreply, s} = Builder.handle_event("place", payload, s)
    assert Writes.composed(s).frames.now.axes == [%{scale: :y, side: :left}]
  end

  # -- frames placed on the graph (spec/14 §18.16, #614) ---------------------------------

  # The builder measured at 800 × 400 with `history` at the left 0.4 and `now` a quarter
  # wide and half high at 0.6, `frame` open.
  defp placed(open) do
    s = measured()

    {:noreply, s} =
      Builder.handle_event("frame_box", %{"frame" => "history", "box" => [0, 0, 0.4, 1]}, s)

    {:noreply, s} =
      Builder.handle_event("frame_box", %{"frame" => "now", "box" => [0.6, 0, 0.25, 0.5]}, s)

    {:noreply, s} = Builder.handle_event("pick", %{"node" => open}, s)
    s
  end

  # The chart's whole `<svg>` as the builder rendered it — its drawn nodes and the open
  # frame's overlay — built as the stub's tree in a graph at (0, 0), and `steps` run over
  # `graph`, `svg`, `hook`, `handle(at)`, `down`, `move`, `up` and `key`.
  defp drawn(s, steps) do
    [svg] = Regex.run(~r/<svg class="vis-builder-chart".*?<\/svg>/s, BuilderFixture.render(s))

    source = """
    const svg = #{Visualize.JsHooks.markup(svg)};
    svg.rect = {left: 0, top: 0, width: 800, height: 400};
    const graph = Stub.markup('div', {'data-builder-scope': 'graph', 'data-builder-target': '1'}, [svg]);
    const hook = Stub.mount(BuilderHook, graph);
    const handle = (at) => svg.querySelectorAll('[data-builder-frame-handle]').find((h) => h.getAttribute('data-builder-frame-handle') === at);
    const down = (target, x, y) => hook.handlePointerDown({target, button: 0, clientX: x, clientY: y});
    const move = (x, y) => graph.fire('pointermove', {clientX: x, clientY: y});
    const up = () => graph.fire('pointerup', {});
    const click = (target, x, y) => hook.handleClick({target, clientX: x, clientY: y});
    const key = (k, shift) => hook.handleKeyDown({target: graph, key: k, shiftKey: !!shift, preventDefault() {}});
    const report = {};
    #{Enum.join(steps, "\n")}
    Stub.done(report);
    """

    assert {:ok, %{"log" => log, "report" => report}} = run(source)
    {for(%{"kind" => "push", "name" => name, "payload" => p} <- log, do: {name, p}), report}
  end

  defp handed(s, pushes) do
    Enum.reduce(pushes, s, fn {name, payload}, s ->
      {:noreply, s} = Builder.handle_event(name, payload, s)
      s
    end)
  end

  defp box(s, frame),
    do: Enum.find_value(s.assigns.uses, &get_in(&1.local, [:frames, frame, :box]))

  test "a click on a frame's empty space picks the frame; on a drawn node, the node" do
    s = placed("marks[0]")

    {pushes, _} =
      drawn(s, [
        "click(svg, 600, 100);",
        "click(svg, 790, 390);",
        "click(svg.querySelector('[data-node]'), 10, 10);"
      ])

    # (790, 390) is in no frame: nothing.
    assert [{"pick", %{"node" => "frames.now"}}, {"pick", %{"node" => "frames.history"}}] =
             pushes
  end

  test "the open frame dragged by its body snaps its edge to the other frame's and is pushed as fractions" do
    s = placed("frames.now")

    {pushes, report} =
      drawn(s, [
        "down(svg, 600, 100);",
        # 157 px left: x 0.40375, within 8 px of `history`'s right edge at 0.4.
        "move(443, 100);",
        "report.outline = svg.querySelector('.vis-builder-frame-outline').getAttribute('x');",
        "up();",
        # The click the browser fires after the drag picks nothing.
        "click(svg, 443, 100);"
      ])

    assert report == %{"outline" => "320"}
    assert [{"frame_box", %{"frame" => "now", "box" => [0.4, 0, 0.25, 0.5]}}] = pushes
    assert box(handed(s, pushes), :now) == [0.4, 0, 0.25, 0.5]
  end

  test "a corner handle resizes, the dragged edges snapping to a half and to the edge" do
    s = placed("frames.now")

    {pushes, _} =
      drawn(s, [
        "down(handle('se'), 680, 200);",
        # The right edge to 0.995 and the bottom to 0.6575: snapped to 1 and to 2/3.
        "move(796, 263);",
        "up();"
      ])

    assert [{"frame_box", %{"frame" => "now", "box" => [0.6, 0, 0.4, h]}}] = pushes
    assert_in_delta h, 2 / 3, 0.0001
    assert [0.6, 0, 0.4, _] = box(handed(s, pushes), :now)

    # The north-west corner: the left edge to the third, the top stays.
    {pushes, _} = drawn(s, ["down(handle('nw'), 480, 0);", "move(270, 0);", "up();"])
    assert [{"frame_box", %{"box" => [x, 0, w, 0.5]}}] = pushes
    assert_in_delta x, 1 / 3, 0.0001
    assert_in_delta w, 0.85 - 1 / 3, 0.0001
  end

  test "a press that does not travel pushes no box, and only the open frame drags" do
    {pushes, _} =
      drawn(placed("frames.now"), ["down(svg, 600, 100);", "move(601, 101);", "up();"])

    assert pushes == []

    # `history` is not open: a press on it starts nothing.
    {pushes, _} =
      drawn(placed("frames.now"), ["down(svg, 100, 100);", "move(200, 100);", "up();"])

    assert pushes == []
  end

  test "arrows move the open frame a twelfth, Shift with an arrow stretches it" do
    s = placed("frames.now")
    {pushes, _} = drawn(s, ["key('ArrowLeft');", "key('ArrowDown', true);"])

    assert [
             {"frame_box", %{"frame" => "now", "box" => [x, 0, 0.25, 0.5]}},
             {"frame_box", %{"frame" => "now", "box" => [0.6, 0, 0.25, h]}}
           ] = pushes

    assert_in_delta x, 0.6 - 1 / 12, 0.0001
    assert_in_delta h, 0.5 + 1 / 12, 0.0001
  end
end
