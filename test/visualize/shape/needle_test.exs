defmodule Visualize.Shape.NeedleTest do
  @moduledoc "The `Needle` polar mark (spec/04 §16, #392)."
  use ExUnit.Case, async: true

  alias Visualize.Scale
  alias Visualize.Shape
  alias Visualize.Shape.Needle

  @pi :math.pi()

  defp reading, do: Scale.linear() |> Scale.domain([0, 100]) |> Scale.range([-@pi / 2, @pi / 2])

  defp needle,
    do: Needle.new() |> Needle.scale(reading()) |> Needle.angle(:v) |> Needle.length(100)

  describe "generate/2" do
    test "a pointer straight up: the base across the hub, the tip at the length, closed" do
      assert Needle.generate(needle(), [%{v: 50}]) == ["M3,0L-3,0L0,-100Z"]
    end

    test "the tail extends behind the hub, and the width sets the base" do
      tailed = needle() |> Needle.tail(10) |> Needle.width(8)
      assert Needle.generate(tailed, [%{v: 50}]) == ["M4,10L-4,10L0,-100Z"]
    end

    test "the caps: flat draws the base's width across the tip, round a half circle about it" do
      flat = needle() |> Needle.cap(:flat)
      assert Needle.generate(flat, [%{v: 50}]) == ["M3,0L-3,0L-3,-100L3,-100Z"]
      round = needle() |> Needle.cap(:round)
      assert Needle.generate(round, [%{v: 50}]) == ["M3,0L-3,0L-3,-100A3,3,0,0,1,3,-100Z"]
    end

    test "the angle maps through the scale, radians without one; the inner radius starts the pointer" do
      right = needle() |> Needle.inner_radius(20)
      assert Needle.generate(right, [%{v: 100}]) == ["M20,3L20,-3L100,0Z"]

      raw = Needle.new() |> Needle.angle(:a) |> Needle.length(:l)
      assert Needle.generate(raw, [%{a: @pi, l: 50}]) == ["M-3,0L3,0L0,50Z"]
      assert Needle.generate(Needle.new(), [{@pi / 2, 10}]) == ["M0,3L0,-3L10,0Z"]
    end

    test "one pointer per datum, in order; the hub is a circle of the hub radius, else the width" do
      assert length(Needle.generate(needle(), [%{v: 0}, %{v: 50}, %{v: 100}])) == 3
      assert Needle.generate(needle(), []) == []

      hub = needle() |> Needle.hub(10)

      assert Visualize.Backend.SVG.path_data(Needle.hub_path(hub, %{v: 1})) ==
               "M-10,0A10,10,0,1,1,10,0A10,10,0,1,1,-10,0Z"

      assert Visualize.Backend.SVG.path_data(Needle.hub_path(needle(), %{v: 1})) ==
               "M-6,0A6,6,0,1,1,6,0A6,6,0,1,1,-6,0Z"
    end

    test "the facade reaches it" do
      needle = Shape.needle() |> Shape.scale(reading()) |> Shape.angle(:v) |> Needle.length(100)
      assert Needle.generate(needle, [%{v: 50}]) == ["M3,0L-3,0L0,-100Z"]
    end
  end
end
