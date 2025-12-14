defmodule Examples.Charts.Globe do
  @moduledoc "Rotating globe using orthographic projection"

  alias Visualize.Geo.{Projection, Path}
  alias Visualize.SVG.Element
  alias Examples.ColorPalettes
  alias Examples.Charts.WorldGeography

  def title, do: "Globe"
  def description, do: "Rotating orthographic projection"

  def render(opts \\ []) do
    width = opts[:width] || 500
    height = opts[:height] || 450
    animation_tick = opts[:animation_tick]
    palette = opts[:palette] || :default
    colors = ColorPalettes.colors(palette)

    # Calculate globe parameters
    size = min(width, height)
    radius = size / 2 - 20
    cx = width / 2
    cy = height / 2

    # Animate rotation
    {rotate_lon, rotate_lat} = if animation_tick do
      lon = rem(animation_tick * 2, 360)
      lat = 15 * :math.sin(animation_tick * 0.03)
      {-lon, -lat}
    else
      {0, -20}
    end

    # Create orthographic projection (globe view)
    projection = Projection.new(:orthographic)
      |> Projection.scale(radius)
      |> Projection.translate(cx, cy)
      |> Projection.rotate(rotate_lon, rotate_lat, 0)

    geo_path = Path.new(projection)

    # Create a unique clip path ID
    clip_id = "globe-clip"

    # Define clip path for the globe circle
    clip_circle = Element.circle(%{cx: cx, cy: cy, r: radius})
    clip_path_elem = Element.clipPath(%{id: clip_id})
      |> Element.append(clip_circle)
    defs = Element.defs(%{})
      |> Element.append(clip_path_elem)

    # Draw ocean (globe background)
    ocean = Element.circle(%{
      cx: cx,
      cy: cy,
      r: radius,
      fill: "#a8d5e5",
      stroke: "#666",
      stroke_width: 1
    })

    # Draw graticule
    graticule = render_graticule(geo_path)

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
          fill_opacity: 0.9,
          stroke: darken(color),
          stroke_width: 0.5
        })
      end)

    # Group content that needs clipping
    clipped_content = Element.g(%{clip_path: "url(##{clip_id})"})
      |> Element.append(ocean)
      |> Element.append(graticule)
      |> Element.append(land_elements)

    # Globe outline (drawn on top, not clipped)
    globe_outline = Element.circle(%{
      cx: cx,
      cy: cy,
      r: radius,
      fill: "none",
      stroke: "#666",
      stroke_width: 1.5
    })

    # Globe highlight (specular reflection effect)
    highlight = Element.ellipse(%{
      cx: cx - radius * 0.3,
      cy: cy - radius * 0.3,
      rx: radius * 0.15,
      ry: radius * 0.1,
      fill: "white",
      fill_opacity: 0.3
    })

    Element.svg(%{width: width, height: height, viewBox: "0 0 #{width} #{height}"})
    |> Element.append(
      Element.rect(%{width: width, height: height, fill: "#1a1a2e"})
    )
    |> Element.append(defs)
    |> Element.append(clipped_content)
    |> Element.append(globe_outline)
    |> Element.append(highlight)
  end

  defp render_graticule(geo_path) do
    # Longitude lines (meridians)
    lon_lines = for lon <- -180..150//30 do
      coords = for lat <- -90..90//5, do: [lon, lat]
      geojson = %{"type" => "LineString", "coordinates" => coords}
      path_data = Path.render(geo_path, geojson)

      Element.path(%{
        d: path_data,
        fill: "none",
        stroke: "#fff",
        stroke_width: 0.3,
        stroke_opacity: 0.4
      })
    end

    # Latitude lines (parallels)
    lat_lines = for lat <- -60..60//30 do
      coords = for lon <- -180..180//5, do: [lon, lat]
      geojson = %{"type" => "LineString", "coordinates" => coords}
      path_data = Path.render(geo_path, geojson)

      Element.path(%{
        d: path_data,
        fill: "none",
        stroke: "#fff",
        stroke_width: if(lat == 0, do: 0.8, else: 0.3),
        stroke_opacity: if(lat == 0, do: 0.6, else: 0.4)
      })
    end

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

    # Orthographic gives a globe view
    projection = Projection.new(:orthographic)
      |> Projection.scale(radius)
      |> Projection.translate(cx, cy)
      |> Projection.rotate(lon, lat, 0)

    geo_path = Path.new(projection)
    path_data = Path.render(geo_path, geojson)

    # Rotation animates the globe spinning
    """
  end
end
