defmodule Visualize.Shape.RoseTest do
  @moduledoc "The `Rose` polar mark (spec/04 §15, D-31)."
  use ExUnit.Case, async: true

  alias Visualize.Scale
  alias Visualize.Shape
  alias Visualize.Shape.{Arc, Rose}

  @pi :math.pi()

  # A four-point compass with an empty south petal.
  @compass [{0, 100}, {90, 60}, {180, 0}, {270, 80}]

  defp bearing, do: Scale.radial() |> Scale.domain([0, 360])

  # `Visualize.Backend.SVG.path_data/1` prints a float that rounds to -0.0 as `-0`; an Arc
  # sector's `L` to the origin hits it (pre-existing, tracked as #32). The
  # sign of zero is not part of the contract (D-6), so the goldens fold it.
  defp fold_negative_zero(d), do: String.replace(d, "-0,", "0,") |> String.replace("-0Z", "0Z")
  defp rose, do: Rose.new() |> Rose.scale(bearing()) |> Rose.width(90)

  describe "generate/2" do
    test "the compass renders the recorded sectors, index-aligned with the data" do
      assert Rose.generate(rose(), @compass) |> Enum.map(&fold_negative_zero/1) == [
               "M-70.7107,-70.7107A100,100,0,0,1,70.7107,-70.7107L0,0Z",
               "M42.4264,-42.4264A60,60,0,0,1,42.4264,42.4264L0,0Z",
               "",
               "M-56.5685,56.5685A80,80,0,0,1,-56.5685,-56.5685L0,0Z"
             ]
    end

    test "every sector is byte-identical to the Arc call with the same numbers" do
      rose = rose() |> Rose.inner_radius(20) |> Rose.pad_angle(0.05)

      expected =
        Enum.map(@compass, fn {deg, r} ->
          Arc.new()
          |> Arc.inner_radius(20)
          |> Arc.outer_radius(r)
          |> Arc.start_angle((deg - 45) / 360 * 2 * @pi)
          |> Arc.end_angle((deg + 45) / 360 * 2 * @pi)
          |> Arc.pad_angle(0.05)
          |> Arc.generate(%{})
        end)

      assert Rose.generate(rose, @compass) == expected
    end

    test "without a scale the angles are radians" do
      [quarter] = Rose.new() |> Rose.width(@pi / 2) |> Rose.generate([{@pi / 4, 50}])
      assert quarter == "M0,-50A50,50,0,0,1,50,0L0,0Z"
    end

    test "map data through atom and function accessors" do
      bins = [%{bearing: 45, count: 16, base: 10}]

      radius = Scale.sqrt() |> Scale.domain([0, 16]) |> Scale.range([0, 40])

      [path] =
        rose()
        |> Rose.angle(:bearing)
        |> Rose.inner_radius(:base)
        |> Rose.outer_radius(fn d -> Scale.apply(radius, d.count) end)
        |> Rose.generate(bins)

      assert path == "M0,-40A40,40,0,0,1,40,0L10,0A10,10,0,0,0,0,-10Z"
    end

    test "an empty list yields []" do
      assert Rose.generate(rose(), []) == []
    end
  end

  test "generate_path/2 returns IR paths" do
    assert [%Visualize.IR.Path{commands: [{:M, _, _} | _]} | _] =
             Rose.generate_path(rose(), @compass)
  end

  describe "through the facade" do
    test "every setter and both generators dispatch" do
      shape =
        Shape.rose()
        |> Shape.scale(bearing())
        |> Shape.angle(:bearing)
        |> Shape.width(90)
        |> Shape.inner_radius(0)
        |> Shape.outer_radius(:r)
        |> Shape.pad_angle(0)

      assert ["M-70.7107,-70.7107A100,100,0,0,1,70.7107,-70.7107L0,0Z"] =
               Shape.generate(shape, [%{bearing: 0, r: 100}]) |> Enum.map(&fold_negative_zero/1)

      assert [%Visualize.IR.Path{}] = Shape.generate_path(shape, [%{bearing: 0, r: 100}])
    end
  end
end
