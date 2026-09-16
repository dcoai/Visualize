defmodule Examples.ScrollTest do
  @moduledoc "The scroll contract's data model (spec/14 §12.6, #296): a scroll is a whole number of samples and of pixels."
  use ExUnit.Case, async: true

  alias Examples.Scroll
  alias Visualize.Scale

  test "the density is the nearest whole number of samples per column, at least one" do
    assert Scroll.density(10, 700) == 1
    assert Scroll.density(700, 700) == 1
    assert Scroll.density(1400, 700) == 2
    assert Scroll.density(10_416, 700) == 15
  end

  test "a window is one sample per column and one more, and a sample is exactly 1/d px" do
    for d <- [1, 2, 5, 12] do
      scroll = Scroll.new(810, d)
      assert Scroll.count(scroll) == d * 810 + 1
      x = Scroll.x_scale(scroll)
      assert_in_delta Scale.Linear.apply(x, d), 1.0, 1.0e-9
      assert_in_delta Scale.Linear.apply(x, Scroll.count(scroll) - 1), 810.0, 1.0e-9
      assert Scroll.samples(scroll, 5) == 5 * d
    end
  end

  test "advance moves the origin by the scroll's samples, and shift keeps a line the window long" do
    scroll = Scroll.new(100, 3) |> Scroll.advance(5)
    assert scroll.origin == 15

    line = Enum.to_list(0..300)
    shifted = Scroll.shift(scroll, line, 5, fn j -> j * 10 end)
    assert length(shifted) == 301
    # The survivors slid left by the scroll; the fresh samples are the absolute indices
    # at the right edge, so the value at column i is the sample origin + i.
    assert Enum.take(shifted, 286) == Enum.drop(line, 15)
    assert Enum.drop(shifted, 286) == for(i <- 286..300, do: (15 + i) * 10)
  end

  test "columns is the buffered sample range under a strip, or nil outside the plot" do
    scroll = Scroll.new(810, 2)
    # The rightmost 5 px strip: samples 1610..1620, two more each side, clamped.
    assert Scroll.columns(scroll, {805, 5}) == {1608, 1620}
    assert Scroll.columns(scroll, {805, 5}, 0) == {1610, 1620}
    # A strip in the margin, past the plot, or of no width.
    assert Scroll.columns(scroll, {-20, 10}) == nil
    assert Scroll.columns(scroll, {820, 5}) == nil
    assert Scroll.columns(scroll, {100, 0}) == nil
  end
end
