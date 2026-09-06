defmodule Visualize.Hooks.BrushTest do
  @moduledoc "The server-side brush helpers on one axis or two (spec/10 §6.3, D-29)."
  use ExUnit.Case, async: true

  alias Visualize.Hooks
  alias Visualize.Hooks.Brush
  alias Visualize.Scale

  @t0 ~U[2024-01-01 00:00:00Z]
  @t1 ~U[2024-01-02 00:00:00Z]

  defp x_scale, do: Scale.time() |> Scale.domain([@t0, @t1]) |> Scale.range([0, 240])
  defp y_scale, do: Scale.linear() |> Scale.domain([0, 100]) |> Scale.range([200, 0])

  # An "x" brush without an extent: y0 = y1 is where the pointer happened to be.
  @x_selection %{x0: 60.0, y0: 37.5, x1: 120.0, y1: 37.5}
  @y_selection %{x0: 0, y0: 50.0, x1: 240, y1: 150.0}
  @xy_selection %{x0: 60.0, y0: 50.0, x1: 120.0, y1: 150.0}

  defp data do
    for h <- 0..23 do
      %{at: DateTime.add(@t0, h * 3600, :second), value: h * 4}
    end
  end

  describe "selection_to_domain/2" do
    test "an x brush is a {start, stop} pair of domain values" do
      assert Brush.selection_to_domain(@x_selection, x_scale: x_scale()) ==
               {~U[2024-01-01 06:00:00Z], ~U[2024-01-01 12:00:00Z]}
    end

    test "a y brush is a pair in pixel order, larger value first under a flipped range" do
      assert {75.0, 25.0} = Brush.selection_to_domain(@y_selection, y_scale: y_scale())
    end

    test "one axis needs only that axis's keys" do
      assert {~U[2024-01-01 06:00:00Z], ~U[2024-01-01 12:00:00Z]} =
               Brush.selection_to_domain(%{x0: 60.0, x1: 120.0}, x_scale: x_scale())
    end

    test "both scales keep the four-key map" do
      assert Brush.selection_to_domain(@xy_selection, x_scale: x_scale(), y_scale: y_scale()) ==
               %{
                 x0: ~U[2024-01-01 06:00:00Z],
                 x1: ~U[2024-01-01 12:00:00Z],
                 y0: 75.0,
                 y1: 25.0
               }
    end

    test "no scale is an ArgumentError" do
      assert_raise ArgumentError, fn -> Brush.selection_to_domain(@xy_selection, []) end
    end

    test "through Visualize.Hooks" do
      assert {_, _} = Hooks.selection_to_domain(@x_selection, x_scale: x_scale())
    end
  end

  describe "filter_selection/3" do
    test "an x brush keeps the data in the time band whatever their y" do
      kept = Brush.filter_selection(data(), @x_selection, x_accessor: & &1.at, x_scale: x_scale())
      assert Enum.map(kept, & &1.at.hour) == Enum.to_list(6..12)
    end

    test "a y brush keeps the data in the value band" do
      kept =
        Brush.filter_selection(data(), @y_selection, y_accessor: & &1.value, y_scale: y_scale())

      assert Enum.map(kept, & &1.value) == [28, 32, 36, 40, 44, 48, 52, 56, 60, 64, 68, 72]
    end

    test "both axes is the rectangle test" do
      kept =
        Brush.filter_selection(data(), @xy_selection,
          x_accessor: & &1.at,
          x_scale: x_scale(),
          y_accessor: & &1.value,
          y_scale: y_scale()
        )

      assert Enum.map(kept, & &1.at.hour) == Enum.to_list(7..12)
    end

    test "a scale without its accessor is a KeyError; no scale is an ArgumentError" do
      assert_raise KeyError, fn ->
        Brush.filter_selection(data(), @x_selection, x_scale: x_scale())
      end

      assert_raise ArgumentError, fn ->
        Brush.filter_selection(data(), @x_selection, x_accessor: & &1.at)
      end
    end

    test "through Visualize.Hooks" do
      assert length(
               Hooks.filter_selection(data(), @x_selection,
                 x_accessor: & &1.at,
                 x_scale: x_scale()
               )
             ) == 7
    end
  end
end
