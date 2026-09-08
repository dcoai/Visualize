defmodule Visualize.Shape.TabularTest do
  @moduledoc """
  Every list-taking generator, `Contour.Density.compute/2` and the chart components accept
  what `Visualize.Data.Table.rows/1` accepts (spec/04 §1.4, spec/07 §7.1, spec/10 §1.2).
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Explorer.DataFrame
  alias Visualize.Components
  alias Visualize.Contour.Density
  alias Visualize.Shape
  alias Visualize.Shape.{Band, PercentileBand, Rose, Rule, XBand}

  @rows [%{t: 1, v: 10.0, w: 4.0}, %{t: 2, v: 20.0, w: 6.0}, %{t: 3, v: 15.0, w: 5.0}]
  @columns %{t: [1, 2, 3], v: [10.0, 20.0, 15.0], w: [4.0, 6.0, 5.0]}
  defp frame, do: DataFrame.new(@columns)

  describe "line, area and the facade" do
    test "a line from an Explorer frame renders the same path as from the row list" do
      line = Shape.line() |> Shape.x(:t) |> Shape.y(:v)
      assert Shape.generate(line, frame()) == Shape.generate(line, @rows)
      assert Shape.generate(line, @rows) == "M1,10L2,20L3,15"
    end

    test "string accessors read atom-keyed rows and Explorer's string columns alike" do
      line = Shape.line() |> Shape.x("t") |> Shape.y("v")
      assert Shape.generate(line, @rows) == "M1,10L2,20L3,15"
      assert Shape.generate(line, frame()) == "M1,10L2,20L3,15"
    end

    test "a column map and a keyword list of columns generate the row list's path" do
      line = Shape.line() |> Shape.x(:t) |> Shape.y(:v)
      expected = Shape.generate_path(line, @rows)
      assert Shape.generate_path(line, @columns) == expected
      assert Shape.generate_path(line, Map.to_list(@columns)) == expected
    end

    test "a rank-2 tensor feeds the default tuple accessors" do
      assert Shape.generate(Shape.line(), Nx.tensor([[1, 10], [2, 20]])) == "M1,10L2,20"
    end

    test "an area from a column map is the area from rows" do
      area = Shape.area() |> Shape.x(:t) |> Shape.y0(0) |> Shape.y1(:v)
      assert Shape.generate(area, @columns) == Shape.generate(area, @rows)
    end

    test "defined/2 still splits runs on tabular data" do
      line = Shape.line() |> Shape.x(:t) |> Shape.y(:v) |> Shape.defined(&(&1.t != 2))
      assert Shape.generate(line, %{t: [1, 2, 3, 4], v: [1, 1, 1, 1]}) == "M3,1L4,1"
    end
  end

  describe "pie and stack" do
    # Each arc and point carries its datum as `:data`; a frame's datum is string-keyed, a
    # row's atom-keyed, so the geometry is compared without it.
    defp without_data(arcs), do: Enum.map(arcs, &Map.delete(&1, :data))

    defp without_point_data(series) do
      Enum.map(series, fn s -> %{s | points: without_data(s.points)} end)
    end

    test "a pie from an Explorer frame is the pie from rows" do
      pie = Shape.pie() |> Shape.value(:v)

      assert without_data(Shape.generate(pie, frame())) ==
               without_data(Shape.generate(pie, @rows))
    end

    test "a nil or absent value is a zero slice" do
      pie = Shape.pie() |> Shape.value(:v)
      [a, b, c] = Shape.generate(pie, [%{v: nil}, %{}, %{v: 3}])
      assert a.value == 0 and b.value == 0 and c.value == 3
    end

    test "the default value accessor reads a map's :value of either spelling" do
      [a, b] = Shape.generate(Shape.pie(), [%{"value" => 1}, %{value: nil}])
      assert a.value == 1 and b.value == 0
    end

    test "stack keys reach Explorer's string columns" do
      stack = Shape.stack() |> Shape.keys([:v, :w])

      assert without_point_data(Shape.generate(stack, frame())) ==
               without_point_data(Shape.generate(stack, @rows))
    end

    test "a stack's nil value stacks as zero" do
      [%{points: [p]}] = Shape.generate(Shape.stack() |> Shape.keys([:v]), [%{v: nil}])
      assert {p.value, p.y0, p.y1} == {0, 0, 0}
    end

    test "an empty column map is no series" do
      assert Shape.generate(Shape.stack() |> Shape.keys([:v]), %{}) == []
    end
  end

  describe "band, rule, x_band, percentile_band and rose" do
    test "band elements from a column map equal those from rows" do
      band = Band.new() |> Band.x0(:t) |> Band.x1(:w) |> Band.y(:v) |> Band.height(2)
      assert Band.generate(band, @columns) == Band.generate(band, @rows)
      assert Band.generate_path(band, frame()) == Band.generate_path(band, @rows)
    end

    test "rule elements from an Explorer frame equal those from rows" do
      rule = Rule.new() |> Rule.x(:t) |> Rule.y0(0) |> Rule.y1(:v)
      assert Rule.generate(rule, frame()) == Rule.generate(rule, @rows)
    end

    test "x_band elements from a keyword list equal those from rows" do
      band = XBand.new() |> XBand.x0(:t) |> XBand.x1(:w) |> XBand.y0(0) |> XBand.y1(:v)
      assert XBand.generate(band, Map.to_list(@columns)) == XBand.generate(band, @rows)
    end

    test "a percentile band from a column map equals the band from rows" do
      band =
        PercentileBand.new()
        |> PercentileBand.x(:t)
        |> PercentileBand.median(:v)
        |> PercentileBand.inner({:w, :v})

      assert PercentileBand.generate(band, @columns) == PercentileBand.generate(band, @rows)
    end

    test "rose paths from an Explorer frame equal those from rows" do
      rose = Rose.new() |> Rose.angle(:t) |> Rose.width(0.5) |> Rose.outer_radius(:v)
      assert Rose.generate(rose, frame()) == Rose.generate(rose, @rows)
    end
  end

  describe "density" do
    test "density contours from a column map equal those from rows" do
      density =
        Density.new() |> Density.size(40, 40) |> Density.cell_size(10) |> Density.thresholds(3)

      rows = [%{x: 10, y: 10}, %{x: 30, y: 30}]

      assert Density.compute(density, %{x: [10, 30], y: [10, 30]}) ==
               Density.compute(density, rows)
    end

    test "the default accessors read either spelling and a tuple" do
      density =
        Density.new() |> Density.size(40, 40) |> Density.cell_size(10) |> Density.thresholds(3)

      from_strings = Density.compute(density, [%{"x" => 10, "y" => 10}, %{"x" => 30, "y" => 30}])
      assert from_strings == Density.compute(density, [{10, 10}, {30, 30}])
    end
  end

  describe "components" do
    @series_rows [%{at: 1, value: 4}, %{at: 2, value: 9}, %{at: 3, value: 2}]
    @series_columns %{at: [1, 2, 3], value: [4, 9, 2]}

    test "a line chart from a column map renders the line chart from rows" do
      assigns = %{x: & &1.at, y: & &1.value}

      assert render_component(&Components.line_chart/1, Map.put(assigns, :data, @series_columns)) ==
               render_component(&Components.line_chart/1, Map.put(assigns, :data, @series_rows))
    end

    test "every chart component takes an Explorer frame" do
      frame = DataFrame.new(@series_columns)
      by_string = %{x: & &1["at"], y: & &1["value"]}
      by_atom = %{x: & &1.at, y: & &1.value}

      for component <- [
            &Components.line_chart/1,
            &Components.bar_chart/1,
            &Components.horizontal_bar_chart/1,
            &Components.scatter_plot/1,
            &Components.area_chart/1
          ] do
        assert render_component(component, Map.put(by_string, :data, frame)) ==
                 render_component(component, Map.put(by_atom, :data, @series_rows))
      end

      pie = &Components.pie_chart/1

      assert render_component(pie, %{data: frame, value: & &1["value"], label: & &1["at"]}) ==
               render_component(pie, %{data: @series_rows, value: & &1.value, label: & &1.at})

      stacked = &Components.stacked_bar_chart/1
      stacked_frame = DataFrame.new(month: ["a", "b"], apples: [1, 2], pears: [3, 4])
      stacked_rows = [%{month: "a", apples: 1, pears: 3}, %{month: "b", apples: 2, pears: 4}]

      assert render_component(stacked, %{
               data: stacked_frame,
               x: & &1["month"],
               keys: [:apples, :pears]
             }) ==
               render_component(stacked, %{
                 data: stacked_rows,
                 x: & &1.month,
                 keys: [:apples, :pears]
               })
    end
  end
end
