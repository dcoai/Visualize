defmodule Examples.RidgelinePlotTest do
  @moduledoc """
  #491: the Ridgeline reads front to back. The ridge at the top of the plot is the farthest
  and is drawn first; each ridge below it is nearer and drawn after it, so it covers the
  one behind. Each ridge's crest is drawn directly after its own fill and before any
  nearer ridge, so a crest is never drawn over a fill in front of it — in the SVG and in
  the hybrid canvas's plan alike.
  """
  use ExUnit.Case, async: true

  alias Examples.Charts.{Design, RidgelinePlot}
  alias Visualize.Backend.CanvasBinary.Decoder

  @ridges 8

  # The marks' paths in document order: the mark type, the ridge, the paint, the path.
  defp paths(svg) do
    Regex.scan(
      ~r/<g class="mark mark-(area|line)"[^>]*>\s*<path d="([^"]+)" data-series="(\d+)" (fill|stroke)="([^"]+)"/,
      svg,
      capture: :all_but_first
    )
    |> Enum.map(fn [type, d, ridge, key, paint] ->
      %{type: type, d: d, ridge: String.to_integer(ridge), key: key, paint: paint}
    end)
  end

  # The pixel y of every point a path passes through.
  defp ys(d) do
    ~r/(-?[\d.]+),(-?[\d.]+)/
    |> Regex.scan(d, capture: :all_but_first)
    |> Enum.map(fn [_x, y] -> y |> Float.parse() |> elem(0) end)
  end

  test "SVG draws each ridge's fill and then its own crest, the top ridge first" do
    paths = paths(RidgelinePlot.render([]))

    assert Enum.map(paths, &{&1.type, &1.ridge}) ==
             for(ridge <- 0..(@ridges - 1), type <- ["area", "line"], do: {type, ridge})

    for [area, crest] <- Enum.chunk_every(paths, 2) do
      # The crest is the fill's own top edge, in the fill's colour.
      assert area.key == "fill" and crest.key == "stroke"
      assert crest.paint == area.paint
      assert String.starts_with?(area.d, crest.d)
    end

    # Nearer ridges come later: each fill's baseline lies lower on the plot than the last.
    baselines = for %{type: "area", d: d} <- paths, do: Enum.max(ys(d))
    assert baselines == Enum.sort(baselines)
    assert length(Enum.uniq(baselines)) == @ridges
  end

  test "the hybrid canvas fills and strokes in the same order, each crest in its fill's colour" do
    %{canvas: canvas} = Design.hybrid(RidgelinePlot, [])

    # Each draw with the colour it is drawn in: the last style record's fill before a
    # `:fill`, its stroke before a `:stroke`.
    {draws, _style} =
      canvas
      |> Base.decode64!()
      |> Decoder.decode()
      |> Enum.reduce({[], %{}}, fn
        {:style, style}, {draws, current} ->
          {draws, Map.merge(current, Map.reject(style, fn {_k, v} -> is_nil(v) end))}

        :fill, {draws, current} ->
          {[{:fill, current.fill} | draws], current}

        :stroke, {draws, current} ->
          {[{:stroke, current.stroke} | draws], current}

        :restore, {draws, _current} ->
          {draws, %{}}

        _record, acc ->
          acc
      end)

    draws = Enum.reverse(draws)
    assert length(draws) == 2 * @ridges

    pairs = Enum.chunk_every(draws, 2)

    for [{:fill, fill}, {:stroke, stroke}] <- pairs, do: assert(fill == stroke)
    assert Enum.all?(pairs, &match?([{:fill, _}, {:stroke, _}], &1))

    # The same ridges in the same order as the SVG: the top ridge's colour first.
    svg_colours =
      for %{type: "area", paint: paint} <- paths(RidgelinePlot.render([])) do
        [hex] = Regex.run(~r/#([0-9a-f]{6})/, paint, capture: :all_but_first)
        <<r::8, g::8, b::8>> = Base.decode16!(hex, case: :lower)
        {r, g, b, 255}
      end

    assert for([{:fill, fill}, _] <- pairs, do: fill) == svg_colours
    assert length(Enum.uniq(svg_colours)) == @ridges
  end
end
