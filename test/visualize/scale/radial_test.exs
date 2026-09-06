defmodule Visualize.Scale.RadialTest do
  @moduledoc "The `Radial` angle scale (spec/03 §14, D-30)."
  use ExUnit.Case, async: true

  alias Visualize.Scale
  alias Visualize.Scale.Radial

  @pi :math.pi()

  defp bearing, do: Scale.radial() |> Scale.domain([0, 360])

  test "the default range is one full turn from a unit domain" do
    assert %Radial{domain: [0, 1], range: [0, tau], clamp?: false} = Radial.new()
    assert_in_delta tau, 2 * @pi, 1.0e-12
    assert_in_delta Scale.apply(Radial.new(), 0.25), @pi / 2, 1.0e-12
  end

  test "apply/2 and invert/2 are Linear's over radians" do
    assert_in_delta Scale.apply(bearing(), 90), @pi / 2, 1.0e-12
    assert_in_delta Scale.apply(bearing(), 450), 2.5 * @pi, 1.0e-12
    assert_in_delta Scale.invert(bearing(), @pi), 180.0, 1.0e-9
    assert_in_delta Scale.apply(Scale.clamp(bearing(), true), 450), 2 * @pi, 1.0e-12
  end

  test "range/2 takes any two radians, descending included" do
    half = bearing() |> Scale.range([-@pi / 2, @pi / 2])
    assert_in_delta Scale.apply(half, 180), 0.0, 1.0e-12

    flipped = bearing() |> Scale.range([2 * @pi, 0])
    assert_in_delta Scale.apply(flipped, 90), 1.5 * @pi, 1.0e-12
    assert_in_delta Scale.invert(flipped, 1.5 * @pi), 90.0, 1.0e-9
  end

  describe "ticks/2" do
    test "divides a full turn into count equal steps, dropping the coincident last one" do
      assert Scale.ticks(bearing(), 4) == [0.0, 90.0, 180.0, 270.0]
      assert Scale.ticks(bearing(), 8) |> length() == 8

      assert Scale.ticks(Scale.radial() |> Scale.domain([0, 24]), 12) ==
               Enum.map(0..11, &(&1 * 2.0))
    end

    test "keeps the last division when the range is not a full turn" do
      half = bearing() |> Scale.range([-@pi / 2, @pi / 2])
      assert Scale.ticks(half, 4) == [0.0, 90.0, 180.0, 270.0, 360.0]
    end

    test "the count is exact, not a nice-step hint" do
      assert Scale.ticks(bearing(), 16) |> length() == 16
      assert Scale.ticks(bearing(), 0) == []
    end
  end

  test "nice/1 is identity; padding/2 identity; bandwidth/1 0" do
    day = Scale.radial() |> Scale.domain([0, 365])
    assert Scale.nice(day) == day
    assert Scale.padding(day, 0.2) == day
    assert Scale.bandwidth(day) == 0
  end
end
