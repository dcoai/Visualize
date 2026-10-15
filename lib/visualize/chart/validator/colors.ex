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

  defp undeclared(_value, _path, :unknown), do: []

  defp undeclared(value, path, names) do
    for name <- value |> Typed.names() |> Enum.uniq(),
        not MapSet.member?(names, name),
        do: {path, {:undeclared, :color, name}}
  end
end
