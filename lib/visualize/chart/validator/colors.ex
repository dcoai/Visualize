defmodule Visualize.Chart.Validator.Colors do
  @moduledoc false

  import Visualize.Chart.Names, only: [is_name: 1]
  # The validator's view of a typed color (spec/14 §3.2, spec/08 §1.9, #664, D-173): its
  # shape, the literal operands a transform computes from, and every name it reads from the
  # theme's color table.

  alias Visualize.Color.Typed

  @doc false
  # The faults of one typed color at `path`: `{:type, :color}` for a shape that is no color
  # value or a literal operand no transform can read, else `{:undeclared, :color, name}` for
  # each name the table lacks, in order — none when the theme is one the validator cannot
  # see (`:unknown`).
  @spec check(term(), list(), MapSet.t() | :unknown) :: [{list(), term()}]
  def check(value, path, names) do
    cond do
      not Typed.value?(value) -> [{path, {:type, :color}}]
      Typed.unreadable(value) != [] -> [{path, {:type, :color}}]
      true -> undeclared(value, path, names)
    end
  end

  @doc false
  # A ramp's anchor is a color string or a name of the theme's table (spec/08 §7.5, #664).
  @spec anchor?(term()) :: boolean()
  def anchor?(anchor), do: is_binary(anchor) or match?({:color, name} when is_name(name), anchor)

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

  @doc false
  # A theme's pinned steps (spec/08 §7.1, #667): integer steps to color strings, whose
  # meaning — 500 among them, each in 0..1000, each a color — the theme's contract holds.
  @spec steps(map(), list()) :: [{list(), term()}]
  def steps(map, path) do
    if Enum.all?(map, fn {n, c} -> is_integer(n) and is_binary(c) end),
      do: [],
      else: [{path, {:type, :theme_color}}]
  end

  defp undeclared(_value, _path, :unknown), do: []

  # A name is the table's by its spelling: a theme's own colors may be keyed either way.
  defp undeclared(value, path, names) do
    case value |> Typed.names() |> Enum.uniq() |> Enum.reject(&MapSet.member?(names, &1)) do
      [] ->
        []

      missing ->
        spelled = MapSet.new(names, &to_string/1)

        for name <- missing,
            not MapSet.member?(spelled, to_string(name)),
            do: {path, {:undeclared, :color, name}}
    end
  end
end
