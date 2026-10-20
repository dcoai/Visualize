defmodule Visualize.Theme.Roles do
  @moduledoc false
  # The contracts the five role styles hold as a set, and the one every palette entry's
  # colors hold (spec/08 §7.7, #666, D-173): the roles apart without hue, their colors apart,
  # their paints readable against the theme's background by WCAG's ratios, and every color
  # name a name of the theme's color table. Each role is read as `Visualize.Theme.style/2`
  # answers it, its cue in place. A fault is `{{:style, name}, message}`, a pair's at its
  # later role.

  alias Visualize.{Color, Theme}
  alias Visualize.Color.Typed

  # WCAG 2.2: SC 1.4.11 (non-text) and SC 1.4.3 (text, AA).
  @non_text 3.0
  @text 4.5
  # The just-noticeable difference in OKLab: below it two colors read as one.
  @jnd 0.02
  @paints [:fill, :stroke]

  @doc false
  # Every fault, the entries whose palette contracts already fail (`broken`) left out.
  @spec violations(Theme.t(), [atom()]) :: [{{:style, atom()}, String.t()}]
  def violations(%Theme{} = theme, broken) do
    palette = Theme.palette(theme)
    unresolved = unresolved(theme, palette, broken)
    skip = broken ++ Enum.map(unresolved, fn {{:style, name}, _} -> name end)

    roles =
      for role <- Theme.role_names(), role not in skip, do: {role, Map.get(palette, role, %{})}

    unresolved ++ readable(roles, theme) ++ apart(roles, theme) ++ hueless(roles)
  end

  # Every `{:color, name}` a palette entry paints with is a name of the table.
  defp unresolved(theme, palette, broken) do
    for {name, entry} <- Enum.sort(palette),
        name not in broken,
        missing = missing(entry, theme),
        missing != [],
        do: {{:style, name}, "names #{list(missing)}, not a color of the theme's color table"}
  end

  # A theme's own color is matched by spelling (D-195): `Theme.color_name?/2`.
  defp missing(entry, theme) do
    for part <- @paints,
        color = color(entry, part),
        name <- Typed.names(color),
        not Theme.color_name?(theme, name),
        uniq: true,
        do: name
  end

  # -- readable -------------------------------------------------------------------------

  defp readable(roles, theme) do
    background = Color.parse(theme.background || "#ffffff") || Color.rgb(255, 255, 255)

    for {role, entry} <- roles,
        part <- @paints,
        color = color(entry, part),
        computable?(color),
        {floor, rule} = rule(entry, part),
        ratio = Color.contrast(over(color, theme, background), background),
        ratio < floor do
      {{:style, role},
       "#{part} #{inspect(color)} is #{ratio(ratio)}:1 against #{Color.to_hex(background)}; " <>
         "a role style's #{rule}"}
    end
  end

  # An entry with a font is text: its fill is the text's color (SC 1.4.3).
  defp rule(entry, :fill) when is_map_key(entry, :font),
    do: {@text, "text must reach 4.5:1 (WCAG 1.4.3, text contrast)"}

  defp rule(_entry, _part),
    do: {@non_text, "paint must reach 3:1 (WCAG 1.4.11, non-text contrast)"}

  # The color as it is seen: laid over the background when translucent.
  defp over(color, theme, background) do
    %Color{r: r, g: g, b: b, opacity: a} = Color.parse(Color.resolve(color, theme, :literal))
    mix = fn x, y -> x * a + y * (1 - a) end
    Color.rgb(mix.(r, background.r), mix.(g, background.g), mix.(b, background.b))
  end

  # -- apart ----------------------------------------------------------------------------

  defp apart(roles, theme) do
    painted =
      for {role, entry} <- roles,
          color = color(entry, :fill) || color(entry, :stroke),
          computable?(color),
          do: {role, color, Color.to_oklab(Color.parse(Color.resolve(color, theme, :literal)))}

    for {{a, ca, la}, i} <- Enum.with_index(painted),
        {{b, cb, lb}, j} <- Enum.with_index(painted),
        i < j,
        (d = delta(la, lb)) < @jnd do
      {{:style, b},
       "the role styles' colors must be distinct, but #{inspect(a)} paints #{inspect(ca)} and " <>
         "#{inspect(b)} #{inspect(cb)}, #{Float.round(d, 3)} ΔEOK apart, under the " <>
         "just-noticeable #{@jnd}"}
    end
  end

  defp delta(a, b),
    do: :math.sqrt((a.l - b.l) ** 2 + (a.a - b.a) ** 2 + (a.b - b.b) ** 2)

  # -- hueless --------------------------------------------------------------------------

  defp hueless(roles) do
    stripped = Enum.map(roles, fn {role, entry} -> {role, strip(entry)} end)

    for {{a, ea}, i} <- Enum.with_index(stripped),
        {{b, eb}, j} <- Enum.with_index(stripped),
        i < j,
        ea == eb do
      {{:style, b},
       "role styles must differ in something besides the colors of fill and stroke (a dash, " <>
         "a marker, a weight), but #{inspect(a)} and #{inspect(b)} differ only in hue"}
    end
  end

  defp strip(entry) do
    Map.new(entry, fn
      {part, %{} = paint} when part in @paints and not is_struct(paint) ->
        {part, Map.delete(paint, :color)}

      other ->
        other
    end)
  end

  # -- reading an entry -----------------------------------------------------------------

  # The color a solid or a hatched paint part gives, `nil` for none, a gradient or `:none`.
  defp color(entry, part) do
    case Map.get(entry, part) do
      %{type: :solid, color: color} -> color
      # A hatch's lines are its color, held to the same ratios (#673).
      %{type: :hatch, color: color} -> color
      %{color: color} = paint when not is_map_key(paint, :type) -> color
      _other -> nil
    end
  end

  # A color the check can compute: a typed color or a literal `Visualize.Color.parse/1`
  # reads — not a field binding, a variable or a CSS word such as `currentColor`.
  defp computable?(color) when is_binary(color), do: Typed.unreadable({:alpha, color, 1}) == []
  defp computable?({:series, _} = color), do: Typed.value?(color)
  defp computable?(color) when is_tuple(color), do: Typed.value?(color)
  defp computable?(_color), do: false

  defp ratio(r), do: :erlang.float_to_binary(Float.floor(r * 100) / 100, decimals: 2)

  defp list(names), do: Enum.map_join(names, ", ", &inspect/1)
end
