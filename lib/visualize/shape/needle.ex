defmodule Visualize.Shape.Needle do
  @moduledoc """
  Needle generator: one filled pointer per datum from the hub to its angle, as long as
  its length — a gauge's indicator, a compass needle (spec/04 §16, #392).

  `angle/2` is in the domain units of the radial scale given to `scale/2` (radians without
  one); `length/2`, `inner_radius/2`, `width/2` and `tail/2` are pixels. Each datum's
  path is a tapered shape from the base at the hub to the tip, closed; `hub_path/2` is
  the hub circle the pointer turns about.

  ## Examples

      reading = Visualize.Scale.linear() |> Visualize.Scale.domain([0, 100]) |> Visualize.Scale.range([-2.0944, 2.0944])

      needle =
        Visualize.Shape.Needle.new()
        |> Visualize.Shape.Needle.scale(reading)
        |> Visualize.Shape.Needle.angle(:value)
        |> Visualize.Shape.Needle.length(120)
        |> Visualize.Shape.Needle.tail(12)

      [path] = Visualize.Shape.Needle.generate_path(needle, [%{value: 42}])

  """

  alias Visualize.IR.Path
  alias Visualize.Shape.{Annotation, Line}

  defstruct angle: nil,
            length: nil,
            scale: nil,
            inner_radius: 0,
            width: 6,
            tail: 0,
            hub: nil,
            cap: :point

  @type cap :: :point | :round | :flat

  @type t :: %__MODULE__{
          angle: Line.accessor() | nil,
          length: Line.accessor() | nil,
          scale: struct() | nil,
          inner_radius: Line.accessor(),
          width: Line.accessor(),
          tail: Line.accessor(),
          hub: Line.accessor() | nil,
          cap: cap()
        }

  @doc "Creates a needle generator reading tuple elements 0 and 1 as angle and length"
  @spec new() :: t()
  def new, do: %__MODULE__{angle: &elem(&1, 0), length: &elem(&1, 1)}

  @doc "Sets the angle accessor, in the scale's domain units (radians without a scale)"
  @spec angle(t(), Line.accessor()) :: t()
  def angle(%__MODULE__{} = n, accessor), do: %{n | angle: Line.normalize_accessor(accessor)}

  @doc "Sets the tip's radius accessor, in pixels"
  @spec length(t(), Line.accessor()) :: t()
  def length(%__MODULE__{} = n, accessor), do: %{n | length: Line.normalize_accessor(accessor)}

  @doc "Sets the radial scale the angles map through; `nil` means radians"
  @spec scale(t(), struct() | nil) :: t()
  def scale(%__MODULE__{} = n, nil), do: %{n | scale: nil}
  def scale(%__MODULE__{} = n, scale) when is_struct(scale), do: %{n | scale: scale}

  @doc "Sets where the pointer starts, in pixels (default `0`)"
  @spec inner_radius(t(), Line.accessor()) :: t()
  def inner_radius(%__MODULE__{} = n, accessor),
    do: %{n | inner_radius: Line.normalize_accessor(accessor)}

  @doc "Sets the base width accessor, in pixels (default `6`)"
  @spec width(t(), Line.accessor()) :: t()
  def width(%__MODULE__{} = n, accessor), do: %{n | width: Line.normalize_accessor(accessor)}

  @doc "Sets how far the pointer extends behind the hub, in pixels (default `0`)"
  @spec tail(t(), Line.accessor()) :: t()
  def tail(%__MODULE__{} = n, accessor), do: %{n | tail: Line.normalize_accessor(accessor)}

  @doc "Sets the hub circle's radius accessor; `nil` means the width"
  @spec hub(t(), Line.accessor() | nil) :: t()
  def hub(%__MODULE__{} = n, nil), do: %{n | hub: nil}
  def hub(%__MODULE__{} = n, accessor), do: %{n | hub: Line.normalize_accessor(accessor)}

  @doc "Sets the tip: `:point`, `:round` or `:flat`"
  @spec cap(t(), cap()) :: t()
  def cap(%__MODULE__{} = n, cap) when cap in [:point, :round, :flat], do: %{n | cap: cap}

  @doc "Returns the list of SVG path-data strings, one pointer per datum"
  @spec generate(t(), Visualize.Data.Table.source()) :: [String.t()]
  def generate(%__MODULE__{} = n, data) do
    n |> generate_path(data) |> Enum.map(&Visualize.Backend.SVG.path_data/1)
  end

  @doc """
  Returns the list of `IR.Path`, one pointer per datum: from the base corner behind the
  hub, round the tail, to the other corner, then to the tip as the cap says, closed.
  """
  @spec generate_path(t(), Visualize.Data.Table.source()) :: [Path.t()]
  def generate_path(%__MODULE__{} = n, data) do
    Enum.map(Visualize.Data.Table.rows(data), &pointer(n, &1))
  end

  @doc "Returns the hub circle's `IR.Path` for a datum, radius `hub` (the width when `nil`)"
  @spec hub_path(t(), term()) :: Path.t()
  def hub_path(%__MODULE__{} = n, d) do
    r = hub_radius(n, d)

    Path.new()
    |> Path.move_to(crisp(-r), 0.0)
    |> Path.arc_to(r, r, 0, 1, 1, crisp(r), 0.0)
    |> Path.arc_to(r, r, 0, 1, 1, crisp(-r), 0.0)
    |> Path.close()
  end

  @doc false
  @spec hub_radius(t(), term()) :: number()
  def hub_radius(%__MODULE__{hub: nil} = n, d), do: Annotation.value(n.width, d)
  def hub_radius(%__MODULE__{hub: hub}, d), do: Annotation.value(hub, d)

  defp pointer(n, d) do
    a = Annotation.position(n.scale, Annotation.value(n.angle, d))
    length = Annotation.value(n.length, d)
    inner = Annotation.value(n.inner_radius, d)
    half = Annotation.value(n.width, d) / 2
    tail = Annotation.value(n.tail, d)
    {ux, uy} = {:math.sin(a), -:math.cos(a)}
    {px, py} = {:math.cos(a), :math.sin(a)}

    at = fn along, across ->
      {crisp(along * ux + across * px), crisp(along * uy + across * py)}
    end

    base = inner - tail
    {x0, y0} = at.(base, half)
    {x1, y1} = at.(base, -half)

    path = Path.new() |> Path.move_to(x0, y0) |> Path.line_to(x1, y1)

    path =
      case n.cap do
        :point ->
          {tx, ty} = at.(length, 0)
          Path.line_to(path, tx, ty)

        :flat ->
          {fx0, fy0} = at.(length, -half)
          {fx1, fy1} = at.(length, half)
          path |> Path.line_to(fx0, fy0) |> Path.line_to(fx1, fy1)

        :round ->
          {fx0, fy0} = at.(length, -half)
          {fx1, fy1} = at.(length, half)
          path |> Path.line_to(fx0, fy0) |> Path.arc_to(half, half, 0, 0, 1, fx1, fy1)
      end

    Path.close(path)
  end

  # Six decimals, negative zero folded (D-6), as every polar coordinate prints.
  defp crisp(x) do
    case Float.round(x * 1.0, 6) do
      r when r == 0 -> 0.0
      r -> r
    end
  end
end
