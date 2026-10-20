defmodule Visualize.Components.ChartTest do
  @moduledoc """
  A plain chart's clicks in LiveView (spec/10 §19.3, #627, D-170): the chart drawn inside
  `TooltipHook` targeted at its component with the drawing's token, a click on a keyed
  datum sent to the page as one `Visualize.Event` with its typed row, and a click on
  another drawing, an undeclared name or a key the drawing lacks dropped.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Phoenix.LiveView.Socket
  alias Visualize.Chart
  alias Visualize.Components.Chart, as: Component
  alias Visualize.Event

  @t0 ~U[2026-10-14 09:00:00Z]

  @design %{
    version: 2,
    sources: %{primary: %{fields: [:t, :service, :v]}},
    frames: %{
      main: %{kind: :cartesian, scales: %{x: %{kind: :time}, y: %{kind: :linear}}}
    },
    marks: [
      %{
        type: :circle,
        data: :primary,
        channels: %{x: :t, y: :v, series: :service},
        tooltip: %{fields: [:service, :v], event: :point_click}
      }
    ]
  }

  defp applied(rows \\ rows()) do
    {:ok, applied} = Chart.apply(@design, sources: %{primary: rows}, size: {300, 200})
    applied
  end

  defp rows, do: for(i <- 0..3, do: %{t: DateTime.add(@t0, i * 60), service: "api", v: i})

  # The component as LiveView holds it after an update: mounted once, then updated.
  defp updated(assigns) do
    {:ok, socket} = Component.mount(%Socket{assigns: %{__changed__: %{}}})
    updated(assigns, socket)
  end

  defp updated(assigns, socket) do
    {:ok, socket} = Component.update(assigns, socket)
    socket
  end

  defp params(drawn, overrides \\ %{}) do
    Map.merge(
      %{
        "event" => "point_click",
        "frame" => "main",
        "mark" => 0,
        "row" => 2,
        "drawn" => drawn,
        "at" => %{"x" => 140, "y" => 60},
        "modifiers" => ["shift"]
      },
      overrides
    )
  end

  test "renders the SVG inside TooltipHook targeted at itself, with the drawing's token" do
    html = render_component(Component, id: "sales", chart: applied(), render: [title: "Sales"])

    assert [_, target, drawn, hover] =
             Regex.run(
               ~r/<div id="sales" phx-hook="TooltipHook" data-tooltip-target="([^"]+)" data-tooltip-drawn="([^"]+)" data-tooltip-class="vis-tooltip" data-vis-hover="([^"]+)">/,
               html
             )

    assert target != "" and drawn != ""

    # The palette's :hover, resolved for the chart's frame (spec/10 §4.4, #638).
    assert hover ==
             "{&quot;stroke&quot;:&quot;#333333&quot;,&quot;stroke-width&quot;:&quot;2&quot;}"

    assert html =~ ~s(aria-label="Sales")
    refute html =~ "<title"
    assert html =~ ~s(data-frame="main" data-mark="0" data-tooltip-event="point_click")
    assert html =~ ~s(data-row="2")
  end

  # #803, D-201: a browser shows an SVG's <title> under the pointer, so the name is an
  # aria-label on every backend, and nothing in the markup is a <title>.
  test "every backend names the chart by aria-label and writes no <title>" do
    for opts <- [[], [backend: :canvas], [backend: :canvas, canvas_format: :json]] do
      html =
        render_component(
          Component,
          [id: "sales", chart: applied(), render: [title: "Sales"]] ++ opts
        )

      assert html =~ ~s(role="img"), inspect(opts)
      assert html =~ ~s(aria-label="Sales"), inspect(opts)
      refute html =~ "<title", inspect(opts)
    end
  end

  test "a click reaches the page as one Visualize.Event with its row typed" do
    socket = updated(%{id: "sales", chart: applied()})

    assert {:noreply, _} =
             Component.handle_event("visualize_event", params(socket.assigns.drawn), socket)

    t2 = DateTime.add(@t0, 120)

    assert_received {:visualize_event, "sales",
                     %Event{
                       event: "point_click",
                       cell: nil,
                       frame: "main",
                       item: {:circle, "api"},
                       path: [{:circle, "api"}],
                       row: %{t: ^t2, service: "api", v: 2},
                       at: %{x: _, y: _},
                       value: %{},
                       modifiers: [:shift]
                     }}
  end

  test "a click on a drawing no longer held, an undeclared name or a missing row is dropped" do
    socket = updated(%{id: "sales", chart: applied()})
    old = socket.assigns.drawn

    # The same chart again is the same drawing: a click in flight still resolves.
    same = updated(%{id: "sales", chart: applied()}, socket)
    assert same.assigns.drawn == old

    # New rows are a new drawing; a click on the old one is dropped, not re-resolved.
    moved = updated(%{id: "sales", chart: applied(Enum.reverse(rows()))}, socket)
    refute moved.assigns.drawn == old
    Component.handle_event("visualize_event", params(old), moved)

    drawn = moved.assigns.drawn
    Component.handle_event("visualize_event", params(drawn, %{"event" => "other"}), moved)
    Component.handle_event("visualize_event", params(drawn, %{"row" => 4}), moved)
    Component.handle_event("visualize_event", params(drawn, %{"mark" => 1}), moved)
    Component.handle_event("visualize_event", %{"event" => "point_click"}, moved)
    Component.handle_event("point_click", %{"v" => "2"}, moved)
    refute_received {:visualize_event, _, _}

    # On the drawing held the reversed rows resolve: ordinal 2 is now the second minute.
    Component.handle_event("visualize_event", params(drawn), moved)
    t1 = DateTime.add(@t0, 60)
    assert_received {:visualize_event, "sales", %Event{row: %{t: ^t1, v: 1}}}
  end

  # #813 (D-203 – D-206): what an update sends. A move is a new chart with one row changed.
  describe "a move (#813)" do
    alias Visualize.Hooks.{Keyboard, Tooltip}
    alias Visualize.Render.Segments

    @backends [
      svg: [],
      json: [backend: :canvas, canvas_format: :json],
      binary: [backend: :canvas]
    ]

    defp moved, do: rows() |> List.update_at(1, &%{&1 | v: 9})

    defp drawn_after_move(opts) do
      first = updated(Map.merge(%{id: "sales", chart: applied()}, Map.new(opts)))
      updated(Map.merge(%{id: "sales", chart: applied(moved())}, Map.new(opts)), first)
    end

    test "the segments are the drawing, and the points and the index are what they were whole" do
      for {name, opts} <- @backends do
        %{assigns: assigns} = drawn_after_move(opts)
        chart = applied(moved())

        case name do
          :svg ->
            assert Segments.text(assigns.segments, :svg) == Chart.render(chart, root: true)

          format ->
            tree = Chart.generate(chart, resolve: :literal)

            stream =
              Visualize.Render.to_string(tree,
                backend: :canvas,
                format: if(format == :json, do: :json, else: :binary_base64)
              )

            assert Segments.text(assigns.segments, format) == IO.iodata_to_binary(stream)
            assert assigns.items == Tooltip.items(tree)
        end

        # The points, one element each, are the points of data-keyboard-points.
        whole = Keyboard.attrs(chart)["data-keyboard-points"] |> Jason.decode!()
        listed = assigns.points |> Enum.map(&Jason.decode!(elem(&1, 1)))
        assert listed == Enum.flat_map(whole, & &1["points"])
      end
    end

    test "a click after a move resolves to the row drawn, on every backend" do
      for {_name, opts} <- @backends do
        socket = drawn_after_move(opts)
        params = params(socket.assigns.drawn, %{"row" => 1})
        assert {:noreply, _} = Component.handle_event("visualize_event", params, socket)
        assert_receive {:visualize_event, "sales", %Event{row: row}}
        assert row.v == 9
      end
    end

    test "the drawing is made apart, and the next is sized by it" do
      first = updated(%{id: "sales", chart: applied()})
      assert first.assigns.heap > 0
      second = updated(%{id: "sales", chart: applied(moved())}, first)
      assert second.assigns.heap > 0

      assert Segments.text(second.assigns.segments, :svg) ==
               Chart.render(applied(moved()), root: true)
    end
  end
end
