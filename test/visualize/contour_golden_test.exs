defmodule Visualize.ContourGoldenTest do
  @moduledoc """
  Output golden for marching squares and density contours (spec/07 §6.3, §7.2, D-72).

  `test/support/contour_golden.txt` records `Visualize.Contour.compute/2`,
  `Visualize.Contour.render/2`, `Visualize.Contour.Density.compute/2` and
  `Visualize.Contour.Density.render/2` over fixed grids and points, recorded from the
  list-walking implementation D-72 replaced, so the indexed grid and the linear ring tracing
  are held to the same rings. Regenerate only when the tracing changes on purpose:

      mix run -e 'ExUnit.start(autorun: false); Code.require_file("test/visualize/contour_golden_test.exs"); Visualize.ContourGoldenTest.write!()'
  """
  use ExUnit.Case, async: true

  alias Visualize.Contour
  alias Visualize.Contour.Density

  @golden "test/support/contour_golden.txt"

  @plateau [[0, 0, 0, 0], [0, 5, 5, 0], [0, 5, 10, 5], [0, 0, 5, 0]]

  # Every grid keeps its corner values off its thresholds: a corner exactly on a threshold
  # is the degenerate case spec/07 §6.3 leaves open.
  def grids do
    :rand.seed(:exsss, {1, 2, 3})

    [
      {"plateau list", 4, 4, @plateau, [2.5, 7.5]},
      {"plateau count", 4, 4, @plateau, 4},
      {"random ints", 6, 5, for(_ <- 1..5, do: for(_ <- 1..6, do: :rand.uniform(10) + 0.25)),
       [3, 5.5, 8]},
      {"random floats", 20, 15, for(_ <- 1..15, do: for(_ <- 1..20, do: :rand.uniform() * 10)),
       6},
      {"sin cos", 30, 30,
       for(
         y <- 0..29,
         do: for(x <- 0..29, do: :math.sin(x / 3) * :math.cos(y / 4) * 10 + rem(x * y, 7))
       ), 8}
    ]
  end

  def points do
    for i <- 1..40, do: %{x: rem(i * 37, 150) + 10, y: rem(i * 53, 110) + 10, w: rem(i, 3) + 1}
  end

  def densities do
    for {w, h, bw, cs, th} <- [
          {160, 120, 10, 4, 5},
          {160, 120, 8, 5, [0.001, 0.003]},
          {80, 80, 5, 2, 3}
        ] do
      density =
        Density.new()
        |> Density.size(w, h)
        |> Density.bandwidth(bw)
        |> Density.cell_size(cs)
        |> Density.thresholds(th)
        |> Density.weight(& &1.w)

      {"density #{w}x#{h} bw#{bw} cs#{cs}", density}
    end
  end

  def render do
    contours =
      for {name, w, h, grid, thresholds} <- grids(), smooth? <- [true, false] do
        contour =
          Contour.new()
          |> Contour.size(w, h)
          |> Contour.thresholds(thresholds)
          |> Contour.smooth(smooth?)

        label = "#{name} smooth=#{smooth?}"
        nested = Contour.compute(contour, grid)
        flat = Contour.compute(contour, List.flatten(grid))

        [
          "#{label} flat=#{if flat == nested, do: "same", else: "DIFFERS"}",
          Enum.map(nested, &result_lines(label, &1)),
          Enum.map(Contour.render(contour, grid), &"#{label} path #{fmt(&1.value)} #{&1.path}")
        ]
      end

    densities =
      for {label, density} <- densities() do
        [
          Enum.map(Density.compute(density, points()), &result_lines(label, &1)),
          Enum.map(
            Density.render(density, points()),
            &"#{label} path #{fmt(&1.value)} #{&1.path}"
          )
        ]
      end

    [contours, densities]
    |> List.flatten()
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  def write!, do: File.write!(@golden, render())

  defp result_lines(label, %{value: value, type: "MultiPolygon", coordinates: polygons}) do
    Enum.map(polygons, fn [ring] ->
      "#{label} #{fmt(value)} " <>
        Enum.map_join(ring, " ", fn [x, y] -> "#{fmt(x)},#{fmt(y)}" end)
    end)
  end

  defp fmt(x) when is_float(x), do: :erlang.float_to_binary(x, decimals: 6)
  defp fmt(x) when is_integer(x), do: Integer.to_string(x)

  test "marching squares and density contours trace exactly as recorded" do
    assert File.read!(@golden) == render()
  end
end
