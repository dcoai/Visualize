defmodule Visualize.AxisGoldenTest do
  @moduledoc """
  Rendered-SVG golden for every axis orientation (spec/05 §1, D-23).

  `test/support/axis_golden.txt` records `Axis.render/1` for each orientation over a linear
  scale, a band scale and a rounded band scale. Regenerate only when axis output changes on
  purpose:

      mix run -e 'ExUnit.start(autorun: false); Code.require_file("test/visualize/axis_golden_test.exs"); Visualize.AxisGoldenTest.write!()'
  """
  use ExUnit.Case, async: true

  alias Visualize.{Axis, Scale}
  alias Visualize.Scale.Band

  @golden "test/support/axis_golden.txt"
  @orientations [:top, :bottom, :left, :right]

  def scales do
    [
      linear: Scale.linear() |> Scale.domain([0, 100]) |> Scale.range([0, 200]),
      band:
        Scale.band() |> Scale.domain([:a, :b, :c]) |> Scale.range([0, 120]) |> Scale.padding(0.2),
      band_round:
        Scale.band()
        |> Scale.domain([:a, :b, :c])
        |> Scale.range([0, 100])
        |> Scale.padding(0.1)
        |> Band.round(true)
    ]
  end

  def render do
    for orient <- @orientations, {name, scale} <- scales() do
      axis = apply(Axis, orient, [scale]) |> Axis.ticks(4)
      "#{orient} #{name} #{Axis.render(axis)}"
    end
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  def write!, do: File.write!(@golden, render())

  test "every orientation renders every scale exactly as recorded" do
    assert File.read!(@golden) == render()
  end

  test "the golden covers every orientation and scale" do
    recorded =
      @golden
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(fn line -> line |> String.split(" ") |> Enum.take(2) |> Enum.join(" ") end)

    expected = for o <- @orientations, {n, _} <- scales(), do: "#{o} #{n}"
    assert recorded == expected
  end
end
