defmodule Examples.ColorPalettes do
  @moduledoc """
  Color palette definitions for chart examples.

  Each palette provides a cohesive set of colors that work well together
  for data visualization.
  """

  @palettes %{
    default: %{
      name: "Default",
      description: "Classic D3-style colors",
      colors: ["#4e79a7", "#f28e2c", "#e15759", "#76b7b2", "#59a14f", "#edc949", "#af7aa1", "#ff9da7"],
      gradient: ["#4e79a7", "#6b92b9", "#89abcb", "#a7c4dd", "#c5ddef"],
      background: "#ffffff",
      text: "#333333",
      axis: "#666666",
      grid: "#eeeeee"
    },

    sunrise: %{
      name: "Sunrise",
      description: "Deep oranges to yellow to white",
      colors: ["#ff4500", "#ff6b35", "#ff8c42", "#ffad5a", "#ffce73", "#ffe08a", "#fff1a8", "#ffffd4"],
      gradient: ["#8b2500", "#cd3700", "#ff4500", "#ff6b35", "#ff8c42", "#ffad5a", "#ffce73", "#ffe08a", "#ffffd4"],
      background: "#fffef5",
      text: "#5c3d2e",
      axis: "#8b5a2b",
      grid: "#ffecd2"
    },

    winter: %{
      name: "Winter",
      description: "Medium blues to white",
      colors: ["#3b82f6", "#60a5fa", "#7dd3fc", "#93c5fd", "#a5d8ff", "#bae6fd", "#d4eeff", "#e8f4ff"],
      gradient: ["#3b82f6", "#60a5fa", "#7dd3fc", "#a5d8ff", "#bae6fd", "#d4eeff", "#f0f9ff", "#ffffff"],
      background: "#f0f9ff",
      text: "#1e40af",
      axis: "#3b82f6",
      grid: "#dbeafe"
    },

    sunset: %{
      name: "Sunset",
      description: "Deep orange to reds to purple",
      colors: ["#ff6b35", "#ff4757", "#e84393", "#be2edd", "#8854d0", "#6c5ce7", "#5f27cd", "#341f97"],
      gradient: ["#ff6b35", "#ff4757", "#e84393", "#be2edd", "#8854d0", "#5f27cd", "#341f97"],
      background: "#fef5f0",
      text: "#4a1942",
      axis: "#6d3461",
      grid: "#f5dce8"
    },

    fall: %{
      name: "Fall",
      description: "Browns to orange and yellow",
      colors: ["#5d4037", "#795548", "#a1887f", "#d7a86e", "#e6a23c", "#f5b041", "#f9c74f", "#fcf876"],
      gradient: ["#3e2723", "#5d4037", "#795548", "#a1887f", "#d7a86e", "#e6a23c", "#f5b041", "#f9c74f"],
      background: "#fdf6e3",
      text: "#4a3728",
      axis: "#6d5039",
      grid: "#efe0c9"
    },

    spring: %{
      name: "Spring",
      description: "Bright green to yellow to white",
      colors: ["#00a86b", "#2ec866", "#5cd85c", "#8ae65c", "#b8f260", "#d4f88d", "#e8fcb4", "#f8ffe0"],
      gradient: ["#006b3c", "#00a86b", "#2ec866", "#5cd85c", "#8ae65c", "#b8f260", "#e8fcb4", "#ffffff"],
      background: "#f0fff0",
      text: "#2d5a3d",
      axis: "#4a7c59",
      grid: "#d4f0d4"
    },

    summer: %{
      name: "Summer",
      description: "Deep blues to green to white",
      colors: ["#1a365d", "#2563eb", "#0891b2", "#06b6d4", "#10b981", "#34d399", "#86efac", "#d1fae5"],
      gradient: ["#1a365d", "#2563eb", "#0891b2", "#10b981", "#34d399", "#86efac", "#d1fae5", "#ffffff"],
      background: "#f0fdfa",
      text: "#134e4a",
      axis: "#2d6a6a",
      grid: "#ccfbf1"
    }
  }

  @doc "Returns list of all available palette keys"
  def list_palettes do
    Map.keys(@palettes) |> Enum.sort()
  end

  @doc "Returns palette metadata for UI display"
  def palette_info do
    @palettes
    |> Enum.map(fn {key, palette} ->
      {key, %{name: palette.name, description: palette.description, preview: Enum.take(palette.colors, 5)}}
    end)
    |> Enum.into(%{})
  end

  @doc "Get a specific palette by key"
  def get(key) when is_atom(key) do
    Map.get(@palettes, key, @palettes.default)
  end

  def get(key) when is_binary(key) do
    get(String.to_existing_atom(key))
  rescue
    ArgumentError -> @palettes.default
  end

  @doc "Get the colors array from a palette"
  def colors(key) do
    get(key).colors
  end

  @doc "Get a single color from a palette by index"
  def color_at(key, index) do
    palette = get(key)
    Enum.at(palette.colors, rem(index, length(palette.colors)))
  end

  @doc "Get gradient colors for continuous scales"
  def gradient(key) do
    get(key).gradient
  end

  @doc "Get background color for a palette"
  def background(key) do
    get(key).background
  end

  @doc "Get text color for a palette"
  def text_color(key) do
    get(key).text
  end

  @doc "Get axis color for a palette"
  def axis_color(key) do
    get(key).axis
  end

  @doc "Get grid color for a palette"
  def grid_color(key) do
    get(key).grid
  end

  @doc "Interpolate between two colors in a gradient"
  def interpolate_gradient(key, t) when t >= 0 and t <= 1 do
    gradient = gradient(key)
    n = length(gradient) - 1

    if n == 0 do
      hd(gradient)
    else
      scaled = t * n
      index = trunc(scaled)
      local_t = scaled - index

      if index >= n do
        List.last(gradient)
      else
        color1 = Enum.at(gradient, index)
        color2 = Enum.at(gradient, index + 1)
        interpolate_color(color1, color2, local_t)
      end
    end
  end

  defp interpolate_color(color1, color2, t) do
    {r1, g1, b1} = parse_hex(color1)
    {r2, g2, b2} = parse_hex(color2)

    r = trunc(r1 + (r2 - r1) * t)
    g = trunc(g1 + (g2 - g1) * t)
    b = trunc(b1 + (b2 - b1) * t)

    r_hex = Integer.to_string(r, 16) |> String.pad_leading(2, "0")
    g_hex = Integer.to_string(g, 16) |> String.pad_leading(2, "0")
    b_hex = Integer.to_string(b, 16) |> String.pad_leading(2, "0")

    "#" <> r_hex <> g_hex <> b_hex
  end

  defp parse_hex("#" <> hex) do
    {r, ""} = Integer.parse(String.slice(hex, 0, 2), 16)
    {g, ""} = Integer.parse(String.slice(hex, 2, 2), 16)
    {b, ""} = Integer.parse(String.slice(hex, 4, 2), 16)
    {r, g, b}
  end
end
