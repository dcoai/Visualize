defmodule Visualize.ContourTest do
  @moduledoc """
  The cost guards of spec/07 §6.3 and §7.2 (D-72): the default density grid is usable, and
  the marching squares cost grows about linearly in the cells. Bounds, not benchmarks —
  the module is synchronous so no other test shares the scheduler while it times.
  """
  use ExUnit.Case, async: false

  alias Visualize.Contour
  alias Visualize.Contour.Density

  doctest Contour

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

    # D-72 by count, not by clock (#271): the tracing follows each segment at most once and
    # the grid is read once per threshold, whatever its size — a wall-clock ratio moved by
    # a third between runs on a shared box and said nothing about the algorithm.
    test "the tracing is linear in the segments and the grid is read once per threshold" do
      for n <- [101, 201] do
        contour = Contour.new() |> Contour.size(n, n) |> Contour.thresholds(10)
        cost = Contour.cost(contour, wavy(n))

        assert cost.hops <= cost.segments,
               "#{n}²: #{cost.hops} hops over #{cost.segments} segments"

        assert cost.reads == (n + 1) * (n + 1) * 10
        assert cost.segments > 0
      end

      # Four times the cells is about four times the work — the reads exactly, and the
      # segments and the hops within the ratio a doubled contour length gives.
      small =
        Contour.cost(Contour.new() |> Contour.size(101, 101) |> Contour.thresholds(10), wavy(101))

      large =
        Contour.cost(Contour.new() |> Contour.size(201, 201) |> Contour.thresholds(10), wavy(201))

      assert large.reads / small.reads < 4.0
      assert large.hops / small.hops < 4.5
    end

    # A smoke, not a ratio (#271): the claim is *usable* — D-72's 159 s became milliseconds
    # — so the bound is generous and absolute, and a shared box cannot trip it by noise.
    test "a density on a plot-sized grid is milliseconds, not seconds" do
      points = [%{x: 10, y: 10}, %{x: 30, y: 30}]

      large =
        best_of_three_ms(fn -> Density.compute(Density.size(Density.new(), 400, 400), points) end)

      assert large < 2000, "400² took #{large} ms"
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
