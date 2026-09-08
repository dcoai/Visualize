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

  alias Visualize.IR.Path
  alias Visualize.Shape.{Curve, Line}

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

  @doc "Sets the defined predicate: a falsy result breaks the area into separate rings"
  @spec defined(t(), (any() -> boolean())) :: t()
  def defined(%__MODULE__{} = area, predicate) when is_function(predicate, 1) do
    %{area | defined: predicate}
  end

  @doc "Sets the curve type"
  @spec curve(t(), Curve.curve_type(), keyword()) :: t()
  def curve(%__MODULE__{} = area, curve_type, opts \\ []) do
    %{area | curve: curve_type, curve_opts: opts}
  end

  @doc """
  Generates the SVG path data string.

  Note: For backend-agnostic usage, prefer `generate_path/2`
  and render with your chosen backend.
  """
  @spec generate(t(), Visualize.Data.Table.source()) :: String.t()
  def generate(%__MODULE__{} = area, data) do
    area
    |> generate_path(data)
    |> Visualize.Backend.SVG.path_data()
  end

  @doc """
  Generates a Path struct.

  Each run of consecutive defined data (see `defined/2`) becomes one closed ring: the top
  edge forward, a line to the bottom edge, the bottom edge reversed, and `Z`. A run of
  fewer than two points draws nothing.
  """
  @spec generate_path(t(), Visualize.Data.Table.source()) :: Path.t()
  def generate_path(%__MODULE__{} = area, data) do
    x0_fn = area.x0 || area.x
    x1_fn = area.x1 || area.x
    y0_fn = area.y0 || area.y
    y1_fn = area.y1 || area.y

    commands =
      data
      |> Visualize.Data.Table.rows()
      |> Line.defined_runs(area.defined)
      |> Enum.flat_map(fn run ->
        top_points =
          Enum.map(run, fn d -> {apply_accessor(x1_fn, d), apply_accessor(y1_fn, d)} end)

        bottom_points =
          run
          |> Enum.map(fn d -> {apply_accessor(x0_fn, d), apply_accessor(y0_fn, d)} end)
          |> Enum.reverse()

        top_path = Curve.generate(area.curve, top_points, area.curve_opts)
        bottom_path = Curve.generate(area.curve, bottom_points, area.curve_opts)
        ring_commands(top_path, bottom_path)
      end)

    %Path{commands: commands}
  end

  defp normalize_accessor(accessor) when is_function(accessor, 1), do: accessor

  defp normalize_accessor(accessor) when is_atom(accessor) or is_binary(accessor),
    do: Visualize.Data.Table.accessor(accessor)

  defp normalize_accessor(accessor) when is_number(accessor), do: fn _d -> accessor end

  defp apply_accessor(accessor, data) when is_function(accessor, 1), do: accessor.(data)
  defp apply_accessor(accessor, _data) when is_number(accessor), do: accessor

  # One closed ring: an empty run (fewer than two points) contributes no commands at all.
  defp ring_commands(%Path{commands: []}, _bottom), do: []

  defp ring_commands(%Path{commands: top_cmds}, %Path{commands: bottom_cmds}) do
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

    top_cmds ++ [{:L, start_x, start_y}] ++ bottom_cmds_without_move ++ [:Z]
  end
end
