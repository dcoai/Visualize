defmodule Visualize.Chart.Migration do
  @moduledoc """
  Schema versions and the migrations between them (spec/14 §9).

  `current/0` is the version this library writes. `migrate/1` steps an older design
  forward one version at a time through the migration registered for each step, so a
  stored design never goes stale; no migration is registered yet, and the hook exists so
  that the first schema change ships with its step rather than with a breaking change.
  """

  alias Visualize.Chart.Validator

  @current 1

  @doc "The schema version this library writes: `#{@current}`."
  @spec current() :: pos_integer()
  def current, do: @current

  @doc """
  The design at the current version.

  A design already there passes through unchanged; an older one is migrated step by
  step; a version above `current/0`, below `1`, missing or not an integer is an error at
  `[:version]`.
  """
  @spec migrate(term()) :: {:ok, map()} | {:error, [Validator.error(), ...]}
  def migrate(%{version: @current} = map), do: {:ok, map}

  def migrate(%{version: v} = map) when is_integer(v) and v >= 1 and v < @current do
    migrate(step(map, v))
  end

  def migrate(%{version: v}) when is_integer(v) do
    {:error, [{[:version], {:unsupported_version, v}}]}
  end

  def migrate(%{version: _}), do: {:error, [{[:version], {:type, :integer}}]}

  def migrate(map) when is_map(map) and not is_struct(map) do
    {:error, [{[:version], :required}]}
  end

  def migrate(_), do: {:error, [{[], {:type, {:node, :design}}}]}

  # One clause per registered migration, from a version to the next, each pure and
  # yielding the map at `from + 1`. Version 1 has none: the first schema change adds
  # `defp step(map, 1)` above this clause, which no reachable call meets.
  defp step(map, from) do
    raise ArgumentError, "no migration from version #{from} for #{inspect(map)}"
  end
end
