defmodule ExamplesWeb.InteractionLiveTest do
  @moduledoc """
  The interaction page's crosshairs sit on the series they snap to (#507, spec/10 §13.3).

  The hook tests hold `CrosshairHook` to the arrays it is given; this holds the arrays to
  the chart the page draws. For both demos — the crosshair over the SVG and the one over
  the binary canvas — and at two sizes, every point of `data-xs` × `data-ys`, offset by
  `data-plot`'s origin, is the vertex the line mark draws for the same row within a pixel:
  the SVG path's in the frame group's coordinates, the canvas stream's through its
  transform. And the canvas draws at the arrays' `data-size`, the `viewBox` of the SVG,
  since a stream draws one canvas pixel per chart unit.

  The legend chart names every series' points as it names their line (#508):
  `LegendHook` hides by `data-series`, so a point without it stayed drawn when its series
  was toggled off.
  """
  use ExUnit.Case, async: true

  import Phoenix.ConnTest, only: [build_conn: 0, init_test_session: 2, html_response: 2]

  alias Examples.Minesweeper
  alias ExamplesWeb.{InteractionLive, MotionDemo}
  alias Phoenix.LiveView.Socket
  alias Visualize.Components.Chart, as: Component

  @endpoint ExamplesWeb.Endpoint
  alias Visualize.Backend.CanvasBinary.Decoder

  # The page's own size, and a narrower one.
  @sizes [{720, 380}, {480, 320}]

  # The page as LiveView first renders it, its tooltip chart a live component (D-170), at
  # the size the session names.
  defp page(size) do
    build_conn()
    |> Plug.Conn.put_private(:phoenix_endpoint, @endpoint)
    |> init_test_session(%{})
    |> Phoenix.LiveView.Controller.live_render(InteractionLive, session: %{"size" => size})
    |> html_response(200)
  end

  # The opening tag of the element with `id`, and the markup after it.
  defp element(html, id) do
    [_, tag, rest] = Regex.run(~r/<div id="#{id}"([^>]*)>(.*)/s, html)
    {tag, rest}
  end

  defp attr(tag, name) do
    [_, value] = Regex.run(~r/\b#{name}="([^"]*)"/, tag)
    value
  end

  defp numbers(text) do
    ~r/-?\d+(?:\.\d+)?(?:e-?\d+)?/
    |> Regex.scan(text)
    |> Enum.map(fn [n] -> n |> Float.parse() |> elem(0) end)
  end

  # Each series' points in chart units, from the crosshair's attributes.
  defp crosshair_points(tag) do
    [left, top | _] = numbers(attr(tag, "data-plot"))
    xs = tag |> attr("data-xs") |> Jason.decode!()

    for ys <- Jason.decode!(attr(tag, "data-ys")) do
      for {x, y} <- Enum.zip(xs, ys), y != nil, do: {left + x, top + y}
    end
  end

  # The line mark's vertices per series in chart units: each path's moveto and curve
  # endpoints, offset by the frame group's translation.
  defp svg_vertices(svg) do
    [_, translate] = Regex.run(~r/<g class="frame" transform="translate\(([^)]+)\)"/, svg)
    [dx, dy] = numbers(translate)
    [_, mark] = Regex.run(~r/<g class="mark mark-line"[^>]*>(.*?)<\/g>/s, svg)

    for [_, d] <- Regex.scan(~r/<path[^>]* d="([^"]*)"/, mark) do
      for [_, args] <- Regex.scan(~r/[MLC]([^MLC]*)/, d) do
        [y, x | _] = args |> numbers() |> Enum.reverse()
        {dx + x, dy + y}
      end
    end
  end

  # The curves the canvas stream draws, per series, in canvas pixels: each cubic run's
  # start and endpoints through the translation in force.
  defp canvas_vertices(binary) do
    {_, runs} =
      binary
      |> Base.decode64!()
      |> Decoder.decode()
      |> Enum.reduce({[{0.0, 0.0}], []}, fn
        :save, {[t | _] = stack, runs} ->
          {[t | stack], runs}

        :restore, {[_ | stack], runs} ->
          {stack, runs}

        {:transform, :translate, {x, y}}, {[{tx, ty} | stack], runs} ->
          {[{tx + x, ty + y} | stack], runs}

        {:cubic_run, {x0, y0}, curves}, {[{tx, ty} | _] = stack, runs} ->
          points = [{x0, y0} | Enum.map(curves, fn {_, _, _, _, x, y} -> {x, y} end)]
          {stack, [Enum.map(points, fn {x, y} -> {tx + x, ty + y} end) | runs]}

        _record, acc ->
          acc
      end)

    Enum.reverse(runs)
  end

  defp assert_on(points, vertices, demo) do
    assert length(points) == length(vertices), "#{demo}: one array per drawn series"

    for {series, drawn} <- Enum.zip(points, vertices) do
      assert length(series) == length(drawn), "#{demo}: one point per drawn vertex"

      for {{px, py}, {vx, vy}} <- Enum.zip(series, drawn) do
        assert abs(px - vx) <= 1 and abs(py - vy) <= 1,
               "#{demo}: crosshair point #{inspect({px, py})} is not the drawn vertex #{inspect({vx, vy})}"
      end
    end
  end

  for {width, height} <- @sizes do
    @size {width, height}

    test "at #{width}x#{height} the SVG crosshair's points are the drawn vertices" do
      {tag, rest} = page(@size) |> element("crosshair-svg")
      [svg] = Regex.run(~r/<svg.*?<\/svg>/s, rest)

      assert attr(svg, "viewBox") == "0 0 #{elem(@size, 0)} #{elem(@size, 1)}"
      assert attr(tag, "data-size") == "#{elem(@size, 0)},#{elem(@size, 1)}"
      assert_on(crosshair_points(tag), svg_vertices(svg), "svg")
    end

    test "at #{width}x#{height} the canvas crosshair's points are the drawn vertices" do
      {tag, rest} = page(@size) |> element("crosshair-canvas")
      {canvas, _} = element(rest, "crosshair-canvas-chart")

      # The stream draws at one canvas pixel per chart unit: the canvas is the frame's size.
      assert "#{attr(canvas, "data-width")},#{attr(canvas, "data-height")}" ==
               attr(tag, "data-size")

      assert attr(tag, "data-size") == "#{elem(@size, 0)},#{elem(@size, 1)}"
      assert_on(crosshair_points(tag), canvas_vertices(attr(canvas, "data-binary")), "canvas")
    end
  end

  test "the legend chart's every line, point and entry names one of the three series (#508)" do
    {_tag, rest} = page({720, 380}) |> element("legend-chart")
    [chart] = Regex.run(~r/<svg.*?<\/svg>/s, rest)
    series = ~w(alpha beta gamma)

    circles = Regex.scan(~r/<circle\b[^>]*>/, chart) |> List.flatten()
    named = for c <- circles, [_, s] <- Regex.scan(~r/data-series="([^"]+)"/, c), do: s

    # A point per hour per series, each naming its series.
    assert length(circles) == 24 * 3
    assert Enum.frequencies(named) == Map.new(series, &{&1, 24})

    for s <- series do
      assert chart =~ ~r/<path\b[^>]*data-series="#{s}"/
      assert chart =~ ~s(class="legend-item" data-series="#{s}")
    end
  end

  test "a click on a point reaches the page as one Visualize.Event, its row typed (D-170)" do
    {tag, rest} = page({720, 380}) |> element("tooltip-chart")
    assert tag =~ ~s(phx-hook="TooltipHook")
    assert tag =~ ~r/data-tooltip-drawn="\d+"/
    assert rest =~ ~s(data-frame="main" data-mark="1" data-tooltip-event="point_click")

    # The component resolves a point's key against the chart it drew: the circles' rows
    # are the page's rows, the fifth beta at hour 1.
    %{applied: applied} = InteractionLive.build({720, 380})

    click = %{
      event: "point_click",
      frame: "main",
      mark: 1,
      row: 4,
      drawn: nil,
      at: nil,
      modifiers: []
    }

    assert {:ok, %Visualize.Event{row: %{series: "beta", hour: 1, value: value} = row} = event} =
             Visualize.Event.resolve(click, applied)

    assert is_float(value)
    assert event.item == {:circle, "beta"}

    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, picked: nil}}

    assert {:noreply, %{assigns: %{picked: {"beta", 1, ^value}}}} =
             InteractionLive.handle_info(
               {:visualize_event, "tooltip-chart", %{event | row: row}},
               socket
             )
  end

  # The motion demo (#653): its bars name their services, change state with a fade, pulse
  # in error and explode when deleted, through MotionHook around the chart's SVG.
  test "the motion demo's bars carry their identities and leave by exploding, through MotionHook" do
    {tag, rest} = page({720, 380}) |> element("motion-chart")
    assert tag =~ ~s(phx-hook="TooltipHook")
    assert rest =~ ~s(<div id="motion-chart-motion" phx-hook="MotionHook">)
    assert rest =~ ~s(data-vis-id="main.1.name=db")
    assert rest =~ "data-vis-exit=\"[&quot;explode&quot;,800,"
    assert rest =~ "vis-enter-"
    assert rest =~ "@keyframes vis-enter-grow"

    rows = MotionDemo.rows()
    errored = rows |> MotionDemo.next_state(0) |> MotionDemo.next_state(0)
    assert hd(errored).state == :error

    svg = Visualize.Chart.render(MotionDemo.applied(errored, {720, 380}), root: true)
    assert svg =~ "@keyframes vis-pulse"
    assert svg =~ ~r/<g class="vis-animation-[0-9a-z]+"><rect/

    # A click on a bar is the page's delete: the row goes, and the chart with it.
    socket = %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, motion_rows: rows, motion_turn: 0, size: {720, 380}}
    }

    event = %Visualize.Event{event: "delete", row: %{name: "db", load: 0, state: :ok}}

    assert {:noreply, %{assigns: %{motion_rows: left, motion_chart: chart}}} =
             InteractionLive.handle_info({:visualize_event, "motion-chart", event}, socket)

    assert Enum.map(left, & &1.name) == Enum.map(rows, & &1.name) -- ["db"]
    refute Visualize.Chart.render(chart) =~ ~s(data-vis-id="main.1.name=db")
  end

  # The animations (#677, #786): every built-in with its own timing, the page's own
  # keyframes by name, and every animation off for a reader who asks for less motion.
  test "the animations panel runs every built-in and the page's keyframes, and stops for reduced motion" do
    html = page({720, 380})
    {_tag, rest} = element(html, "animations-chart-0")

    for name <- ~w(pulse blink shake spin), do: assert(rest =~ "@keyframes vis-#{name}", name)
    assert rest =~ "animation: vis-blink 800ms linear 400ms 3;"
    assert rest =~ "animation: vis-spin 3000ms linear 0ms infinite;"
    assert rest =~ ~r/animation: vis-shake 700ms linear\([^)]*\) 200ms 4;/
    # The host's keyframes are named as written, and the page defines them.
    assert rest =~ "animation: wiggle 900ms "
    assert html =~ "@keyframes wiggle {"
    assert rest =~ "@media (prefers-reduced-motion: reduce)"
    assert rest =~ ~s([class*="vis-animation-"] { animation: none !important; })

    # Replay remounts the chart under a new id, so the browser starts every animation over.
    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, animations_run: 0}}

    assert {:noreply, %{assigns: %{animations_run: 1}}} =
             InteractionLive.handle_event("animations_replay", %{}, socket)
  end

  # The Minesweeper panel (#800): the game of `/minesweeper` played in place. Seed 42 opened
  # at the center, the layout `Examples.MinesweeperTest` holds exactly.
  @mines_seed 42
  @mines_first {4, 4}

  defp mines_page do
    {:ok, socket} =
      InteractionLive.mount(%{}, %{"mines_seed" => @mines_seed}, %Socket{
        assigns: %{__changed__: %{}}
      })

    socket
  end

  # A move on the cell `{r, c}` as `TooltipHook` or `KeyboardHook` pushes it on the panel's
  # chart — the rect mark (the frame's first), the cell's ordinal among the rows, and the
  # token of the drawing it landed on — resolved by the component, and its message handled
  # by the page. `event` is `"flag"` for a right-click, a long-press or the Menu key.
  defp mines_move(socket, {r, c}, event \\ "cell_click", modifiers \\ []) do
    {:ok, component} = Component.mount(%Socket{assigns: %{__changed__: %{}}})

    {:ok, component} =
      Component.update(%{id: "mines-panel-chart", chart: socket.assigns.mines_chart}, component)

    params = %{
      "event" => event,
      "frame" => "main",
      "mark" => 0,
      "row" => r * 9 + c,
      "drawn" => component.assigns.drawn,
      "modifiers" => modifiers
    }

    {:noreply, _component} = Component.handle_event("visualize_event", params, component)
    assert_receive {:visualize_event, "mines-panel-chart", event} = message
    assert event.item == {:rect, %{"row" => r, "col" => c}}
    {:noreply, socket} = InteractionLive.handle_info(message, socket)
    socket
  end

  defp mines_layout, do: Minesweeper.reveal(Minesweeper.new(seed: @mines_seed), @mines_first)

  # The status line as the panel renders it, without the full page's clock.
  defp render_status(game) do
    %{game: game, elapsed: nil}
    |> ExamplesWeb.MinesweeperLive.status()
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  test "the Minesweeper panel draws the grid at the page's chart height, with its status, New game and the full page" do
    html = page({720, 380})
    {tag, rest} = element(html, "mines-panel-chart")
    assert tag =~ ~s(phx-hook="TooltipHook")
    assert rest =~ ~s(data-tooltip-event="cell_click" )
    assert rest =~ ~s(data-tooltip-context-event="flag")
    # Nothing follows the pointer (#803): no hover text or outline (D-200), and the chart
    # is named by aria-label rather than a <title> the browser shows on hover (D-201).
    assert rest =~ ~s(data-tooltip-show="false")
    [svg] = Regex.run(~r/<svg [^>]*>/, rest)
    assert svg =~ ~s(aria-label="Minesweeper")
    refute rest =~ "<title"
    # One tab stop whose cells the arrows reach by row and column (D-198).
    {keys, _rest} = element(html, "mines-panel-chart-keys")
    assert keys =~ ~s(phx-hook="KeyboardHook")
    assert keys =~ "&quot;grid&quot;:true"
    assert length(Regex.scan(~r/<rect data-datum="state count"/, rest)) == 81
    assert rest =~ ~s(viewBox="0 0 380 380")

    [{_id, body}] = Enum.filter(panels(html), &(elem(&1, 0) == "panel-minesweeper"))
    assert body =~ "10 mines left"
    assert body =~ "Click any cell to start"
    refute body =~ "mines-time"

    assert body =~
             ~s(<button type="button" class="backend-btn" phx-click="mines_new">New game</button>)

    assert body =~ ~s(<a href="/minesweeper">)
    assert body =~ "<code>context_event</code>"
    assert body =~ "<code>KeyboardHook</code>"
    assert html =~ ".mines-board .mark-text, .mines-board .mark-symbol { pointer-events: none; }"

    # At a narrower page the grid is drawn square at its height.
    assert page({480, 320}) |> element("mines-panel-chart") |> elem(1) =~
             ~s(viewBox="0 0 320 320")
  end

  test "the Minesweeper panel plays a seeded game to a win in place" do
    game = mines_layout()
    socket = mines_move(mines_page(), @mines_first)
    assert socket.assigns.mines_game.status == :playing

    # A flag, by the context event, comes off again; Shift held flags as well.
    socket = mines_move(socket, {0, 0}, "flag")
    assert Minesweeper.mines_left(socket.assigns.mines_game) == 9
    socket = mines_move(socket, {0, 0}, "cell_click", ["shift"])
    assert Minesweeper.mines_left(socket.assigns.mines_game) == 10

    safe = for cell <- Minesweeper.cells(game), not Minesweeper.mine?(game, cell), do: cell
    socket = Enum.reduce(safe, socket, &mines_move(&2, &1))

    assert socket.assigns.mines_game.status == :won
    assert render_status(socket.assigns.mines_game) =~ "Cleared: you won"
    assert render_status(socket.assigns.mines_game) =~ "0 mines left"
  end

  test "the Minesweeper panel plays a seeded game to a loss, and New game starts another" do
    socket =
      mines_page()
      |> mines_move(@mines_first)
      |> mines_move({1, 1}, "flag")
      |> mines_move({0, 0})

    assert socket.assigns.mines_game.status == :lost
    assert render_status(socket.assigns.mines_game) =~ "Boom: you lost"
    svg = Visualize.Chart.render(socket.assigns.mines_chart, root: true)
    assert svg =~ ~s(data-datum-state="exploded")

    {:noreply, socket} = InteractionLive.handle_event("mines_new", %{}, socket)
    assert socket.assigns.mines_game.status == :ready
    assert render_status(socket.assigns.mines_game) =~ "Click any cell to start"
  end

  # Every demo's panel, its heading and the id of the chart it holds (#505); the code
  # section holds its markup in place of a chart.
  @panels [
    {"panel-tooltip", "Tooltip", "tooltip-chart"},
    {"panel-crosshair-svg", "Crosshair over the SVG", "crosshair-svg"},
    {"panel-crosshair-canvas", "Crosshair over the canvas", "crosshair-canvas"},
    {"panel-legend", "Legend toggling", "legend-chart"},
    {"panel-motion", "Motion by identity", "motion-chart"},
    {"panel-animations", "Animations", "animations-chart-0"},
    {"panel-force", "A simulation, live", "force-graph"},
    {"panel-minesweeper", "Minesweeper", "mines-panel-chart"},
    {"panel-code", "The design and the markup", nil}
  ]

  defp panels(html) do
    for [_, id, body] <-
          Regex.scan(~r/<section id="([^"]+)" class="panel(?: [^"]*)?">(.*?)<\/section>/s, html),
        do: {id, body}
  end

  test "the demos are a row of panels each as wide as its chart; the code takes a row (#513)" do
    html = page({720, 380})
    {width, _height} = hd(@sizes)

    assert InteractionLive.panel_width() == "--chart-w: #{width}px"
    assert html =~ ~s(<main class="main-wide">)
    assert html =~ ~s(<div class="panels panels-row" style="--chart-w: #{width}px">)
    assert html =~ ~s(<section id="panel-code" class="panel panel-wide">)

    for {id, _, chart} <- @panels, chart do
      assert html =~ ~s(<section id="#{id}" class="panel">), "#{id}: a chart-wide panel"
    end
  end

  test "each demo is one panel holding its heading, its explanation and its chart (#505)" do
    found = panels(page({720, 380}))

    assert Enum.map(found, &elem(&1, 0)) == Enum.map(@panels, &elem(&1, 0))

    for {{id, body}, {id, heading, chart}} <- Enum.zip(found, @panels) do
      assert body =~ ~s(<h2 class="panel-title">#{heading}</h2>), "#{id}: its heading"
      assert body =~ ~s(<p class="panel-note">), "#{id}: its explanation"

      if chart,
        do: assert(body =~ ~s(<div id="#{chart}"), "#{id}: its chart"),
        else: assert(body =~ ~s(<pre><code class="highlight), "#{id}: its markup")
    end

    # Every chart sits in exactly one panel.
    for {_, _, chart} <- @panels, chart do
      assert Enum.count(found, fn {_, body} -> body =~ ~s(<div id="#{chart}") end) == 1
    end
  end

  for {width, height} <- @sizes do
    @size {width, height}

    test "at #{width}x#{height} every SVG demo's legend sits right of the plot, inside the chart" do
      html = page(@size)
      {crosshair, _} = element(html, "crosshair-svg")
      [left, _top, plot_width, _plot_height] = numbers(attr(crosshair, "data-plot"))

      for id <- ~w(tooltip-chart crosshair-svg legend-chart) do
        {_tag, rest} = element(html, id)
        [svg] = Regex.run(~r/<svg.*?<\/svg>/s, rest)

        [_, translate] =
          Regex.run(~r/<g class="legend"[^>]* transform="translate\(([^)]+)\)"/, svg)

        # The legend group is placed in the frame group's coordinates, the plot's origin.
        [x, _y] = numbers(translate)

        assert x >= plot_width,
               "#{id}: the legend at x #{x} is over the plot (width #{plot_width})"

        # Its estimated width (spec/14 §4.5) ends inside the chart's own width.
        assert left + x + 67.2 <= elem(@size, 0), "#{id}: the legend runs off the chart"
      end
    end
  end
end
