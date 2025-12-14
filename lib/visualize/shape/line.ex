defmodule Visualize.Shape.Line do
  @moduledoc """
  Line generator for creating SVG paths from data points.

  Similar to D3's line generator, this produces path data for line charts.

  ## Examples

      data = [
        %{date: ~D[2024-01-01], value: 10},
        %{date: ~D[2024-01-02], value: 25},
        %{date: ~D[2024-01-03], value: 15}
      ]

      line = Visualize.Shape.Line.new()
        |> Visualize.Shape.Line.x(fn d -> scale_x.(d.date) end)
        |> Visualize.Shape.Line.y(fn d -> scale_y.(d.value) end)
        |> Visualize.Shape.Line.curve(:monotone_x)

      path_data = Visualize.Shape.Line.generate(line, data)

  """

  alias Visualize.Shape.Curve
  alias Visualize.SVG.Path

  defstruct x: nil,
            y: nil,
            defined: nil,
            curve: :linear,
            curve_opts: []

  @type accessor :: (any() -> number()) | atom()
  @type t :: %__MODULE__{
          x: accessor() | nil,
          y: accessor() | nil,
          defined: (any() -> boolean()) | nil,
          curve: Curve.curve_type(),
          curve_opts: keyword()
        }

  @doc "Creates a new line generator"
  @spec new() :: t()
  def new do
    %__MODULE__{
      x: fn d -> elem(d, 0) end,
      y: fn d -> elem(d, 1) end
    }
  end

  @doc """
  Sets the x accessor function or field name.

  ## Examples

      Line.x(line, fn d -> d.timestamp end)
      Line.x(line, :x)  # equivalent to fn d -> Map.get(d, :x) end

  """
  @spec x(t(), accessor()) :: t()
  def x(%__MODULE__{} = line, accessor) when is_function(accessor, 1) do
    %{line | x: accessor}
  end

  def x(%__MODULE__{} = line, field) when is_atom(field) do
    %{line | x: fn d -> Map.get(d, field) end}
  end

  @doc """
  Sets the y accessor function or field name.
  """
  @spec y(t(), accessor()) :: t()
  def y(%__MODULE__{} = line, accessor) when is_function(accessor, 1) do
    %{line | y: accessor}
  end

  def y(%__MODULE__{} = line, field) when is_atom(field) do
    %{line | y: fn d -> Map.get(d, field) end}
  end

  @doc """
  Sets the defined predicate function.

  Points where this returns false will create gaps in the line.
  """
  @spec defined(t(), (any() -> boolean())) :: t()
  def defined(%__MODULE__{} = line, predicate) when is_function(predicate, 1) do
    %{line | defined: predicate}
  end

  @doc """
  Sets the curve interpolation type.

  Available curves:
  - `:linear` - straight lines (default)
  - `:step` - step at midpoint
  - `:step_before` - step at start
  - `:step_after` - step at end
  - `:basis` - B-spline
  - `:cardinal` - cardinal spline (use `curve_opts` for tension)
  - `:catmull_rom` - Catmull-Rom spline (use `curve_opts` for alpha)
  - `:monotone_x` - monotone cubic (preserves monotonicity in x)
  - `:monotone_y` - monotone cubic (preserves monotonicity in y)
  - `:natural` - natural cubic spline

  """
  @spec curve(t(), Curve.curve_type(), keyword()) :: t()
  def curve(%__MODULE__{} = line, curve_type, opts \\ []) do
    %{line | curve: curve_type, curve_opts: opts}
  end

  @doc """
  Generates the SVG path data string from the data.
  """
  @spec generate(t(), [any()]) :: String.t()
  def generate(%__MODULE__{} = line, data) do
    line
    |> generate_path(data)
    |> Path.to_string()
  end

  @doc """
  Generates a Path struct from the data.
  """
  @spec generate_path(t(), [any()]) :: Path.t()
  def generate_path(%__MODULE__{x: x_fn, y: y_fn, defined: defined_fn, curve: curve_type, curve_opts: opts}, data) do
    # Filter and transform data to points
    points =
      data
      |> maybe_filter_defined(defined_fn)
      |> Enum.map(fn d -> {x_fn.(d), y_fn.(d)} end)

    if Enum.empty?(points) do
      Path.new()
    else
      Curve.generate(curve_type, points, opts)
    end
  end

  @doc """
  Generates path data and creates an SVG path element.
  """
  @spec to_element(t(), [any()], keyword()) :: Visualize.SVG.Element.t()
  def to_element(%__MODULE__{} = line, data, attrs \\ []) do
    path_data = generate(line, data)

    default_attrs = %{
      d: path_data,
      fill: "none",
      stroke: "currentColor",
      stroke_width: 1.5
    }

    merged_attrs = Map.merge(default_attrs, Map.new(attrs))
    Visualize.SVG.Element.path(merged_attrs)
  end

  defp maybe_filter_defined(data, nil), do: data

  defp maybe_filter_defined(data, defined_fn) do
    Enum.filter(data, defined_fn)
  end
end
