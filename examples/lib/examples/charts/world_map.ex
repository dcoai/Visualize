defmodule Examples.Charts.WorldMap do
  @moduledoc "World map with selectable projections"

  alias Visualize.Geo.{Projection, Path}
  alias Visualize.SVG.Element
  alias Examples.ColorPalettes
  alias Examples.Charts.WorldGeography

  # Graticule lines (longitude/latitude grid)
  @graticule_lons (for lon <- -180..180//30, do: lon)
  @graticule_lats (for lat <- -90..90//30, do: lat)

  def title, do: "World Map"
  def description, do: "Natural Earth projection with graticule"

  def render(opts \\ []) do
    width = opts[:width] || 700
    height = opts[:height] || 400
    animation_tick = opts[:animation_tick]
    palette = opts[:palette] || :default
    colors = ColorPalettes.colors(palette)

    # Animate by slowly rotating the map center
    {center_lon, center_lat} = if animation_tick do
      lon = rem(animation_tick * 2, 360) - 180
      {lon, 0}
    else
      {0, 0}
    end

    # Create projection
    projection = Projection.new(:natural_earth)
      |> Projection.scale(width / 5.5)
      |> Projection.translate(width / 2, height / 2)
      |> Projection.center(center_lon, center_lat)

    geo_path = Path.new(projection)

    # Calculate ellipse parameters for clipping
    cx = width / 2
    cy = height / 2
    rx = width / 2 - 20
    ry = height / 2 - 20

    # Create clip path for the projection boundary
    clip_id = "world-map-clip"
    clip_ellipse = Element.ellipse(%{cx: cx, cy: cy, rx: rx, ry: ry})
    clip_path_elem = Element.clipPath(%{id: clip_id})
      |> Element.append(clip_ellipse)
    defs = Element.defs(%{})
      |> Element.append(clip_path_elem)

    # Ocean background inside the ellipse
    ocean = Element.ellipse(%{
      cx: cx,
      cy: cy,
      rx: rx,
      ry: ry,
      fill: "#a8d5e5"
    })

    # Draw graticule
    graticule_elements = render_graticule(geo_path, width, height)

    # Draw land masses
    world_data = WorldGeography.world_data()
    land_elements = world_data["features"]
      |> Enum.with_index()
      |> Enum.map(fn {feature, idx} ->
        path_data = Path.render(geo_path, feature)
        color = Enum.at(colors, rem(idx, length(colors)))

        Element.path(%{
          d: path_data,
          fill: color,
          fill_opacity: 0.8,
          stroke: darken(color),
          stroke_width: 0.5
        })
      end)

    # Group content that needs clipping
    clipped_content = Element.g(%{clip_path: "url(##{clip_id})"})
      |> Element.append(ocean)
      |> Element.append(graticule_elements)
      |> Element.append(land_elements)

    # Sphere outline (drawn on top, not clipped)
    sphere_outline = Element.ellipse(%{
      cx: cx,
      cy: cy,
      rx: rx,
      ry: ry,
      fill: "none",
      stroke: "#666",
      stroke_width: 1.5
    })

    Element.svg(%{width: width, height: height, viewBox: "0 0 #{width} #{height}"})
    |> Element.append(
      Element.rect(%{width: width, height: height, fill: "#e8f4f8"})
    )
    |> Element.append(defs)
    |> Element.append(clipped_content)
    |> Element.append(sphere_outline)
  end

  defp render_graticule(geo_path, _width, _height) do
    # Longitude lines
    lon_lines = Enum.map(@graticule_lons, fn lon ->
      coords = for lat <- -90..90//5, do: [lon, lat]
      geojson = %{"type" => "LineString", "coordinates" => coords}
      path_data = Path.render(geo_path, geojson)

      Element.path(%{
        d: path_data,
        fill: "none",
        stroke: "#ccc",
        stroke_width: 0.5,
        stroke_opacity: 0.5
      })
    end)

    # Latitude lines
    lat_lines = Enum.map(@graticule_lats, fn lat ->
      coords = for lon <- -180..180//5, do: [lon, lat]
      geojson = %{"type" => "LineString", "coordinates" => coords}
      path_data = Path.render(geo_path, geojson)

      Element.path(%{
        d: path_data,
        fill: "none",
        stroke: "#ccc",
        stroke_width: if(lat == 0, do: 1, else: 0.5),
        stroke_opacity: if(lat == 0, do: 0.8, else: 0.5)
      })
    end)

    Element.g(%{})
    |> Element.append(lon_lines)
    |> Element.append(lat_lines)
  end

  defp darken("#" <> hex) do
    {r, ""} = Integer.parse(String.slice(hex, 0, 2), 16)
    {g, ""} = Integer.parse(String.slice(hex, 2, 2), 16)
    {b, ""} = Integer.parse(String.slice(hex, 4, 2), 16)

    r = trunc(r * 0.7)
    g = trunc(g * 0.7)
    b = trunc(b * 0.7)

    "#" <>
      (Integer.to_string(r, 16) |> String.pad_leading(2, "0")) <>
      (Integer.to_string(g, 16) |> String.pad_leading(2, "0")) <>
      (Integer.to_string(b, 16) |> String.pad_leading(2, "0"))
  end

  def sample_code do
    ~S"""
    alias Visualize.Geo.{Projection, Path}

    projection = Projection.new(:natural_earth)
      |> Projection.scale(150)
      |> Projection.translate(width / 2, height / 2)

    geo_path = Path.new(projection)

    # Render GeoJSON
    path_data = Path.render(geo_path, geojson_feature)

    # Available projections:
    # :mercator, :orthographic, :natural_earth,
    # :mollweide, :equal_earth, :robinson, etc.
    """
  end
end
