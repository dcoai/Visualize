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
  # Every transform of a color and one number: the five above, and `shade` on 0..1000.
  @ops @unary ++ [:shade]
  @not_names [nil, true, false]
  # CSS's 100% chroma in `oklch()`: where `saturate` moves chroma toward.
  @full_chroma 0.4
  # Where `shade` moves lightness toward, either side of its base (#667).
  @near_white 0.97
  @near_black 0.2

  @doc false
  @spec unary() :: [atom(), ...]
  def unary, do: @unary

  @doc false
  # Every transform of a color and one number, `shade` among them.
  @spec ops() :: [atom(), ...]
  def ops, do: @ops

  @doc false
  # Whether a term is a color value of spec/08 §1.9, its operands included.
  @spec value?(term()) :: boolean()
  def value?(v) when is_binary(v), do: true
  def value?({:color, name}), do: name?(name)
  def value?({:series, i}), do: is_integer(i) and i >= 1
  def value?({:ramp, name, t}), do: name?(name) and unit?(t)
  def value?({:shade, c, n}), do: value?(c) and is_number(n) and n >= 0 and n <= 1000
  def value?({op, c, t}) when op in @unary, do: value?(c) and unit?(t)
  def value?({:blend, [_ | _] = list}), do: Enum.all?(list, &value?/1)
  def value?({:contrast, :under}), do: true
  def value?({:contrast, c}), do: value?(c)
  def value?(_other), do: false

  @doc false
  # Whether a term is tagged as a typed color, whatever its operands: what a paint's
  # shorthand is read as, so a malformed one is reported as the color it tries to be.
  @spec tagged?(term()) :: boolean()
  def tagged?(v) when is_tuple(v) and tuple_size(v) in [2, 3],
    do: elem(v, 0) in [:color, :blend, :contrast | @ops]

  def tagged?(_v), do: false

  @doc false
  # Whether a value is computed (a transform) rather than looked up.
  @spec transform?(term()) :: boolean()
  def transform?({op, _c, _t}) when op in @ops, do: true
  def transform?({:blend, _list}), do: true
  def transform?({:contrast, _c}), do: true
  def transform?(_value), do: false

  @doc false
  # The names a color value reads from the theme's color table, operands included, in
  # order: what the validator checks against the table (spec/14 §3.2).
  @spec names(term()) :: [atom()]
  def names({:color, name}), do: [name]
  def names({op, c, _t}) when op in @ops, do: names(c)
  def names({:blend, list}) when is_list(list), do: Enum.flat_map(list, &names/1)
  def names({:contrast, c}), do: names(c)
  def names(_other), do: []

  @doc false
  # The literal strings among a value's operands that no transform could compute from:
  # strings `Visualize.Color.parse/1` does not read. A literal that is the whole value is a
  # CSS color as written and is never computed, so it is not among them.
  @spec unreadable(term()) :: [String.t()]
  def unreadable(value) do
    if transform?(value), do: value |> operands() |> Enum.reject(&readable?/1), else: []
  end

  defp operands(v) when is_binary(v), do: [v]
  defp operands({op, c, _t}) when op in @ops, do: operands(c)
  defp operands({:blend, list}) when is_list(list), do: Enum.flat_map(list, &operands/1)
  defp operands({:contrast, c}), do: operands(c)
  defp operands(_other), do: []

  @hex ~r/^#([0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})$/i

  # A literal `parse/1` reads, checked without letting a malformed hex digit raise in it.
  defp readable?(literal) do
    trimmed = String.trim(literal)

    if String.starts_with?(trimmed, "#"),
      do: Regex.match?(@hex, trimmed),
      else: Color.parse(trimmed) != nil
  end

  @doc false
  @spec name?(term()) :: boolean()
  # A color's name: the library's atom, or the string of one a theme declares (D-195).
  def name?(name) when is_binary(name), do: name != ""
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
  # The ink over whatever is under the text; with nothing known under it, the background's
  # (spec/14 §3.2). A mark's inline label inks against its element instead (§5.5).
  def resolve({:contrast, :under}, theme, _mode), do: Theme.ink(theme, nil)
  def resolve({:contrast, c}, theme, _mode), do: ink(c, theme)

  def resolve(value, theme, mode) when is_tuple(value) do
    cond do
      not transform?(value) -> invalid!(value)
      mode == :css -> css(value, theme)
      true -> value |> compute(theme) |> literal()
    end
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

  # A step the theme pins of a name is that color; any other is on the curve (#667).
  def compute({:shade, c, n}, theme) do
    case pinned(c, n, theme) do
      nil ->
        {toward, u, k} = curve(n)
        polar(c, theme, fn {l, ch, h} -> {l + (toward - l) * u, ch * k, h} end)

      literal ->
        literal |> parsed!() |> oklab()
    end
  end

  def compute({:blend, list}, theme), do: blend(list, theme)
  def compute({:contrast, :under}, theme), do: theme |> Theme.ink(nil) |> parsed!() |> oklab()
  def compute({:contrast, c}, theme), do: c |> ink(theme) |> parsed!() |> oklab()
  def compute(value, theme), do: value |> resolve(theme, :literal) |> parsed!() |> oklab()

  defp polar(c, theme, fun) do
    {lab, alpha} = compute(c, theme)
    {lab |> OK.to_lch() |> fun.() |> OK.from_lch(), alpha}
  end

  @doc false
  # The one curve of `shade/2` (spec/08 §1.9, #667), both modes': for step `n` in 0..1000,
  # the lightness it moves toward (0.97, near white, below 500; 0.2, near black, above), the
  # fraction `u = |n − 500| / 500` of the way it moves, and the factor `1 − u²` on chroma.
  @spec curve(number()) :: {float(), float(), float()}
  def curve(n) do
    u = abs(n - 500) / 500
    {if(n < 500, do: @near_white, else: @near_black), u, 1 - u * u}
  end

  # The step a theme pins of a name's scale, `nil` for a step it does not pin or a color
  # that is not a name.
  defp pinned({:color, name}, n, theme), do: Theme.step(theme, name, n)
  defp pinned(_c, _n, _theme), do: nil

  # CSS Color 5's `color-mix` over any number of colors: weights normalized, OKLab averaged
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
  # An OKLab color and alpha as the literal a canvas takes: `#rrggbb`, with `aa` below an
  # alpha of 1, gamut-mapped (spec/08 §1.9).
  @spec literal({{number(), number(), number()}, number()}) :: String.t()
  def literal({lab, alpha}) do
    {r, g, b} = OK.map_to_srgb(lab)
    # An alpha that rounds to the opaque byte is opaque: no `ff` written after the color.
    alpha = if round(alpha * 255) >= 255, do: 1.0, else: alpha
    Color.to_hex(Color.rgb(r * 255, g * 255, b * 255, alpha))
  end

  # -- :css (spec/08 §1.9, #665) ------------------------------------------------------------

  # A transform as the CSS that computes it, its operands each in their own `:css` form, so
  # a stylesheet's theme switch carries through it.
  defp css(v, _theme) when is_binary(v), do: v
  defp css({:contrast, _} = ink, theme), do: resolve(ink, theme, :css)

  defp css({:intensity, c, t}, theme),
    do: "color-mix(in oklab, #{css(c, theme)} #{pct(t)}, transparent)"

  defp css({:alpha, c, a}, theme), do: "oklch(from #{css(c, theme)} l c h / #{num(a)})"

  defp css({:lighten, c, t}, theme),
    do: "oklch(from #{css(c, theme)} calc(l + (1 - l) * #{num(t)}) c h / alpha)"

  defp css({:darken, c, t}, theme),
    do: "oklch(from #{css(c, theme)} calc(l * #{num(1 - t)}) c h / alpha)"

  defp css({:saturate, c, t}, theme),
    do: "oklch(from #{css(c, theme)} l calc(c + (#{@full_chroma} - c) * #{num(t)}) h / alpha)"

  defp css({:shade, c, n}, theme) do
    case {pinned(c, n, theme), c} do
      _base when n == 500 ->
        css(c, theme)

      {nil, _c} ->
        {toward, u, k} = curve(n)
        sign = if toward > 0.5, do: "l + (#{num(toward)} - l)", else: "l - (l - #{num(toward)})"
        "oklch(from #{css(c, theme)} calc(#{sign} * #{num(u)}) calc(c * #{num(k)}) h / alpha)"

      {literal, {:color, name}} ->
        "var(--vis-#{name |> Atom.to_string() |> String.replace("_", "-")}-#{n}, #{literal})"
    end
  end

  defp css({:blend, list}, theme) do
    weighted =
      list
      |> Enum.map(fn
        {:intensity, c, w} -> {c, w}
        c -> {c, 1}
      end)
      |> Enum.reject(fn {_c, w} -> w == 0 end)

    total = weighted |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    case weighted do
      [] -> "transparent"
      [{c, 1}] -> css(c, theme)
      [{c, w}] -> css({:intensity, c, w}, theme)
      # Above 1 the weights are scaled to sum to 1, which CSS would do too, but a
      # percentage above 100% is not CSS.
      _many when total > 1 -> mix(Enum.map(weighted, fn {c, w} -> {c, w / total} end), theme)
      _many -> mix(weighted, theme)
    end
  end

  defp css(value, theme), do: resolve(value, theme, :css)

  # `color-mix` of two, or of the first n − 1 normalized and mixed at their sum with the
  # last: premultiplied averaging is associative, so the nesting is exact.
  defp mix([{c1, w1}, {c2, w2}], theme),
    do: "color-mix(in oklab, #{css(c1, theme)} #{pct(w1)}, #{css(c2, theme)} #{pct(w2)})"

  defp mix(weighted, theme) do
    {init, [{last, w}]} = Enum.split(weighted, -1)
    sum = init |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    inner = mix(Enum.map(init, fn {c, v} -> {c, v / sum} end), theme)
    "color-mix(in oklab, #{inner} #{pct(sum)}, #{css(last, theme)} #{pct(w)})"
  end

  defp pct(t), do: num(t * 100) <> "%"

  # At most four decimals, no trailing zeros: `65`, `0.3`, `33.3333`.
  defp num(x) when is_integer(x), do: Integer.to_string(x)

  defp num(x) do
    rounded = Float.round(x * 1.0, 4)

    if rounded == trunc(rounded),
      do: Integer.to_string(trunc(rounded)),
      else: :erlang.float_to_binary(rounded, [:compact, decimals: 4])
  end

  defp invalid!(value) do
    raise ArgumentError,
          "not a color value: #{inspect(value)}; a color is color(name), ramp(name, t), " <>
            "{:series, i}, a literal string or a transform of them (spec/08 §1.9)"
  end
end
