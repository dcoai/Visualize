defmodule Visualize.Scale.Color do
  @moduledoc """
  Color scales for encoding data with colors.

  Provides sequential and diverging color scales with various built-in
  color schemes.
  """

  defstruct type: :sequential,
            domain: [0, 1],
            interpolator: nil,
            clamp?: true

  @type t :: %__MODULE__{
          type: :sequential | :diverging,
          domain: [number()],
          interpolator: (number() -> String.t()) | [String.t()],
          clamp?: boolean()
        }

  # Built-in color schemes (D3-compatible)
  @schemes %{
    # Sequential single-hue
    blues: ["#f7fbff", "#deebf7", "#c6dbef", "#9ecae1", "#6baed6", "#4292c6", "#2171b5", "#084594"],
    greens: ["#f7fcf5", "#e5f5e0", "#c7e9c0", "#a1d99b", "#74c476", "#41ab5d", "#238b45", "#005a32"],
    greys: ["#ffffff", "#f0f0f0", "#d9d9d9", "#bdbdbd", "#969696", "#737373", "#525252", "#252525"],
    oranges: ["#fff5eb", "#fee6ce", "#fdd0a2", "#fdae6b", "#fd8d3c", "#f16913", "#d94801", "#8c2d04"],
    purples: ["#fcfbfd", "#efedf5", "#dadaeb", "#bcbddc", "#9e9ac8", "#807dba", "#6a51a3", "#4a1486"],
    reds: ["#fff5f0", "#fee0d2", "#fcbba1", "#fc9272", "#fb6a4a", "#ef3b2c", "#cb181d", "#99000d"],

    # Sequential multi-hue
    viridis: ["#440154", "#482777", "#3f4a8a", "#31678e", "#26838f", "#1f9d8a", "#6cce5a", "#b6de2b", "#fee825"],
    inferno: ["#000004", "#1b0c41", "#4a0c6b", "#781c6d", "#a52c60", "#cf4446", "#ed6925", "#fb9b06", "#f7d13d", "#fcffa4"],
    magma: ["#000004", "#180f3d", "#440f76", "#721f81", "#9e2f7f", "#cd4071", "#f1605d", "#fd9668", "#feca8d", "#fcfdbf"],
    plasma: ["#0d0887", "#46039f", "#7201a8", "#9c179e", "#bd3786", "#d8576b", "#ed7953", "#fb9f3a", "#fdca26", "#f0f921"],

    # Diverging
    brbg: ["#8c510a", "#bf812d", "#dfc27d", "#f6e8c3", "#f5f5f5", "#c7eae5", "#80cdc1", "#35978f", "#01665e"],
    piyg: ["#c51b7d", "#de77ae", "#f1b6da", "#fde0ef", "#f7f7f7", "#e6f5d0", "#b8e186", "#7fbc41", "#4d9221"],
    prgn: ["#762a83", "#9970ab", "#c2a5cf", "#e7d4e8", "#f7f7f7", "#d9f0d3", "#a6dba0", "#5aae61", "#1b7837"],
    rdbu: ["#b2182b", "#d6604d", "#f4a582", "#fddbc7", "#f7f7f7", "#d1e5f0", "#92c5de", "#4393c3", "#2166ac"],
    rdgy: ["#b2182b", "#d6604d", "#f4a582", "#fddbc7", "#ffffff", "#e0e0e0", "#bababa", "#878787", "#4d4d4d"],
    rdylbu: ["#d73027", "#f46d43", "#fdae61", "#fee090", "#ffffbf", "#e0f3f8", "#abd9e9", "#74add1", "#4575b4"],
    rdylgn: ["#d73027", "#f46d43", "#fdae61", "#fee08b", "#ffffbf", "#d9ef8b", "#a6d96a", "#66bd63", "#1a9850"],
    spectral: ["#9e0142", "#d53e4f", "#f46d43", "#fdae61", "#fee08b", "#ffffbf", "#e6f598", "#abdda4", "#66c2a5", "#3288bd", "#5e4fa2"],

    # Categorical
    category10: ["#1f77b4", "#ff7f0e", "#2ca02c", "#d62728", "#9467bd", "#8c564b", "#e377c2", "#7f7f7f", "#bcbd22", "#17becf"],
    accent: ["#7fc97f", "#beaed4", "#fdc086", "#ffff99", "#386cb0", "#f0027f", "#bf5b17", "#666666"],
    dark2: ["#1b9e77", "#d95f02", "#7570b3", "#e7298a", "#66a61e", "#e6ab02", "#a6761d", "#666666"],
    paired: ["#a6cee3", "#1f78b4", "#b2df8a", "#33a02c", "#fb9a99", "#e31a1c", "#fdbf6f", "#ff7f00", "#cab2d6", "#6a3d9a"],
    set1: ["#e41a1c", "#377eb8", "#4daf4a", "#984ea3", "#ff7f00", "#ffff33", "#a65628", "#f781bf", "#999999"],
    set2: ["#66c2a5", "#fc8d62", "#8da0cb", "#e78ac3", "#a6d854", "#ffd92f", "#e5c494", "#b3b3b3"],
    set3: ["#8dd3c7", "#ffffb3", "#bebada", "#fb8072", "#80b1d3", "#fdb462", "#b3de69", "#fccde5", "#d9d9d9", "#bc80bd"]
  }

  @doc "Creates a sequential color scale"
  @spec sequential(atom() | [String.t()] | (number() -> String.t())) :: t()
  def sequential(interpolator) do
    %__MODULE__{
      type: :sequential,
      interpolator: resolve_interpolator(interpolator)
    }
  end

  @doc "Creates a diverging color scale"
  @spec diverging(atom() | [String.t()] | (number() -> String.t())) :: t()
  def diverging(interpolator) do
    %__MODULE__{
      type: :diverging,
      domain: [0, 0.5, 1],
      interpolator: resolve_interpolator(interpolator)
    }
  end

  @doc "Sets the domain"
  @spec domain(t(), [number()]) :: t()
  def domain(%__MODULE__{type: :sequential} = scale, [d0, d1]) do
    %{scale | domain: [d0, d1]}
  end

  def domain(%__MODULE__{type: :diverging} = scale, [d0, d1, d2]) do
    %{scale | domain: [d0, d1, d2]}
  end

  @doc "Sets the range (color interpolator)"
  @spec range(t(), atom() | [String.t()]) :: t()
  def range(%__MODULE__{} = scale, interpolator) do
    %{scale | interpolator: resolve_interpolator(interpolator)}
  end

  @doc "Applies the scale to get a color"
  @spec apply(t(), number()) :: String.t()
  def apply(%__MODULE__{type: :sequential, domain: [d0, d1], interpolator: interp, clamp?: clamp?}, value) do
    t = (value - d0) / (d1 - d0)
    t = if clamp?, do: clamp_value(t, 0, 1), else: t
    interpolate_color(interp, t)
  end

  def apply(%__MODULE__{type: :diverging, domain: [d0, d1, d2], interpolator: interp, clamp?: clamp?}, value) do
    t =
      cond do
        value < d1 -> 0.5 * (value - d0) / (d1 - d0)
        value > d1 -> 0.5 + 0.5 * (value - d1) / (d2 - d1)
        true -> 0.5
      end

    t = if clamp?, do: clamp_value(t, 0, 1), else: t
    interpolate_color(interp, t)
  end

  @doc "Enables or disables clamping"
  @spec clamp(t(), boolean()) :: t()
  def clamp(%__MODULE__{} = scale, clamp?) do
    %{scale | clamp?: clamp?}
  end

  @doc "Returns the list of available color schemes"
  @spec schemes() :: [atom()]
  def schemes, do: Map.keys(@schemes)

  @doc "Gets a color scheme by name"
  @spec scheme(atom()) :: [String.t()] | nil
  def scheme(name), do: Map.get(@schemes, name)

  # Not applicable
  def invert(_, _), do: nil
  def ticks(%__MODULE__{domain: [d0, d1]}, count), do: Visualize.Scale.Linear.ticks(%Visualize.Scale.Linear{domain: [d0, d1]}, count)
  def nice(scale), do: scale
  def padding(scale, _), do: scale
  def bandwidth(_), do: 0

  defp resolve_interpolator(name) when is_atom(name) do
    Map.get(@schemes, name, @schemes.blues)
  end

  defp resolve_interpolator(colors) when is_list(colors), do: colors
  defp resolve_interpolator(func) when is_function(func, 1), do: func

  defp interpolate_color(colors, t) when is_list(colors) do
    n = length(colors) - 1
    i = t * n
    i0 = trunc(i) |> max(0) |> min(n - 1)
    i1 = min(i0 + 1, n)
    local_t = i - i0

    c0 = Enum.at(colors, i0)
    c1 = Enum.at(colors, i1)

    interpolate_rgb(c0, c1, local_t)
  end

  defp interpolate_color(func, t) when is_function(func, 1) do
    func.(t)
  end

  defp interpolate_rgb(c0, c1, t) do
    {r0, g0, b0} = parse_hex(c0)
    {r1, g1, b1} = parse_hex(c1)

    r = round(r0 + (r1 - r0) * t)
    g = round(g0 + (g1 - g0) * t)
    b = round(b0 + (b1 - b0) * t)

    "#" <> hex_byte(r) <> hex_byte(g) <> hex_byte(b)
  end

  defp parse_hex("#" <> hex) do
    case hex do
      <<r::binary-size(2), g::binary-size(2), b::binary-size(2)>> ->
        {String.to_integer(r, 16), String.to_integer(g, 16), String.to_integer(b, 16)}

      <<r::binary-size(1), g::binary-size(1), b::binary-size(1)>> ->
        {String.to_integer(r <> r, 16), String.to_integer(g <> g, 16), String.to_integer(b <> b, 16)}
    end
  end

  defp hex_byte(n), do: n |> Integer.to_string(16) |> String.pad_leading(2, "0") |> String.downcase()

  defp clamp_value(value, min_val, max_val) do
    value |> max(min_val) |> min(max_val)
  end
end
