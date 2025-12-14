defmodule Visualize.Shape.Pie do
  @moduledoc """
  Pie layout generator that computes angles for pie and donut charts.

  This doesn't generate paths directly - it computes start and end angles
  that can be passed to the Arc generator.

  ## Examples

      data = [
        %{name: "A", value: 30},
        %{name: "B", value: 50},
        %{name: "C", value: 20}
      ]

      pie = Visualize.Shape.Pie.new()
        |> Visualize.Shape.Pie.value(fn d -> d.value end)

      arcs = Visualize.Shape.Pie.generate(pie, data)
      # Returns list of maps with :data, :value, :index, :start_angle, :end_angle, :pad_angle

  """

  @tau 2 * :math.pi()

  defstruct value: nil,
            sort: nil,
            sort_values: nil,
            start_angle: 0,
            end_angle: @tau,
            pad_angle: 0

  @type accessor :: (any() -> number()) | atom()
  @type comparator :: (any(), any() -> boolean())
  @type t :: %__MODULE__{
          value: accessor() | nil,
          sort: comparator() | nil,
          sort_values: comparator() | nil,
          start_angle: number() | (any() -> number()),
          end_angle: number() | (any() -> number()),
          pad_angle: number() | (any() -> number())
        }

  @type arc_data :: %{
          data: any(),
          value: number(),
          index: non_neg_integer(),
          start_angle: number(),
          end_angle: number(),
          pad_angle: number()
        }

  @doc "Creates a new pie generator"
  @spec new() :: t()
  def new do
    %__MODULE__{
      value: fn d ->
        cond do
          is_number(d) -> d
          is_map(d) -> Map.get(d, :value, 0)
          true -> 0
        end
      end
    }
  end

  @doc "Sets the value accessor"
  @spec value(t(), accessor()) :: t()
  def value(%__MODULE__{} = pie, accessor) do
    %{pie | value: normalize_accessor(accessor)}
  end

  @doc """
  Sets a comparator to sort the data before computing angles.

  Takes a function that receives two data elements and returns true
  if the first should come before the second.
  """
  @spec sort(t(), comparator() | nil) :: t()
  def sort(%__MODULE__{} = pie, comparator) do
    %{pie | sort: comparator, sort_values: nil}
  end

  @doc """
  Sets a comparator to sort by computed values.

  Takes a function that receives two values and returns true
  if the first should come before the second.
  """
  @spec sort_values(t(), comparator() | nil) :: t()
  def sort_values(%__MODULE__{} = pie, comparator) do
    %{pie | sort_values: comparator, sort: nil}
  end

  @doc "Sets the start angle (in radians)"
  @spec start_angle(t(), number()) :: t()
  def start_angle(%__MODULE__{} = pie, angle) do
    %{pie | start_angle: angle}
  end

  @doc "Sets the end angle (in radians)"
  @spec end_angle(t(), number()) :: t()
  def end_angle(%__MODULE__{} = pie, angle) do
    %{pie | end_angle: angle}
  end

  @doc "Sets the pad angle between arcs (in radians)"
  @spec pad_angle(t(), number()) :: t()
  def pad_angle(%__MODULE__{} = pie, angle) do
    %{pie | pad_angle: angle}
  end

  @doc """
  Generates arc data from the input data.

  Returns a list of maps, each containing:
  - `:data` - the original data element
  - `:value` - the computed value
  - `:index` - the original index
  - `:start_angle` - start angle in radians
  - `:end_angle` - end angle in radians
  - `:pad_angle` - padding angle in radians
  """
  @spec generate(t(), [any()]) :: [arc_data()]
  def generate(%__MODULE__{} = pie, data) do
    n = length(data)

    if n == 0 do
      []
    else
      # Compute values and indices
      indexed_values =
        data
        |> Enum.with_index()
        |> Enum.map(fn {d, i} ->
          %{data: d, value: max(0, apply_accessor(pie.value, d)), index: i}
        end)

      # Sort if needed
      sorted =
        cond do
          pie.sort != nil ->
            Enum.sort(indexed_values, fn a, b -> pie.sort.(a.data, b.data) end)

          pie.sort_values != nil ->
            Enum.sort(indexed_values, fn a, b -> pie.sort_values.(a.value, b.value) end)

          true ->
            indexed_values
        end

      # Calculate total
      total = Enum.reduce(sorted, 0, fn item, acc -> acc + item.value end)

      # Calculate angles
      a0 = apply_angle(pie.start_angle, data)
      a1 = apply_angle(pie.end_angle, data)
      da = min(@tau, max(-@tau, a1 - a0))
      pad = apply_angle(pie.pad_angle, data)

      # Distribute angles
      k = if total > 0, do: (da - n * pad) / total, else: 0

      {arcs, _} =
        Enum.map_reduce(sorted, a0, fn item, angle ->
          arc_pad = if item.value > 0, do: pad, else: 0
          arc_da = item.value * k

          arc = %{
            data: item.data,
            value: item.value,
            index: item.index,
            start_angle: angle,
            end_angle: angle + arc_da,
            pad_angle: arc_pad
          }

          {arc, angle + arc_da + arc_pad}
        end)

      # Return in original order
      Enum.sort_by(arcs, & &1.index)
    end
  end

  defp normalize_accessor(accessor) when is_function(accessor, 1), do: accessor
  defp normalize_accessor(field) when is_atom(field), do: fn d -> Map.get(d, field, 0) end
  defp normalize_accessor(value) when is_number(value), do: fn _ -> value end

  defp apply_accessor(accessor, data) when is_function(accessor, 1), do: accessor.(data)

  defp apply_angle(angle, _data) when is_number(angle), do: angle
  defp apply_angle(angle, data) when is_function(angle, 1), do: angle.(data)
end
