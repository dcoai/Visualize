defmodule Examples.Charts.WorldGeography do
  @moduledoc """
  World geography for the gallery's maps (#129, #499): the land of Natural Earth's 1:110m
  physical vectors, `ne_110m_land` — coastlines and islands, no borders — and a graticule.

  The land is stored as GeoJSON beside the app, `priv/geo/ne_110m_land.geojson`, with its
  source, version and checksum in the README there. It is read and decoded when this
  module compiles (`@external_resource`), so `land/0` is a pure function, and nothing is
  fetched at build or test time. Natural Earth is public domain; the maps credit it.

  The two geo designs read it as rows: `land/0`, one row per land mass with a stable id
  under `name` and its GeoJSON feature under `shape`, and `graticule/1`, one row per
  meridian and parallel at the given step with the line under `shape`, each the geometry a
  `:projection` step over `field: :shape` turns into a path (spec/14 §5.4.4).
  """

  @land_file Path.expand("../../../priv/geo/ne_110m_land.geojson", __DIR__)
  @external_resource @land_file

  # Natural Earth's land features carry no names, so a row's `name` is its place in the
  # file — stable while the file is — which the maps' color scale reads as a category.
  @land (for {feature, n} <- Enum.with_index(Jason.decode!(File.read!(@land_file))["features"], 1) do
           %{name: "land-#{n}", shape: feature}
         end)

  @doc """
  One row per land mass of Natural Earth's 1:110m land, in the file's order: `name`, the
  id `"land-<n>"` (1-based), and `shape`, the GeoJSON feature as the file holds it.
  """
  @spec land() :: [map()]
  def land, do: @land

  @doc """
  The graticule at `step` degrees as rows: `kind` (`:meridian` or `:parallel`), `degree`
  and `shape`, the `LineString` sampled every five degrees. The equator and the prime
  meridian are the lines at degree 0.
  """
  @spec graticule(pos_integer()) :: [map()]
  def graticule(step) do
    meridians =
      for lon <- -180..(180 - step)//step do
        line(:meridian, lon, for(lat <- -90..90//5, do: [lon, lat]))
      end

    parallels =
      for lat <- (-90 + step)..(90 - step)//step do
        line(:parallel, lat, for(lon <- -180..180//5, do: [lon, lat]))
      end

    meridians ++ parallels
  end

  defp line(kind, degree, coordinates) do
    %{kind: kind, degree: degree, shape: %{"type" => "LineString", "coordinates" => coordinates}}
  end
end
