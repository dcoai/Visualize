defmodule Visualize.IR.Transform do
  @moduledoc """
  Backend-agnostic transformation representation.

  Stores a sequence of transformation operations that can be
  applied to elements when rendering.

  ## Examples

      iex> alias Visualize.IR.Transform
      iex> Transform.new()
      ...> |> Transform.translate(100, 50)
      ...> |> Transform.rotate(45)
      ...> |> Transform.scale(2, 2)
      %Visualize.IR.Transform{operations: [{:translate, 100, 50}, {:rotate, 45}, {:scale, 2, 2}]}

  """

  defstruct operations: []

  @type operation ::
          {:translate, number(), number()}
          | {:rotate, number()}
          | {:rotate, number(), number(), number()}
          | {:scale, number(), number()}
          | {:skew_x, number()}
          | {:skew_y, number()}
          | {:matrix, number(), number(), number(), number(), number(), number()}

  @type t :: %__MODULE__{operations: [operation()]}

  @doc """
  Creates a new empty transform.
  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Creates a transform with a single translate operation.
  """
  @spec translate(number(), number()) :: t()
  def translate(x, y) do
    new() |> translate(x, y)
  end

  @doc """
  Adds a translate operation.
  """
  @spec translate(t(), number(), number()) :: t()
  def translate(%__MODULE__{operations: ops} = t, x, y) do
    %{t | operations: ops ++ [{:translate, x, y}]}
  end

  @doc """
  Creates a transform with a single rotate operation.
  Angle is in degrees.
  """
  @spec rotate(number()) :: t()
  def rotate(angle) do
    new() |> rotate(angle)
  end

  @doc """
  Adds a rotate operation.
  Angle is in degrees.
  """
  @spec rotate(t(), number()) :: t()
  def rotate(%__MODULE__{operations: ops} = t, angle) do
    %{t | operations: ops ++ [{:rotate, angle}]}
  end

  @doc """
  Adds a rotate operation around a specific center point.
  Angle is in degrees.
  """
  @spec rotate(t(), number(), number(), number()) :: t()
  def rotate(%__MODULE__{operations: ops} = t, angle, cx, cy) do
    %{t | operations: ops ++ [{:rotate, angle, cx, cy}]}
  end

  @doc """
  Creates a transform with a single scale operation.
  """
  @spec scale(number()) :: t()
  def scale(s), do: new() |> scale(s, s)

  @doc """
  Creates a transform with a single scale operation.
  """
  @spec scale(number(), number()) :: t()
  def scale(sx, sy), do: new() |> scale(sx, sy)

  @doc """
  Adds a scale operation.
  If only one argument is provided, scales uniformly.
  """
  @spec scale(t(), number()) :: t()
  def scale(%__MODULE__{} = t, s), do: scale(t, s, s)

  @doc """
  Adds a scale operation with separate x and y factors.
  """
  @spec scale(t(), number(), number()) :: t()
  def scale(%__MODULE__{operations: ops} = t, sx, sy) do
    %{t | operations: ops ++ [{:scale, sx, sy}]}
  end

  @doc """
  Adds a skewX operation.
  Angle is in degrees.
  """
  @spec skew_x(t(), number()) :: t()
  def skew_x(%__MODULE__{operations: ops} = t, angle) do
    %{t | operations: ops ++ [{:skew_x, angle}]}
  end

  @doc """
  Adds a skewY operation.
  Angle is in degrees.
  """
  @spec skew_y(t(), number()) :: t()
  def skew_y(%__MODULE__{operations: ops} = t, angle) do
    %{t | operations: ops ++ [{:skew_y, angle}]}
  end

  @doc """
  Adds a matrix transformation.
  The matrix is specified as (a, b, c, d, e, f) which corresponds to:

      | a c e |
      | b d f |
      | 0 0 1 |
  """
  @spec matrix(t(), number(), number(), number(), number(), number(), number()) :: t()
  def matrix(%__MODULE__{operations: ops} = t, a, b, c, d, e, f) do
    %{t | operations: ops ++ [{:matrix, a, b, c, d, e, f}]}
  end

  @doc """
  Returns whether the transform is empty (has no operations).
  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{operations: []}), do: true
  def empty?(%__MODULE__{}), do: false

  @doc """
  Combines two transforms by appending the operations.
  """
  @spec concat(t(), t()) :: t()
  def concat(%__MODULE__{operations: ops1}, %__MODULE__{operations: ops2}) do
    %__MODULE__{operations: ops1 ++ ops2}
  end

  # ============================================================
  # Serialization
  # ============================================================

  @doc """
  Converts the transform to an SVG transform attribute string.

  ## Examples

      iex> alias Visualize.IR.Transform
      iex> Transform.translate(100, 50) |> Transform.to_string()
      "translate(100,50)"

  """
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{operations: operations}) do
    operations
    |> Enum.map(&operation_to_string/1)
    |> Enum.join(" ")
  end

  defp operation_to_string({:translate, x, y}) do
    "translate(#{format_num(x)},#{format_num(y)})"
  end

  defp operation_to_string({:rotate, angle}) do
    "rotate(#{format_num(angle)})"
  end

  defp operation_to_string({:rotate, angle, cx, cy}) do
    "rotate(#{format_num(angle)},#{format_num(cx)},#{format_num(cy)})"
  end

  defp operation_to_string({:scale, sx, sy}) when sx == sy do
    "scale(#{format_num(sx)})"
  end

  defp operation_to_string({:scale, sx, sy}) do
    "scale(#{format_num(sx)},#{format_num(sy)})"
  end

  defp operation_to_string({:skew_x, angle}) do
    "skewX(#{format_num(angle)})"
  end

  defp operation_to_string({:skew_y, angle}) do
    "skewY(#{format_num(angle)})"
  end

  defp operation_to_string({:matrix, a, b, c, d, e, f}) do
    "matrix(#{format_num(a)},#{format_num(b)},#{format_num(c)},#{format_num(d)},#{format_num(e)},#{format_num(f)})"
  end

  defp format_num(n) when is_integer(n), do: Integer.to_string(n)
  defp format_num(n) when is_float(n) do
    :erlang.float_to_binary(n, decimals: 4)
    |> String.trim_trailing("0")
    |> String.trim_trailing(".")
  end
end
