defmodule Visualize.Color.Typed do
  @moduledoc false
  # The typed colors of spec/08 §1.9 (D-173): which terms are color values, and how one
  # resolves against a theme. A name, a series or a ramp position is the theme's to
  # resolve, exactly as `Visualize.Theme.resolve/3` resolves a slot; a transform is computed
  # in OKLab from its operands' literals and written as a literal. `Visualize.Color` is the
  # public face.

  alias Visualize.{Color, Theme}
  alias Visualize.Color.OK

  # The transforms that take a color and one number in `0..1`.
  @unary [:intensity, :alpha, :lighten, :darken, :saturate]
  @not_names [nil, true, false]
  # CSS's 100% chroma in `oklch()`: where `saturate` moves chroma toward.
  @full_chroma 0.4

  @doc false
  @spec unary() :: [atom(), ...]
  def unary, do: @unary

  @doc false
  # Whether a term is a color value of spec/08 §1.9, its operands included.
  @spec value?(term()) :: boolean()
  def value?(v) when is_binary(v), do: true
  def value?({:color, name}), do: name?(name)
  def value?({:series, i}), do: is_integer(i) and i >= 1
  def value?({:ramp, name, t}), do: name?(name) and unit?(t)
  def value?({op, c, t}) when op in @unary, do: value?(c) and unit?(t)
  def value?({:blend, [_ | _] = list}), do: Enum.all?(list, &value?/1)
  def value?({:contrast, c}), do: value?(c)
  def value?(_other), do: false

  @doc false
  # Whether a value is computed (a transform) rather than looked up.
  @spec transform?(term()) :: boolean()
  def transform?({op, _c, _t}) when op in @unary, do: true
  def transform?({:blend, _list}), do: true
  def transform?({:contrast, _c}), do: true
  def transform?(_value), do: false

  @doc false
  @spec name?(term()) :: boolean()
  def name?(name), do: is_atom(name) and name not in @not_names

  @doc false
  @spec unit?(term()) :: boolean()
  def unit?(t), do: is_number(t) and t >= 0 and t <= 1

  # -- resolution -------------------------------------------------------------------------

  @doc false
  # A color value against a theme, in `mode` (spec/08 §1.9, §7.3). A bare atom is still
  # read as the slot it named, for the callers that hold one: a scale's range, a component.
  @spec resolve(term(), Theme.t(), Theme.mode()) :: String.t()
  def resolve(v, _theme, _mode) when is_binary(v), do: v
  def resolve({:color, name}, theme, mode), do: Theme.resolve(theme, name, mode)
  def resolve({:series, _} = slot, theme, mode), do: Theme.resolve(theme, slot, mode)
  def resolve({:ramp, _, _} = position, theme, mode), do: Theme.resolve(theme, position, mode)
  def resolve({:contrast, c}, theme, _mode), do: ink(c, theme)

  def resolve(value, theme, _mode) when is_tuple(value) do
    if transform?(value), do: value |> compute(theme) |> literal(), else: invalid!(value)
  end

  def resolve(slot, theme, mode) when is_atom(slot) and slot not in @not_names,
    do: Theme.resolve(theme, slot, mode)

  def resolve(value, _theme, _mode), do: invalid!(value)

  @doc false
  # A color value as OKLab and its alpha, `{{l, a, b}, alpha}`, unmapped: a step of a chain
  # stays where its arithmetic puts it, and only the result is brought into sRGB.
  @spec compute(term(), Theme.t()) :: {{float(), float(), float()}, float()}
  def compute({:intensity, c, t}, theme) do
    {lab, alpha} = compute(c, theme)
    {lab, alpha * t}
  end

  def compute({:alpha, c, a}, theme) do
    {lab, _alpha} = compute(c, theme)
    {lab, a * 1.0}
  end

  def compute({:lighten, c, t}, theme),
    do: polar(c, theme, fn {l, ch, h} -> {l + (1 - l) * t, ch, h} end)

  def compute({:darken, c, t}, theme),
    do: polar(c, theme, fn {l, ch, h} -> {l * (1 - t), ch, h} end)

  def compute({:saturate, c, t}, theme),
    do: polar(c, theme, fn {l, ch, h} -> {l, ch + (@full_chroma - ch) * t, h} end)

  def compute({:blend, list}, theme), do: blend(list, theme)
  def compute({:contrast, c}, theme), do: c |> ink(theme) |> parsed!() |> oklab()
  def compute(value, theme), do: value |> resolve(theme, :literal) |> parsed!() |> oklab()

  defp polar(c, theme, fun) do
    {lab, alpha} = compute(c, theme)
    {lab |> OK.to_lch() |> fun.() |> OK.from_lch(), alpha}
  end

  # CSS Color 5's `color-mix` over any number of colours: weights normalized, OKLab averaged
  # with premultiplied alpha, and a sum of weights below 1 multiplying the alpha.
  defp blend(list, theme) do
    weighted =
      Enum.map(list, fn
        {:intensity, c, w} -> {compute(c, theme), w}
        c -> {compute(c, theme), 1}
      end)

    total = weighted |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    if total == 0 do
      {{0.0, 0.0, 0.0}, 0.0}
    else
      {l, a, b, alpha} =
        Enum.reduce(weighted, {0.0, 0.0, 0.0, 0.0}, fn {{{l, a, b}, al}, w}, {sl, sa, sb, sal} ->
          p = w / total
          {sl + p * al * l, sa + p * al * a, sb + p * al * b, sal + p * al}
        end)

      lab = if alpha > 0, do: {l / alpha, a / alpha, b / alpha}, else: {0.0, 0.0, 0.0}
      {lab, alpha * min(total, 1)}
    end
  end

  # The theme's ink over `c`, laid over the theme's background when translucent: what the
  # text is read against (spec/08 §1.9, §7.3).
  defp ink(c, theme) do
    {lab, alpha} = compute(c, theme)
    {r, g, b} = OK.map_to_srgb(lab)
    {br, bg, bb} = background(theme)
    over = fn x, y -> x * alpha + y * (1 - alpha) end
    Theme.ink(theme, Color.rgb(over.(r, br) * 255, over.(g, bg) * 255, over.(b, bb) * 255))
  end

  defp background(theme) do
    case Color.parse(theme.background || "") do
      %Color{r: r, g: g, b: b} -> {r / 255, g / 255, b / 255}
      nil -> {1.0, 1.0, 1.0}
    end
  end

  defp oklab(%Color{r: r, g: g, b: b, opacity: alpha}),
    do: {OK.from_srgb({r / 255, g / 255, b / 255}), alpha * 1.0}

  defp parsed!(literal) do
    Color.parse(literal) ||
      raise ArgumentError,
            "a color transform's operand must resolve to a color Visualize.Color.parse/1 " <>
              "reads, got #{inspect(literal)}"
  end

  @doc false
  # An OKLab colour and alpha as the literal a canvas takes: `#rrggbb`, with `aa` below an
  # alpha of 1, gamut-mapped (spec/08 §1.9).
  @spec literal({{number(), number(), number()}, number()}) :: String.t()
  def literal({lab, alpha}) do
    {r, g, b} = OK.map_to_srgb(lab)
    # An alpha that rounds to the opaque byte is opaque: no `ff` written after the colour.
    alpha = if round(alpha * 255) >= 255, do: 1.0, else: alpha
    Color.to_hex(Color.rgb(r * 255, g * 255, b * 255, alpha))
  end

  defp invalid!(value) do
    raise ArgumentError,
          "not a color value: #{inspect(value)}; a color is color(name), ramp(name, t), " <>
            "{:series, i}, a literal string or a transform of them (spec/08 §1.9)"
  end
end
