defmodule Visualize.Chart.Validator.Palette do
  @moduledoc false
  # The validator's view of the style palette (spec/14 §2.5, §3.3, §3.6, §4.3, #637,
  # D-171): which style names a design may reference under its theme, how a stored theme's
  # palette entry is read by the style grammar, and whether a scale ranges over styles, so
  # a `{:scale, name, field}` stack entry has styles to lay.

  alias Visualize.Chart.{Fact, Var}
  alias Visualize.Theme
  alias Visualize.Theme.Palette

  @series ~r/^style_[1-9]\d*$/
  @kinds [:ordinal, :threshold]

  @doc false
  # The palette names a reference may take under a theme: the theme's own when the
  # validator can see it, built-in or inline; else the fixed names of the roles, the states
  # and the furniture, the style series being the host theme's to say (`open?/1`).
  @spec names(Theme.t() | :unknown) :: [atom()]
  def names(%Theme{} = theme), do: Theme.style_names(theme)
  def names(:unknown), do: Palette.names([])

  @doc false
  # Whether a name is one of a style series, `:style_k`: accepted under a theme the
  # validator cannot see, which may hold any number of them (spec/14 §3.3).
  @spec series?(term()) :: boolean()
  def series?(name) when is_atom(name), do: Regex.match?(@series, Atom.to_string(name))
  def series?(_name), do: false

  @doc false
  # A stored theme's palette entry as the style grammar reads it (spec/14 §2.5): a role's
  # `:cue` and an `extends` are the palette contract's to judge, so they are left to it.
  @spec entry(map()) :: map()
  def entry(entry) do
    entry |> Map.delete(:extends) |> Map.reject(fn {_key, value} -> value == :cue end)
  end

  @doc false
  # A styles range on a scale that has no categories or bands to give it (spec/14 §4.3).
  @spec style_range(map(), list()) :: [{list(), {:style_range, atom()}}]
  def style_range(%{kind: kind, range: {:styles, _set}}, path)
      when is_atom(kind) and kind not in @kinds,
      do: [{path ++ [:range], {:style_range, kind}}]

  def style_range(_scale, _path), do: []

  @doc false
  # Whether a scale node ranges over styles (spec/14 §3.6): an ordinal or threshold scale
  # whose range is a set of styles, a list or a map of style names — `name?` says which
  # names are — a feed's status, or a variable that application will bind.
  @spec styles?(map(), (atom() -> boolean())) :: boolean()
  def styles?(node, name?) do
    kind = Map.get(node, :kind)
    (kind in @kinds or is_struct(kind, Var)) and range?(Map.get(node, :range, :auto), name?)
  end

  defp range?({:styles, set}, _name?), do: set in [:roles, :series]
  defp range?(%Var{}, _name?), do: true
  defp range?(%Fact{key: key}, _name?), do: key == :status
  defp range?([_ | _] = names, name?), do: Enum.all?(names, &style?(&1, name?))

  defp range?(map, name?) when is_map(map) and not is_struct(map) and map_size(map) > 0,
    do: Enum.all?(map, fn {_category, value} -> style?(value, name?) end)

  defp range?(_range, _name?), do: false

  defp style?(value, name?) when is_atom(value) and value not in [nil, true, false],
    do: name?.(value)

  defp style?(_value, _name?), do: false
end
