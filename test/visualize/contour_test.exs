defmodule Visualize.ContourTest do
  @moduledoc """
  The cost guards of spec/07 §6.3 and §7.2 (D-72): the default density grid is usable, and
  the marching squares cost grows about linearly in the cells. Bounds, not benchmarks —
  the module is synchronous so no other test shares the scheduler while it times.
  """
  use ExUnit.Case, async: false

  alias Visualize.Contour
  alias Visualize.Contour.Density

  @points [
    %{x: 100, y: 100},
    %{x: 300, y: 250},
    %{x: 500, y: 120},
    %{x: 700, y: 400},
    %{x: 820, y: 60}
  ]

  # Milliseconds of the best of three runs, so a scheduler hiccup cannot fail a bound.
  defp best_of_three_ms(fun) do
    Enum.min(for _ <- 1..3, do: elem(:timer.tc(fun), 0)) / 1000
  end

  describe "the default density grid" do
    test "traces twenty contours over a handful of points well inside a second" do
      density = Density.new()
      {us, contours} = :timer.tc(fn -> Density.compute(density, @points) end)

      assert length(contours) == 20
      assert Enum.all?(contours, &(length(&1.coordinates) == length(@points)))
      assert us < 1_000_000, "took #{div(us, 1000)} ms — before D-72 two points took 159 s"
    end

    test "every default-grid ring is closed and in pixel coordinates" do
      for %{coordinates: polygons} <- Density.compute(Density.new(), @points),
          [ring] <- polygons do
        assert List.first(ring) == List.last(ring)
        assert Enum.all?(ring, fn [x, y] -> x >= 0 and x <= 960 and y >= 0 and y <= 500 end)
      end
    end
  end

  describe "cost against grid size" do
    defp wavy(n) do
      for y <- 0..(n - 1), x <- 0..(n - 1), do: :math.sin(x / 5) * :math.cos(y / 7) * 10
    end

    defp contour_ms(n) do
      contour = Contour.new() |> Contour.size(n, n) |> Contour.thresholds(10)
      grid = wavy(n)
      best_of_three_ms(fn -> Contour.compute(contour, grid) end)
    end

    test "four times the cells cost at most about five times the time" do
      # Quadratic in the cells — the list walk D-72 replaced — is fourteen times.
      small = contour_ms(101)
      large = contour_ms(201)

      assert large <= max(6 * small, 50),
             "101² took #{small} ms, 201² took #{large} ms (#{Float.round(large / small, 1)}×)"
    end

    test "four times the density cells cost at most about five times the time" do
      points = [%{x: 10, y: 10}, %{x: 30, y: 30}]

      small =
        best_of_three_ms(fn -> Density.compute(Density.size(Density.new(), 200, 200), points) end)

      large =
        best_of_three_ms(fn -> Density.compute(Density.size(Density.new(), 400, 400), points) end)

      assert large <= max(6 * small, 50),
             "51² took #{small} ms, 101² took #{large} ms (#{Float.round(large / small, 1)}×)"
    end
  end

  describe "the tracing terminates" do
    # A corner exactly on a threshold heads two segments from one point; before D-72 the
    # walk cycled forever. What such a grid should trace is #81's question — only the
    # return is held here.
    test "on the moduledoc grid with a threshold equal to a corner value" do
      grid = [[0, 0, 0, 0], [0, 5, 5, 0], [0, 5, 10, 5], [0, 0, 5, 0]]
      contour = Contour.new() |> Contour.size(4, 4) |> Contour.thresholds(3)
      task = Task.async(fn -> Contour.compute(contour, grid) end)

      assert {:ok, [%{value: 2.5}, %{value: 5.0}, %{value: 7.5}]} = Task.yield(task, 5_000)
    end
  end
end
