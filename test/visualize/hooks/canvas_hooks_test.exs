defmodule Visualize.Hooks.CanvasHooksTest do
  @moduledoc """
  The shipped canvas hooks (spec/10 §4, §7–§9; D-40): the bundle exports all nine, and the
  JavaScript decoder is written against every opcode and sub-opcode the encoder emits.
  """
  use ExUnit.Case, async: true

  alias Visualize.Backend.CanvasBinary.Opcodes
  alias Visualize.Hooks

  require Opcodes

  @hooks ~w(ZoomHook BrushHook CanvasChart CanvasBinaryChart CanvasIncrementalChart ResizeHook TooltipHook CrosshairHook LegendHook BuilderHook)

  test "js_code/0 defines and exports the ten hooks once each" do
    js = Hooks.js_code()

    for hook <- @hooks do
      assert length(String.split(js, "export const #{hook} = {")) == 2
    end

    refute js =~ ~r/^\s*export\s*\{/m
    assert js =~ "export default { #{Enum.join(@hooks, ", ")} };"
    refute js =~ "console.log"
  end

  test "the decoder precedes the hooks that call it and is defined once" do
    js = Hooks.js_code()
    decoder_at = :binary.match(js, "export function executeVisualizeBinary") |> elem(0)
    binary_at = :binary.match(js, "export const CanvasBinaryChart") |> elem(0)
    incremental_at = :binary.match(js, "export const CanvasIncrementalChart") |> elem(0)
    assert decoder_at < binary_at and decoder_at < incremental_at
    assert length(String.split(js, "export function executeVisualizeBinary")) == 2
  end

  describe "the binary decoder" do
    defp case_literal(byte),
      do:
        "case 0x" <>
          String.pad_leading(Integer.to_string(byte, 16) |> String.upcase(), 2, "0") <> ":"

    test "has a case for every opcode of Opcodes" do
      decoder = Hooks.CanvasBinary.js_decoder()

      for byte <- [
            Opcodes.path(),
            Opcodes.path_cubic(),
            Opcodes.circles(),
            Opcodes.rects(),
            Opcodes.path32(),
            Opcodes.path_cubic32(),
            Opcodes.cubic_run(),
            Opcodes.style(),
            Opcodes.transform(),
            Opcodes.save(),
            Opcodes.restore(),
            Opcodes.fill(),
            Opcodes.stroke()
          ] do
        assert decoder =~ case_literal(byte), "no case for opcode #{byte}"
      end
    end

    test "has a case for every path_cubic sub-opcode and every transform kind" do
      decoder = Hooks.CanvasBinary.js_decoder()

      for byte <- 0x01..0x0F do
        assert decoder =~ case_literal(byte), "no case for sub-opcode #{byte}"
      end

      for byte <- [0x01, 0x03, 0xFF], do: assert(decoder =~ case_literal(byte))
    end

    test "the f32 path records share the f64 readers at a 4-byte width (D-73)" do
      decoder = Hooks.CanvasBinary.js_decoder()
      assert decoder =~ "case 0x05: { // path32"
      assert decoder =~ "case 0x06: { // path_cubic32"
      assert decoder =~ "drawPolyline(ctx, view, offset + 4, count, 4)"
      assert decoder =~ "drawPathCommands(ctx, view, bytes, offset + 4, cmdCount, 4)"

      assert decoder =~
               "width === 4 ? view.getFloat32(offset, true) : view.getFloat64(offset, true)"
    end

    test "the cubic run moves to its start point and draws each six-f32 entry (D-74)" do
      decoder = Hooks.CanvasBinary.js_decoder()
      assert decoder =~ "case 0x07: { // cubic_run"
      assert decoder =~ "drawCubicRun(ctx, view, offset + 4, count)"

      assert decoder =~
               ~r/function drawCubicRun.*?ctx\.moveTo\(view\.getFloat32.*?ctx\.bezierCurveTo\(/s
    end

    test "composes a full matrix with ctx.transform and throws on an unknown byte" do
      decoder = Hooks.CanvasBinary.js_decoder()
      refute decoder =~ "setTransform"
      assert decoder =~ ~r/case 0xFF:.*?ctx\.transform\(/s
      assert decoder =~ "throw new Error('Unknown canvas binary opcode"
    end
  end

  test "a decode failure is visible on the page, and rethrown (spec/10 §9.2, #270)" do
    js = Visualize.Hooks.js_code()
    assert length(String.split(js, "export function reportVisualizeError(el, error)")) == 2
    assert js =~ "el.setAttribute('data-vis-error', message);"
    assert js =~ "note.className = 'vis-canvas-error';"
    assert js =~ "note.setAttribute('role', 'alert');"
    # Both replaying hooks guard, clear on success, report and rethrow on failure.
    assert length(Regex.scan(~r/reportVisualizeError\(this\.el, error\);\n\s+throw error;/, js)) ==
             2

    assert length(Regex.scan(~r/clearVisualizeError\(this\.el\);/, js)) == 2
    # The reporter precedes the hooks that call it.
    reporter_at = :binary.match(js, "export function reportVisualizeError") |> elem(0)
    binary_at = :binary.match(js, "export const CanvasBinaryChart") |> elem(0)
    assert reporter_at < binary_at
  end

  test "CanvasIncrementalChart handles the 0x60 record and ignores mode none" do
    hook = Hooks.CanvasIncremental.js_hook()
    assert hook =~ "0x60"
    assert hook =~ "if (mode === 'none') return;"
    assert hook =~ "executeVisualizeBinary(ctx, bytes, 27)"
    assert hook =~ "ctx.clip();"
  end

  test "CanvasIncrementalChart acknowledges frames when asked, at most once per interval (D-107, #304)" do
    hook = Hooks.CanvasIncremental.js_hook()
    # Opt-in by data-ack; the interval defaults to 100 ms; only payloads with a seq count.
    assert hook =~ "this.ackEvent = this.el.dataset.ack || null;"
    assert hook =~ "parseInt(this.el.dataset.ackInterval, 10) || 100"
    assert hook =~ "if (payload.seq !== undefined) this.acknowledge(payload.seq);"
    assert hook =~ "if (this.ackEvent === null) return;"
    # The first frame in an interval schedules the flush; the flush pushes the last seq and
    # the count since, then resets the count — a trailing ack, never more than one per interval.
    assert hook =~
             ~r/if \(this\.ackTimer === null\) \{\s+this\.ackTimer = setTimeout\(\(\) => this\.flushAck\(\), this\.ackInterval\);/

    assert hook =~
             "this.pushEvent(this.ackEvent, { seq: this.ackSeq, drawn: this.ackDrawn, at: performance.now() });"

    assert hook =~ "this.ackDrawn = 0;"

    # A "none" payload is handled and so acknowledged: the ack follows handleIncremental unconditionally.
    assert hook =~ ~r/this\.handleIncremental\(payload\);\s+if \(payload\.seq !== undefined\)/
  end

  test "CanvasIncrementalChart copies the record's viewport alone, clipped to it (D-106, #294)" do
    hook = Hooks.CanvasIncremental.js_hook()
    # The viewport read from bytes 10-25, the regions counted at byte 26.
    assert hook =~ "x: view.getFloat32(10, true)"
    assert hook =~ "h: view.getFloat32(22, true)"
    assert hook =~ "let offset = 26;"
    # A source-rectangle copy inside a clip to the viewport: nothing outside it is read or
    # written, so a margin's axes survive every scroll frame.
    assert hook =~
             ~r/ctx\.rect\(v\.x, v\.y, v\.w, v\.h\);\s+ctx\.clip\(\);\s+ctx\.clearRect\(v\.x, v\.y, v\.w, v\.h\);/

    assert hook =~
             "ctx.drawImage(this.offscreen, v.x, v.y, v.w, v.h, v.x - intDx, v.y - intDy, v.w, v.h);"

    refute hook =~ "ctx.drawImage(this.offscreen, -intDx, -intDy)"
  end

  test "CanvasChart replays data-commands as JSON and data-script as JavaScript" do
    hook = Hooks.Canvas.js_hook()
    assert hook =~ "this.handleEvent(\"canvas_commands\""
    assert hook =~ "cmd.startsWith('set_')"
    assert hook =~ "new Function('ctx', script)(ctx)"
  end

  test "CanvasBinaryChart reads data-binary and canvas_update events" do
    hook = Hooks.CanvasBinary.js_hook()
    assert hook =~ "this.handleEvent(\"canvas_update\""
    assert hook =~ "executeVisualizeBinary(ctx, decodeBase64(base64Data))"
  end
end
