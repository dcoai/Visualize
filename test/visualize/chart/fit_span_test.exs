defmodule Visualize.Chart.FitSpanTest do
  @moduledoc """
  A fit's minimum span (spec/14 §4.6, #828, D-212): points that coincide still fit to a view
  of at least `min_span` meters on the ground, points that reach farther fit as before,
  and `0` adds nothing.
  """
  use ExUnit.Case, async: true

  alias Visualize.Chart
  alias Visualize.Geo.Projection

  @size {400, 300}
  @radius 6_371_008.8

  defp frame(points, fit) do
    design = %{
      version: 3,
      sources: %{points: %{fields: [:lon, :lat]}},
      frames: %{
        main: %{
          kind: :geo,
          margin: %{top: 0, right: 0, bottom: 0, left: 0},
          projection: %{
            type: :mercator,
            fit: Map.merge(%{data: :points, fields: [:lon, :lat]}, fit)
          }
        }
      }
    }

    {:ok, applied} = Chart.apply(design, sources: %{points: points}, size: @size)
    applied.frames["main"]
  end

  # Meters on the ground across the plot's height, at the plot's middle: the latitudes of
  # its top and bottom edges, along the meridian.
  defp ground_height(frame) do
    {w, h} = @size
    {_, top} = Projection.invert(frame.projection, w / 2, 0)
    {_, bottom} = Projection.invert(frame.projection, w / 2, h)
    abs(top - bottom) * :math.pi() / 180 * @radius
  end

  @finish [%{lon: -92.0938, lat: 46.781}, %{lon: -92.0938, lat: 46.781}]
  @spread [%{lon: -92.10, lat: 46.77}, %{lon: -92.00, lat: 46.85}]

  test "points that coincide fit to the span: the tighter axis holds it exactly" do
    # The plot is wider than tall, and a span is the same both ways, so the height binds.
    assert_in_delta ground_height(frame(@finish, %{min_span: 500})), 500, 1
    assert_in_delta ground_height(frame(@finish, %{min_span: 2_000})), 2_000, 4
  end

  test "the span is about the points' center, which stays in the middle of the plot" do
    frame = frame(@finish, %{min_span: 500})
    {x, y} = Projection.project(frame.projection, -92.0938, 46.781)
    assert_in_delta x, 200, 1.0e-6
    # Mercator stretches north of the middle a little more than south of it.
    assert_in_delta y, 150, 0.01
  end

  test "points that reach farther than the span fit as without it" do
    assert frame(@spread, %{min_span: 500}).projection == frame(@spread, %{}).projection
  end

  test "0, the default, adds nothing" do
    assert Chart.Schema.default(:fit, :min_span) == 0
    assert frame(@spread, %{min_span: 0}).projection == frame(@spread, %{}).projection
    assert frame(@finish, %{min_span: 0}).projection == frame(@finish, %{}).projection
  end
end
