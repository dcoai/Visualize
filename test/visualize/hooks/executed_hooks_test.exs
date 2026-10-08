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
end
