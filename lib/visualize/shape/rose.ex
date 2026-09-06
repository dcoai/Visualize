defmodule Visualize.Shape.Rose do
  @moduledoc """
  Rose generator: one `Visualize.Shape.Arc` sector per datum, centred on its angle and
  as long as its value (spec/04 §15, D-31).

  `angle/2` and `width/2` are in the domain units of the radial scale given to `scale/2`
  (radians without one); the radii are pixels. Each datum's path is exactly the `Arc`
  call with the same numbers, so a stacked wind rose is several roses with rising inner
  radii.

  ## Examples

      bearing = Visualize.Scale.radial() |> Visualize.Scale.domain([0, 360])
      radius = Visualize.Scale.sqrt() |> Visualize.Scale.domain([0, 40]) |> Visualize.Scale.range([0, 120])

      rose =
        Visualize.Shape.Rose.new()
        |> Visualize.Shape.Rose.scale(bearing)
        |> Visualize.Shape.Rose.angle(:bearing)
        |> Visualize.Shape.Rose.width(45)
        |> Visualize.Shape.Rose.outer_radius(fn d -> Visualize.Scale.apply(radius, d.count) end)
        |> Visualize.Shape.Rose.pad_angle(0.02)

      paths = Visualize.Shape.Rose.generate(rose, bins)

  """

  alias Visualize.IR.Path
  alias Visualize.Shape.{Annotation, Arc, Line}

  defstruct angle: nil,
            width: 1,
            scale: nil,
            inner_radius: 0,
            outer_radius: nil,
            pad_angle: 0

  @type accessor :: Line.accessor()
  @type t :: %__MODULE__{
          angle: accessor() | nil,
          width: accessor(),
          scale: struct() | nil,
          inner_radius: accessor(),
          outer_radius: accessor() | nil,
          pad_angle: accessor()
        }

  @doc "Creates a rose generator reading tuple elements 0 and 1 as angle and outer radius"
  @spec new() :: t()
  def new do
    %__MODULE__{angle: fn d -> elem(d, 0) end, outer_radius: fn d -> elem(d, 1) end}
  end

  @doc "Sets the sector-centre accessor, in the scale's domain units"
  @spec angle(t(), accessor()) :: t()
  def angle(%__MODULE__{} = rose, accessor) do
    %{rose | angle: Line.normalize_accessor(accessor)}
  end

  @doc "Sets the sector-width accessor, in the scale's domain units"
  @spec width(t(), accessor()) :: t()
  def width(%__MODULE__{} = rose, accessor) do
    %{rose | width: Line.normalize_accessor(accessor)}
  end

  @doc "Sets the radial scale the angles map through; `nil` means radians"
  @spec scale(t(), struct() | nil) :: t()
  def scale(%__MODULE__{} = rose, nil), do: %{rose | scale: nil}
  def scale(%__MODULE__{} = rose, scale) when is_struct(scale), do: %{rose | scale: scale}

  @doc "Sets the inner radius accessor, in pixels"
  @spec inner_radius(t(), accessor()) :: t()
  def inner_radius(%__MODULE__{} = rose, accessor) do
    %{rose | inner_radius: Line.normalize_accessor(accessor)}
  end

  @doc "Sets the outer radius accessor, in pixels"
  @spec outer_radius(t(), accessor()) :: t()
  def outer_radius(%__MODULE__{} = rose, accessor) do
    %{rose | outer_radius: Line.normalize_accessor(accessor)}
  end

  @doc "Sets the pad angle accessor, radians, as `Visualize.Shape.Arc.pad_angle/2`"
  @spec pad_angle(t(), accessor()) :: t()
  def pad_angle(%__MODULE__{} = rose, accessor) do
    %{rose | pad_angle: Line.normalize_accessor(accessor)}
  end

  @doc "Returns one SVG path-data string per datum"
  @spec generate(t(), [any()]) :: [String.t()]
  def generate(%__MODULE__{} = rose, data) do
    rose |> generate_path(data) |> Enum.map(&Visualize.Backend.SVG.path_data/1)
  end

  @doc "Returns one `IR.Path` per datum: the `Arc` sector centred on its angle"
  @spec generate_path(t(), [any()]) :: [Path.t()]
  def generate_path(%__MODULE__{} = rose, data) do
    Enum.map(data, fn d ->
      centre = Annotation.value(rose.angle, d)
      half = Annotation.value(rose.width, d) / 2

      Arc.new()
      |> Arc.inner_radius(Annotation.value(rose.inner_radius, d))
      |> Arc.outer_radius(Annotation.value(rose.outer_radius, d))
      |> Arc.start_angle(Annotation.position(rose.scale, centre - half))
      |> Arc.end_angle(Annotation.position(rose.scale, centre + half))
      |> Arc.pad_angle(Annotation.value(rose.pad_angle, d))
      |> Arc.generate_path(d)
    end)
  end
end
