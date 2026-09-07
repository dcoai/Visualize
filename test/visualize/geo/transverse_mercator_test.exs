defmodule Visualize.Geo.TransverseMercatorTest do
  @moduledoc "D-51: the transverse Mercator inverse holds on the whole golden grid."
  use ExUnit.Case, async: true

  alias Visualize.Geo.Projection

  @lons [-170, -120, -60, -15, 0, 15, 60, 120, 170]
  @lats [-80, -60, -30, -5, 0, 5, 30, 60, 80]

  test "invert(project(p)) returns p on every grid point, including those that raised" do
    proj =
      Projection.new(:transverse_mercator) |> Projection.scale(100) |> Projection.translate(0, 0)

    for lon <- @lons, lat <- @lats do
      {x, y} = Projection.project(proj, lon, lat)
      {ilon, ilat} = Projection.invert(proj, x, y)
      assert_in_delta ilon, lon, 1.0e-6, "lon #{lon} lat #{lat}"
      assert_in_delta ilat, lat, 1.0e-6, "lon #{lon} lat #{lat}"
    end
  end
end
