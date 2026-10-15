defmodule Visualize.Scale.ColorTest do
  @moduledoc "Color scale defects from #13 (spec/03 §13.2, D-17)."
  use ExUnit.Case, async: true

  alias Visualize.Scale
  alias Visualize.Scale.Color

  @hex ~r/^#[0-9a-f]{6}$/

  test "an unknown scheme raises instead of silently becoming :blues" do
    assert_raise ArgumentError, ~r/unknown color scheme :nope/, fn -> Scale.sequential(:nope) end
    assert_raise ArgumentError, ~r/schemes\/0/, fn -> Scale.diverging(:nope) end
    assert_raise ArgumentError, fn -> Scale.sequential(:blues) |> Scale.range(:nope) end
  end

  test "every named scheme resolves" do
    for name <- Color.schemes() do
      assert Scale.sequential(name) |> Scale.apply(0.5) =~ @hex
    end
  end

  test "an unclamped value beyond the domain still yields a well-formed color" do
    scale = Scale.sequential(:blues) |> Scale.domain([0, 1]) |> Scale.clamp(false)
    assert Scale.apply(scale, 3) =~ @hex
    assert Scale.apply(scale, -2) =~ @hex
  end

  test "clamped values pin to the end stops" do
    scale = Scale.sequential(["#000000", "#ffffff"]) |> Scale.domain([0, 1])
    assert Scale.apply(scale, 5) == "#ffffff"
    assert Scale.apply(scale, -5) == "#000000"
    assert Scale.apply(scale, 0.5) == "#808080"
  end

  test "a diverging scale ticks over its whole domain and maps the pivot to the middle stop" do
    scale = Scale.diverging(["#ff0000", "#ffffff", "#0000ff"]) |> Scale.domain([-10, 0, 10])
    assert Scale.ticks(scale, 4) == [-10.0, -5.0, 0.0, 5.0, 10.0]
    assert Scale.apply(scale, 0) == "#ffffff"
  end
end
