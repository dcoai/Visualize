defmodule Visualize.Chart.ChordCentreTest do
  @moduledoc """
  One centre for a chord diagram (spec/14 §5.4.3, #488): a `:chord` step's paths are about
  the point an `:arc` mark is about — the plot's middle, or the origin of a polar frame's
  centred group — and its `size` sets the radius only. So the ribbons' ends lie on the
  ring's inner edge at their group's angles whether the step is sized or not.
  """
  use ExUnit.Case, async: true

  import Visualize.Chart.Build

  alias Visualize.Chart
  alias Visualize.Chart.{Frame, Mark, Transform}
  alias Visualize.IR

  @flows for {from, to, value} <- [
               {"a", "a", 4},
               {"a", "b", 5},
               {"b", "c", 3},
               {"c", "a", 2},
               {"c", "d", 6},
               {"d", "b", 1}
             ],
             do: %{from: from, to: to, value: value}
  @sources %{flows: @flows}
  # A plot that is not square, so a centre on the wrong axis shows.
  @size {500, 400}

  # The ribbons and the ring of one design; `step` is the ribbons' extra options.
  defp design(frame, step, inner) do
    {:ok, design} =
      Chart.compose([
        chart(),
        source(:flows, [:from, :to, :value]),
        frame,
        ordinal_scale(:color),
        path(
          chord(:flows, [:from, :to], :value, [padding: 0.05, output: :chords] ++ step),
          %{path: :path}
        ),
        arc(
          chord(:flows, [:from, :to], :value, padding: 0.05),
          %{value: :value, start: :start_angle, end: :end_angle},
          options: %{inner_radius: inner, outer_radius: inner / 0.9}
        )
      ])

    chart = Chart.from_map!(design)
    frame = Frame.new(chart, sources: @sources, size: @size)
    [ribbons, ring] = chart.marks
    {frame, ribbons, ring}
  end

  # The point an `:arc` mark's group is about, in plot coordinates.
  defp ring_centre(frame, ring) do
    case Mark.generate(frame, ring, sources: @sources).transform do
      nil -> {0, 0}
      %IR.Transform{operations: [{:translate, x, y}]} -> {x, y}
    end
  end

  # Every end point of a ribbon — the move, each arc's end, each curve's end — and the
  # curves' control points.
  defp ends(%IR.Path{commands: commands}) do
    Enum.flat_map(commands, fn
      {:M, x, y} -> [{x, y}]
      {:A, _, _, _, _, _, x, y} -> [{x, y}]
      {:Q, _, _, x, y} -> [{x, y}]
      _ -> []
    end)
  end

  defp controls(%IR.Path{commands: commands}),
    do: for({:Q, x, y, _, _} <- commands, do: {x, y})

  # The angle of a point about the centre, clockwise from 12 o'clock in [0, 2π).
  defp angle({x, y}, {cx, cy}) do
    a = :math.atan2(x - cx, -(y - cy))
    if a < 0, do: a + 2 * :math.pi(), else: a
  end

  defp assert_on_ring(frame, ribbons, ring, inner) do
    centre = ring_centre(frame, ring)
    groups = Map.new(Mark.rows(frame, ring, @sources), &{&1.id, &1})
    rows = Mark.rows(frame, ribbons, @sources)
    assert rows != []

    for %{source: source, target: target, path: path} <- rows do
      for {x, y} = point <- ends(path) do
        {cx, cy} = centre
        assert_in_delta :math.sqrt((x - cx) ** 2 + (y - cy) ** 2), inner, 1.0e-6

        # Each end lies within the arc of the ribbon's own source or target group.
        a = angle(point, centre)

        assert Enum.any?([groups[source], groups[target]], fn g ->
                 a >= g.start_angle - 1.0e-6 and a <= g.end_angle + 1.0e-6
               end)
      end

      for {x, y} <- controls(path) do
        {cx, cy} = centre
        assert_in_delta x, cx, 1.0e-6
        assert_in_delta y, cy, 1.0e-6
      end
    end

    centre
  end

  describe "a cartesian frame" do
    @zero %{top: 0, right: 0, bottom: 0, left: 0}

    test "with no size the ribbons meet the ring at 0.9 of the plot's radius, at its centre" do
      # The plot is 500 × 400, so R is 200 and the ring's inner edge 180.
      {frame, ribbons, ring} = design(cartesian(margin: @zero), [], 180.0)
      assert assert_on_ring(frame, ribbons, ring, 180.0) == {250.0, 200.0}
    end

    test "with a size the ribbons keep the plot's centre and take only their radius" do
      # A 300 × 340 step: R is 150, the inner edge 135 — and still about (250, 200),
      # never the size's own middle (150, 170).
      {frame, ribbons, ring} = design(cartesian(margin: @zero), [size: [300, 340]], 135.0)
      assert assert_on_ring(frame, ribbons, ring, 135.0) == {250.0, 200.0}
    end

    test "with margins the centre is the plot's, as the arc mark's is" do
      margin = %{top: 20, right: 40, bottom: 60, left: 10}
      {frame, ribbons, ring} = design(cartesian(margin: margin), [size: [200, 200]], 90.0)
      # The plot is 450 × 320.
      assert assert_on_ring(frame, ribbons, ring, 90.0) == {225.0, 160.0}
    end
  end

  test "in a polar frame the ribbons are about the centred group's origin, as the arc is" do
    {frame, ribbons, ring} = design(polar(), [size: [300, 300]], 135.0)
    assert Mark.generate(frame, ring, sources: @sources).transform == nil
    assert assert_on_ring(frame, ribbons, ring, 135.0) == {0, 0}
  end

  describe "the step alone" do
    test "is about centre:, with size setting the radius only" do
      [%{path: path} | _] =
        Transform.apply(
          [%{op: :chord, fields: [:from, :to], field: :value, output: :chords, size: [100, 60]}],
          @flows,
          size: [500, 400],
          centre: [250, 200]
        )

      assert [{250.0, 200.0} | _] = controls(path)
      [{x, y} | _] = ends(path)
      assert_in_delta :math.sqrt((x - 250) ** 2 + (y - 200) ** 2), 27.0, 1.0e-6
    end

    test "defaults its centre to the middle of size:" do
      [%{path: path} | _] =
        Transform.apply(
          [%{op: :chord, fields: [:from, :to], field: :value, output: :chords}],
          @flows,
          size: [500, 400]
        )

      assert [{250.0, 200.0} | _] = controls(path)
    end
  end
end
