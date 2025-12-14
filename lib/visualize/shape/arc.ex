defmodule Visualize.Shape.Arc do
  @moduledoc """
  Arc generator for creating circular or annular sectors.

  Used for pie charts, donut charts, and radial visualizations.

  ## Examples

      arc = Visualize.Shape.Arc.new()
        |> Visualize.Shape.Arc.inner_radius(50)
        |> Visualize.Shape.Arc.outer_radius(100)

      # Generate from angles
      path_data = Visualize.Shape.Arc.generate(arc, %{
        start_angle: 0,
        end_angle: :math.pi() / 2
      })

  """

  alias Visualize.SVG.Path

  defstruct inner_radius: 0,
            outer_radius: nil,
            corner_radius: 0,
            start_angle: nil,
            end_angle: nil,
            pad_angle: 0,
            pad_radius: nil

  @type accessor :: (any() -> number()) | number()
  @type t :: %__MODULE__{
          inner_radius: accessor(),
          outer_radius: accessor() | nil,
          corner_radius: accessor(),
          start_angle: accessor() | nil,
          end_angle: accessor() | nil,
          pad_angle: accessor(),
          pad_radius: accessor() | nil
        }

  @tau 2 * :math.pi()
  @epsilon 1.0e-12

  @doc "Creates a new arc generator"
  @spec new() :: t()
  def new do
    %__MODULE__{
      outer_radius: 100,
      start_angle: fn d -> Map.get(d, :start_angle, 0) end,
      end_angle: fn d -> Map.get(d, :end_angle, @tau) end
    }
  end

  @doc "Sets the inner radius"
  @spec inner_radius(t(), accessor()) :: t()
  def inner_radius(%__MODULE__{} = arc, radius) do
    %{arc | inner_radius: normalize_accessor(radius)}
  end

  @doc "Sets the outer radius"
  @spec outer_radius(t(), accessor()) :: t()
  def outer_radius(%__MODULE__{} = arc, radius) do
    %{arc | outer_radius: normalize_accessor(radius)}
  end

  @doc "Sets the corner radius"
  @spec corner_radius(t(), accessor()) :: t()
  def corner_radius(%__MODULE__{} = arc, radius) do
    %{arc | corner_radius: normalize_accessor(radius)}
  end

  @doc "Sets the start angle accessor"
  @spec start_angle(t(), accessor()) :: t()
  def start_angle(%__MODULE__{} = arc, angle) do
    %{arc | start_angle: normalize_accessor(angle)}
  end

  @doc "Sets the end angle accessor"
  @spec end_angle(t(), accessor()) :: t()
  def end_angle(%__MODULE__{} = arc, angle) do
    %{arc | end_angle: normalize_accessor(angle)}
  end

  @doc "Sets the pad angle"
  @spec pad_angle(t(), accessor()) :: t()
  def pad_angle(%__MODULE__{} = arc, angle) do
    %{arc | pad_angle: normalize_accessor(angle)}
  end

  @doc "Generates the SVG path data string"
  @spec generate(t(), map() | any()) :: String.t()
  def generate(%__MODULE__{} = arc, data) do
    arc
    |> generate_path(data)
    |> Path.to_string()
  end

  @doc "Generates a Path struct"
  @spec generate_path(t(), map() | any()) :: Path.t()
  def generate_path(%__MODULE__{} = arc, data) do
    r0 = apply_accessor(arc.inner_radius, data)
    r1 = apply_accessor(arc.outer_radius, data)
    a0 = apply_accessor(arc.start_angle, data) - :math.pi() / 2
    a1 = apply_accessor(arc.end_angle, data) - :math.pi() / 2
    da = abs(a1 - a0)
    cw = a1 > a0

    path = Path.new()

    cond do
      # Full circle or annulus
      da > @tau - @epsilon ->
        path
        |> Path.move_to(r1 * :math.cos(a0), r1 * :math.sin(a0))
        |> Path.arc_to(r1, r1, 0, 1, bool_to_int(cw), r1 * :math.cos(a0 + :math.pi()), r1 * :math.sin(a0 + :math.pi()))
        |> Path.arc_to(r1, r1, 0, 1, bool_to_int(cw), r1 * :math.cos(a0), r1 * :math.sin(a0))
        |> maybe_add_inner_ring(r0, a0, cw)

      # Partial arc
      da > @epsilon ->
        generate_partial_arc(path, r0, r1, a0, a1, da, cw)

      # Negligible arc
      true ->
        path
    end
  end

  @doc "Generates a centroid point for the arc"
  @spec centroid(t(), map() | any()) :: {number(), number()}
  def centroid(%__MODULE__{} = arc, data) do
    r0 = apply_accessor(arc.inner_radius, data)
    r1 = apply_accessor(arc.outer_radius, data)
    a0 = apply_accessor(arc.start_angle, data) - :math.pi() / 2
    a1 = apply_accessor(arc.end_angle, data) - :math.pi() / 2

    r = (r0 + r1) / 2
    a = (a0 + a1) / 2

    {r * :math.cos(a), r * :math.sin(a)}
  end

  @doc "Generates path data and creates an SVG path element"
  @spec to_element(t(), any(), keyword()) :: Visualize.SVG.Element.t()
  def to_element(%__MODULE__{} = arc, data, attrs \\ []) do
    path_data = generate(arc, data)

    default_attrs = %{
      d: path_data,
      fill: "currentColor"
    }

    merged_attrs = Map.merge(default_attrs, Map.new(attrs))
    Visualize.SVG.Element.path(merged_attrs)
  end

  defp generate_partial_arc(path, r0, r1, a0, a1, da, cw) do
    large_arc = if da > :math.pi(), do: 1, else: 0

    x0_outer = r1 * :math.cos(a0)
    y0_outer = r1 * :math.sin(a0)
    x1_outer = r1 * :math.cos(a1)
    y1_outer = r1 * :math.sin(a1)

    path = path
      |> Path.move_to(x0_outer, y0_outer)
      |> Path.arc_to(r1, r1, 0, large_arc, bool_to_int(cw), x1_outer, y1_outer)

    if r0 > @epsilon do
      # Has inner radius - create annular sector
      x0_inner = r0 * :math.cos(a1)
      y0_inner = r0 * :math.sin(a1)
      x1_inner = r0 * :math.cos(a0)
      y1_inner = r0 * :math.sin(a0)

      path
      |> Path.line_to(x0_inner, y0_inner)
      |> Path.arc_to(r0, r0, 0, large_arc, bool_to_int(not cw), x1_inner, y1_inner)
      |> Path.close()
    else
      # No inner radius - create pie slice
      path
      |> Path.line_to(0, 0)
      |> Path.close()
    end
  end

  defp maybe_add_inner_ring(path, r0, a0, cw) when r0 > @epsilon do
    path
    |> Path.move_to(r0 * :math.cos(a0), r0 * :math.sin(a0))
    |> Path.arc_to(r0, r0, 0, 1, bool_to_int(not cw), r0 * :math.cos(a0 + :math.pi()), r0 * :math.sin(a0 + :math.pi()))
    |> Path.arc_to(r0, r0, 0, 1, bool_to_int(not cw), r0 * :math.cos(a0), r0 * :math.sin(a0))
  end

  defp maybe_add_inner_ring(path, _, _, _), do: Path.close(path)

  defp normalize_accessor(value) when is_function(value, 1), do: value
  defp normalize_accessor(value) when is_number(value), do: fn _ -> value end
  defp normalize_accessor(value) when is_atom(value), do: fn d -> Map.get(d, value) end

  defp apply_accessor(accessor, data) when is_function(accessor, 1), do: accessor.(data)
  defp apply_accessor(accessor, _data) when is_number(accessor), do: accessor

  defp bool_to_int(true), do: 1
  defp bool_to_int(false), do: 0
end
