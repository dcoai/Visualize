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
    assert [%{scale: :y, side: :left}] = for(%{local: %{axis: a}} <- s.assigns.uses, do: a)
  end
end
