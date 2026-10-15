defmodule Visualize.Chart.Style.Sizes do
  @moduledoc false
  # Unit values in a style, resolved to user units on the server (spec/14 §3.9, #651,
  # D-174), so every backend gets a number.
  #
  # An absolute unit converts at CSS's ratios. An `em` at `font.size` is measured against
  # the **inherited** font size — what the element's containers' defaults give, the theme's
  # root `font_size` when none does — and an `em` anywhere else against the element's own
  # resolved font size. A `pct` at `font.size` is of the inherited size; at a text offset
  # and a marker size it has a box only the layout knows, so it is kept for the placement
  # and the symbol to resolve; anywhere else the validator refuses it, and here it raises.
  # A style with no unit value is returned as it is.

  alias Visualize.{Theme, Units}

  @doc false
  # The font size `containers` give, each container's relative size measured against the
  # one before it (spec/14 §3.9): a relative size over nothing stays relative to the root,
  # an `em` over an `em` multiplies, and over a number, an absolute unit or a slot it is a
  # number in user units. `size` is the size laid so far, `set` the container's own.
  @spec nest(term(), term(), Theme.t() | nil) :: term()
  def nest(size, set, theme) do
    case relative(set) do
      nil -> set
      factor -> over(size, factor, theme)
    end
  end

  defp over(nil, factor, _theme), do: {factor, :em}
  defp over({n, :em}, factor, _theme) when is_number(n), do: {n * factor, :em}
  defp over({:field, _} = field, _factor, _theme), do: field

  defp over(size, factor, theme) do
    case px(size, theme) do
      nil -> {factor, :em}
      base -> base * factor
    end
  end

  # The factor of a relative font size, `nil` for any other.
  defp relative({n, :em}) when is_number(n), do: n
  defp relative({n, :pct}) when is_number(n), do: n / 100
  defp relative(_size), do: nil

  @doc false
  # The style in its parts with every unit value in user units but a `pct` where a box is
  # needed: `style` is `stack` laid over `base`, the style the containers laid
  # (`Visualize.Chart.Style.Defaults`), and `theme` the root's.
  @spec resolve(map(), map(), map(), Theme.t()) :: map()
  def resolve(style, base, stack, theme) do
    if units?(style) do
      inherited = inherited(base, theme)
      own = own(get_in(stack, [:font, :size]), get_in(base, [:font, :size]), inherited)
      em = px(own, theme) || inherited

      style
      |> put_part(:font, :size, own)
      |> update_part(:stroke, :width, &length(&1, em, :width))
      |> update_part(:stroke, :dash, &dash(&1, em))
      |> update_part(:effect, :radius, &length(&1, em, :radius))
      |> update_part(:text, :offset, &offset(&1, em))
      |> update_part(:marker, :size, &marker(&1, em))
      |> opacities()
    else
      style
    end
  end

  # The inherited font size in user units: the containers', the root's when none sets one.
  defp inherited(base, theme) do
    root = theme.font_size

    case get_in(base, [:font, :size]) do
      nil -> root
      {n, :em} when is_number(n) -> n * root
      size -> px(size, theme) || root
    end
  end

  # The element's own font size: the inherited size where its stack sets none, measured
  # against it where the stack makes it relative, converted where absolute.
  defp own(nil, base, inherited), do: if(Units.unit?(base), do: inherited, else: base)

  defp own(set, _base, inherited) do
    case relative(set) do
      nil -> if Units.unit?(set), do: Units.to_px(set), else: set
      factor -> inherited * factor
    end
  end

  # A font size in user units, `nil` when it is not one the server can know (a binding).
  defp px(size, _theme) when is_number(size), do: size
  defp px({n, :em}, theme) when is_number(n), do: n * theme.font_size

  defp px(size, theme) when is_atom(size) and size != nil do
    case Theme.resolve(theme, size, :literal) do
      n when is_number(n) -> n
      _other -> nil
    end
  end

  defp px(size, _theme) do
    if Units.unit?(size), do: Units.to_px(size)
  end

  defp length({_n, :pct}, _em, key), do: no_box!(key)
  defp length(size, em, _key), do: units(size, em)

  defp dash(list, em) when is_list(list), do: Enum.map(list, &length(&1, em, :dash))
  defp dash(dash, _em), do: dash

  defp offset(list, em) when is_list(list), do: Enum.map(list, &box(&1, em))
  defp offset(offset, _em), do: offset

  # A unit-valued marker size is the side of the square of the area (spec/14 §3.9).
  defp marker({n, unit} = size, em) when is_number(n) and unit != :pct do
    if Units.unit?(size), do: :math.pow(Units.resolve(size, %{em: em}), 2), else: size
  end

  defp marker(size, _em), do: size

  # A `pct` is kept for the layout, which knows the box.
  defp box({_n, :pct} = size, _em), do: size
  defp box(size, em), do: units(size, em)

  defp units({n, _unit} = size, em) when is_number(n) do
    if Units.unit?(size), do: Units.resolve(size, %{em: em}), else: size
  end

  defp units(size, _em), do: size

  defp opacities(style) do
    for {path, value} <- [
          {[:opacity], Map.get(style, :opacity)},
          {[:fill, :opacity], get_in(style, [:fill, :opacity])},
          {[:stroke, :opacity], get_in(style, [:stroke, :opacity])}
        ],
        Units.unit?(value) do
      raise ArgumentError,
            "#{inspect(value)} at #{inspect(path)}: an opacity is a fraction, not a length " <>
              "(spec/14 §3.9)"
    end

    style
  end

  defp no_box!(key) do
    raise ArgumentError,
          "a pct at a stroke's or an effect's #{key} has no box to be a percentage of " <>
            "(spec/14 §3.9)"
  end

  # Whether any value of the style's parts is a unit value.
  defp units?(style) do
    Enum.any?(style, fn
      {_key, %{} = part} when not is_struct(part) ->
        Enum.any?(part, fn {_k, v} -> unit_in?(v) end)

      {_key, value} ->
        unit_in?(value)
    end)
  end

  defp unit_in?(list) when is_list(list), do: Enum.any?(list, &Units.unit?/1)
  defp unit_in?(value), do: Units.unit?(value)

  defp put_part(style, _part, _key, nil), do: style

  defp put_part(style, part, key, value),
    do: Map.update(style, part, %{key => value}, &Map.put(&1, key, value))

  defp update_part(style, part, key, fun) do
    case style do
      %{^part => %{^key => value} = node} when not is_struct(node) ->
        Map.put(style, part, Map.put(node, key, fun.(value)))

      _other ->
        style
    end
  end
end
