defmodule Visualize.ContourTest do
  @moduledoc """
  The cost guards of spec/07 §6.3 and §7.2 (D-72): the default density grid is usable, and
  the marching squares cost grows about linearly in the cells. Held by count, never by
  clock (spec/12 §6, D-114, #271, #462): the time a run takes is a `:benchmark` test.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Visualize.Contour
  alias Visualize.Contour.Density
  alias Visualize.Work

  doctest Contour

  @points [
    %{x: 100, y: 100},
    %{x: 300, y: 250},
    %{x: 500, y: 120},
    %{x: 700, y: 400},
    %{x: 820, y: 60}
  ]

  # Forty reductions per padded cell per threshold: the grid a density traces is its
  # plot over the cell size, plus one, padded by one each side.
  defp density_budget(%Density{} = density) do
    columns = div(density.width, density.cell_size) + 3
    rows = div(density.height, density.cell_size) + 3
    40 * columns * rows * density.thresholds
  end

  describe "the default density grid" do
    # Usable, stated as work (spec/07 §7.2, D-72): about fifteen reductions per padded
    # cell per threshold. The list-walking grid D-72 replaced spent 371 million calls on a
    # 51 × 51 grid, and two points on this one took 159 s.
    test "traces twenty contours over a handful of points within a budget per cell" do
      density = Density.new()
      {work, contours} = Work.reductions(fn -> Density.compute(density, @points) end)

      assert length(contours) == 20
      assert Enum.all?(contours, &(length(&1.coordinates) == length(@points)))

      budget = density_budget(density)
      assert work < budget, "#{work} reductions against a budget of #{budget}"
    end

    # A point touches the cells of its footprint, never the whole grid (spec/07 §7.2):
    # ten times the points is a small part of the grid's own cost.
    test "ten times the points costs under one and a half times the work" do
      points = fn n ->
        for i <- 1..n, do: %{x: rem(i * 37, 900) + 30, y: rem(i * 53, 450) + 25}
      end

      {five, _} = Work.reductions(fn -> Density.compute(Density.new(), points.(5)) end)
      {fifty, _} = Work.reductions(fn -> Density.compute(Density.new(), points.(50)) end)

      assert fifty < five * 1.5,
             "fifty points cost #{Float.round(fifty / five, 2)}x five points' reductions"
    end

    # The time it takes, stated rather than gated: `mix test --only benchmark`.
    @tag :benchmark
    test "the default grid's time over a handful of points" do
      {us, contours} = :timer.tc(fn -> Density.compute(Density.new(), @points) end)
      IO.puts("\ndefault density grid over #{length(@points)} points: #{div(us, 1000)} ms")
      assert length(contours) == 20
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

    # *Usable* at another size, by the same budget as the default grid's (#271, #462).
    test "a density on a plot-sized grid is within the budget per cell" do
      density = Density.size(Density.new(), 400, 400)

      {work, _} =
        Work.reductions(fn -> Density.compute(density, [%{x: 10, y: 10}, %{x: 30, y: 30}]) end)

      budget = density_budget(density)
      assert work < budget, "400²: #{work} reductions against a budget of #{budget}"
    end
  end

  describe "the tracing terminates" do
    # A corner exactly on a threshold headed two segments from one point; before D-72 the
    # walk cycled forever, and until D-112 (#81) the ring through it closed early.
    test "on the moduledoc grid with a threshold equal to a corner value" do
      grid = [[0, 0, 0, 0], [0, 5, 5, 0], [0, 5, 10, 5], [0, 0, 5, 0]]
      contour = Contour.new() |> Contour.size(4, 4) |> Contour.thresholds(3)
      task = Task.async(fn -> Contour.compute(contour, grid) end)

      assert {:ok, [%{value: 2.5}, %{value: 5.0}, %{value: 7.5}]} = Task.yield(task, 5_000)
    end
  end

  describe "a corner on a threshold (spec/07 §6.3, D-112)" do
    # The moduledoc grid at 5: four corners sit on the threshold. Every ring closes, on its
    # exact start, with at least four points — no two-point polyline.
    test "traces closed rings of at least four points, smoothing on and off" do
      grid = [[0, 0, 0, 0], [0, 5, 5, 0], [0, 5, 10, 5], [0, 0, 5, 0]]

      for smooth? <- [true, false] do
        contour =
          Contour.new()
          |> Contour.size(4, 4)
          |> Contour.thresholds([5])
          |> Contour.smooth(smooth?)

        [%{value: 5, coordinates: polygons}] = Contour.compute(contour, grid)
        assert polygons != []
        Enum.each(polygons, fn [ring] -> assert_closed(ring) end)
      end
    end

    test "the crossing sits a hair along each edge of the corner, never on it" do
      grid = [[0, 0, 0], [0, 5, 0], [0, 0, 0]]
      contour = Contour.new() |> Contour.size(3, 3) |> Contour.thresholds([5])
      [%{coordinates: polygons}] = Contour.compute(contour, grid)

      points = for [ring] <- polygons, point <- ring, do: point
      refute [1, 1] in points
      assert Enum.any?(points, fn [x, y] -> abs(x - 1) < 1.0e-5 and abs(y - 1) < 1.0e-5 end)
    end

    test "render/2 closes every ring with Z" do
      grid = [[0, 0, 0, 0], [0, 5, 5, 0], [0, 5, 10, 5], [0, 0, 5, 0]]
      contour = Contour.new() |> Contour.size(4, 4) |> Contour.thresholds([5])
      [%{path: path}] = Contour.render(contour, grid)

      assert path != ""
      for ring <- String.split(path, "M", trim: true), do: assert(String.ends_with?(ring, "Z"))
    end

    # Random small integer grids and integer thresholds put corners on thresholds all over:
    # the tracing returns, and every ring is closed with at least four points.
    property "every ring of a random integer grid is closed with at least four points" do
      check all(
              width <- integer(2..6),
              height <- integer(2..6),
              grid <- list_of(list_of(integer(0..4), length: width), length: height),
              threshold <- integer(1..4),
              smooth? <- boolean(),
              max_runs: 200
            ) do
        contour =
          Contour.new()
          |> Contour.size(width, height)
          |> Contour.thresholds([threshold])
          |> Contour.smooth(smooth?)

        [%{value: ^threshold, coordinates: polygons}] = Contour.compute(contour, grid)
        Enum.each(polygons, fn [ring] -> assert_closed(ring) end)
      end
    end

    defp assert_closed(ring) do
      assert length(ring) >= 4, "a ring of #{length(ring)} points: #{inspect(ring)}"
      assert List.first(ring) == List.last(ring), "an open ring: #{inspect(ring)}"
    end
  end
end
