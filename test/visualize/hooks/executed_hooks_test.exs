defmodule Visualize.Hooks.ExecutedHooksTest do
  @moduledoc """
  The canvas hooks executed under node against the recording DOM stub (spec/12 §6, #458):
  each scenario pins a defect that shipped green while the hooks were only read as text —
  the #456 resize of both hooks, the #270 decode of the current record types, `data-frame`
  filtering (#432) and acknowledgements (D-107) — and the crosshair's markers held to the
  drawing under the pointer, not to the container's box (#507).
  """
  use ExUnit.Case, async: true

  import Visualize.JsHooks, only: [run: 1, after_mark: 2, calls: 2]

  alias Visualize.Backend.{CanvasBinary, CanvasIncremental}
  alias Visualize.Chart
  alias Visualize.Chart.Frame
  alias Visualize.Hooks.Crosshair
  alias Visualize.IR.{Element, Path}

  @moduletag :js

  @drawing ~w(moveTo lineTo bezierCurveTo quadraticCurveTo arc rect fill stroke)

  # A short stroked polyline: the path32 record, one moveTo and two lineTo.
  defp chart do
    path = Path.new() |> Path.move_to(10, 20) |> Path.line_to(30, 40) |> Path.line_to(50, 10)
    Element.group([Element.path(path, %{stroke: "#336699", stroke_width: 2})])
  end

  defp binary, do: chart() |> CanvasBinary.encode_element!() |> CanvasBinary.to_base64()
  defp js(value), do: Jason.encode!(value)

  defp full(size), do: chart() |> CanvasIncremental.encode_full_redraw(size) |> Base.encode64()

  defp scroll(size) do
    [bounds] = CanvasIncremental.exposed_regions({20, 0}, size)
    Base.encode64(CanvasIncremental.encode_incremental({20, 0}, size, [{bounds, chart()}]))
  end

  defp drew?(entries, canvas), do: Enum.any?(calls(entries, canvas), &(&1 in @drawing))

  describe "a resize redraws (#456)" do
    test "CanvasBinaryChart takes data-width x data-height on updated() and redraws the same binary" do
      assert {:ok, %{"log" => log, "report" => report}} =
               run("""
               const el = Stub.element({binary: #{js(binary())}, width: '600', height: '400'}, 600, 400);
               const hook = Stub.mount(CanvasBinaryChart, el);
               Stub.mark('resize');
               el.dataset.width = '1200';
               el.dataset.height = '800';
               hook.updated();
               Stub.mark('again');
               hook.updated();
               Stub.done({canvas: hook.canvas.id, width: hook.canvas.width, height: hook.canvas.height});
               """)

      canvas = report["canvas"]
      assert %{"width" => 1200, "height" => 800} = report

      resize = after_mark(log, "resize")

      assert [
               %{"kind" => "set", "name" => "width", "value" => 1200},
               %{"kind" => "clear"},
               %{"kind" => "set", "name" => "height", "value" => 800},
               %{"kind" => "clear"} | drawn
             ] = Enum.filter(resize, &(&1["on"] == canvas))

      # The whole canvas cleared from the identity, then the stream replayed onto it.
      assert ["setTransform", "clearRect", "beginPath", "moveTo", "lineTo", "lineTo", "stroke"] =
               calls(drawn, canvas) -- ["save", "restore"]

      assert %{"name" => "clearRect", "args" => [0, 0, 1200, 800]} =
               Enum.find(drawn, &(&1["name"] == "clearRect"))

      # The size unchanged, the binary unchanged: nothing is drawn again.
      assert after_mark(log, "again") == []
    end

    test "CanvasIncrementalChart resizes its offscreen buffer and draws no scroll until a full record" do
      size = {600, 400}

      assert {:ok, %{"log" => log, "report" => report}} =
               run("""
               const el = Stub.element({width: '600', height: '400'}, 600, 400);
               const hook = Stub.mount(CanvasIncrementalChart, el);
               const full = {binary: #{js(full(size))}, dx: 0, dy: 0, mode: 'full'};
               const scroll = {binary: #{js(scroll(size))}, dx: 20, dy: 0, mode: 'scroll_x'};
               Stub.deliver(hook, 'canvas_incremental', full);
               Stub.mark('scroll');
               Stub.deliver(hook, 'canvas_incremental', scroll);
               Stub.mark('updated');
               el.dataset.width = '1200';
               el.dataset.height = '800';
               hook.updated();
               Stub.mark('stale scroll');
               Stub.deliver(hook, 'canvas_incremental', scroll);
               Stub.mark('resized by the payload');
               el.dataset.width = '900';
               el.dataset.height = '500';
               Stub.deliver(hook, 'canvas_incremental', scroll);
               Stub.mark('full');
               Stub.deliver(hook, 'canvas_incremental', full);
               Stub.mark('fresh scroll');
               Stub.deliver(hook, 'canvas_incremental', scroll);
               Stub.done({
                 canvas: hook.canvas.id, offscreen: hook.offscreen.id,
                 size: [hook.canvas.width, hook.canvas.height],
                 offscreenSize: [hook.offscreen.width, hook.offscreen.height]
               });
               """)

      %{"canvas" => canvas, "offscreen" => offscreen} = report
      assert %{"size" => [900, 500], "offscreenSize" => [900, 500]} = report

      # Before any resize a scroll copies through the offscreen buffer and draws.
      assert "drawImage" in calls(after_mark(log, "scroll"), canvas)

      # updated() resizes both canvases, which clears them.
      updated = after_mark(log, "updated")

      for target <- [canvas, offscreen] do
        assert [
                 %{"name" => "width", "value" => 1200},
                 %{"kind" => "clear"},
                 %{"name" => "height", "value" => 800},
                 %{"kind" => "clear"}
               ] = Enum.filter(updated, &(&1["on"] == target))
      end

      # A scroll onto the cleared canvas is dropped: nothing drawn, nothing copied.
      assert after_mark(log, "stale scroll") == []

      # A payload arriving with a new size and no updated() resizes and is dropped too.
      payload_resize = after_mark(log, "resized by the payload")

      assert Enum.map(payload_resize, &{&1["on"], &1["kind"], &1["value"]}) == [
               {canvas, "set", 900},
               {canvas, "clear", nil},
               {canvas, "set", 500},
               {canvas, "clear", nil},
               {offscreen, "set", 900},
               {offscreen, "clear", nil},
               {offscreen, "set", 500},
               {offscreen, "clear", nil}
             ]

      # The full record is drawn, and a scroll after it is drawn again.
      full_drawn = after_mark(log, "full")
      assert drew?(full_drawn, canvas)

      assert %{"args" => [0, 0, 900, 500]} =
               Enum.find(full_drawn, &(&1["name"] == "clearRect"))

      assert "drawImage" in calls(after_mark(log, "fresh scroll"), canvas)
    end
  end

  describe "the decoder replays the current record types (#270)" do
    test "path32, path_cubic32, cubic_run and their f64 forms decode without throwing" do
      polyline = Path.new() |> Path.move_to(10, 20) |> Path.line_to(30, 40)
      run_ = Path.new() |> Path.move_to(0, 0) |> Path.curve_to(1, 2, 3, 4, 5, 6)

      commands =
        Path.new()
        |> Path.move_to(0, 0)
        |> Path.line_to(5, 5)
        |> Path.curve_to(1, 2, 3, 4, 7, 8)
        |> Path.close()

      tree =
        Element.group([
          Element.path(polyline, %{stroke: "#ff0000", stroke_width: 2}),
          Element.path(run_, %{fill: "blue"}),
          Element.path(commands, %{fill: "green"}),
          Element.circle(5, 5, 2, %{fill: "red"}),
          Element.rect(0, 0, 4, 4, %{fill: "red"})
        ])

      f32 = CanvasBinary.encode_element!(tree)
      f64 = CanvasBinary.encode_element!(tree, precision: :f64)
      # The f32 records are the ones a page receives by default (D-73), the f64 the opt-in.
      assert byte_size(f32) < byte_size(f64)

      for stream <- [f32, f64] do
        assert {:ok, %{"log" => log, "report" => report}} =
                 run("""
                 const el = Stub.element({binary: #{js(Base.encode64(stream))}, width: '100', height: '100'}, 100, 100);
                 const hook = Stub.mount(CanvasBinaryChart, el);
                 const bytes = decodeBase64(el.dataset.binary);
                 Stub.mark('direct');
                 const reached = executeVisualizeBinary(hook.ctx, bytes);
                 Stub.done({canvas: hook.canvas.id, reached, length: bytes.length,
                            error: el.getAttribute('data-vis-error')});
                 """)

        %{"canvas" => canvas, "reached" => reached, "length" => length} = report
        assert reached == length
        assert report["error"] == nil

        drawn = Enum.filter(after_mark(log, "direct"), &(&1["on"] == canvas))
        args = fn name -> for %{"name" => ^name, "args" => a} <- drawn, do: a end

        assert args.("moveTo") == [[10, 20], [0, 0], [0, 0], [7, 5]]
        assert args.("lineTo") == [[30, 40], [5, 5]]
        assert args.("bezierCurveTo") == [[1, 2, 3, 4, 5, 6], [1, 2, 3, 4, 7, 8]]
        assert args.("closePath") == [[]]
        assert args.("rect") == [[0, 0, 4, 4]]

        assert %{"name" => "lineWidth", "value" => 2} =
                 Enum.find(drawn, &(&1["name"] == "lineWidth"))
      end
    end
  end

  describe "data-frame filtering (#432)" do
    test "a payload for another frame draws nothing on either hook" do
      size = {600, 400}

      assert {:ok, %{"log" => log, "report" => report}} =
               run("""
               const binEl = Stub.element({width: '600', height: '400', frame: 'main'}, 600, 400);
               const bin = Stub.mount(CanvasBinaryChart, binEl);
               const incEl = Stub.element({width: '600', height: '400', frame: 'main'}, 600, 400);
               const inc = Stub.mount(CanvasIncrementalChart, incEl);
               const binary = #{js(binary())};
               const full = #{js(full(size))};
               Stub.mark('other');
               Stub.deliver(bin, 'canvas_update', {binary, frame: 'legend'});
               Stub.deliver(inc, 'canvas_incremental', {binary: full, dx: 0, dy: 0, mode: 'full', frame: 'legend'});
               Stub.mark('own');
               Stub.deliver(bin, 'canvas_update', {binary, frame: 'main'});
               Stub.deliver(inc, 'canvas_incremental', {binary: full, dx: 0, dy: 0, mode: 'full', frame: 'main'});
               Stub.done({bin: bin.canvas.id, inc: inc.canvas.id, binary: binEl.dataset.binary || null});
               """)

      %{"bin" => bin, "inc" => inc} = report
      assert after_mark(log, "other") == []
      own = after_mark(log, "own")
      assert drew?(own, bin)
      assert drew?(own, inc)
      assert report["binary"] == binary()
    end

    test "a hook with no data-frame draws every payload" do
      assert {:ok, %{"log" => log, "report" => %{"canvas" => canvas}}} =
               run("""
               const el = Stub.element({width: '600', height: '400'}, 600, 400);
               const hook = Stub.mount(CanvasBinaryChart, el);
               Stub.mark('any');
               Stub.deliver(hook, 'canvas_update', {binary: #{js(binary())}, frame: 'legend'});
               Stub.done({canvas: hook.canvas.id});
               """)

      assert drew?(after_mark(log, "any"), canvas)
    end
  end

  describe "acknowledgements (D-107)" do
    for {hook, event, payload} <- [
          {"CanvasBinaryChart", "canvas_update", "{binary: BIN + ''}"},
          {"CanvasIncrementalChart", "canvas_incremental",
           "{binary: '', dx: 0, dy: 0, mode: 'none'}"}
        ] do
      test "#{hook} pushes {seq, drawn, at} at most once per data-ack-interval" do
        assert {:ok, %{"log" => log}} =
                 run("""
                 const BIN = #{js(binary())};
                 const el = Stub.element({width: '600', height: '400', ack: 'frame_ack', ackInterval: '50'}, 600, 400);
                 const hook = Stub.mount(#{unquote(hook)}, el);
                 const payload = (seq) => Object.assign(#{unquote(payload)}, seq === null ? {} : {seq});
                 const send = (seq) => Stub.deliver(hook, #{js(unquote(event))}, payload(seq));
                 Stub.mark('burst');
                 send(1); send(2); send(3);
                 Stub.advance(49);
                 Stub.mark('interval');
                 Stub.advance(1);
                 Stub.mark('later');
                 Stub.advance(10);
                 send(4);
                 send(null);
                 Stub.advance(50);
                 Stub.mark('quiet');
                 send(null);
                 Stub.advance(500);
                 Stub.done();
                 """)

        pushes = fn label -> for %{"kind" => "push"} = p <- after_mark(log, label), do: p end

        # Three frames within one interval: no push until it elapses, then one, the last.
        assert pushes.("burst") == []

        assert [%{"name" => "frame_ack", "payload" => %{"seq" => 3, "drawn" => 3, "at" => 50}}] =
                 pushes.("interval")

        # One frame later, and a payload without seq neither counted nor acknowledged.
        assert [%{"payload" => %{"seq" => 4, "drawn" => 1, "at" => 110}}] = pushes.("later")
        assert pushes.("quiet") == []
      end
    end

    test "a hook without data-ack pushes nothing" do
      assert {:ok, %{"log" => log}} =
               run("""
               const el = Stub.element({width: '600', height: '400'}, 600, 400);
               const hook = Stub.mount(CanvasBinaryChart, el);
               Stub.deliver(hook, 'canvas_update', {binary: #{js(binary())}, seq: 1});
               Stub.advance(1000);
               Stub.done();
               """)

      refute Enum.any?(log, &(&1["kind"] == "push"))
    end
  end

  describe "a plot mounted mid-run (#502, D-128)" do
    # A page switches backend during a run: the old plot's element goes, the new one
    # mounts with the run's sequences already past the floor — six frames went to the old
    # backend — and the first frame it is sent is the full one the switch forces.
    test "a fresh CanvasIncrementalChart draws the first full frame whole and acks it above the floor" do
      size = {600, 400}

      assert {:ok, %{"log" => log, "report" => %{"old" => old, "inc" => inc}}} =
               run("""
               const ack = {ack: 'frame_drawn', ackInterval: '50', frame: 'main'};
               const oldEl = Stub.element(Object.assign({width: '600', height: '400', binary: #{js(binary())}}, ack), 600, 400);
               const old = Stub.mount(CanvasBinaryChart, oldEl);
               for (let seq = 1; seq <= 6; seq++) Stub.deliver(old, 'canvas_update', {binary: #{js(binary())}, seq, frame: 'main'});
               Stub.advance(50);
               Stub.mark('old frame in flight');
               Stub.deliver(old, 'canvas_update', {binary: #{js(binary())}, seq: 7, frame: 'main'});
               old.destroyed();
               Stub.advance(100);
               Stub.mark('mount');
               const incEl = Stub.element(Object.assign({width: '600', height: '400'}, ack), 600, 400);
               const inc = Stub.mount(CanvasIncrementalChart, incEl);
               Stub.mark('first frame');
               Stub.deliver(inc, 'canvas_incremental', {binary: #{js(full(size))}, dx: 0, dy: 0, mode: 'full', seq: 8, frame: 'main'});
               Stub.advance(50);
               Stub.mark('scroll');
               Stub.deliver(inc, 'canvas_incremental', {binary: #{js(scroll(size))}, dx: 20, dy: 0, mode: 'scroll_x', seq: 9, frame: 'main'});
               Stub.advance(50);
               Stub.done({old: old.canvas.id, inc: inc.canvas.id});
               """)

      pushes = fn label -> for %{"kind" => "push"} = p <- after_mark(log, label), do: p end

      # The old hook acked its six; the frame it was sent as the switch came is never
      # acked, its element gone before the interval — and an ack that had left anyway is
      # below the floor the page keeps.
      assert [%{"payload" => %{"seq" => 6}}] =
               for(%{"kind" => "push"} = p <- log, p["payload"]["seq"] <= 6, do: p)

      assert pushes.("old frame in flight") == []

      # Mounted, the new canvas draws nothing until it is sent a frame.
      refute drew?(after_mark(log, "mount"), inc)

      # The first frame: the whole canvas cleared and the stream replayed, then one ack
      # with the new backend's sequence, above the floor.
      first = after_mark(log, "first frame")
      assert "clearRect" in calls(first, inc)
      assert drew?(first, inc)
      refute "drawImage" in calls(first, inc)

      assert [%{"name" => "frame_drawn", "payload" => %{"seq" => 8, "drawn" => 1}}] =
               for(%{"kind" => "push"} = p <- first, do: p)

      # Its pixels are current, so the next scroll copies them.
      assert "drawImage" in calls(after_mark(log, "scroll"), inc)
      assert [%{"payload" => %{"seq" => 9}}] = pushes.("scroll")
      refute drew?(after_mark(log, "mount"), old)
    end

    test "a fresh CanvasBinaryChart draws its markup's frame at mount and acks the next above the floor" do
      assert {:ok, %{"log" => log, "report" => %{"canvas" => canvas}}} =
               run("""
               Stub.mark('mount');
               const el = Stub.element({width: '600', height: '400', binary: #{js(binary())}, ack: 'frame_drawn', ackInterval: '50', frame: 'main'}, 600, 400);
               const hook = Stub.mount(CanvasBinaryChart, el);
               Stub.mark('first frame');
               Stub.deliver(hook, 'canvas_update', {binary: #{js(binary())} + '', seq: 8, frame: 'main'});
               Stub.advance(50);
               Stub.done({canvas: hook.canvas.id});
               """)

      assert drew?(after_mark(log, "mount"), canvas)

      assert [%{"name" => "frame_drawn", "payload" => %{"seq" => 8, "drawn" => 1}}] =
               for(%{"kind" => "push"} = p <- after_mark(log, "first frame"), do: p)
    end
  end

  describe "a sync group shares hover (#466, spec/10 §4.3)" do
    # The crosshair's attributes of a real design, applied at a size, as a hook's dataset:
    # the arrays, the plot, the size and the group's mapping, all from the server.
    defp member(size, opts \\ []) do
      domain = Keyword.get(opts, :domain, [0, 100])
      [lo, hi] = domain
      rows = for t <- lo..hi//div(hi - lo, 10), do: %{t: t, v: t * 2}

      design = %{
        version: 2,
        interaction: %{sync: Keyword.get(opts, :group, "dash")},
        sources: %{s: %{fields: [:t, :v]}},
        frames: %{
          main: %{
            kind: :cartesian,
            scales: %{x: %{kind: :linear, domain: domain}, y: %{kind: :linear}}
          }
        },
        marks: [%{type: :line, data: :s, channels: %{x: :t, y: :v}}]
      }

      {:ok, applied} = Chart.apply(design, sources: %{s: rows}, size: size)

      applied.frame
      |> Crosshair.attrs(applied.sources)
      |> Map.put("data-crosshair-event", "hover")
      |> dataset()
    end

    # The browser's dataset of a map of `data-*` attributes: `data-vis-sync-x` is `visSyncX`.
    defp dataset(attrs) do
      Map.new(attrs, fn {"data-" <> name, value} ->
        [first | rest] = String.split(name, "-")
        {Enum.join([first | Enum.map(rest, &String.capitalize/1)]), value}
      end)
    end

    # Every crosshair is mounted through a spy that records which charts handled a
    # received hover, so an echo would show.
    @prelude """
    const synced = [];
    const Spy = Object.create(CrosshairHook);
    Spy.syncTo = function (value) {
      synced.push(this.tag || this.el.id);
      return CrosshairHook.syncTo.call(this, value);
    };
    function mount(id, dataset, left, cssWidth) {
      const el = Stub.element(dataset);
      el.id = id;
      const [w, h] = dataset.size.split(',').map(Number);
      el.rect = {left, top: 0, width: cssWidth || w, height: h};
      return Stub.mount(Spy, el);
    }
    const at = (hook) => ({x1: hook.rule.getAttribute('x1'), display: hook.overlay.style.display});
    """

    defp events(entries), do: for(%{"kind" => "event"} = e <- entries, do: e)

    test "three charts of different widths put their crosshairs at the same domain x" do
      tooltip = Frame.sync_attrs(applied_frame({600, 200})) |> dataset()

      assert {:ok, %{"log" => log, "report" => report}} =
               run("""
               #{@prelude}
               const a = mount('a', #{js(member({600, 200}))}, 0);
               const b = mount('b', #{js(member({300, 200}))}, 700, 450);
               const c = mount('c', #{js(member({900, 200}))}, 1200);
               const far = mount('far', #{js(member({600, 200}, domain: [200, 300]))}, 2200);
               const other = mount('other', #{js(member({600, 200}, group: "other"))}, 3000);

               // A tooltip whose chart markup carries the group, one dot per datum.
               const tipEl = Stub.element({});
               tipEl.id = 'tip';
               tipEl.rect = {left: 4000, top: 50, width: 600, height: 200};
               const svg = tipEl.appendChild(Stub.node('svg', #{js(tooltip)}));
               const dots = [];
               for (let t = 0; t <= 100; t += 10) {
                 const dot = svg.appendChild(Stub.node('circle', {datum: 't v', datumT: String(t), datumV: String(2 * t)}));
                 dot.rect = {left: 4000 + 40 + t * 5.4 - 3, top: 150, width: 6, height: 6};
                 dots.push(dot);
               }
               const tip = Stub.mount(TooltipHook, tipEl);
               const tipShown = () => ({text: tip.tip.textContent || null, display: tip.tip.style.display});

               Stub.mark('hover');
               // 50 on a: chart x 40 + 270 of a 600-wide chart.
               Stub.fire(a.el, 'mousemove', {clientX: 310, clientY: 100});
               const hovered = {a: at(a), b: at(b), c: at(c), far: at(far), other: at(other), tip: tipShown()};
               const syncedOnHover = synced.splice(0);

               Stub.mark('leave');
               Stub.fire(a.el, 'mouseleave');
               const left = {a: at(a), b: at(b), c: at(c), tip: tipShown()};

               Stub.mark('tooltip hover');
               // 30 on the tooltip's chart: 40 + 162 of its 600.
               Stub.fire(tipEl, 'mousemove', {clientX: 4202, clientY: 150, pageX: 4202, pageY: 150, target: dots[3]});
               const fromTip = {a: at(a), b: at(b), c: at(c)};

               Stub.done({hovered, syncedOnHover, left, fromTip});
               """)

      assert %{
               "hovered" => hovered,
               "syncedOnHover" => synced,
               "left" => left,
               "fromTip" => from_tip
             } = report

      # 50 of [0, 100] is half of each plot: 540, 240 (shown at 450 CSS px) and 840 wide.
      assert %{"x1" => "270", "display" => "block"} = hovered["a"]
      assert %{"x1" => "120", "display" => "block"} = hovered["b"]
      assert %{"x1" => "420", "display" => "block"} = hovered["c"]
      assert %{"text" => "t: 50\nv: 100", "display" => "block"} = hovered["tip"]

      # A member whose domain does not hold 50 draws nothing; another group is untouched.
      assert %{"x1" => nil, "display" => "none"} = hovered["far"]
      assert %{"x1" => nil, "display" => "none"} = hovered["other"]

      # The chart under the pointer never handles its own echo, and the other group never hears.
      assert Enum.sort(synced) == ["b", "c", "far"]

      # One hover is one event on the bus in domain units, and one push, from its origin.
      hover = after_mark(log, "hover")

      assert [%{"name" => "vis:sync:dash", "payload" => %{"x" => 50, "source" => "a"}}] =
               events(hover)

      assert [%{"kind" => "push", "name" => "hover", "payload" => %{"index" => 5}}] =
               Enum.filter(hover, &(&1["kind"] == "push"))

      # Leaving clears every member.
      assert [%{"payload" => %{"x" => nil, "source" => "a"}}] = events(after_mark(log, "leave"))
      for chart <- ~w(a b c), do: assert(%{"display" => "none"} = left[chart])
      assert %{"display" => "none"} = left["tip"]

      # A tooltip publishes too: 30 on its chart moves every crosshair to 30.
      assert [%{"payload" => %{"x" => 30, "source" => "tip"}}] =
               events(after_mark(log, "tooltip hover"))

      assert %{"a" => %{"x1" => "162"}, "b" => %{"x1" => "72"}, "c" => %{"x1" => "252"}} =
               from_tip
    end

    test "destroyed() removes the listener, a remount hears once, and updated() moves it" do
      assert {:ok, %{"log" => log, "report" => report}} =
               run("""
               #{@prelude}
               const name = 'vis:sync:dash';
               const a = mount('a', #{js(member({600, 200}))}, 0);
               const first = mount('b', #{js(member({300, 200}))}, 700);
               first.tag = 'b1';
               const tip = Stub.mount(TooltipHook, Stub.element(#{js(member({600, 200}))}));

               const counts = {mounted: Stub.listeners(name)};
               first.destroyed();
               counts.destroyed = Stub.listeners(name);
               const second = Stub.mount(Spy, first.el);
               second.tag = 'b2';
               counts.remounted = Stub.listeners(name);

               Stub.mark('hover');
               Stub.fire(a.el, 'mousemove', {clientX: 310, clientY: 100});
               Stub.mark('after');
               const handled = synced.splice(0);

               second.el.dataset.visSync = 'elsewhere';
               second.updated();
               counts.moved = [Stub.listeners(name), Stub.listeners('vis:sync:elsewhere')];

               for (const hook of [a, second, tip]) hook.destroyed();
               counts.gone = [Stub.listeners(name), Stub.listeners('vis:sync:elsewhere')];
               Stub.done({counts, handled, overlays: document.body.children.length});
               """)

      # a, b and the tooltip; one fewer once b is destroyed, and one again on its remount.
      assert %{"mounted" => 3, "destroyed" => 2, "remounted" => 3} = report["counts"]

      # The destroyed mount hears nothing; the remount handles the one event once.
      assert report["handled"] == ["b2"]
      assert [_one] = events(after_mark(log, "hover"))

      # A new group moves the listener; everything destroyed leaves none, and nothing drawn.
      assert report["counts"]["moved"] == [2, 1]
      assert report["counts"]["gone"] == [0, 0]
      assert report["overlays"] == 0
    end
  end

  describe "a sync group shares the brush (#467, spec/10 §6.4)" do
    # A brush member as a page renders one: a container holding the chart's SVG, whose
    # frame group carries the group's attributes of a real design at a size, and the plot
    # as the brush's extent.
    defp brush_member(size, opts \\ []) do
      design = %{
        version: 2,
        interaction: %{sync: Keyword.get(opts, :group, "dash")},
        frames: %{
          main: %{
            kind: :cartesian,
            scales: %{x: %{kind: :linear, domain: Keyword.get(opts, :domain, [0, 100])}}
          }
        }
      }

      {:ok, %{frame: frame}} = Chart.apply(design, size: size)
      %{left: left, top: top} = frame.margin
      {width, height} = size

      %{
        size: [width, height],
        sync: Frame.sync_attrs(frame),
        extent: Enum.join([left, top, left + frame.plot.width, top + frame.plot.height], ",")
      }
    end

    # Every brush is mounted through a spy that records which charts drew a received
    # brush; `band` reads the drawn selection as [x, width, y, height], null when hidden.
    @brush_prelude """
    const handled = [];
    const Spy = Object.create(BrushHook);
    Spy.syncTo = function (extent) {
      handled.push(this.tag || this.el.id);
      return BrushHook.syncTo.call(this, extent);
    };
    function brush(id, m, left, cssWidth) {
      const [w, h] = m.size;
      const css = cssWidth || w;
      const svg = Stub.markup('svg', {viewBox: '0 0 ' + w + ' ' + h}, [Stub.markup('g', m.sync)]);
      svg.rect = {left, top: 0, width: css, height: h * css / w};
      const el = Stub.markup('div', {'data-brush-type': 'x', 'data-brush-extent': m.extent}, [svg]);
      el.id = id;
      return Stub.mount(Spy, el);
    }
    const band = (hook) => {
      const r = hook.selectionRect;
      if (r.getAttribute('visibility') !== 'visible') return null;
      return ['x', 'width', 'y', 'height'].map((a) => Number(r.getAttribute(a)));
    };
    const press = (hook, clientX) =>
      Stub.fire(hook.captureRect, 'mousedown', {button: 0, clientX, clientY: 100, preventDefault() {}});
    const move = (clientX) => Stub.fire(document, 'mousemove', {clientX, clientY: 100, preventDefault() {}});
    const release = () => Stub.fire(document, 'mouseup', {});
    """

    defp pushes(entries), do: for(%{"kind" => "push"} = p <- entries, do: p)

    test "brushing one of three charts shows the band on all three at the same domain extent" do
      assert {:ok, %{"log" => log, "report" => report}} =
               run("""
               #{@brush_prelude}
               const a = brush('a', #{js(brush_member({600, 200}))}, 0);
               const b = brush('b', #{js(brush_member({300, 200}))}, 700, 450);
               const c = brush('c', #{js(brush_member({900, 200}))}, 1200);
               const part = brush('part', #{js(brush_member({600, 200}, domain: [40, 140]))}, 2200);
               const far = brush('far', #{js(brush_member({600, 200}, domain: [200, 300]))}, 2900);
               const other = brush('other', #{js(brush_member({600, 200}, group: "other"))}, 3600);
               const bands = () => ({a: band(a), b: band(b), c: band(c), part: band(part), far: band(far), other: band(other)});

               Stub.mark('drag');
               // 20 to 50 of [0, 100] on a: chart x 40 + 108 to 40 + 270 of its 540-wide plot.
               press(a, 148);
               move(229);
               const during = bands();
               move(310);
               Stub.mark('release');
               release();
               const brushed = bands();
               const heard = handled.splice(0);
               Stub.done({during, brushed, heard});
               """)

      %{"during" => during, "brushed" => brushed, "heard" => heard} = report

      # The members follow the rubber band while it is drawn: 20 to 35 on b already.
      assert [88, w, 20, 150] = during["b"]
      assert_in_delta w, 36, 0.01

      # One extent, every member at its own pixels: 20..50 of a 240-, 540- and 840-wide plot.
      assert brushed["a"] == [148, 162, 20, 150]
      assert brushed["b"] == [88, 72, 20, 150]
      assert brushed["c"] == [208, 252, 20, 150]

      # Clipped to [40, 50] where the domain holds part of it; nothing where it holds none,
      # nor in another group.
      assert brushed["part"] == [40, 54, 20, 150]
      assert brushed["far"] == nil
      assert brushed["other"] == nil

      # The chart brushed never handles its own echo, and the other group never hears.
      assert heard |> Enum.uniq() |> Enum.sort() == ~w(b c far part)

      # Each move publishes the extent in domain units, and nothing goes to the server.
      drag = after_mark(log, "drag")

      assert [
               %{
                 "name" => "vis:sync-brush:dash",
                 "payload" => %{"extent" => [20, mid], "source" => "a"}
               },
               %{"payload" => %{"extent" => [20, 50], "source" => "a"}}
             ] = events(drag)

      assert_in_delta mid, 35, 0.01
      assert pushes(drag) == []

      # The release publishes the final window once more and pushes exactly one event,
      # from the chart brushed, with its pixels and the window's domain.
      release = after_mark(log, "release")
      assert [%{"payload" => %{"extent" => [20, 50], "source" => "a"}}] = events(release)

      assert [
               %{
                 "name" => "brush_select",
                 "payload" => %{
                   "x0" => 148,
                   "x1" => 310,
                   "y0" => 20,
                   "y1" => 170,
                   "domain" => [20, 50]
                 }
               }
             ] = pushes(log)
    end

    test "a clear propagates with one push, from the chart acted on" do
      assert {:ok, %{"log" => log, "report" => report}} =
               run("""
               #{@brush_prelude}
               const a = brush('a', #{js(brush_member({600, 200}))}, 0);
               const b = brush('b', #{js(brush_member({300, 200}))}, 700);
               const c = brush('c', #{js(brush_member({900, 200}))}, 1200);
               const bands = () => [band(a), band(b), band(c)];
               press(a, 148); move(310); release();
               const shown = bands();

               Stub.mark('double-click');
               Stub.fire(a.captureRect, 'dblclick', {});
               const cleared = bands();
               Stub.mark('again');

               press(a, 148); move(310); release();
               Stub.mark('click on a member');
               // A click without a move on b is too small to select: it clears the group.
               press(b, 760); release();
               const clickCleared = bands();
               Stub.done({shown, cleared, clickCleared});
               """)

      assert Enum.all?(report["shown"], &is_list/1)
      assert report["cleared"] == [nil, nil, nil]
      assert report["clickCleared"] == [nil, nil, nil]

      dbl = after_mark(log, "double-click")
      assert [%{"payload" => %{"extent" => nil, "source" => "a"}}] = events(dbl)
      assert [%{"name" => "brush_clear", "payload" => %{}}] = pushes(dbl)

      click = after_mark(log, "click on a member")
      assert [%{"payload" => %{"extent" => nil, "source" => "b"}}] = events(click)
      assert [%{"name" => "brush_clear"}] = pushes(click)
    end

    test "destroyed() removes the listener, a remount hears once, and a y brush joins no group" do
      assert {:ok, %{"log" => log, "report" => report}} =
               run("""
               #{@brush_prelude}
               const name = 'vis:sync-brush:dash';
               const m = #{js(brush_member({300, 200}))};
               const a = brush('a', #{js(brush_member({600, 200}))}, 0);
               const first = brush('b', m, 700);
               first.tag = 'b1';

               const counts = {mounted: Stub.listeners(name), moves: Stub.listeners('mousemove')};
               first.destroyed();
               counts.destroyed = Stub.listeners(name);
               const second = brush('b', m, 700);
               second.tag = 'b2';
               counts.remounted = Stub.listeners(name);

               // A "y" brush shares no x: it joins no group.
               const yEl = Stub.markup('div', {'data-brush-type': 'y'}, [Stub.markup('svg', {}, [Stub.markup('g', m.sync)])]);
               const y = Stub.mount(BrushHook, yEl);
               counts.withY = Stub.listeners(name);

               Stub.mark('brush');
               press(a, 148); move(310); release();
               const heard = handled.splice(0);
               const remountBand = band(second);

               for (const hook of [a, second, y]) hook.destroyed();
               counts.gone = [Stub.listeners(name), Stub.listeners('mousemove')];
               Stub.done({counts, heard, remountBand});
               """)

      assert %{"mounted" => 2, "moves" => 2, "destroyed" => 1, "remounted" => 2, "withY" => 2} =
               report["counts"]

      # The destroyed mount hears nothing; the remount handles each event once and draws.
      assert report["heard"] == ["b2", "b2"]
      assert report["remountBand"] == [88, 72, 20, 150]
      assert [_one] = pushes(after_mark(log, "brush"))
      assert report["counts"]["gone"] == [0, 0]
    end
  end

  describe "the design's brush (#565, spec/10 §6.5)" do
    # A chart whose design says `brush: :x`, alone on its page: its frame group carries the
    # brush's kind, x mapping and plot area, and the hook element only names the event.
    defp designed(size, domain) do
      design = %{
        version: 2,
        interaction: %{brush: :x},
        frames: %{main: %{kind: :cartesian, scales: %{x: %{kind: :linear, domain: domain}}}}
      }

      {:ok, %{frame: frame}} = Chart.apply(design, size: size)
      {width, height} = size
      %{size: [width, height], brush: Frame.brush_attrs(frame)}
    end

    @designed_prelude """
    function chart(id, m, own) {
      const [w, h] = m.size;
      const g = Stub.markup('g', m.brush);
      const svg = Stub.markup('svg', {viewBox: '0 0 ' + w + ' ' + h}, [g]);
      svg.rect = {left: 0, top: 0, width: w, height: h};
      const el = Stub.markup('div', Object.assign({'data-brush-event': 'zoom'}, own || {}), [svg]);
      el.id = id;
      return {hook: Stub.mount(BrushHook, el), g};
    }
    const capture = (hook) => ['x', 'y', 'width', 'height'].map((a) => Number(hook.captureRect.getAttribute(a)));
    const drag = (hook, from, to) => {
      Stub.fire(hook.captureRect, 'mousedown', {button: 0, clientX: from, clientY: 100, preventDefault() {}});
      Stub.fire(document, 'mousemove', {clientX: to, clientY: 100, preventDefault() {}});
      Stub.fire(document, 'mouseup', {});
    };
    """

    test "a chart in no sync group captures its plot and pushes the window in domain units" do
      assert {:ok, %{"log" => log, "report" => report}} =
               run("""
               #{@designed_prelude}
               const {hook, g} = chart('solo', #{js(designed({600, 200}, [0, 100]))});
               const mounted = {capture: capture(hook), type: hook.brushType, sync: hook.sync};

               Stub.mark('first');
               // 20 to 50 of [0, 100]: chart x 40 + 108 to 40 + 270 of its 540-wide plot.
               drag(hook, 148, 310);

               // Re-rendered for the window brushed, at a new width: the hook reads it again.
               g.setAttribute('data-vis-brush-x', '20,50,40,380,400');
               g.setAttribute('data-vis-brush-extent', '40,20,380,170');
               hook.updated();
               const updated = capture(hook);
               Stub.mark('second');
               drag(hook, 108, 210);
               Stub.done({mounted, updated});
               """)

      # The capture area is the design's plot, and the brush its kind, with no group joined.
      assert report["mounted"] == %{"capture" => [40, 20, 540, 150], "type" => "x", "sync" => nil}
      assert report["updated"] == [40, 20, 340, 150]

      assert [
               %{
                 "name" => "zoom",
                 "payload" => %{
                   "x0" => 148,
                   "x1" => 310,
                   "y0" => 20,
                   "y1" => 170,
                   "domain" => [20, 50]
                 }
               }
             ] = pushes(after_mark(log, "first") -- after_mark(log, "second"))

      # 68 to 170 of the new 340-wide plot over [20, 50]: 26 to 35.
      assert [%{"name" => "zoom", "payload" => %{"domain" => [lo, hi]}}] =
               pushes(after_mark(log, "second"))

      assert_in_delta lo, 26, 0.01
      assert_in_delta hi, 35, 0.01
    end

    test "the element's own type and extent win over the design's" do
      assert {:ok, %{"report" => report}} =
               run("""
               #{@designed_prelude}
               const own = {'data-brush-type': 'xy', 'data-brush-extent': '0,0,600,200'};
               const {hook} = chart('own', #{js(designed({600, 200}, [0, 100]))}, own);
               Stub.done({capture: capture(hook), type: hook.brushType});
               """)

      assert report == %{"capture" => [0, 0, 600, 200], "type" => "xy"}
    end
  end

  describe "the crosshair sits on the drawing (#507, spec/10 §13.3)" do
    # Three smooth series over 24 hours, as /interaction draws them, realised at `size`:
    # the crosshair's attributes as a dataset, and each series' vertices in chart units.
    defp drawn(size) do
      rows =
        for i <- 0..23,
            {s, phase} <- [{"a", 0.0}, {"b", 1.2}, {"c", 2.4}],
            do: %{t: i, s: s, v: 50 + 30 * :math.sin(i / 3 + phase) + 8 * phase}

      design = %{
        version: 2,
        sources: %{p: %{fields: [:t, :s, :v]}},
        frames: %{
          main: %{
            kind: :cartesian,
            margin: %{top: 30, right: 120, bottom: 40, left: 50},
            scales: %{x: %{kind: :linear, domain: [0, 23]}, y: %{kind: :linear, nice: true}}
          }
        },
        marks: [
          %{type: :line, data: :p, channels: %{x: :t, y: :v, series: :s}, style: :smooth}
        ],
        styles: %{smooth: %{curve: :monotone_x}}
      }

      {:ok, applied} = Chart.apply(design, sources: %{p: rows}, size: size)
      attrs = Crosshair.attrs(applied.frame, applied.sources)
      [left, top | _] = attrs["data-plot"] |> String.split(",") |> Enum.map(&number/1)
      xs = Jason.decode!(attrs["data-xs"])

      vertices =
        for ys <- Jason.decode!(attrs["data-ys"]),
            do: for({x, y} <- Enum.zip(xs, ys), do: {left + x, top + y})

      {dataset(attrs), vertices}
    end

    defp number(text), do: text |> Float.parse() |> elem(0)

    # Mounts a crosshair on a container holding `child` (an svg or a canvas) laid out at
    # `chart` (its client rectangle) inside a container laid out at `box`, puts the pointer
    # on every vertex of the first series, and reports where each marker landed, in client
    # pixels through the overlay's viewBox (a browser's default `xMidYMid meet`).
    defp hover(size, child, chart, box) do
      {dataset, vertices} = drawn(size)
      {width, height} = size
      %{left: cl, top: ct, width: cw, height: ch} = chart

      pointers =
        for {u, v} <- hd(vertices), do: [cl + u * cw / width, ct + v * ch / height]

      make =
        case child do
          :svg -> "Stub.node('svg')"
          :canvas -> "Stub.element({}, #{width}, #{height}).children[0]"
        end

      assert {:ok, %{"report" => %{"hits" => hits}}} =
               run("""
               const el = Stub.element(#{js(dataset)});
               el.rect = #{js(box)};
               const chart = #{make};
               chart.rect = #{js(chart)};
               el.appendChild(chart);
               const hook = Stub.mount(CrosshairHook, el);
               const px = (v) => parseFloat(v);
               const hits = #{js(pointers)}.map(([x, y]) => {
                 Stub.fire(el, 'mousemove', {clientX: x, clientY: y});
                 const o = hook.overlay.style;
                 const box = hook.overlay.getAttribute('viewBox').split(' ').map(Number);
                 const k = Math.min(px(o.width) / box[2], px(o.height) / box[3]);
                 const ox = px(o.left) + (px(o.width) - box[2] * k) / 2;
                 const oy = px(o.top) + (px(o.height) - box[3] * k) / 2;
                 return hook.markers.map((m) => [
                   ox + k * (hook.plot.left + parseFloat(m.getAttribute('cx'))),
                   oy + k * (hook.plot.top + parseFloat(m.getAttribute('cy')))
                 ]);
               });
               Stub.done({hits});
               """)

      expected =
        for j <- 0..(length(hd(vertices)) - 1) do
          for series <- vertices do
            {u, v} = Enum.at(series, j)
            [cl + u * cw / width, ct + v * ch / height]
          end
        end

      for {markers, want} <- Enum.zip(hits, expected),
          {[x, y], [wx, wy]} <- Enum.zip(markers, want) do
        assert abs(x - wx) <= 1 and abs(y - wy) <= 1,
               "marker at #{inspect({x, y})}, its vertex at #{inspect({wx, wy})}"
      end
    end

    test "over an svg whose container is a descender gap taller, every marker is on its vertex" do
      hover({720, 380}, :svg, %{left: 30, top: 100, width: 720, height: 380}, %{
        left: 30,
        top: 100,
        width: 720,
        height: 387
      })
    end

    test "over a CSS-scaled canvas in a taller container, every marker is on its vertex" do
      hover({480, 320}, :canvas, %{left: 10, top: 50, width: 360, height: 240}, %{
        left: 10,
        top: 50,
        width: 360,
        height: 247
      })
    end
  end

  describe "a stroke that does not scale keeps its width on screen (spec/14 §3.9, #651)" do
    # A 2-wide non-scaling stroke under a group scaled by `zoom`: the line width the hook
    # sets is 2 / zoom, so the stroke draws 2 pixels wide at every zoom.
    defp zoomed(zoom) do
      path = Path.new() |> Path.move_to(0, 0) |> Path.line_to(10, 10)

      Element.group(
        [
          Element.path(path, %{
            stroke: "#336699",
            stroke_width: 2,
            vector_effect: :non_scaling_stroke
          })
        ],
        transform: Visualize.IR.Transform.scale(zoom, zoom)
      )
    end

    defp widths(log, canvas) do
      for %{"on" => ^canvas, "kind" => "set", "name" => "lineWidth", "value" => w} <- log, do: w
    end

    for zoom <- [1, 2] do
      test "CanvasChart, from :json commands, at zoom #{zoom}" do
        zoom = unquote(zoom)
        commands = Visualize.Backend.Canvas.render_element(zoomed(zoom), format: :json)

        assert {:ok, %{"log" => log, "report" => %{"canvas" => canvas}}} =
                 run("""
                 const el = Stub.element({commands: #{js(IO.iodata_to_binary(commands))}, width: '100', height: '100'}, 100, 100);
                 const hook = Stub.mount(CanvasChart, el);
                 Stub.done({canvas: hook.canvas.id});
                 """)

        assert widths(log, canvas) == [2 / zoom]
      end

      test "CanvasChart, from the :js script, at zoom #{zoom}" do
        zoom = unquote(zoom)
        script = Visualize.Backend.Canvas.render_element(zoomed(zoom), format: :js)

        assert {:ok, %{"log" => log, "report" => %{"canvas" => canvas}}} =
                 run("""
                 const el = Stub.element({script: #{js(IO.iodata_to_binary(script))}, width: '100', height: '100'}, 100, 100);
                 const hook = Stub.mount(CanvasChart, el);
                 Stub.done({canvas: hook.canvas.id});
                 """)

        assert widths(log, canvas) == [2 / zoom]
      end

      test "CanvasBinaryChart, from the binary stream, at zoom #{zoom}" do
        zoom = unquote(zoom)
        binary = zoomed(zoom) |> CanvasBinary.encode_element!() |> CanvasBinary.to_base64()

        assert {:ok, %{"log" => log, "report" => %{"canvas" => canvas}}} =
                 run("""
                 const el = Stub.element({binary: #{js(binary)}, width: '100', height: '100'}, 100, 100);
                 const hook = Stub.mount(CanvasBinaryChart, el);
                 Stub.done({canvas: hook.canvas.id});
                 """)

        assert widths(log, canvas) == [2 / zoom]
      end
    end
  end

  defp applied_frame(size) do
    design = %{
      version: 2,
      interaction: %{sync: "dash"},
      frames: %{main: %{kind: :cartesian, scales: %{x: %{kind: :linear, domain: [0, 100]}}}}
    }

    {:ok, applied} = Chart.apply(design, size: size)
    applied.frame
  end
end
