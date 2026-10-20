defmodule Visualize.Hooks.SegmentsHooksTest do
  @moduledoc """
  The canvas hooks draw a stream sent in keyed segments (spec/10 §7.1, §8.2, #813, D-203)
  exactly as they draw it whole: executed under node against the recording DOM stub
  (spec/12 §6), the segments beside the hook's element as `Visualize.Components.Chart`
  renders them, the same drawing is not decoded again, and a new one is.
  """
  use ExUnit.Case, async: true

  import Visualize.JsHooks, only: [run: 1, after_mark: 2]

  alias Visualize.Designs
  alias Visualize.Render.Segments

  @moduletag :js

  defp js(value), do: Jason.encode!(value)

  # What a canvas was asked to do, without which canvas: the calls and the properties set.
  defp drawn(log, label, canvas) do
    for %{"on" => ^canvas} = entry <- after_mark(log, label),
        do: Map.take(entry, ["kind", "name", "args", "value"])
  end

  defp tree(name), do: name |> Designs.apply() |> Visualize.Chart.generate(resolve: :literal)

  for {format, hook, attribute} <- [
        {:binary, "CanvasBinaryChart", "binary"},
        {:json, "CanvasChart", "commands"}
      ] do
    test "#{hook} draws its segments as it draws the stream whole" do
      format = unquote(format)
      tree = tree(:stacked_bar)

      # `Segments.binary/2` or `Segments.json/2`.
      {segments, _cache} = apply(Segments, format, [tree, %{}])

      whole = Segments.text(segments, format)
      pieces = Enum.map(segments, &elem(&1, 1))
      # Another drawing: the stream short of its last three segments.
      fewer = Enum.drop(pieces, -3)

      assert {:ok, %{"log" => log, "report" => report}} =
               run("""
               const piece = (c) => Stub.markup('i', {'data-c': c});
               const list = Stub.markup('div', {'data-vis-stream': ''}, #{js(pieces)}.map(piece));
               const segEl = Stub.element({stream: '', drawn: '1', width: '400', height: '300'}, 400, 300);
               Stub.markup('div', {}, [list, segEl]);
               const wholeEl = Stub.element({#{unquote(attribute)}: #{js(whole)}, width: '400', height: '300'}, 400, 300);
               Stub.mark('segments');
               const seg = Stub.mount(#{unquote(hook)}, segEl);
               Stub.mark('whole');
               const all = Stub.mount(#{unquote(hook)}, wholeEl);
               Stub.mark('same');
               seg.updated();
               Stub.mark('next');
               list.children.slice().forEach((c) => c.remove());
               #{js(fewer)}.forEach((c) => list.appendChild(piece(c)));
               segEl.dataset.drawn = '2';
               seg.updated();
               Stub.done({seg: seg.canvas.id, all: all.canvas.id});
               """)

      %{"seg" => seg, "all" => all} = report
      assert [_ | _] = drawn(log, "whole", all)
      assert drawn(log, "segments", seg) == drawn(log, "whole", all)
      assert drawn(log, "same", seg) == []
      assert [_ | _] = drawn(log, "next", seg)
      refute drawn(log, "next", seg) == drawn(log, "segments", seg)
    end
  end
end
