defmodule Visualize.Chart.Validator.Palette do
  @moduledoc false
  # The validator's view of the style palette (spec/14 §2.5, §3.3, #637, D-171): which
  # style names a design may reference under its theme, and how a stored theme's palette
  # entry is read by the style grammar.

  alias Visualize.Theme
  alias Visualize.Theme.Palette

  @series ~r/^style_[1-9]\d*$/

  @doc false
  # The palette names a reference may take under a theme: the theme's own when the
  # validator can see it, built-in or inline; else the fixed names of the roles, the states
  # and the furniture, the style series being the host theme's to say (`open?/1`).
  # A design names a style by its string (spec/14 §1.4, D-195), so the palette's are spelled.
  @spec names(Theme.t() | :unknown) :: [String.t()]
  def names(%Theme{} = theme), do: theme |> Theme.style_names() |> Enum.map(&Atom.to_string/1)
  def names(:unknown), do: [] |> Palette.names() |> Enum.map(&Atom.to_string/1)

  @doc false
  # Whether a name is one of a style series, `:style_k`: accepted under a theme the
  # validator cannot see, which may hold any number of them (spec/14 §3.3).
  @spec series?(term()) :: boolean()
  def series?(name) when is_atom(name), do: Regex.match?(@series, Atom.to_string(name))
  def series?(name) when is_binary(name), do: Regex.match?(@series, name)
  def series?(_name), do: false

  @doc false
  # A stored theme's palette entry as the style grammar reads it (spec/14 §2.5): a role's
  # `:cue` — a stroke's `dash` or a marker's `shape` — and an `extends` are the palette
  # contract's to judge, so they are left to it.
  @spec entry(map()) :: map()
  def entry(entry) do
    entry
    |> Visualize.Chart.Style.normalize()
    |> Map.delete(:extends)
    |> Map.new(fn
      {key, part} when is_map(part) and not is_struct(part) ->
        {key, Map.reject(part, fn {_key, value} -> value == :cue end)}

      other ->
        other
    end)
  end
end
