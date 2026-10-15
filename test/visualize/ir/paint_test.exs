defmodule Visualize.IR.PaintTest do
  @moduledoc """
  `Visualize.IR.Paint` (spec/02 §2.1, #652, D-175): the tight box a canvas builds a paint
  over, and the exact user-unit line of a box-unit linear gradient.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Visualize.IR.{Element, Paint, Path}

  doctest Visualize.IR.Paint

  defp linear(x1, y1, x2, y2),
    do: %Paint{id: "p", type: :linear, geometry: %{x1: x1, y1: y1, x2: x2, y2: y2}, stops: []}

  describe "bounds/1 is the tight box SVG's objectBoundingBox is measured over" do
    test "the shapes by their attributes, a rect of negative size normalized" do
      assert Paint.bounds(Element.rect(10, 20, -4, 6)) == {6, 20, 4, 6}
      assert Paint.bounds(Element.ellipse(0, 0, 3, 2)) == {-3, -2, 6, 4}
      assert Paint.bounds(Element.line(5, 1, 1, 9)) == {1, 1, 4, 8}
      assert Paint.bounds(Element.polygon([{0, 0}, {4, 1}, {2, 7}])) == {0, 0, 4, 7}
      assert Paint.bounds(Element.text("a", x: 1, y: 2)) == nil
      assert Paint.bounds(Element.path(Path.new())) == nil
    end

    test "a cubic by its extremes, not its control points" do
      path = Path.new() |> Path.move_to(0, 0) |> Path.curve_to(0, 100, 100, 100, 100, 0)
      assert {0, 0, 100, h} = Paint.bounds(Element.path(path))
      assert_in_delta h, 75, 1.0e-9
    end

    test "a quadratic by its extreme" do
      path = Path.new() |> Path.move_to(0, 0) |> Path.quad_to(50, 100, 100, 0)
      assert {0, 0, 100, h} = Paint.bounds(Element.path(path))
      assert_in_delta h, 50, 1.0e-9
    end

    test "an arc by the extremes its sweep passes: a half circle is half as tall as wide" do
      half = Path.new() |> Path.move_to(0, 0) |> Path.arc_to(50, 50, 0, 0, 1, 100, 0)
      {x, y, w, h} = Paint.bounds(Element.path(half))
      assert_in_delta x, 0, 1.0e-9
      assert_in_delta w, 100, 1.0e-9
      assert_in_delta h, 50, 1.0e-9
      assert_in_delta abs(y), 50, 1.0e-9

      # The other sweep goes round the other side of the chord.
      {_x, y2, _w, h2} =
        Paint.bounds(
          Element.path(Path.new() |> Path.move_to(0, 0) |> Path.arc_to(50, 50, 0, 0, 0, 100, 0))
        )

      assert_in_delta h2, 50, 1.0e-9
      assert_in_delta y2, if(y < 0, do: 0, else: -50), 1.0e-9
    end
  end

  describe "linear_line/2 maps a box-unit gradient exactly into user units (spec/09 §3.3.3)" do
    property "the canvas gradient's value at a point is the box-unit gradient's, on any box" do
      check all(
              angle <- StreamData.integer(0..359),
              {x, y} <-
                StreamData.tuple({StreamData.integer(-50..50), StreamData.integer(-50..50)}),
              {w, h} <- StreamData.tuple({StreamData.integer(1..400), StreamData.integer(1..400)}),
              {u, v} <-
                StreamData.tuple(
                  {StreamData.float(min: 0.0, max: 1.0), StreamData.float(min: 0.0, max: 1.0)}
                )
            ) do
        a = angle * :math.pi() / 180
        {sx, cx} = {:math.sin(a) / 2, :math.cos(a) / 2}
        paint = linear(0.5 - sx, 0.5 + cx, 0.5 + sx, 0.5 - cx)
        g = paint.geometry

        # SVG: the projection of the box point onto the line, in box units.
        {dx, dy} = {g.x2 - g.x1, g.y2 - g.y1}
        svg = ((u - g.x1) * dx + (v - g.y1) * dy) / (dx * dx + dy * dy)

        # Canvas: the projection of the user point onto the line linear_line/2 gives.
        {x0, y0, x1, y1} = Paint.linear_line(paint, {x, y, w, h})
        {px, py} = {x + u * w, y + v * h}
        {ex, ey} = {x1 - x0, y1 - y0}
        canvas = ((px - x0) * ex + (py - y0) * ey) / (ex * ex + ey * ey)

        assert_in_delta canvas, svg, 1.0e-9
      end
    end
  end

  test "rgba/1 multiplies the stop's opacity into the alpha; canvas_stops/1 writes rgba()" do
    assert Paint.rgba({0, "#ff000080", 0.5}) == {255, 0, 0, 64}
    assert Paint.rgba({0, "not a color", 1}) == {0, 0, 0, 255}

    paint = %{linear(0, 0, 1, 0) | stops: [{0.0, "#3b6fa8", 1}, {1.0, "#ffffff", 0.5}]}

    assert Paint.canvas_stops(paint) == [
             [0.0, "rgba(59,111,168,1)"],
             [1.0, "rgba(255,255,255,0.502)"]
           ]
  end
end
