defmodule ExamplesWeb.MinesweeperLiveTest do
  @moduledoc """
  The `/minesweeper` page (#758) played through its chart. Each move is a click on a cell
  as `TooltipHook` pushes it — the cell's mark and row ordinal, and the token of the
  drawing it landed on — handed to the page's `Visualize.Components.Chart`, which resolves
  it to a `Visualize.Event` whose item is the cell's declared identity (D-167, D-170) and
  sends it to the page, whose clause makes the next game. A seeded game is played so to a
  win and to a loss, on SVG, the JSON canvas and the binary canvas: a click resolves to
  the same event on each (D-197). A right-click, a long-press or the Menu key sends
  `flag` (D-199), which flags in either mode.

  The examples carry no LiveView test DOM, so the page and its component are driven as
  LiveView drives them — mount, update, the event, the message — as the other pages'
  tests do; the page's markup is read from its first, disconnected render.
  """
  use ExUnit.Case, async: true

  doctest ExamplesWeb.MinesweeperLive

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Examples.Minesweeper
  alias ExamplesWeb.MinesweeperLive
  alias Phoenix.LiveView.Socket
  alias Visualize.Components.Chart, as: Component

  @endpoint ExamplesWeb.Endpoint

  # Seed 42 opened at the center; `Examples.MinesweeperTest` holds its layout exactly.
  @seed 42
  @first {4, 4}

  defp page(mode \\ "reveal") do
    {:ok, socket} =
      MinesweeperLive.mount(%{"seed" => "#{@seed}"}, %{}, %Socket{assigns: %{__changed__: %{}}})

    {:noreply, socket} = MinesweeperLive.handle_event("mode", %{"mode" => mode}, socket)
    socket
  end

  # A click on the cell `{r, c}`: the page's chart drawn by its component, the click the
  # hook sends on that drawing — the rect mark (the frame's first) and the cell's ordinal
  # among the rows, row by row — resolved by the component, and its message handled by the
  # page. `modifiers` are the keys held; `event` is `"flag"` for a secondary gesture.
  defp click(socket, {r, c}, modifiers \\ [], event \\ "cell_click") do
    component = drawn(socket)

    params = %{
      "event" => event,
      "frame" => "main",
      "mark" => 0,
      "row" => r * socket.assigns.game.cols + c,
      "drawn" => component.assigns.drawn,
      "modifiers" => modifiers
    }

    {:noreply, _component} = Component.handle_event("visualize_event", params, component)
    assert_receive {:visualize_event, "mines-chart", event} = message
    assert event.item == {:rect, %{"row" => r, "col" => c}}
    {:noreply, socket} = MinesweeperLive.handle_info(message, socket)
    socket
  end

  defp drawn(socket) do
    {:ok, component} = Component.mount(%Socket{assigns: %{__changed__: %{}}})

    {:ok, component} = Component.update(assigns(socket), component)
    component
  end

  # The component's assigns as the page renders them, on the page's backend.
  defp assigns(socket) do
    {_name, _label, opts} =
      Enum.find(MinesweeperLive.backends(), &(elem(&1, 0) == socket.assigns.backend))

    Map.merge(%{id: "mines-chart", chart: socket.assigns.chart}, Map.new(opts))
  end

  defp on(socket, backend) do
    {:noreply, socket} = MinesweeperLive.handle_event("backend", %{"backend" => backend}, socket)
    socket
  end

  # The game the page plays, opened as the page opens it, to read the layout from.
  defp layout, do: Minesweeper.reveal(Minesweeper.new(seed: @seed), @first)

  # Each cell's state, as the chart drew it: the rect's datum, found by its row ordinal.
  defp states(socket) do
    svg = Visualize.Chart.render(socket.assigns.chart, root: true)

    for [_, state, i] <- Regex.scan(~r/data-datum-state="([a-z]+)" data-row="(\d+)"/, svg),
        into: %{} do
      i = String.to_integer(i)
      cols = socket.assigns.game.cols
      {{div(i, cols), rem(i, cols)}, state}
    end
  end

  test "the page draws the grid as a design, every cell a declared identity" do
    html = build_conn() |> get("/minesweeper?seed=#{@seed}") |> html_response(200)

    assert html =~ ~s(<h2 class="panel-title">Minesweeper</h2>)
    assert html =~ ~s(id="mines-chart" phx-hook="TooltipHook")
    assert html =~ ~s(data-tooltip-event="cell_click")
    assert html =~ "10 mines left"
    assert html =~ "Click any cell to start"
    assert html =~ ~s(phx-value-mode="flag")
    assert html =~ "New game"

    # 81 cells, each keyed to its row and carrying its identity, row and column together;
    # the motion it has plays through MotionHook.
    assert length(Regex.scan(~r/<rect data-datum="state count"/, html)) == 81
    assert html =~ ~s(data-vis-id="main.1.col=4&amp;row=4")
    assert html =~ ~s(phx-hook="MotionHook")
  end

  # #806: the buttons are the site's segmented control, its style in the layout's
  # stylesheet, and each toggle group marks its current option for the eye and for a
  # screen reader.
  test "the buttons are the site's, and each toggle marks its current option" do
    html = build_conn() |> get("/minesweeper?seed=#{@seed}") |> html_response(200)

    buttons = Regex.scan(~r/<button [^>]*>/, html) |> List.flatten()
    assert buttons != []
    assert Enum.all?(buttons, &(&1 =~ ~s(class="backend-btn))), inspect(buttons)

    pressed = fn value ->
      [tag] = Enum.filter(buttons, &(&1 =~ ~s(="#{value}")))
      {tag =~ "backend-btn active", Regex.run(~r/aria-pressed="(\w+)"/, tag) |> List.last()}
    end

    assert pressed.("reveal") == {true, "true"}
    assert pressed.("flag") == {false, "false"}
    assert pressed.("svg") == {true, "true"}
    assert pressed.("binary") == {false, "false"}
    assert html =~ ~s(<button type="button" class="backend-btn" phx-click="new">New game</button>)

    # The style is the layout's, shared with the chart page, with a hover and a focus ring.
    assert html =~ ".backend-btn.active {"
    assert html =~ ".backend-btn:hover {"
    assert html =~ ".backend-btn:focus-visible {"
  end

  # #803: nothing follows the pointer over the grid. The page's chart, drawn by its
  # component on each backend, runs under the library's hook harness (spec/12 §6): a
  # pointer over a cell shows no tooltip and no outline (D-200), the markup holds no
  # <title> a browser would show on hover (D-201), and the click and the flag still push.
  @tag :js
  test "nothing follows the pointer over the grid on every backend; clicks and flags push" do
    for {backend, _label, _opts} <- MinesweeperLive.backends() do
      html = render_component(Component, assigns(on(page(), backend)))
      svg? = backend == "svg"

      refute html =~ "<title", backend
      assert html =~ ~s(aria-label="Minesweeper"), backend

      scenario = """
      const el = #{Visualize.JsHooks.markup(html)};
      const chart = el.querySelector('svg') || el.querySelector('canvas');
      chart.rect = {left: 0, top: 0, width: 500, height: 500};
      const tipEl = el.querySelector('[data-tooltip-drawn]');
      const hook = Stub.mount(TooltipHook, tipEl);
      // The cell {0, 0}, the top-left: its rect on an SVG, the canvas on a canvas.
      const cell = #{svg?} ? tipEl.querySelectorAll('[data-row]').filter((n) => n.getAttribute('data-row') === '0')[0] : chart;
      if (cell !== chart) cell.rect = {left: 6, top: 6, width: 50, height: 50};
      document.elementFromPoint = () => cell;
      const at = {target: cell, pageX: 30, pageY: 30, clientX: 30, clientY: 30};
      const shown = () => [hook.tip.style.display,
        document.body.querySelectorAll('.vis-tooltip-hover').filter((o) => o.style.display === 'block').length];
      Stub.fire(tipEl, 'mousemove', at);
      const report = {moved: shown()};
      Stub.fire(tipEl, 'touchmove', {target: cell, touches: [{clientX: 30, clientY: 30, pageX: 30, pageY: 30}]});
      report.touched = shown();
      Stub.mark('click');
      Stub.fire(tipEl, 'click', at);
      Stub.mark('flag');
      Stub.fire(tipEl, 'contextmenu', Object.assign({preventDefault: () => {}}, at));
      Stub.done(report);
      """

      assert {:ok, %{"log" => log, "report" => report}} = Visualize.JsHooks.run(scenario),
             backend

      assert report["moved"] == ["none", 0], backend
      assert report["touched"] == ["none", 0], backend

      pushed = fn mark ->
        for %{"kind" => "push"} = p <- Visualize.JsHooks.after_mark(log, mark),
            do: {p["payload"]["event"], p["payload"]["row"]}
      end

      assert pushed.("click") == [{"cell_click", 0}], backend
      assert pushed.("flag") == [{"flag", 0}], backend
    end
  end

  test "a click is resolved to the cell's identity, and Shift or Flag mode flags" do
    socket = click(page(), @first)
    assert states(socket)[@first] == "revealed"
    assert socket.assigns.game.status == :playing
    assert socket.assigns.started != nil

    # Shift held: the click flags; again, the flag comes off.
    socket = click(socket, {0, 0}, ["shift"])
    assert states(socket)[{0, 0}] == "flagged"
    assert Minesweeper.mines_left(socket.assigns.game) == 9
    socket = click(socket, {0, 0}, ["shift"])
    assert states(socket)[{0, 0}] == "hidden"

    # Flag mode: a plain click flags, and a flag is not revealed through.
    {:noreply, socket} = MinesweeperLive.handle_event("mode", %{"mode" => "flag"}, socket)
    socket = click(socket, {0, 0})
    assert states(socket)[{0, 0}] == "flagged"
    {:noreply, socket} = MinesweeperLive.handle_event("mode", %{"mode" => "reveal"}, socket)
    socket = click(socket, {0, 0})
    assert states(socket)[{0, 0}] == "flagged"
  end

  test "a click on a drawing the page no longer holds is dropped" do
    socket = page()
    stale = drawn(socket)
    socket = click(socket, @first)

    # The component now holds the new drawing; the old token resolves to nothing.
    current = Component.update(%{id: "mines-chart", chart: socket.assigns.chart}, stale)
    {:ok, current} = current
    params = %{"event" => "cell_click", "frame" => "main", "mark" => 0, "row" => 0}

    Component.handle_event(
      "visualize_event",
      Map.put(params, "drawn", stale.assigns.drawn),
      current
    )

    # The event is resolved within the call, so nothing sent by now is nothing sent.
    refute_received {:visualize_event, _, _}
  end

  test "a seeded game played to a win, on every backend" do
    for {backend, _label, _opts} <- MinesweeperLive.backends() do
      game = layout()
      socket = page() |> on(backend) |> click(@first)

      safe = for cell <- Minesweeper.cells(game), not Minesweeper.mine?(game, cell), do: cell
      socket = Enum.reduce(safe, socket, &click(&2, &1))

      assert socket.assigns.game.status == :won, backend
    end

    game = layout()
    socket = click(page(), @first)

    safe = for cell <- Minesweeper.cells(game), not Minesweeper.mine?(game, cell), do: cell
    socket = Enum.reduce(safe, socket, &click(&2, &1))

    assert socket.assigns.game.status == :won
    assert Minesweeper.mines_left(socket.assigns.game) == 0
    states = states(socket)

    for cell <- Minesweeper.cells(game) do
      assert states[cell] == if(Minesweeper.mine?(game, cell), do: "flagged", else: "revealed")
    end

    # The counts are drawn as text in their colors, the flags as triangles.
    svg = Visualize.Chart.render(socket.assigns.chart, root: true)
    assert svg =~ ~r/<text class="mark-text"[^>]*fill="var\(--vis-red, #c23238\)"[^>]*>3<\/text>/
    assert length(Regex.scan(~r/<g class="vis-enter-[0-9a-z]+"><path/, svg)) == 10

    html = static(socket)
    assert html =~ "Cleared: you won"
    assert html =~ "0 mines left"
  end

  test "a seeded game played to a loss" do
    game = layout()

    socket =
      page()
      |> click(@first)
      |> click({1, 1}, ["shift"])
      |> click({0, 1}, ["shift"])
      |> click({0, 0})

    assert socket.assigns.game.status == :lost
    states = states(socket)
    assert states[{0, 0}] == "exploded"
    assert states[{1, 1}] == "flagged"
    assert states[{0, 1}] == "misflagged"

    for cell <- Minesweeper.cells(game) -- [{0, 0}, {1, 1}],
        Minesweeper.mine?(game, cell),
        do: assert(states[cell] == "mine")

    assert static(socket) =~ "Boom: you lost"

    # Nothing moves once it is over; New game starts another, nothing mined.
    assert states(click(socket, {8, 4})) == states
    {:noreply, socket} = MinesweeperLive.handle_event("new", %{}, socket)
    assert socket.assigns.game.status == :ready
    assert Enum.all?(states(socket), fn {_cell, state} -> state == "hidden" end)
  end

  test "the clock ticks while its game goes on, and a tick of a game over or replaced changes nothing" do
    socket = click(page(), @first)
    started = socket.assigns.started

    {:noreply, ticked} = MinesweeperLive.handle_info({:tick, started}, socket)
    assert ticked.assigns.elapsed == 0

    lost = click(socket, {0, 0})
    assert lost.assigns.game.status == :lost
    assert {:noreply, ^lost} = MinesweeperLive.handle_info({:tick, started}, lost)

    {:noreply, socket} = MinesweeperLive.handle_event("new", %{}, socket)
    assert {:noreply, ^socket} = MinesweeperLive.handle_info({:tick, started}, socket)
  end

  test "a secondary gesture flags in either mode, and Enter's key is a click's" do
    socket = click(page(), @first)

    # The flag event, as a right-click, a long-press or the Menu key sends it, in Reveal mode.
    socket = click(socket, {0, 0}, [], "flag")
    assert states(socket)[{0, 0}] == "flagged"
    socket = click(socket, {0, 0}, [], "flag")
    assert states(socket)[{0, 0}] == "hidden"

    # The keyboard reaches every cell, by row and column, each keyed as its click (D-198).
    keys = Visualize.Hooks.Keyboard.attrs(socket.assigns.chart)["data-keyboard-points"]
    assert keys =~ ~s("grid":true)
    assert keys =~ ~s({"event":"cell_click","context":"flag","frame":"main","mark":0,"row":0})
    assert keys =~ ~s(cells, 41 of 81: col 4, row 4, revealed")
  end

  test "the backend switch draws on a canvas with the hit index, and refuses a name it lacks" do
    socket = page()

    for {backend, hook} <- [{"json", "CanvasChart"}, {"binary", "CanvasBinaryChart"}] do
      html = socket |> on(backend) |> assigns() |> then(&render_component(Component, &1))
      assert html =~ ~s(phx-hook="#{hook}"), backend

      assert html =~
               ~s(data-vis-items="[{&quot;event&quot;:&quot;cell_click&quot;,&quot;context&quot;:&quot;flag&quot;),
             backend

      assert html =~ ~s(phx-hook="KeyboardHook"), backend
    end

    assert on(socket, "webgl").assigns.backend == "svg"
    html = build_conn() |> get("/minesweeper?seed=#{@seed}") |> html_response(200)
    assert html =~ ~s(phx-value-backend="binary")
    refute html =~ "Drawn as SVG only"
  end

  test "the design validates, and its cells require the identity the schema declares" do
    assert {:ok, _chart} = Visualize.Chart.from_map(MinesweeperLive.design())
    assert Visualize.Data.Schema.identity(MinesweeperLive.schema()) == [:col, :row]
    assert MinesweeperLive.applied(layout()).schemas["cells"] == MinesweeperLive.schema()
  end

  # #808: the board is chosen on the page and lives in the address with the seed.
  describe "the board size" do
    # The page mounted at `params`, the address's, and its params handled, as LiveView
    # does on a page's first render.
    defp page_at(params) do
      {:ok, socket} = MinesweeperLive.mount(params, %{}, %Socket{assigns: %{__changed__: %{}}})
      uri = "http://localhost/minesweeper?" <> URI.encode_query(params)
      {:noreply, socket} = MinesweeperLive.handle_params(params, uri, socket)
      socket
    end

    defp board(socket),
      do: {socket.assigns.game.rows, socket.assigns.game.cols, socket.assigns.game.mines}

    # Where a choice sent the page: the address it patched to, parsed.
    defp patched(socket) do
      {:live, :patch, %{to: to}} = socket.redirected
      %URI{path: "/minesweeper", query: query} = URI.parse(to)
      URI.decode_query(query)
    end

    test "the address names the board and the seed, and a game replays from it" do
      socket = page_at(%{"rows" => "16", "cols" => "30", "mines" => "99", "seed" => "7"})
      assert board(socket) == {16, 30, 99}
      assert socket.assigns.game.seed == 7

      assert MinesweeperLive.path(board(socket), 7) ==
               "/minesweeper?rows=16&cols=30&mines=99&seed=7"

      # The same address is the same layout.
      again = page_at(%{"rows" => "16", "cols" => "30", "mines" => "99", "seed" => "7"})
      first = Minesweeper.reveal(socket.assigns.game, {8, 15})
      assert Minesweeper.reveal(again.assigns.game, {8, 15}).mined == first.mined

      # A seed alone is Beginner's board, as `/minesweeper?seed=n` always was.
      assert board(page_at(%{"seed" => "42"})) == {9, 9, 10}
    end

    test "values are clamped to the bounds, and anything not a whole number is Beginner's" do
      assert MinesweeperLive.board(%{"rows" => "2", "cols" => "99", "mines" => "5"}) == {5, 50, 5}

      assert MinesweeperLive.board(%{"rows" => "50", "cols" => "50", "mines" => "9999"}) ==
               {50, 50, 2499}

      assert MinesweeperLive.board(%{"rows" => "-3", "cols" => " 12 ", "mines" => "-1"}) ==
               {5, 12, 1}

      # Mines left out, or left empty, are about one cell in six.
      assert MinesweeperLive.board(%{"rows" => "20", "cols" => "20"}) == {20, 20, 64}

      assert MinesweeperLive.board(%{"rows" => "20", "cols" => "20", "mines" => ""}) ==
               {20, 20, 64}

      for bad <- [
            %{"rows" => "1e3", "cols" => "20"},
            %{"rows" => "20", "cols" => "twenty"},
            %{"rows" => "20", "cols" => "20", "mines" => "lots"},
            %{"rows" => "20.5", "cols" => "20"},
            %{"rows" => "", "cols" => "20"},
            %{"rows" => "20"},
            %{"rows" => ["20"], "cols" => "20"},
            %{}
          ] do
        assert MinesweeperLive.board(bad) == {9, 9, 10}, inspect(bad)
      end

      # The page plays what the clamp gives, and a bad seed is a new game's.
      socket = page_at(%{"rows" => "80", "cols" => "50", "seed" => "x"})
      assert board(socket) == {50, 50, 400}
      assert is_integer(socket.assigns.game.seed)
    end

    test "the address is the game's own once connected: a seed is written, a clamp shown" do
      for {params, board} <- [
            {%{"rows" => "16", "cols" => "16", "mines" => "40"}, {16, 16, 40}},
            {%{"rows" => "99", "cols" => "3", "mines" => "0", "seed" => "5"}, {50, 5, 1}}
          ] do
        {:ok, socket} = MinesweeperLive.mount(params, %{}, %Socket{assigns: %{__changed__: %{}}})
        # A connected socket: the address it was asked for is rewritten in place.
        socket = %{socket | transport_pid: self()}
        uri = "http://localhost/minesweeper?" <> URI.encode_query(params)
        {:noreply, socket} = MinesweeperLive.handle_params(params, uri, socket)

        {:live, :patch, %{to: to, kind: :replace}} = socket.redirected
        assert to == MinesweeperLive.path(board, socket.assigns.game.seed)
        assert board(socket) == board
      end

      # An address that is already the game's own is left alone.
      params = %{"rows" => "16", "cols" => "16", "mines" => "40", "seed" => "3"}
      {:ok, socket} = MinesweeperLive.mount(params, %{}, %Socket{assigns: %{__changed__: %{}}})
      socket = %{socket | transport_pid: self()}
      own = "http://localhost" <> MinesweeperLive.path({16, 16, 40}, 3)
      game = socket.assigns.game
      {:noreply, socket} = MinesweeperLive.handle_params(params, own, socket)
      assert socket.redirected == nil
      assert socket.assigns.game == game
    end

    test "a preset, Custom and New game start a game and put it in the address" do
      socket = page_at(%{"seed" => "42"})

      {:noreply, expert} = MinesweeperLive.handle_event("preset", %{"preset" => "expert"}, socket)
      assert board(expert) == {16, 30, 99}
      assert expert.assigns.game.status == :ready

      assert patched(expert) == %{
               "rows" => "16",
               "cols" => "30",
               "mines" => "99",
               "seed" => "#{expert.assigns.game.seed}"
             }

      # The patch's own params find the game already on the page, and keep it.
      {:noreply, kept} =
        MinesweeperLive.handle_params(patched(expert), "http://localhost/", %{
          expert
          | redirected: nil
        })

      assert kept.assigns.game == expert.assigns.game

      {:noreply, custom} =
        MinesweeperLive.handle_event(
          "custom",
          %{"rows" => "50", "cols" => "50", "mines" => ""},
          socket
        )

      assert board(custom) == {50, 50, 400}
      assert patched(custom)["rows"] == "50"

      {:noreply, bad} =
        MinesweeperLive.handle_event("custom", %{"rows" => "x", "cols" => "9"}, socket)

      assert board(bad) == {9, 9, 10}

      # A preset the selector does not name is refused, and nothing changes.
      assert {:noreply, ^socket} =
               MinesweeperLive.handle_event("preset", %{"preset" => "huge"}, socket)

      # New game keeps the board under a new seed.
      # (LiveView would have followed the patch; the test clears it.)
      played = click(%{custom | redirected: nil}, {25, 25})
      {:noreply, renewed} = MinesweeperLive.handle_event("new", %{}, played)
      assert board(renewed) == {50, 50, 400}
      assert renewed.assigns.game.status == :ready
      assert patched(renewed)["seed"] == "#{renewed.assigns.game.seed}"
    end

    test "the selector marks the current board, and the grid is drawn at the board's size" do
      for {query, current, view, min} <- [
            {"seed=42", "beginner", "0 0 368 368", 152},
            {"rows=16&cols=30&mines=99&seed=7", "expert", "0 0 1208 648", 488},
            {"rows=50&cols=50&mines=400&seed=7", nil, "0 0 1208 1208", 808}
          ] do
        html = build_conn() |> get("/minesweeper?" <> query) |> html_response(200)

        [form] = Regex.run(~r/<form class="mines-bar mines-size".*?<\/form>/s, html)

        on =
          Regex.scan(~r/class="backend-btn active"[^>]*>\s*(\w+)/, form) |> Enum.map(&List.last/1)

        assert on == [if(current, do: String.capitalize(current), else: "Custom")], query

        for {_name, label, _board} <- MinesweeperLive.presets(), do: assert(form =~ label)
        assert form =~ ~s(phx-submit="custom")
        assert html =~ ~s(viewBox="#{view}"), query
        assert html =~ "--mines-min-width: #{min}px", query
      end

      html =
        build_conn() |> get("/minesweeper?rows=16&cols=30&mines=99&seed=7") |> html_response(200)

      assert html =~ ~s(name="rows" aria-label="rows" min="5" max="50" value="16")
      assert html =~ ~s(name="mines" aria-label="mines" min="1" value="99")
      assert length(Regex.scan(~r/<rect data-datum="state count"/, html)) == 480
      assert html =~ "99 mines left"
    end

    test "the cell follows the board, and the counts and glyphs the cell" do
      assert MinesweeperLive.cell_size(9, 9) == 40
      assert MinesweeperLive.cell_size(16, 30) == 40
      assert MinesweeperLive.cell_size(50, 50) == 24
      assert MinesweeperLive.cell_size(50, 50) >= 16

      big = MinesweeperLive.design(50, 50, 24)
      assert {:ok, _chart} = Visualize.Chart.from_map(big)
      assert big.frames.main.scales.x.domain == Enum.to_list(0..49)
      assert big.frames.main.scales.y.domain == Enum.to_list(49..0//-1)
      assert big.styles.count_face.font.size == 14
      assert big.styles.flag.marker.size == 54

      # At 40 pixels and over, the classic board's faces.
      assert MinesweeperLive.design().styles.count_face.font.size == 18
      assert MinesweeperLive.design(9, 9, 41.3).styles.bomb.marker.size == 200
    end

    # 2,500 cells, played through the chart's component on every backend. A sparse board
    # opens almost whole at the first reveal (the flood fill); seed 2's leaves two cells.
    test "a 50 × 50 game played to a win and to a loss, on every backend" do
      for {backend, _label, _opts} <- MinesweeperLive.backends() do
        socket =
          page_at(%{"rows" => "50", "cols" => "50", "mines" => "10", "seed" => "2"})
          |> on(backend)
          |> click({25, 25})

        assert MapSet.size(socket.assigns.game.revealed) == 2488, backend

        socket =
          Enum.reduce_while(Stream.cycle([:move]), socket, fn :move, socket ->
            game = socket.assigns.game

            case Enum.find(Minesweeper.cells(game), fn cell ->
                   not Minesweeper.mine?(game, cell) and not MapSet.member?(game.revealed, cell)
                 end) do
              nil -> {:halt, socket}
              cell -> {:cont, click(socket, cell)}
            end
          end)

        assert socket.assigns.game.status == :won, backend
        assert Minesweeper.mines_left(socket.assigns.game) == 0

        # The default density, and a mine revealed after the first click.
        socket =
          page_at(%{"rows" => "50", "cols" => "50", "seed" => "42"})
          |> on(backend)
          |> click({25, 25})

        mine =
          Enum.find(
            Minesweeper.cells(socket.assigns.game),
            &Minesweeper.mine?(socket.assigns.game, &1)
          )

        socket = click(socket, mine)
        assert socket.assigns.game.status == :lost, backend
        assert states(socket)[mine] == "exploded"
        assert map_size(states(socket)) == 2500
      end
    end
  end

  # The status line as the page renders it for `socket`'s game.
  defp static(socket) do
    %{game: socket.assigns.game, elapsed: socket.assigns.elapsed}
    |> MinesweeperLive.status()
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end
end
