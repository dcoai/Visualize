defmodule Examples.Charts.ContourPlot do
  @moduledoc "Contour plot using marching squares algorithm"

  alias Visualize.Contour
  alias Visualize.SVG.Element
  alias Examples.ColorPalettes

  def title, do: "Contour Plot"
  def description, do: "Topographic elevation data"

  def render(opts \\ []) do
    width = opts[:width] || 500
    height = opts[:height] || 400
    palette = opts[:palette] || :default
    gradient = ColorPalettes.gradient(palette)

    # Generate sample data (gaussian peaks)
    grid_width = 50
    grid_height = 40
    animation_tick = opts[:animation_tick]

    grid = if animation_tick do
      generate_animated_peaks(grid_width, grid_height, animation_tick)
    else
      generate_peaks_data(grid_width, grid_height)
    end

    # Create contour generator
    thresholds = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]

    contour = Contour.new()
      |> Contour.size(grid_width, grid_height)
      |> Contour.thresholds(thresholds)
      |> Contour.smooth(true)

    contours = Contour.render(contour, grid)

    # Scale factors
    scale_x = width / grid_width
    scale_y = height / grid_height

    # Draw contours as filled regions (from lowest to highest)
    contour_elements = contours
      |> Enum.with_index()
      |> Enum.map(fn {%{value: _value, path: path}, i} ->
        t = i / max(1, length(contours) - 1)
        color = interpolate_gradient(gradient, t)

        Element.path(%{
          d: path,
          fill: color,
          stroke: darken_color(color),
          stroke_width: 0.1,
          transform: "scale(#{scale_x},#{scale_y})"
        })
      end)

    # Add legend
    legend = create_legend(thresholds, gradient, width - 80, 20)

    Element.svg(%{width: width, height: height, viewBox: "0 0 #{width} #{height}"})
    |> Element.append(contour_elements)
    |> Element.append(legend)
  end

  defp generate_peaks_data(width, height) do
    # Generate multiple gaussian peaks
    peaks = [
      {width * 0.3, height * 0.3, 0.8, 8},
      {width * 0.7, height * 0.6, 0.9, 10},
      {width * 0.5, height * 0.8, 0.6, 6}
    ]

    for y <- 0..(height - 1) do
      for x <- 0..(width - 1) do
        Enum.reduce(peaks, 0, fn {px, py, amplitude, sigma}, acc ->
          dist_sq = (x - px) * (x - px) + (y - py) * (y - py)
          acc + amplitude * :math.exp(-dist_sq / (2 * sigma * sigma))
        end)
      end
    end
  end

  # Animation: peaks move and pulse
  defp generate_animated_peaks(width, height, tick) do
    phase = tick * 0.08
    # Peaks orbit in small circles and vary in amplitude
    peaks = [
      {width * 0.3 + 5 * :math.cos(phase), height * 0.3 + 5 * :math.sin(phase),
       0.7 + 0.2 * :math.sin(phase * 1.5), 8},
      {width * 0.7 + 6 * :math.cos(phase + 2), height * 0.6 + 6 * :math.sin(phase + 2),
       0.8 + 0.2 * :math.sin(phase * 1.2 + 1), 10},
      {width * 0.5 + 4 * :math.cos(phase + 4), height * 0.8 + 4 * :math.sin(phase + 4),
       0.5 + 0.2 * :math.sin(phase + 2), 6}
    ]

    for y <- 0..(height - 1) do
      for x <- 0..(width - 1) do
        Enum.reduce(peaks, 0, fn {px, py, amplitude, sigma}, acc ->
          dist_sq = (x - px) * (x - px) + (y - py) * (y - py)
          acc + amplitude * :math.exp(-dist_sq / (2 * sigma * sigma))
        end)
      end
    end
  end

  defp darken_color("#" <> hex) do
    {r, ""} = Integer.parse(String.slice(hex, 0, 2), 16)
    {g, ""} = Integer.parse(String.slice(hex, 2, 2), 16)
    {b, ""} = Integer.parse(String.slice(hex, 4, 2), 16)

    r = trunc(r * 0.7)
    g = trunc(g * 0.7)
    b = trunc(b * 0.7)

    r_hex = Integer.to_string(r, 16) |> String.pad_leading(2, "0")
    g_hex = Integer.to_string(g, 16) |> String.pad_leading(2, "0")
    b_hex = Integer.to_string(b, 16) |> String.pad_leading(2, "0")

    "#" <> r_hex <> g_hex <> b_hex
  end

  defp interpolate_gradient(gradient, t) do
    t = max(0, min(1, t))
    n = length(gradient) - 1
    idx = t * n
    lower = trunc(idx)
    upper = min(lower + 1, n)
    local_t = idx - lower

    color1 = Enum.at(gradient, lower)
    color2 = Enum.at(gradient, upper)

    interpolate_color(color1, color2, local_t)
  end

  defp interpolate_color("#" <> hex1, "#" <> hex2, t) do
    {r1, ""} = Integer.parse(String.slice(hex1, 0, 2), 16)
    {g1, ""} = Integer.parse(String.slice(hex1, 2, 2), 16)
    {b1, ""} = Integer.parse(String.slice(hex1, 4, 2), 16)

    {r2, ""} = Integer.parse(String.slice(hex2, 0, 2), 16)
    {g2, ""} = Integer.parse(String.slice(hex2, 2, 2), 16)
    {b2, ""} = Integer.parse(String.slice(hex2, 4, 2), 16)

    r = trunc(r1 + (r2 - r1) * t)
    g = trunc(g1 + (g2 - g1) * t)
    b = trunc(b1 + (b2 - b1) * t)

    r_hex = Integer.to_string(r, 16) |> String.pad_leading(2, "0")
    g_hex = Integer.to_string(g, 16) |> String.pad_leading(2, "0")
    b_hex = Integer.to_string(b, 16) |> String.pad_leading(2, "0")

    "#" <> r_hex <> g_hex <> b_hex
  end

  defp create_legend(thresholds, gradient, x, y) do
    items = thresholds
      |> Enum.with_index()
      |> Enum.map(fn {threshold, i} ->
        t = i / max(1, length(thresholds) - 1)
        color = interpolate_gradient(gradient, t)

        Element.g(%{transform: "translate(0,#{i * 18})"})
        |> Element.append(
          Element.rect(%{width: 15, height: 15, fill: color, stroke: "#666", stroke_width: 0.5})
        )
        |> Element.append(
          Element.text(%{x: 20, y: 12, font_size: 10, fill: "#333"})
          |> Element.content("#{Float.round(threshold, 2)}")
        )
      end)

    Element.g(%{transform: "translate(#{x},#{y})"})
    |> Element.append(items)
  end

  def sample_code do
    ~S"""
    alias Visualize.Contour

    grid = [
      [0, 0, 0, 0],
      [0, 5, 5, 0],
      [0, 5, 10, 5],
      [0, 0, 5, 0]
    ]

    contour = Contour.new()
      |> Contour.size(4, 4)
      |> Contour.thresholds([2.5, 7.5])
      |> Contour.smooth(true)

    contours = Contour.render(contour, grid)
    # Each contour has: value, path (SVG path string)
    """
  end
end
