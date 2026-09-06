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

  alias Visualize.IR.Path
  alias Visualize.Shape.Curve

  defstruct x: nil,
            y: nil,
            defined: nil,
            curve: :linear,
            curve_opts: []

  @type accessor :: (any() -> number()) | atom() | number()
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
  Sets the x accessor: a 1-arity function, a field name, or a constant.

  ## Examples

      Line.x(line, fn d -> d.timestamp end)
      Line.x(line, :x)  # equivalent to fn d -> Map.get(d, :x) end
      Line.x(line, 0)   # every point at x = 0

  """
  @spec x(t(), accessor()) :: t()
  def x(%__MODULE__{} = line, accessor) do
    %{line | x: normalize_accessor(accessor)}
  end

  @doc """
  Sets the y accessor: a 1-arity function, a field name, or a constant.
  """
  @spec y(t(), accessor()) :: t()
  def y(%__MODULE__{} = line, accessor) do
    %{line | y: normalize_accessor(accessor)}
  end

  @doc """
  Sets the defined predicate function.

  A datum for which it returns a falsy value breaks the line: the points before it and
  the points after it become separate subpaths, so the gap is visible.
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

  Note: For backend-agnostic usage, prefer `generate_path/2`
  and render with your chosen backend.
  """
  @spec generate(t(), [any()]) :: String.t()
  def generate(%__MODULE__{} = line, data) do
    line
    |> generate_path(data)
    |> Visualize.Backend.SVG.path_data()
  end

  @doc """
  Generates a Path struct from the data.

  Each run of consecutive defined data (see `defined/2`) becomes one subpath, generated
  through the curve; a run of fewer than two points draws nothing.
  """
  @spec generate_path(t(), [any()]) :: Path.t()
  def generate_path(
        %__MODULE__{x: x_fn, y: y_fn, defined: defined_fn, curve: curve_type, curve_opts: opts},
        data
      ) do
    commands =
      data
      |> defined_runs(defined_fn)
      |> Enum.flat_map(fn run ->
        points = Enum.map(run, fn d -> {x_fn.(d), y_fn.(d)} end)
        Curve.generate(curve_type, points, opts).commands
      end)

    %Path{commands: commands}
  end

  @doc false
  @spec defined_runs([any()], (any() -> boolean()) | nil) :: [[any()]]
  def defined_runs(data, nil), do: [data]

  def defined_runs(data, defined_fn) do
    data
    |> Enum.map(&{!!defined_fn.(&1), &1})
    |> Enum.chunk_by(&elem(&1, 0))
    |> Enum.filter(&elem(hd(&1), 0))
    |> Enum.map(fn run -> Enum.map(run, &elem(&1, 1)) end)
  end

  @doc false
  @spec normalize_accessor(accessor()) :: (any() -> number())
  def normalize_accessor(accessor) when is_function(accessor, 1), do: accessor
  def normalize_accessor(field) when is_atom(field), do: fn d -> Map.get(d, field) end
  def normalize_accessor(constant) when is_number(constant), do: fn _d -> constant end
end
