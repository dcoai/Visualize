defmodule Visualize.Shape.Area do
  @moduledoc """
  Area generator for creating filled areas between two lines.

  Useful for area charts, stacked areas, and range visualizations.

  ## Examples

      data = [
        %{date: ~D[2024-01-01], value: 10},
        %{date: ~D[2024-01-02], value: 25},
        %{date: ~D[2024-01-03], value: 15}
      ]

      area = Visualize.Shape.Area.new()
        |> Visualize.Shape.Area.x(fn d -> scale_x.(d.date) end)
        |> Visualize.Shape.Area.y0(fn _d -> height end)  # baseline
        |> Visualize.Shape.Area.y1(fn d -> scale_y.(d.value) end)
        |> Visualize.Shape.Area.curve(:monotone_x)

      path_data = Visualize.Shape.Area.generate(area, data)

  """

  alias Visualize.Shape.Curve
  alias Visualize.SVG.Path

  defstruct x: nil,
            x0: nil,
            x1: nil,
            y: nil,
            y0: nil,
            y1: nil,
            defined: nil,
            curve: :linear,
            curve_opts: []

  @type accessor :: (any() -> number()) | atom() | number()
  @type t :: %__MODULE__{
          x: accessor() | nil,
          x0: accessor() | nil,
          x1: accessor() | nil,
          y: accessor() | nil,
          y0: accessor() | nil,
          y1: accessor() | nil,
          defined: (any() -> boolean()) | nil,
          curve: Curve.curve_type(),
          curve_opts: keyword()
        }

  @doc "Creates a new area generator"
  @spec new() :: t()
  def new do
    %__MODULE__{
      x: fn d -> elem(d, 0) end,
      y0: 0,
      y1: fn d -> elem(d, 1) end
    }
  end

  @doc "Sets the x accessor (used for both x0 and x1)"
  @spec x(t(), accessor()) :: t()
  def x(%__MODULE__{} = area, accessor) do
    accessor = normalize_accessor(accessor)
    %{area | x: accessor, x0: accessor, x1: accessor}
  end

  @doc "Sets the x0 accessor (left edge)"
  @spec x0(t(), accessor()) :: t()
  def x0(%__MODULE__{} = area, accessor) do
    %{area | x0: normalize_accessor(accessor)}
  end

  @doc "Sets the x1 accessor (right edge)"
  @spec x1(t(), accessor()) :: t()
  def x1(%__MODULE__{} = area, accessor) do
    %{area | x1: normalize_accessor(accessor)}
  end

  @doc "Sets the y accessor (used for both y0 and y1)"
  @spec y(t(), accessor()) :: t()
  def y(%__MODULE__{} = area, accessor) do
    accessor = normalize_accessor(accessor)
    %{area | y: accessor, y0: accessor, y1: accessor}
  end

  @doc "Sets the y0 accessor (bottom edge / baseline)"
  @spec y0(t(), accessor()) :: t()
  def y0(%__MODULE__{} = area, accessor) do
    %{area | y0: normalize_accessor(accessor)}
  end

  @doc "Sets the y1 accessor (top edge)"
  @spec y1(t(), accessor()) :: t()
  def y1(%__MODULE__{} = area, accessor) do
    %{area | y1: normalize_accessor(accessor)}
  end

  @doc "Sets the defined predicate function"
  @spec defined(t(), (any() -> boolean())) :: t()
  def defined(%__MODULE__{} = area, predicate) when is_function(predicate, 1) do
    %{area | defined: predicate}
  end

  @doc "Sets the curve type"
  @spec curve(t(), Curve.curve_type(), keyword()) :: t()
  def curve(%__MODULE__{} = area, curve_type, opts \\ []) do
    %{area | curve: curve_type, curve_opts: opts}
  end

  @doc "Generates the SVG path data string"
  @spec generate(t(), [any()]) :: String.t()
  def generate(%__MODULE__{} = area, data) do
    area
    |> generate_path(data)
    |> Path.to_string()
  end

  @doc "Generates a Path struct"
  @spec generate_path(t(), [any()]) :: Path.t()
  def generate_path(%__MODULE__{} = area, data) do
    data = maybe_filter_defined(data, area.defined)

    if Enum.empty?(data) do
      Path.new()
    else
      # Get accessors
      x0_fn = area.x0 || area.x
      x1_fn = area.x1 || area.x
      y0_fn = area.y0 || area.y
      y1_fn = area.y1 || area.y

      # Top line points (forward)
      top_points =
        Enum.map(data, fn d ->
          x = if x1_fn, do: apply_accessor(x1_fn, d), else: apply_accessor(x0_fn, d)
          y = apply_accessor(y1_fn, d)
          {x, y}
        end)

      # Bottom line points (reverse for closing the path)
      bottom_points =
        data
        |> Enum.map(fn d ->
          x = apply_accessor(x0_fn, d)
          y = apply_accessor(y0_fn, d)
          {x, y}
        end)
        |> Enum.reverse()

      # Generate top curve
      top_path = Curve.generate(area.curve, top_points, area.curve_opts)

      # Generate bottom curve and append to path
      bottom_path = Curve.generate(area.curve, bottom_points, area.curve_opts)

      # Combine: top path + line to bottom start + bottom path + close
      combine_paths(top_path, bottom_path)
    end
  end

  @doc "Generates path data and creates an SVG path element"
  @spec to_element(t(), [any()], keyword()) :: Visualize.SVG.Element.t()
  def to_element(%__MODULE__{} = area, data, attrs \\ []) do
    path_data = generate(area, data)

    default_attrs = %{
      d: path_data,
      fill: "currentColor",
      stroke: "none"
    }

    merged_attrs = Map.merge(default_attrs, Map.new(attrs))
    Visualize.SVG.Element.path(merged_attrs)
  end

  defp normalize_accessor(accessor) when is_function(accessor, 1), do: accessor
  defp normalize_accessor(accessor) when is_atom(accessor), do: fn d -> Map.get(d, accessor) end
  defp normalize_accessor(accessor) when is_number(accessor), do: fn _d -> accessor end

  defp apply_accessor(accessor, data) when is_function(accessor, 1), do: accessor.(data)
  defp apply_accessor(accessor, _data) when is_number(accessor), do: accessor

  defp maybe_filter_defined(data, nil), do: data
  defp maybe_filter_defined(data, defined_fn), do: Enum.filter(data, defined_fn)

  defp combine_paths(%Path{commands: top_cmds}, %Path{commands: bottom_cmds}) do
    # Get the first point of bottom path for the connecting line
    {start_x, start_y} =
      case bottom_cmds do
        [{:M, x, y} | _] -> {x, y}
        _ -> {0, 0}
      end

    # Remove the move command from bottom path
    bottom_cmds_without_move =
      case bottom_cmds do
        [{:M, _, _} | rest] -> rest
        cmds -> cmds
      end

    combined_commands =
      top_cmds ++
        [{:L, start_x, start_y}] ++
        bottom_cmds_without_move ++
        [:Z]

    %Path{commands: combined_commands}
  end
end
