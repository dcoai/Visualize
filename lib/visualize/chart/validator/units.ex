defmodule Visualize.Chart.Validator.Units do
  @moduledoc false
  # The validator's view of a unit value (spec/14 §3.9, spec/08 §13, #651, D-174): the
  # shape a `:size` or a `:length` takes when it is one, and what a key owes its units — a
  # `pct` only where a size has a box, no unit at an opacity.

  alias Visualize.Units

  # The keys whose size has no box a percentage could be of.
  @boxless %{stroke: [:width, :dash], effect: [:radius, :offset], paint: [:spacing, :width]}

  @doc false
  # The faults of a value at a `:size` or a `:length` position (spec/14 §1.4): none for a
  # number or a unit value, `{:type, type}` for a tuple of a number that is not one or for
  # any other value at a `:length`; `nil` for any other value at a `:size`, which may be a
  # slot the caller checks.
  @spec check(:size | :length, term(), list()) :: [{list(), term()}] | nil
  def check(_type, n, _path) when is_number(n), do: []

  def check(type, {n, _unit} = value, path) when is_number(n) do
    if Units.unit?(value), do: [], else: [{path, {:type, type}}]
  end

  def check(:length, _value, path), do: [{path, {:type, :length}}]
  def check(:size, _value, _path), do: nil

  @doc """
  The units a size at a node kind's key may be written in (spec/14 §3.9): none at an
  opacity, every unit but `:pct` where the size has no box, else every unit — the table the
  validator checks and the builder's unit select offers (§18.6).

      iex> :pct in Visualize.Chart.Validator.Units.units(:stroke, :width)
      false

      iex> :pct in Visualize.Chart.Validator.Units.units(:font, :size)
      true

      iex> Visualize.Chart.Validator.Units.units(:paint, :opacity)
      []
  """
  @spec units(atom(), atom()) :: [Units.unit()]
  def units(_kind, :opacity), do: []

  def units(kind, key) do
    if key in Map.get(@boxless, kind, []), do: Units.units() -- [:pct], else: Units.units()
  end

  @doc false
  # What a key of a node kind owes its units, beside its type: `{:no_box, key}` for a `pct`
  # where the size has no box, `{:no_unit, key}` for any unit at an opacity.
  @spec faults(atom(), atom(), term(), list()) :: [{list(), term()}]
  def faults(_kind, :opacity, value, path) do
    if Units.unit?(value), do: [{path, {:no_unit, :opacity}}], else: []
  end

  def faults(kind, key, value, path) do
    if key in Map.get(@boxless, kind, []) and pct?(value),
      do: [{path, {:no_box, key}}],
      else: []
  end

  defp pct?({n, :pct}) when is_number(n), do: true
  defp pct?(list) when is_list(list), do: Enum.any?(list, &pct?/1)
  defp pct?(_value), do: false
end
