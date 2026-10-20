defmodule Visualize.Render.SegmentsTest do
  @moduledoc """
  A drawing as keyed segments (spec/09 §1.4, #813, D-203): the segments are the backend's
  output, byte for byte, on every output; the cache changes nothing but the work; and a
  key follows the element it names.
  """
  use ExUnit.Case, async: true

  alias Visualize.Designs
  alias Visualize.IR.Element
  alias Visualize.Render
  alias Visualize.Render.Segments

  doctest Segments

  @outputs [svg: :svg, json: :json, binary: :binary]

  defp whole(tree, :svg), do: Render.to_string(tree, backend: :svg)

  defp whole(tree, :json),
    do: tree |> Render.to_string(backend: :canvas, format: :json) |> IO.iodata_to_binary()

  defp whole(tree, :binary), do: Render.to_string(tree, backend: :canvas, format: :binary_base64)

  defp keys(segments), do: Enum.map(segments, &elem(&1, 0))

  test "every design's segments are its output, on every output, with and without a cache" do
    for name <- Designs.names(), mode <- [:css, :literal], {output, format} <- @outputs do
      applied = Designs.apply(name)
      tree = Visualize.Chart.generate(applied, root: true, resolve: mode)
      {segments, cache} = apply(Segments, output, [tree, %{}])

      assert Segments.text(segments, format) == whole(tree, format), "#{name} #{mode} #{output}"
      assert keys(segments) == Enum.uniq(keys(segments)), "#{name} #{output}: a key repeats"
      assert {^segments, _} = apply(Segments, output, [tree, cache])
    end
  end

  defp grid(states) do
    cells =
      for {state, i} <- Enum.with_index(states) do
        Element.rect(i * 10, 0, 10, 10, %{fill: state})
      end

    Element.root(100, 10, children: [Element.group(cells, style: %{class: "cells"})])
  end

  test "a changed element changes its segment and no other" do
    before = grid(~w(red red red red))
    now = grid(~w(red blue red red))
    {first, cache} = Segments.svg(before, %{})
    {second, _cache} = Segments.svg(now, cache)

    changed = (second -- first) |> keys()
    assert length(changed) == 1
    assert length(first -- second) == 1
    assert Segments.text(second, :svg) == Render.to_string(now, backend: :svg)
  end

  test "an element keeps its key when one before it comes or goes" do
    same = Element.root(100, 10, children: [Element.group([Element.rect(0, 0, 5, 5, %{})])])

    added =
      Element.root(100, 10,
        children: [Element.group([Element.rect(9, 9, 1, 1, %{}), Element.rect(0, 0, 5, 5, %{})])]
      )

    # The rectangle first in `same` is second in `added`, after a new one: its place
    # changed and its key did not, so it is not sent again.
    {[_, _, {kept, _} | _], _} = Segments.svg(same, %{})
    {segments, _} = Segments.svg(added, %{})
    assert kept in keys(segments)
  end

  test "an identity is a key, a repeated one made unique, and its element drawn alone" do
    item = fn id, x -> Element.rect(x, 0, 5, 5, %{}) |> Element.put_attr("data-vis-id", id) end
    tree = Element.group([item.("main.1.a", 0), item.("main.1.a", 10), item.("main.1.b", 20)])
    {segments, _} = Segments.svg(tree, %{})

    assert ["r<", "id:main.1.a", "id:main.1.a#2", "id:main.1.b", "r>"] = keys(segments)
    assert Segments.text(segments, :svg) == Render.to_string(tree, backend: :svg)
  end

  test "a cache of another output is not read" do
    tree = grid(~w(red blue))
    {_svg, svg_cache} = Segments.svg(tree, %{})
    {json, _} = Segments.json(tree, svg_cache)
    assert Segments.text(json, :json) == whole(tree, :json)
  end
end
