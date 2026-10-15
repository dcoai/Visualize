defmodule Visualize.Chart.Validator.Motion do
  @moduledoc false
  # The checks a motion part needs beyond its schema (spec/14 §3.10, §3.11, §10.1, §10.3,
  # D-176): a time or a count is never negative, and an animation's name that is a string —
  # keyframes the host registers — is one CSS identifier, since it is written into a
  # stylesheet.

  @times [:duration, :delay, :iterations]
  @kinds [:style_transition, :part_transition, :style_animation, :style_enter, :style_exit]
  @identifier ~r/\A-?[_a-zA-Z][_a-zA-Z0-9-]*\z/

  @doc false
  # `:negative` at each time of the node below zero; `{:unsafe, :animation}` at a name
  # that is not a CSS identifier.
  @spec check(map(), list()) :: [{list(), term()}]
  def check(node, path) do
    negative =
      for key <- @times,
          value = Map.get(node, key),
          is_number(value) and value < 0,
          do: {path ++ [key], :negative}

    negative ++ name(Map.get(node, :name), path)
  end

  defp name(name, path) when is_binary(name) do
    if identifier?(name), do: [], else: [{path ++ [:name], {:unsafe, :animation}}]
  end

  defp name(_name, _path), do: []

  @doc false
  # The node kinds of the motion parts.
  @spec kinds() :: [atom(), ...]
  def kinds, do: @kinds

  @doc false
  # Whether a host's keyframes name may be written into a stylesheet.
  @spec identifier?(String.t()) :: boolean()
  def identifier?(name), do: Regex.match?(@identifier, name)
end
