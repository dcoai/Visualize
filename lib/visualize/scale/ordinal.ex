defmodule Visualize.Scale.Ordinal do
  @moduledoc """
  A discrete scale that maps categorical values to a discrete range.

  Useful for encoding categorical data with colors or shapes.
  """

  defstruct domain: [],
            range: [],
            unknown: nil

  @type t :: %__MODULE__{
          domain: [any()],
          range: [any()],
          unknown: any()
        }

  @doc "Creates a new ordinal scale"
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Sets the domain (list of categories)"
  @spec domain(t(), [any()]) :: t()
  def domain(%__MODULE__{} = scale, categories) when is_list(categories) do
    %{scale | domain: categories}
  end

  @doc "Sets the range (list of output values)"
  @spec range(t(), [any()]) :: t()
  def range(%__MODULE__{} = scale, values) when is_list(values) do
    %{scale | range: values}
  end

  @doc "Sets the value to return for unknown domain values"
  @spec unknown(t(), any()) :: t()
  def unknown(%__MODULE__{} = scale, value) do
    %{scale | unknown: value}
  end

  @doc "Applies the scale to a categorical value"
  @spec apply(t(), any()) :: any()
  def apply(%__MODULE__{domain: domain, range: range, unknown: unknown}, value) do
    case Enum.find_index(domain, &(&1 == value)) do
      nil ->
        unknown

      index ->
        # Cycle through range if domain is larger
        range_index = rem(index, length(range))
        Enum.at(range, range_index)
    end
  end

  @doc "Not applicable for ordinal scales"
  @spec invert(t(), any()) :: nil
  def invert(%__MODULE__{}, _value), do: nil

  @doc "Returns the domain values as ticks"
  @spec ticks(t(), integer()) :: [any()]
  def ticks(%__MODULE__{domain: domain}, _count), do: domain

  @doc "Returns the scale unchanged"
  @spec nice(t()) :: t()
  def nice(%__MODULE__{} = scale), do: scale

  # Not applicable
  def clamp(scale, _), do: scale
  def padding(scale, _), do: scale
  def bandwidth(_), do: 0
end
