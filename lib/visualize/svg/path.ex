defmodule Visualize.SVG.Path do
  @moduledoc """
  SVG path command builder.

  Provides a fluent API for constructing SVG path `d` attribute strings.
  All commands follow SVG path specification.

  ## Examples

      iex> alias Visualize.SVG.Path
      iex> Path.new()
      ...> |> Path.move_to(10, 20)
      ...> |> Path.line_to(100, 200)
      ...> |> Path.close()
      ...> |> Path.to_string()
      "M10,20L100,200Z"

  """

  defstruct commands: []

  @type t :: %__MODULE__{commands: [command()]}
  @type command ::
          {:M, number(), number()}
          | {:m, number(), number()}
          | {:L, number(), number()}
          | {:l, number(), number()}
          | {:H, number()}
          | {:h, number()}
          | {:V, number()}
          | {:v, number()}
          | {:C, number(), number(), number(), number(), number(), number()}
          | {:c, number(), number(), number(), number(), number(), number()}
          | {:S, number(), number(), number(), number()}
          | {:s, number(), number(), number(), number()}
          | {:Q, number(), number(), number(), number()}
          | {:q, number(), number(), number(), number()}
          | {:T, number(), number()}
          | {:t, number(), number()}
          | {:A, number(), number(), number(), integer(), integer(), number(), number()}
          | {:a, number(), number(), number(), integer(), integer(), number(), number()}
          | :Z

  @doc """
  Creates a new empty path.
  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Move to absolute position.
  """
  @spec move_to(t(), number(), number()) :: t()
  def move_to(%__MODULE__{} = path, x, y) do
    append_command(path, {:M, x, y})
  end

  @doc """
  Move to relative position.
  """
  @spec move_to_rel(t(), number(), number()) :: t()
  def move_to_rel(%__MODULE__{} = path, dx, dy) do
    append_command(path, {:m, dx, dy})
  end

  @doc """
  Line to absolute position.
  """
  @spec line_to(t(), number(), number()) :: t()
  def line_to(%__MODULE__{} = path, x, y) do
    append_command(path, {:L, x, y})
  end

  @doc """
  Line to relative position.
  """
  @spec line_to_rel(t(), number(), number()) :: t()
  def line_to_rel(%__MODULE__{} = path, dx, dy) do
    append_command(path, {:l, dx, dy})
  end

  @doc """
  Horizontal line to absolute x.
  """
  @spec horizontal_to(t(), number()) :: t()
  def horizontal_to(%__MODULE__{} = path, x) do
    append_command(path, {:H, x})
  end

  @doc """
  Horizontal line to relative x.
  """
  @spec horizontal_to_rel(t(), number()) :: t()
  def horizontal_to_rel(%__MODULE__{} = path, dx) do
    append_command(path, {:h, dx})
  end

  @doc """
  Vertical line to absolute y.
  """
  @spec vertical_to(t(), number()) :: t()
  def vertical_to(%__MODULE__{} = path, y) do
    append_command(path, {:V, y})
  end

  @doc """
  Vertical line to relative y.
  """
  @spec vertical_to_rel(t(), number()) :: t()
  def vertical_to_rel(%__MODULE__{} = path, dy) do
    append_command(path, {:v, dy})
  end

  @doc """
  Cubic Bezier curve to absolute position.
  """
  @spec curve_to(t(), number(), number(), number(), number(), number(), number()) :: t()
  def curve_to(%__MODULE__{} = path, x1, y1, x2, y2, x, y) do
    append_command(path, {:C, x1, y1, x2, y2, x, y})
  end

  @doc """
  Cubic Bezier curve to relative position.
  """
  @spec curve_to_rel(t(), number(), number(), number(), number(), number(), number()) :: t()
  def curve_to_rel(%__MODULE__{} = path, dx1, dy1, dx2, dy2, dx, dy) do
    append_command(path, {:c, dx1, dy1, dx2, dy2, dx, dy})
  end

  @doc """
  Smooth cubic Bezier curve to absolute position.
  """
  @spec smooth_curve_to(t(), number(), number(), number(), number()) :: t()
  def smooth_curve_to(%__MODULE__{} = path, x2, y2, x, y) do
    append_command(path, {:S, x2, y2, x, y})
  end

  @doc """
  Smooth cubic Bezier curve to relative position.
  """
  @spec smooth_curve_to_rel(t(), number(), number(), number(), number()) :: t()
  def smooth_curve_to_rel(%__MODULE__{} = path, dx2, dy2, dx, dy) do
    append_command(path, {:s, dx2, dy2, dx, dy})
  end

  @doc """
  Quadratic Bezier curve to absolute position.
  """
  @spec quad_to(t(), number(), number(), number(), number()) :: t()
  def quad_to(%__MODULE__{} = path, x1, y1, x, y) do
    append_command(path, {:Q, x1, y1, x, y})
  end

  @doc """
  Quadratic Bezier curve to relative position.
  """
  @spec quad_to_rel(t(), number(), number(), number(), number()) :: t()
  def quad_to_rel(%__MODULE__{} = path, dx1, dy1, dx, dy) do
    append_command(path, {:q, dx1, dy1, dx, dy})
  end

  @doc """
  Smooth quadratic Bezier curve to absolute position.
  """
  @spec smooth_quad_to(t(), number(), number()) :: t()
  def smooth_quad_to(%__MODULE__{} = path, x, y) do
    append_command(path, {:T, x, y})
  end

  @doc """
  Smooth quadratic Bezier curve to relative position.
  """
  @spec smooth_quad_to_rel(t(), number(), number()) :: t()
  def smooth_quad_to_rel(%__MODULE__{} = path, dx, dy) do
    append_command(path, {:t, dx, dy})
  end

  @doc """
  Arc to absolute position.

  - `rx`, `ry`: radii of the ellipse
  - `x_rotation`: rotation of the ellipse in degrees
  - `large_arc`: 0 or 1, whether to use the larger arc
  - `sweep`: 0 or 1, direction of the arc
  - `x`, `y`: end point
  """
  @spec arc_to(t(), number(), number(), number(), integer(), integer(), number(), number()) :: t()
  def arc_to(%__MODULE__{} = path, rx, ry, x_rotation, large_arc, sweep, x, y) do
    append_command(path, {:A, rx, ry, x_rotation, large_arc, sweep, x, y})
  end

  @doc """
  Arc to relative position.
  """
  @spec arc_to_rel(t(), number(), number(), number(), integer(), integer(), number(), number()) ::
          t()
  def arc_to_rel(%__MODULE__{} = path, rx, ry, x_rotation, large_arc, sweep, dx, dy) do
    append_command(path, {:a, rx, ry, x_rotation, large_arc, sweep, dx, dy})
  end

  @doc """
  Close the path.
  """
  @spec close(t()) :: t()
  def close(%__MODULE__{} = path) do
    append_command(path, :Z)
  end

  @doc """
  Converts the path to an SVG path string.
  """
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{commands: commands}) do
    commands
    |> Enum.map(&command_to_string/1)
    |> Enum.join("")
  end

  defp append_command(%__MODULE__{commands: commands} = path, command) do
    %{path | commands: commands ++ [command]}
  end

  defp command_to_string({:M, x, y}), do: "M#{format_num(x)},#{format_num(y)}"
  defp command_to_string({:m, dx, dy}), do: "m#{format_num(dx)},#{format_num(dy)}"
  defp command_to_string({:L, x, y}), do: "L#{format_num(x)},#{format_num(y)}"
  defp command_to_string({:l, dx, dy}), do: "l#{format_num(dx)},#{format_num(dy)}"
  defp command_to_string({:H, x}), do: "H#{format_num(x)}"
  defp command_to_string({:h, dx}), do: "h#{format_num(dx)}"
  defp command_to_string({:V, y}), do: "V#{format_num(y)}"
  defp command_to_string({:v, dy}), do: "v#{format_num(dy)}"

  defp command_to_string({:C, x1, y1, x2, y2, x, y}) do
    "C#{format_num(x1)},#{format_num(y1)},#{format_num(x2)},#{format_num(y2)},#{format_num(x)},#{format_num(y)}"
  end

  defp command_to_string({:c, dx1, dy1, dx2, dy2, dx, dy}) do
    "c#{format_num(dx1)},#{format_num(dy1)},#{format_num(dx2)},#{format_num(dy2)},#{format_num(dx)},#{format_num(dy)}"
  end

  defp command_to_string({:S, x2, y2, x, y}) do
    "S#{format_num(x2)},#{format_num(y2)},#{format_num(x)},#{format_num(y)}"
  end

  defp command_to_string({:s, dx2, dy2, dx, dy}) do
    "s#{format_num(dx2)},#{format_num(dy2)},#{format_num(dx)},#{format_num(dy)}"
  end

  defp command_to_string({:Q, x1, y1, x, y}) do
    "Q#{format_num(x1)},#{format_num(y1)},#{format_num(x)},#{format_num(y)}"
  end

  defp command_to_string({:q, dx1, dy1, dx, dy}) do
    "q#{format_num(dx1)},#{format_num(dy1)},#{format_num(dx)},#{format_num(dy)}"
  end

  defp command_to_string({:T, x, y}), do: "T#{format_num(x)},#{format_num(y)}"
  defp command_to_string({:t, dx, dy}), do: "t#{format_num(dx)},#{format_num(dy)}"

  defp command_to_string({:A, rx, ry, rot, large, sweep, x, y}) do
    "A#{format_num(rx)},#{format_num(ry)},#{format_num(rot)},#{large},#{sweep},#{format_num(x)},#{format_num(y)}"
  end

  defp command_to_string({:a, rx, ry, rot, large, sweep, dx, dy}) do
    "a#{format_num(rx)},#{format_num(ry)},#{format_num(rot)},#{large},#{sweep},#{format_num(dx)},#{format_num(dy)}"
  end

  defp command_to_string(:Z), do: "Z"

  defp format_num(n) when is_integer(n), do: Integer.to_string(n)

  defp format_num(n) when is_float(n) do
    n
    |> Float.round(4)
    |> Float.to_string()
    |> String.trim_trailing("0")
    |> String.trim_trailing(".")
  end
end

defimpl String.Chars, for: Visualize.SVG.Path do
  def to_string(path), do: Visualize.SVG.Path.to_string(path)
end
