defmodule Visualize.Chart.Validator.Motion do
  @moduledoc false
  # The checks a motion part needs beyond its schema (spec/14 §3.10, §10.1, D-176): a time
  # is never negative.

  @times [:duration]

  @doc false
  # `:negative` at each time of the node below zero.
  @spec check(map(), list()) :: [{list(), :negative}]
  def check(node, path) do
    for key <- @times,
        value = Map.get(node, key),
        is_number(value) and value < 0,
        do: {path ++ [key], :negative}
  end
end
