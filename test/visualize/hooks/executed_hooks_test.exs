defmodule Visualize.Hooks.ExecutedHooksTest do
  @moduledoc """
  The canvas hooks executed under node against the recording DOM stub (spec/12 §6, #458):
  each scenario pins a defect that shipped green while the hooks were only read as text —
  the #456 resize of both hooks, the #270 decode of the current record types, `data-frame`
  filtering (#432) and acknowledgements (D-107).
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
