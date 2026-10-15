defmodule Examples.ColorPalettes do
  @moduledoc """
  Color palette definitions for chart examples.

  Each palette provides a cohesive set of colors that work well together for data
  visualization. The `:default` and `:dark` palettes are `Visualize.Theme.default/0` and
  `Visualize.Theme.dark/0`, and `:color_safe` is `Visualize.Theme.color_safe/0`; every
  palette is available as a `Visualize.Theme` through `theme/1`, which is what the charts
  hand their axes.
  """

  alias Visualize.Theme

  @light Theme.default()
  @dark Theme.dark()
  @safe Theme.color_safe()

  # A UI font stack, ending in the generic family: the gallery's text is set in the first
  # face the viewer has, where the library's default theme names only `sans-serif` (#486).
  @font_family "Inter, system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif"
  # A status green that holds 3:1 on every tinted page of the gallery (spec/08 §7.7).
  @good "#3d8b3c"

  @palettes %{
    default: %{
      name: "Default",
      description: "The library's light theme",
      colors: @light.series,
      gradient: ["#3b6fa8", "#5f8abb", "#83a5cd", "#a7c0e0", "#cbdbf2"],
      background: @light.background,
      text: @light.text,
      axis: @light.axis,
      grid: @light.grid,
      surface: @light.surface
    },
    color_safe: %{
      name: "Color-safe",
      description: "The library's color-vision-safe theme: status runs blue → orange → red",
      colors: @safe.series,
      gradient: ["#3b6fa8", "#5f8abb", "#83a5cd", "#a7c0e0", "#cbdbf2"],
      background: @safe.background,
      text: @safe.text,
      axis: @safe.axis,
      grid: @safe.grid,
      surface: @safe.surface
    },
    dark: %{
      name: "Dark",
      description: "The library's dark theme",
      colors: @dark.series,
      gradient: ["#2b4a6e", "#4a6f97", "#6a95c0", "#8abbe8", "#b0d4f5"],
      background: @dark.background,
      text: @dark.text,
      axis: @dark.axis,
      grid: @dark.grid,
      surface: @dark.surface
    },
    sunrise: %{
      name: "Sunrise",
      description: "Warm amber to deep oranges",
      colors: [
        "#ffd098",
        "#ffbc7a",
        "#ffa862",
        "#fa944a",
        "#f58035",
        "#f06d20",
        "#e85a10",
        "#d94500"
      ],
      gradient: [
        "#ffd098",
        "#ffa862",
        "#fa944a",
        "#f58035",
        "#f06d20",
        "#e85a10",
        "#d94500",
        "#c03800",
        "#8b2500"
      ],
      background: "#fff8f0",
      text: "#5c3d2e",
      axis: "#8b5a2b",
      grid: "#ffecd2",
      surface: "#fff2e2"
    },
    winter: %{
      name: "Winter",
      description: "Cool grays with blue undertones",
      colors: [
        "#4a6278",
        "#5d7a94",
        "#7192aa",
        "#88a8bc",
        "#a0bccb",
        "#b8ced9",
        "#d0dfe6",
        "#e8eff3"
      ],
      gradient: [
        "#4a6278",
        "#5d7a94",
        "#7192aa",
        "#a0bccb",
        "#b8ced9",
        "#d0dfe6",
        "#e8eff3",
        "#f8fafb"
      ],
      background: "#f5f7f9",
      text: "#2c3e50",
      axis: "#4a6278",
      grid: "#dce4ea",
      surface: "#ebf0f3"
    },
    sunset: %{
      name: "Sunset",
      description: "Purple to reds to deep orange",
      colors: [
        "#341f97",
        "#5f27cd",
        "#6c5ce7",
        "#8854d0",
        "#be2edd",
        "#e84393",
        "#ff4757",
        "#ff6b35"
      ],
      gradient: ["#341f97", "#5f27cd", "#8854d0", "#be2edd", "#e84393", "#ff4757", "#ff6b35"],
      background: "#fef5f0",
      text: "#4a1942",
      axis: "#6d3461",
      grid: "#f5dce8",
      surface: "#faeaec"
    },
    fall: %{
      name: "Fall",
      description: "Browns to orange and yellow",
      colors: [
        "#5d4037",
        "#795548",
        "#a1887f",
        "#d7a86e",
        "#e6a23c",
        "#f5b041",
        "#f9c74f",
        "#fcf876"
      ],
      gradient: [
        "#3e2723",
        "#5d4037",
        "#795548",
        "#a1887f",
        "#d7a86e",
        "#e6a23c",
        "#f5b041",
        "#f9c74f"
      ],
      background: "#fdf6e3",
      light_end: "#faf6f2",
      text: "#4a3728",
      axis: "#6d5039",
      grid: "#efe0c9",
      surface: "#f6ebd6"
    },
    spring: %{
      name: "Spring",
      description: "Bright green to yellow to white",
      colors: [
        "#00a86b",
        "#2ec866",
        "#5cd85c",
        "#8ae65c",
        "#b8f260",
        "#d4f88d",
        "#e8fcb4",
        "#f8ffe0"
      ],
      gradient: [
        "#006b3c",
        "#00a86b",
        "#2ec866",
        "#5cd85c",
        "#8ae65c",
        "#b8f260",
        "#e8fcb4",
        "#ffffff"
      ],
      background: "#f0fff0",
      text: "#2d5a3d",
      axis: "#4a7c59",
      grid: "#d4f0d4",
      surface: "#e2f8e2"
    },
    summer: %{
      name: "Summer",
      description: "Deep greens to light mint",
      colors: [
        "#0d5c3d",
        "#0f7a4e",
        "#15946a",
        "#22a87a",
        "#34c78e",
        "#5dd9a4",
        "#8eeabc",
        "#c5f5dc"
      ],
      gradient: [
        "#0d5c3d",
        "#0f7a4e",
        "#15946a",
        "#22a87a",
        "#34c78e",
        "#5dd9a4",
        "#8eeabc",
        "#e0fbee"
      ],
      background: "#f0fdf6",
      text: "#0d4a2d",
      axis: "#1a6b45",
      grid: "#d4f5e4",
      surface: "#e2f9ed"
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
      {key,
       %{
         name: palette.name,
         description: palette.description,
         preview: Enum.take(palette.colors, 5)
       }}
    end)
    |> Enum.into(%{})
  end

  @doc "Get a specific palette by key"
  def get(key) when is_atom(key) do
    Map.get(@palettes, key, @palettes.default)
  end

  def get(key) when is_binary(key) do
    get(Enum.find(list_palettes(), :default, &(Atom.to_string(&1) == key)))
  end

  @doc "The palette as a `Visualize.Theme`: its colors as the series, its base colors as the slots, the gallery's font stack as its `font_family`"
  def theme(key) when is_binary(key) do
    theme(Enum.find(list_palettes(), :default, &(Atom.to_string(&1) == key)))
  end

  def theme(key) when is_atom(key) do
    palette = get(key)

    # A built-in theme's palette keeps its ramps and roles — the dark theme's are tuned for
    # its page, the color-safe theme's status is its point. Any other palette tunes one
    # ramp, `sequential`, to run from its page to its first color, so a heatmap takes the
    # palette's tone; its other ramps and roles are the default's (spec/08 §7.5).
    #
    # On a tinted page the default's light-page green falls under WCAG's 3:1 (spec/08 §7.7,
    # #666), so such a palette's `good` is a step darker, standing apart from the ramp.
    case Theme.builtin(key) do
      nil ->
        Theme.default()
        |> Theme.merge(ramps: %{sequential: sequential(palette)}, colors: %{good: @good})

      builtin ->
        builtin
    end
    |> Theme.merge(
      name: if(Map.has_key?(@palettes, key), do: key, else: :default),
      series: palette.colors,
      background: palette.background,
      text: palette.text,
      axis: palette.axis,
      grid: palette.grid,
      surface: palette.surface,
      font_family: @font_family
    )
  end

  # The page to the first color, unless the palette names a light end of its own: a cream
  # page is a hue of its own, too far round from the palette's to make one hue family.
  defp sequential(palette) do
    [Map.get(palette, :light_end, palette.background), hd(palette.colors)]
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
