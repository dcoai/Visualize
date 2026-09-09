defmodule Visualize.IR.ElementDatumTest do
  @moduledoc "`Visualize.IR.Element.datum/2` (spec/02 §2.1, spec/10 §12.2, D-75)."
  use ExUnit.Case, async: true

  alias Visualize.IR.Element
  alias Visualize.Render

  doctest Element

  test "a keyword list writes the fields in its order, a map in sorted order" do
    keyword = Element.rect(0, 0, 1, 1) |> Element.datum(v: 4, t: 1)
    assert keyword.attrs["data-datum"] == "v t"

    map = Element.rect(0, 0, 1, 1) |> Element.datum(%{v: 4, t: 1})
    assert map.attrs["data-datum"] == "t v"
    assert map.attrs["data-datum-t"] == "1"
    assert map.attrs["data-datum-v"] == "4"
  end

  test "string field names and values of any term print through to_string/1" do
    element =
      Element.circle(0, 0, 1)
      |> Element.datum([{"region", :west}, {"at", ~D[2024-01-01]}, {"ratio", 0.5}])

    assert element.attrs["data-datum"] == "region at ratio"
    assert element.attrs["data-datum-region"] == "west"
    assert element.attrs["data-datum-at"] == "2024-01-01"
    assert element.attrs["data-datum-ratio"] == "0.5"
  end

  test "a nil value keeps its name in data-datum and writes no attribute" do
    element = Element.circle(0, 0, 1) |> Element.datum(v: nil, t: 1)
    assert element.attrs["data-datum"] == "v t"
    refute Map.has_key?(element.attrs, "data-datum-v")
  end

  test "the attributes render sorted with the geometry, hyphenated as given" do
    svg =
      Element.circle(1, 2, 3)
      |> Element.datum(big_v: 4, t: "a<b")
      |> Render.to_string()

    assert svg ==
             ~s|<circle cx="1" cy="2" data-datum="big_v t" data-datum-big-v="4" | <>
               ~s|data-datum-t="a&lt;b" r="3"/>|
  end

  test "a second call replaces the names and the attributes it writes" do
    element =
      Element.circle(1, 2, 3) |> Element.datum(v: 4) |> Element.datum(v: 5, w: 6)

    assert element.attrs["data-datum"] == "v w"
    assert element.attrs["data-datum-v"] == "5"
  end
end
