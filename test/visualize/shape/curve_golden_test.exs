defmodule Visualize.Shape.CurveGoldenTest do
  @moduledoc """
  Path golden for every curve type (spec/04 §5, D-19).

  `test/support/curve_golden.txt` records the SVG `d` string `Curve.generate/3` produces
  for each type over one fixed point set. The set has a repeated x (a vertical segment,
  which is the `dx = 0` case of the monotone tangents) and a reversal in both axes, so
  every branch of every curve runs. Regenerate only when curve maths changes on purpose:

      mix run -e 'Visualize.Shape.CurveGoldenTest.write!()'
  """
  use ExUnit.Case, async: true

  alias Visualize.Backend.SVG
  alias Visualize.Shape.Curve

  @golden "test/support/curve_golden.txt"

  @types [
    :linear,
    :step,
    :step_before,
    :step_after,
    :basis,
    :cardinal,
    :catmull_rom,
    :monotone_x,
    :monotone_y,
    :natural
  ]

  @points [{0, 80}, {30, 20}, {60, 50}, {60, 90}, {100, 10}, {130, 60}, {160, 40}]

  def types, do: @types

  # `SVG.path_data/1` rounds every coordinate to four decimals, which hides float noise from
  # a reordered expression and shows any genuine change in the maths.
  def render do
    Enum.map_join(@types, "\n", fn type ->
      "#{type} #{SVG.path_data(Curve.generate(type, @points))}"
    end) <> "\n"
  end

  def write!, do: File.write!(@golden, render())

  test "every curve type renders the fixed point set exactly as recorded" do
    assert File.read!(@golden) == render()
  end

  test "the golden covers every curve type" do
    recorded =
      @golden |> File.read!() |> String.split("\n", trim: true) |> Enum.map(&hd(String.split(&1)))

    assert recorded == Enum.map(@types, &Atom.to_string/1)
  end
end
