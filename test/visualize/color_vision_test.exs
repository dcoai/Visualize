defmodule Visualize.Color.VisionTest do
  @moduledoc """
  Color-vision simulation (spec/08 §1.8, D-139): Machado, Oliveira and Fernandes (2009)
  at severity 1.0, over linear sRGB.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Visualize.{Color, Theme}
  alias Visualize.Color.Vision

  doctest Vision

  defp hex(string, deficiency),
    do: string |> Color.parse() |> Vision.simulate(deficiency) |> Color.to_hex()

  test "the matrices are the paper's severity 1.0 matrices" do
    assert Vision.matrix(:protanopia) == [
             [0.152286, 1.052583, -0.204868],
             [0.114503, 0.786281, 0.099216],
             [-0.003882, -0.048116, 1.051998]
           ]

    assert Vision.matrix(:deuteranopia) == [
             [0.367322, 0.860646, -0.227968],
             [0.280085, 0.672501, 0.047413],
             [-0.011820, 0.042940, 0.968881]
           ]

    assert Vision.matrix(:tritanopia) == [
             [1.255528, -0.076749, -0.178779],
             [-0.078411, 0.930809, 0.147602],
             [0.004733, 0.691367, 0.303900]
           ]
  end

  test "every row sums to one, which is what fixes the grays" do
    for deficiency <- Vision.deficiencies(), row <- Vision.matrix(deficiency) do
      assert_in_delta Enum.sum(row), 1.0, 1.0e-5
    end
  end

  property "a gray is its own simulation under every deficiency" do
    check all(v <- integer(0..255), deficiency <- member_of(Vision.deficiencies())) do
      gray = Color.rgb(v, v, v)
      assert Color.to_rgb(Vision.simulate(gray, deficiency)) == {v, v, v}
    end
  end

  test "the primaries, worked by hand through the linear-light model" do
    # Red under protanopia: linear (1, 0, 0) times the first column, 0.152286 and 0.114503,
    # the blue row clamped from -0.003882 to 0; encoded, 0.4266 and 0.3727 of 255.
    assert hex("#ff0000", :protanopia) == "#6d5f00"
    assert hex("#ff0000", :deuteranopia) == "#a39000"
    assert hex("#00ff00", :protanopia) == "#ffe500"
    assert hex("#0000ff", :tritanopia) == "#006b96"
  end

  test "red and green collapse for the red-green deficiencies and stay apart for tritanopia" do
    # The two ends of the default status ramp: green and red.
    good = "#4ca34b"
    bad = "#c23238"

    hue = fn color -> color |> Color.parse() |> Color.to_hcl() |> Map.fetch!(:h) end
    arc = fn a, b -> min(abs(a - b), 360 - abs(a - b)) end

    for deficiency <- [:protanopia, :deuteranopia] do
      assert arc.(hue.(hex(good, deficiency)), hue.(hex(bad, deficiency))) < 30,
             inspect(deficiency)
    end

    assert arc.(hue.(hex(good, :tritanopia)), hue.(hex(bad, :tritanopia))) > 90
  end

  test "the color-safe status keeps its ends further apart than the default's" do
    distance = fn theme, deficiency ->
      [a, b] =
        for role <- [:good, :bad] do
          theme
          |> Theme.resolve(role, :literal)
          |> Color.parse()
          |> Vision.simulate(deficiency)
          |> Color.to_lab()
        end

      :math.sqrt(:math.pow(a.l - b.l, 2) + :math.pow(a.a - b.a, 2) + :math.pow(a.b - b.b, 2))
    end

    for deficiency <- [:protanopia, :deuteranopia] do
      assert distance.(Theme.color_safe(), deficiency) > distance.(Theme.default(), deficiency),
             inspect(deficiency)
    end
  end

  test ":none is the color, the opacity is kept, and an unknown deficiency is refused" do
    color = Color.rgb(12, 200, 99, 0.5)
    assert Vision.simulate(color, :none) == color
    assert Vision.simulate(color, :deuteranopia).opacity == 0.5

    assert_raise ArgumentError, ~r/:achromatopsia is not a deficiency/, fn ->
      Vision.simulate(color, :achromatopsia)
    end
  end

  test "recolor rewrites every color literal of a text and nothing else" do
    svg =
      ~s|<g fill="#ff0000" style="stroke: #f00"><rect fill="url(#bad)" id="abc"/><text>#ff0000</text></g>|

    assert Vision.recolor(svg, :protanopia) ==
             ~s|<g fill="#6d5f00" style="stroke: #6d5f00"><rect fill="url(#bad)" id="abc"/><text>#ff0000</text></g>|

    assert Vision.recolor(svg, :none) == svg
  end
end
