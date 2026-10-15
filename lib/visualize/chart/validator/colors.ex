defmodule Visualize.Chart.Validator.Colors do
  @moduledoc false
  # The validator's view of a typed color (spec/14 §3.2, spec/08 §1.9, #664, D-173): its
  # shape, the literal operands a transform computes from, and every name it reads from the
  # theme's color table.

  alias Visualize.Color.Typed

  @doc false
  # The faults of one typed color at `path`: `{:type, :colour}` for a shape that is no color
  # value or a literal operand no transform can read, else `{:undeclared, :color, name}` for
  # each name the table lacks, in order — none when the theme is one the validator cannot
  # see (`:unknown`).
  @spec check(term(), list(), MapSet.t() | :unknown) :: [{list(), term()}]
  def check(value, path, names) do
    cond do
      not Typed.value?(value) -> [{path, {:type, :colour}}]
      Typed.unreadable(value) != [] -> [{path, {:type, :colour}}]
      true -> undeclared(value, path, names)
    end
  end

  @doc false
  # A ramp's anchor is a colour string or a name of the theme's table (spec/08 §7.5, #664).
  @spec anchor?(term()) :: boolean()
  def anchor?(anchor), do: is_binary(anchor) or match?({:color, name} when is_atom(name), anchor)

  # The fields of an inline theme its contracts are measured with: the role styles are read
  # against its own background and colors (spec/08 §7.7, #666).
  @measured [:ramps, :colors, :styles, :background, :text, :axis, :grid, :surface, :series]

  @doc false
  # An inline theme's fields its contracts are measured with, each only when well typed: a
  # type fault is the type check's to report.
  @spec measured(map()) :: map()
  def measured(map) do
    map
    |> Map.take(@measured)
    |> Map.filter(fn
      {:series, v} -> is_list(v) and v != [] and Enum.all?(v, &is_binary/1)
      {k, v} when k in [:background, :text, :axis, :grid, :surface] -> is_binary(v)
      _ramps_colors_styles -> true
    end)
  end

  defp undeclared(_value, _path, :unknown), do: []

  defp undeclared(value, path, names) do
    for name <- value |> Typed.names() |> Enum.uniq(),
        not MapSet.member?(names, name),
        do: {path, {:undeclared, :color, name}}
  end
end
