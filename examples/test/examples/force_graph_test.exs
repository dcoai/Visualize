defmodule Examples.ForceGraphTest do
  # The gallery's Force-Directed Graph moves from where it was (spec/14 §12.5, #527,
  # D-132): its link distance breathes with the tick, so the renderer compiles it again
  # every tick, and `Examples.Frames` carries the warm layout across each recompilation
  # on every backend.
  use ExUnit.Case, async: true

  alias Examples.Charts.{Design, ForceGraph}
  alias Examples.Frames

  # Pixels at the gallery's 600 × 400. Laid out cold every frame, as it was, a node moved
  # by up to 327 px between consecutive ticks.
  @bound 15

  defp run(backend, ticks) do
    state = Frames.prepare(ForceGraph, [], backend)

    {layouts, _state} =
      Enum.map_reduce(ticks, state, fn tick, state ->
        {_frame, state} =
          Frames.frame(ForceGraph, [animation_tick: tick, at: tick * 50], backend, state)

        [{_name, compiled}] = state.compiled
        [{_key, nodes}] = Map.to_list(compiled.forces)
        {Map.new(nodes, fn {id, m} -> {id, {m.x, m.y}} end), state}
      end)

    layouts
  end

  defp moved(a, b) do
    Enum.max(
      for {id, {x, y}} <- a, {x2, y2} = b[id], do: :math.sqrt((x2 - x) ** 2 + (y2 - y) ** 2)
    )
  end

  test "ticks 0..60 are one graph moving: every node within the bound, on SVG and on Canvas" do
    svg = run(:svg, 0..60)
    canvas = run(:canvas, 0..60)

    # The same graph on both backends: each keeps a compiled chart and carries it.
    assert svg == canvas

    moves = svg |> Enum.chunk_every(2, 1, :discard) |> Enum.map(fn [a, b] -> moved(a, b) end)
    assert Enum.max(moves) < @bound
    assert Enum.min(moves) > 0.01
    assert moved(hd(svg), List.last(svg)) > 20
  end

  test "the design carries state, so a run keeps its compiled chart on SVG too" do
    assert Design.stateful?(ForceGraph)
    refute Design.transitions?(ForceGraph)

    assert %{compiled: [{_name, %Visualize.Chart.Compiled{}}]} =
             Frames.prepare(ForceGraph, [], :svg)

    # An SVG frame draws the compiled chart's layout.
    state = Frames.prepare(ForceGraph, [], :svg)
    {frame, state} = Frames.frame(ForceGraph, [animation_tick: 3, at: 150], :svg, state)
    [{_name, compiled}] = state.compiled
    [{_key, nodes}] = Map.to_list(compiled.forces)

    drawn =
      for [_, x, y] <- Regex.scan(~r/cx="([-\d.e]+)" cy="([-\d.e]+)"/, frame.svg),
          do: {elem(Float.parse(x), 0), elem(Float.parse(y), 0)}

    assert length(drawn) == map_size(nodes)

    for %{x: x, y: y} <- Map.values(nodes) do
      assert Enum.any?(drawn, fn {dx, dy} -> abs(dx - x) < 0.01 and abs(dy - y) < 0.01 end)
    end
  end

  test "rendered whole, the design is cold: the same tick draws the same graph" do
    assert ForceGraph.render(animation_tick: 7) == ForceGraph.render(animation_tick: 7)
  end
end
