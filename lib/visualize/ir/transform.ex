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
  Creates a transform with a single uniform scale operation.
  """
  @spec scale(number()) :: t()
  def scale(s) when is_number(s), do: new() |> scale(s, s)

  @doc """
  With two numbers, creates a transform with a single scale operation.
  With a transform and one number, adds a uniform scale operation to it.
  """
  @spec scale(number(), number()) :: t()
  @spec scale(t(), number()) :: t()
  def scale(sx, sy) when is_number(sx) and is_number(sy), do: new() |> scale(sx, sy)
  def scale(%__MODULE__{} = t, s) when is_number(s), do: scale(t, s, s)

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
  # Matrix form
  # ============================================================

  @typedoc """
  An affine matrix `{a, b, c, d, e, f}` for `[a c e; b d f; 0 0 1]`: a point maps as
  `x' = a·x + c·y + e`, `y' = b·x + d·y + f`.
  """
  @type matrix :: {number(), number(), number(), number(), number(), number()}

  @doc """
  Folds the operations into one affine matrix `{a, b, c, d, e, f}`.

  Composition follows SVG: `M = Op₁ · Op₂ · … · Opₙ`, so the last operation applies to a
  point first, exactly as the `transform` attribute string would. `rotate(a, cx, cy)` is
  `translate(cx, cy) rotate(a) translate(-cx, -cy)`; angles are degrees.

  ## Examples

      iex> alias Visualize.IR.Transform
      iex> Transform.translate(10, 20) |> Transform.to_matrix()
      {1.0, 0.0, 0.0, 1.0, 10.0, 20.0}

  """
  @spec to_matrix(t()) :: matrix()
  def to_matrix(%__MODULE__{operations: operations}) do
    Enum.reduce(operations, {1.0, 0.0, 0.0, 1.0, 0.0, 0.0}, fn op, acc ->
      multiply(acc, operation_matrix(op))
    end)
  end

  @doc """
  The product `m1 · m2` of two affine matrices, so that applying the result to a point is
  applying `m2` first and then `m1`.
  """
  @spec multiply(matrix(), matrix()) :: matrix()
  def multiply({a1, b1, c1, d1, e1, f1}, {a2, b2, c2, d2, e2, f2}) do
    {
      a1 * a2 + c1 * b2,
      b1 * a2 + d1 * b2,
      a1 * c2 + c1 * d2,
      b1 * c2 + d1 * d2,
      a1 * e2 + c1 * f2 + e1,
      b1 * e2 + d1 * f2 + f1
    }
  end

  @doc """
  Applies an affine matrix to a point.
  """
  @spec apply_matrix(matrix(), {number(), number()}) :: {number(), number()}
  def apply_matrix({a, b, c, d, e, f}, {x, y}), do: {a * x + c * y + e, b * x + d * y + f}

  defp operation_matrix({:translate, tx, ty}), do: {1.0, 0.0, 0.0, 1.0, tx * 1.0, ty * 1.0}
  defp operation_matrix({:scale, sx, sy}), do: {sx * 1.0, 0.0, 0.0, sy * 1.0, 0.0, 0.0}

  defp operation_matrix({:rotate, angle}) do
    rad = angle * :math.pi() / 180
    cos = :math.cos(rad)
    sin = :math.sin(rad)
    {cos, sin, -sin, cos, 0.0, 0.0}
  end

  defp operation_matrix({:rotate, angle, cx, cy}) do
    operation_matrix({:translate, cx, cy})
    |> multiply(operation_matrix({:rotate, angle}))
    |> multiply(operation_matrix({:translate, -cx, -cy}))
  end

  defp operation_matrix({:skew_x, angle}),
    do: {1.0, 0.0, :math.tan(angle * :math.pi() / 180), 1.0, 0.0, 0.0}

  defp operation_matrix({:skew_y, angle}),
    do: {1.0, :math.tan(angle * :math.pi() / 180), 0.0, 1.0, 0.0, 0.0}

  defp operation_matrix({:matrix, a, b, c, d, e, f}),
    do: {a * 1.0, b * 1.0, c * 1.0, d * 1.0, e * 1.0, f * 1.0}

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

  # The one number formatter of every serialiser (spec/09 §1.3, D-12, D-32).
  defp format_num(n), do: Visualize.IR.Path.format_number(n)
end
