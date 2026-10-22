defmodule Visualize.Hooks.ExecutedBuilderHookTest do
  @moduledoc """
  `BuilderHook` executed under node against the recording DOM stub (spec/12 §6, #458),
  over the stack panel's rows exactly as the builder renders them (#468).

  A drop's position is a flat position of the tree, read off the rows — the gap before a
  row is its `data-builder-layer`, the gap at the end the last row's `data-builder-end` —
  and never a count of the drawn rows, which falls short below a closed group (spec/14
  §18.17, spec/10 §16.2, D-75). Each scenario's push is handed back to the builder, so the
  test holds where the row lands, not only the number sent.
  """
  use ExUnit.Case, async: true

  import Visualize.JsHooks, only: [run: 1]

  alias Visualize.BuilderFixture
  alias Visualize.Chart.Builder
  alias Visualize.Chart.Builder.Stack

  @moduletag :js

  @row_height 20

  # house and shared grouped into "group 1" at 0 (its rows 1 and 2), panel at 3, and an
  # empty layer "layer 2" at 4, after panel.
  defp grouped(opts \\ []) do
    s = BuilderFixture.socket(BuilderFixture.layers(), opts)
    {:noreply, s} = Builder.handle_event("select_layer", %{"index" => "0"}, s)

    {:noreply, s} =
      Builder.handle_event("select_layer", %{"index" => "1", "extend" => "range"}, s)

    {:noreply, s} = Builder.handle_event("group_sites", %{"index" => "0"}, s)
    {:noreply, s} = Builder.handle_event("select_layer", %{"index" => "3"}, s)
    {:noreply, s} = Builder.handle_event("new_layer", %{}, s)
    assert BuilderFixture.names(s) == ["group 1", :house, :shared, :panel, "layer 2"]
    s
  end

  defp closed(s) do
    {:noreply, s} = Builder.handle_event("toggle_site", %{"index" => "0"}, s)
    s
  end

  # The stack panel's row elements as the builder rendered them: each `<li>`'s attributes,
  # in document order — the rows a browser would lay out, a closed group's not among them.
  defp rows(s) do
    html = BuilderFixture.render(s)

    for [tag] <- Regex.scan(~r/<li id="[^"]*-layers-row-\d+"[^>]*>/, html) do
      for [_, name, value] <- Regex.scan(~r/([\w-]+)="([^"]*)"/, tag),
          name in ~w(class data-builder-layer data-builder-end data-builder-into data-builder-parent draggable),
          into: %{},
          do: {name, value}
    end
  end

  # The rows laid out top to bottom, one row height each; the pointer is dragged from the
  # row at `from` (its index among the drawn rows) and dropped `dy` pixels below the top of
  # the drawn row `over`, or below the last row when `over` is the row count. What the hook
  # pushed is returned.
  defp drag(rows, from, over, dy \\ 2) do
    scenario = """
    const rows = #{Jason.encode!(rows)}.map((attributes, i) => {
      const row = Stub.markup('li', attributes, [Stub.markup('span', {class: 'vis-builder-layer-name'})]);
      row.rect = {top: i * #{@row_height}, left: 0, width: 200, height: #{@row_height}};
      return row;
    });
    const list = Stub.markup('ol', {class: 'vis-builder-layers', 'data-builder-stack': 'true'}, rows);
    const hook = Stub.mount(BuilderHook, list);
    const transfer = {types: [], setData() {}, getData() { return ''; }};
    const source = rows[#{from}].children[0];
    hook.handleDragStart({target: source, dataTransfer: transfer});
    const y = #{over * @row_height + dy};
    hook.handleDragOver({target: list, clientY: y, dataTransfer: transfer, preventDefault() {}});
    const marked = rows.findIndex((row) => row.classList.contains('vis-builder-layer-over'));
    const end = rows.findIndex((row) => row.classList.contains('vis-builder-layer-over-end'));
    Stub.mark('drop');
    hook.handleDrop({target: list, clientY: y, dataTransfer: transfer, preventDefault() {}});
    hook.handleDragEnd({});
    Stub.done({marked, end});
    """

    assert {:ok, %{"log" => log, "report" => report}} = run(scenario)
    {for(%{"kind" => "push", "name" => name, "payload" => p} <- log, do: {name, p}), report}
  end

  # A library entry named `name` dropped from outside the hook element — the library's own
  # instance started the drag — onto the drawn rows `dy` pixels below the top of the drawn
  # row `over`. What the hook pushed is returned; a throw fails the run.
  defp drop_entry(rows, over, dy, name) do
    scenario = """
    const rows = #{Jason.encode!(rows)}.map((attributes, i) => {
      const row = Stub.markup('li', attributes, [Stub.markup('span', {class: 'vis-builder-layer-name'})]);
      row.rect = {top: i * #{@row_height}, left: 0, width: 200, height: #{@row_height}};
      return row;
    });
    const list = Stub.markup('ol', {class: 'vis-builder-layers', 'data-builder-stack': 'true'}, rows);
    const hook = Stub.mount(BuilderHook, list);
    #{library_transfer(name)}
    const y = #{over * @row_height + dy};
    hook.handleDragOver({target: list, clientY: y, dataTransfer: transfer, preventDefault() {}});
    hook.handleDrop({target: list, clientY: y, dataTransfer: transfer, preventDefault() {}});
    hook.handleDragEnd({});
    Stub.done({});
    """

    assert {:ok, %{"log" => log}} = run(scenario)
    for %{"kind" => "push", "name" => event, "payload" => p} <- log, do: {event, p}
  end

  # What a drag from the library carries: the entry's name under its type, and nothing else.
  defp library_transfer(name) do
    """
    const transfer = {
      types: ['application/x-visualize-fragment'],
      setData() {},
      getData: (type) => type === 'application/x-visualize-fragment' ? #{Jason.encode!(name)} : ''
    };
    """
  end

  defp position(s, label) do
    # The flat position the server gives the row: its index in Stack.all/1.
    Enum.find_index(
      Stack.all(s.assigns.uses),
      &(to_string(Stack.label(s.assigns.labels, &1.use)) == label)
    )
  end

  describe "a drop below a closed group (#468)" do
    test "every drawn row carries its flat position and the position past what it holds" do
      s = closed(grouped())

      assert [
               %{"data-builder-layer" => "0", "data-builder-end" => "3"},
               %{"data-builder-layer" => "3", "data-builder-end" => "4"},
               %{"data-builder-layer" => "4", "data-builder-end" => "5"}
             ] = rows(s)

      open = rows(grouped())
      assert Enum.map(open, & &1["data-builder-layer"]) == ~w(0 1 2 3 4)
      assert Enum.map(open, & &1["data-builder-end"]) == ~w(3 2 3 4 5)
    end

    test "a row dropped between the closed group and the next row lands before that row, outside the group" do
      s = closed(grouped())
      panel = position(s, "panel")
      assert panel == 3

      # layer 2 (drawn third) dropped on the top of panel's row (drawn second).
      {pushes, report} = drag(rows(s), 2, 1)
      assert report["marked"] == 1
      assert pushes == [{"reorder", %{"from" => 4, "to" => panel}}]

      {:noreply, moved} = Builder.handle_event("reorder", %{"from" => 4, "to" => panel}, s)
      assert BuilderFixture.names(moved) == ["group 1", :house, :shared, "layer 2", :panel]
    end

    test "a group dropped directly below its own last row pushes nothing, open or closed" do
      # Open: the gap below shared (drawn third) is the top of panel's row (drawn fourth).
      # The gap is marked on panel's row, so nothing pushed is the no-op and not a hook that
      # read no rows.
      assert {[], %{"marked" => 3}} = drag(rows(grouped()), 0, 3)
      # Closed: the gap below the group's row is the top of panel's row (drawn second).
      assert {[], %{"marked" => 1}} = drag(rows(closed(grouped())), 0, 1)
    end

    test "a group dragged past the next row moves by the rows it holds" do
      s = grouped()
      # The open group dropped on the top of layer 2's row (drawn fifth): past panel.
      {pushes, _report} = drag(rows(s), 0, 4)
      assert pushes == [{"reorder", %{"from" => 0, "to" => 1}}]

      {:noreply, moved} = Builder.handle_event("reorder", %{"from" => 0, "to" => 1}, s)
      assert BuilderFixture.names(moved) == [:panel, "group 1", :house, :shared, "layer 2"]
    end

    test "the end of the stack is the last drawn row's end, and is marked on it" do
      s = closed(grouped())
      # panel dropped below everything: the gap at the end, past layer 2.
      {pushes, report} = drag(rows(s), 1, 3)
      assert report["end"] == 2
      assert pushes == [{"reorder", %{"from" => 3, "to" => 4}}]

      {:noreply, moved} = Builder.handle_event("reorder", %{"from" => 3, "to" => 4}, s)
      assert BuilderFixture.names(moved) == ["group 1", :house, :shared, "layer 2", :panel]
    end
  end

  # Every library drop read the entry's name through a method the frame drag's box had
  # replaced, and threw before it pushed (#923, spec/10 §16.3): each path is run here.
  describe "a library entry dropped is inserted (#923)" do
    test "on the stack at a gap, it pushes insert at that gap, and the builder inserts it there" do
      s = closed(grouped(store: BuilderFixture.Library))
      # On the top of panel's row (drawn second): the gap before panel, outside the group.
      assert [{"insert", %{"name" => "composite:1", "at" => 3} = push}] =
               drop_entry(rows(s), 1, 2, "composite:1")

      assert map_size(push) == 2

      {:noreply, added} = Builder.handle_event("insert", push, s)
      assert length(BuilderFixture.names(added)) == length(BuilderFixture.names(s)) + 1
      assert Enum.at(BuilderFixture.names(added), 4) == :panel
    end

    test "on the middle of a group's row, it pushes insert into that group" do
      s = grouped(store: BuilderFixture.Library)
      [%{"data-builder-into" => into} | _] = rows(s)

      assert [{"insert", %{"name" => "composite:1", "into" => ^into} = push}] =
               drop_entry(rows(s), 0, div(@row_height, 2), "composite:1")

      {:noreply, added} = Builder.handle_event("insert", push, s)
      assert length(BuilderFixture.names(added)) == length(BuilderFixture.names(s)) + 1
    end

    test "on a reference field, it pushes insert into that field" do
      scenario = """
      const field = Stub.markup('input', {'data-builder-ref': 'style'});
      const panel = Stub.markup('div', {'data-builder-scope': 'ref'}, [field]);
      const hook = Stub.mount(BuilderHook, panel);
      #{library_transfer("style:1")}
      hook.handleDragOver({target: field, dataTransfer: transfer, preventDefault() {}});
      hook.handleDrop({target: field, dataTransfer: transfer, preventDefault() {}});
      Stub.done({});
      """

      assert {:ok, %{"log" => log}} = run(scenario)

      assert [
               %{
                 "name" => "insert",
                 "payload" => %{"field" => "style", "name" => "style:1", "scope" => "ref"}
               }
             ] = Enum.filter(log, &(&1["kind"] == "push"))
    end

    test "on the graph, it pushes place at the chart point" do
      scenario = """
      const svg = Stub.markup('svg', {class: 'vis-builder-chart', viewBox: '0 0 400 200'});
      svg.rect = {left: 0, top: 0, width: 800, height: 400};
      const graph = Stub.markup('div', {'data-builder-scope': 'graph'}, [svg]);
      const hook = Stub.mount(BuilderHook, graph);
      #{library_transfer("composite:1")}
      hook.handleDragOver({target: svg, clientX: 200, clientY: 100, dataTransfer: transfer, preventDefault() {}});
      hook.handleDrop({target: svg, clientX: 200, clientY: 100, dataTransfer: transfer, preventDefault() {}});
      Stub.done({});
      """

      assert {:ok, %{"log" => log}} = run(scenario)

      assert [
               %{
                 "name" => "place",
                 "payload" => %{
                   "name" => "composite:1",
                   "x" => 100,
                   "y" => 50,
                   "scope" => "graph"
                 }
               }
             ] = Enum.filter(log, &(&1["kind"] == "push"))
    end
  end
end
