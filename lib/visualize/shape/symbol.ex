defmodule Visualize.Shape.Symbol do
  @moduledoc """
  Symbol generator for categorical point marks.

  Provides various symbol shapes commonly used in scatter plots
  and legends to distinguish categories.

  ## Examples

      symbol = Visualize.Shape.Symbol.new()
        |> Visualize.Shape.Symbol.type(:circle)
        |> Visualize.Shape.Symbol.size(64)

      path_data = Visualize.Shape.Symbol.generate(symbol)

  """

  alias Visualize.SVG.{Path, Element}

  @sqrt3 :math.sqrt(3)
  @tau 2 * :math.pi()

  defstruct type: :circle,
            size: 64

  @type symbol_type ::
          :circle
          | :cross
          | :diamond
          | :square
          | :star
          | :triangle
          | :wye

  @type t :: %__MODULE__{
          type: symbol_type() | (any() -> symbol_type()),
          size: number() | (any() -> number())
        }

  @doc "Creates a new symbol generator"
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Sets the symbol type"
  @spec type(t(), symbol_type() | (any() -> symbol_type())) :: t()
  def type(%__MODULE__{} = symbol, type) do
    %{symbol | type: type}
  end

  @doc """
  Sets the symbol size in square pixels.

  For a circle, this is the area. For other symbols, the bounding box
  area is approximately this size.
  """
  @spec size(t(), number() | (any() -> number())) :: t()
  def size(%__MODULE__{} = symbol, size) do
    %{symbol | size: size}
  end

  @doc "Generates the SVG path data string"
  @spec generate(t(), any()) :: String.t()
  def generate(%__MODULE__{} = symbol, data \\ nil) do
    symbol
    |> generate_path(data)
    |> Path.to_string()
  end

  @doc "Generates a Path struct"
  @spec generate_path(t(), any()) :: Path.t()
  def generate_path(%__MODULE__{type: type, size: size}, data) do
    symbol_type = apply_value(type, data)
    symbol_size = apply_value(size, data)

    case symbol_type do
      :circle -> circle_path(symbol_size)
      :cross -> cross_path(symbol_size)
      :diamond -> diamond_path(symbol_size)
      :square -> square_path(symbol_size)
      :star -> star_path(symbol_size)
      :triangle -> triangle_path(symbol_size)
      :wye -> wye_path(symbol_size)
    end
  end

  @doc "Returns all available symbol types"
  @spec types() :: [symbol_type()]
  def types, do: [:circle, :cross, :diamond, :square, :star, :triangle, :wye]

  @doc """
  Generates a symbol as native SVG element(s) instead of a path.

  For `:circle` and `:square`, this produces more efficient SVG using
  native `<circle>` and `<rect>` elements. For `:cross`, it uses two
  overlapping `<rect>` elements. Other symbols fall back to `<path>`.

  ## Examples

      symbol = Symbol.new() |> Symbol.type(:circle) |> Symbol.size(64)
      element = Symbol.to_element(symbol, fill: "red")
      # Returns an Element struct for <circle r="4.51" cx="0" cy="0" fill="red"/>

      # With transformation for positioning
      element = Symbol.to_element(symbol, fill: "blue", transform: "translate(100, 50)")

  """
  @spec to_element(t(), keyword()) :: Element.t()
  def to_element(%__MODULE__{type: type, size: size}, attrs \\ []) do
    symbol_type = apply_value(type, nil)
    symbol_size = apply_value(size, nil)

    case symbol_type do
      :circle -> circle_element(symbol_size, attrs)
      :square -> square_element(symbol_size, attrs)
      :cross -> cross_element(symbol_size, attrs)
      # Fall back to path for other symbols
      _ -> path_element(symbol_type, symbol_size, attrs)
    end
  end

  # Native SVG circle element
  defp circle_element(size, attrs) do
    r = :math.sqrt(size / :math.pi())

    Element.circle(
      Keyword.merge([r: r, cx: 0, cy: 0], attrs)
    )
  end

  # Native SVG rect element for square
  defp square_element(size, attrs) do
    side = :math.sqrt(size)

    Element.rect(
      Keyword.merge([
        x: -side / 2,
        y: -side / 2,
        width: side,
        height: side
      ], attrs)
    )
  end

  # Two overlapping rects for cross
  defp cross_element(size, attrs) do
    r = :math.sqrt(size / 5)
    w = r * 3
    h = r

    # Create group with two rects
    horizontal = Element.rect(
      Keyword.merge([x: -w / 2, y: -h / 2, width: w, height: h], attrs)
    )

    vertical = Element.rect(
      Keyword.merge([x: -h / 2, y: -w / 2, width: h, height: w], attrs)
    )

    Element.g(attrs)
    |> Element.append([horizontal, vertical])
  end

  # Fallback to path for other symbol types
  defp path_element(symbol_type, size, attrs) do
    path_data = generate(%__MODULE__{type: symbol_type, size: size})

    Element.path(
      Keyword.merge([d: path_data], attrs)
    )
  end

  # Circle: area = pi * r^2, so r = sqrt(size / pi)
  defp circle_path(size) do
    r = :math.sqrt(size / :math.pi())

    Path.new()
    |> Path.move_to(r, 0)
    |> Path.arc_to(r, r, 0, 1, 1, -r, 0)
    |> Path.arc_to(r, r, 0, 1, 1, r, 0)
    |> Path.close()
  end

  # Cross (plus sign)
  defp cross_path(size) do
    r = :math.sqrt(size / 5) / 2

    Path.new()
    |> Path.move_to(-3 * r, -r)
    |> Path.line_to(-3 * r, r)
    |> Path.line_to(-r, r)
    |> Path.line_to(-r, 3 * r)
    |> Path.line_to(r, 3 * r)
    |> Path.line_to(r, r)
    |> Path.line_to(3 * r, r)
    |> Path.line_to(3 * r, -r)
    |> Path.line_to(r, -r)
    |> Path.line_to(r, -3 * r)
    |> Path.line_to(-r, -3 * r)
    |> Path.line_to(-r, -r)
    |> Path.close()
  end

  # Diamond (rotated square)
  defp diamond_path(size) do
    r = :math.sqrt(size / (2 * @sqrt3))
    h = r * @sqrt3

    Path.new()
    |> Path.move_to(0, -h)
    |> Path.line_to(r, 0)
    |> Path.line_to(0, h)
    |> Path.line_to(-r, 0)
    |> Path.close()
  end

  # Square
  defp square_path(size) do
    r = :math.sqrt(size) / 2

    Path.new()
    |> Path.move_to(-r, -r)
    |> Path.line_to(r, -r)
    |> Path.line_to(r, r)
    |> Path.line_to(-r, r)
    |> Path.close()
  end

  # 5-pointed star
  defp star_path(size) do
    r_outer = :math.sqrt(size * 0.6)
    r_inner = r_outer * 0.4

    points =
      for i <- 0..9 do
        angle = i * @tau / 10 - :math.pi() / 2
        r = if rem(i, 2) == 0, do: r_outer, else: r_inner
        {r * :math.cos(angle), r * :math.sin(angle)}
      end

    [{x0, y0} | rest] = points

    path = Path.new() |> Path.move_to(x0, y0)

    rest
    |> Enum.reduce(path, fn {x, y}, acc ->
      Path.line_to(acc, x, y)
    end)
    |> Path.close()
  end

  # Triangle (equilateral, pointing up)
  defp triangle_path(size) do
    h = :math.sqrt(size / @sqrt3)
    w = h * @sqrt3 / 2

    Path.new()
    |> Path.move_to(0, -h * 2 / 3)
    |> Path.line_to(w, h / 3)
    |> Path.line_to(-w, h / 3)
    |> Path.close()
  end

  # Wye (Y shape)
  defp wye_path(size) do
    r = :math.sqrt(size / 4)
    c = r * :math.cos(@tau / 12)
    s = r * :math.sin(@tau / 12)

    Path.new()
    |> Path.move_to(0, -r)
    |> Path.line_to(s, -c)
    |> Path.line_to(c + s, -c)
    |> Path.line_to(c, 0)
    |> Path.line_to(c + s, c)
    |> Path.line_to(s, c)
    |> Path.line_to(0, r)
    |> Path.line_to(-s, c)
    |> Path.line_to(-c - s, c)
    |> Path.line_to(-c, 0)
    |> Path.line_to(-c - s, -c)
    |> Path.line_to(-s, -c)
    |> Path.close()
  end

  defp apply_value(value, _data) when is_atom(value), do: value
  defp apply_value(value, _data) when is_number(value), do: value
  defp apply_value(func, data) when is_function(func, 1), do: func.(data)
  defp apply_value(func, _data) when is_function(func, 0), do: func.()
end
