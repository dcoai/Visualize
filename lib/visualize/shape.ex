defmodule Visualize.Shape do
  @moduledoc """
  Shape generators for creating SVG paths from data.

  Provides generators for common chart elements:
  - Lines and areas for time series
  - Arcs for pie and donut charts
  - Symbols for scatter plots
  - Stacks for stacked bar/area charts

  ## Examples

      # Line chart
      line = Visualize.Shape.line()
        |> Visualize.Shape.x(fn d -> scale_x.(d.date) end)
        |> Visualize.Shape.y(fn d -> scale_y.(d.value) end)
        |> Visualize.Shape.curve(:monotone_x)

      path_data = Visualize.Shape.generate(line, data)

      # Pie chart
      pie = Visualize.Shape.pie()
        |> Visualize.Shape.value(:count)

      arcs = Visualize.Shape.generate(pie, data)

      # Stacked area chart
      stack = Visualize.Shape.stack()
        |> Visualize.Shape.keys([:apples, :oranges, :bananas])

      series = Visualize.Shape.generate(stack, data)

  """

  alias Visualize.Shape.{Line, Area, Arc, Pie, Symbol, Stack}

  # Line generator
  @doc "Creates a new line generator"
  defdelegate line(), to: Line, as: :new

  # Area generator
  @doc "Creates a new area generator"
  defdelegate area(), to: Area, as: :new

  # Arc generator
  @doc "Creates a new arc generator"
  defdelegate arc(), to: Arc, as: :new

  # Pie layout
  @doc "Creates a new pie layout generator"
  defdelegate pie(), to: Pie, as: :new

  # Symbol generator
  @doc "Creates a new symbol generator"
  defdelegate symbol(), to: Symbol, as: :new

  # Stack generator
  @doc "Creates a new stack generator"
  defdelegate stack(), to: Stack, as: :new

  # Common configuration functions that work across generators

  @doc "Sets the x accessor"
  def x(%Line{} = shape, accessor), do: Line.x(shape, accessor)
  def x(%Area{} = shape, accessor), do: Area.x(shape, accessor)

  @doc "Sets the y accessor"
  def y(%Line{} = shape, accessor), do: Line.y(shape, accessor)
  def y(%Area{} = shape, accessor), do: Area.y(shape, accessor)

  @doc "Sets the x0 accessor (for areas)"
  def x0(%Area{} = shape, accessor), do: Area.x0(shape, accessor)

  @doc "Sets the x1 accessor (for areas)"
  def x1(%Area{} = shape, accessor), do: Area.x1(shape, accessor)

  @doc "Sets the y0 accessor (baseline for areas)"
  def y0(%Area{} = shape, accessor), do: Area.y0(shape, accessor)

  @doc "Sets the y1 accessor (for areas)"
  def y1(%Area{} = shape, accessor), do: Area.y1(shape, accessor)

  @doc "Sets the curve interpolation type"
  def curve(shape, type, opts \\ [])
  def curve(%Line{} = shape, type, opts), do: Line.curve(shape, type, opts)
  def curve(%Area{} = shape, type, opts), do: Area.curve(shape, type, opts)

  @doc "Sets the defined predicate"
  def defined(%Line{} = shape, pred), do: Line.defined(shape, pred)
  def defined(%Area{} = shape, pred), do: Area.defined(shape, pred)

  @doc "Sets the value accessor (for pie and stack)"
  def value(%Pie{} = shape, accessor), do: Pie.value(shape, accessor)
  def value(%Stack{} = shape, accessor), do: Stack.value(shape, accessor)

  @doc "Sets the keys for stack generator"
  def keys(%Stack{} = shape, keys), do: Stack.keys(shape, keys)

  @doc "Sets the order for stack generator"
  def order(%Stack{} = shape, order), do: Stack.order(shape, order)

  @doc "Sets the offset for stack generator"
  def offset(%Stack{} = shape, offset), do: Stack.offset(shape, offset)

  @doc "Sets the inner radius (for arcs)"
  def inner_radius(%Arc{} = shape, radius), do: Arc.inner_radius(shape, radius)

  @doc "Sets the outer radius (for arcs)"
  def outer_radius(%Arc{} = shape, radius), do: Arc.outer_radius(shape, radius)

  @doc "Sets the start angle (for arcs and pies)"
  def start_angle(%Arc{} = shape, angle), do: Arc.start_angle(shape, angle)
  def start_angle(%Pie{} = shape, angle), do: Pie.start_angle(shape, angle)

  @doc "Sets the end angle (for arcs and pies)"
  def end_angle(%Arc{} = shape, angle), do: Arc.end_angle(shape, angle)
  def end_angle(%Pie{} = shape, angle), do: Pie.end_angle(shape, angle)

  @doc "Sets the pad angle (for arcs and pies)"
  def pad_angle(%Arc{} = shape, angle), do: Arc.pad_angle(shape, angle)
  def pad_angle(%Pie{} = shape, angle), do: Pie.pad_angle(shape, angle)

  @doc "Sets the symbol type"
  def type(%Symbol{} = shape, type), do: Symbol.type(shape, type)

  @doc "Sets the symbol size"
  def size(%Symbol{} = shape, size), do: Symbol.size(shape, size)

  @doc """
  Generates output from a shape generator.

  For Line, Area, Arc: returns path data string
  For Pie: returns list of arc data maps
  For Symbol: returns path data string
  For Stack: returns list of series with stacked values
  """
  def generate(shape, data \\ nil)
  def generate(%Line{} = shape, data), do: Line.generate(shape, data)
  def generate(%Area{} = shape, data), do: Area.generate(shape, data)
  def generate(%Arc{} = shape, data), do: Arc.generate(shape, data)
  def generate(%Pie{} = shape, data), do: Pie.generate(shape, data)
  def generate(%Symbol{} = shape, data), do: Symbol.generate(shape, data)
  def generate(%Stack{} = shape, data), do: Stack.generate(shape, data)

  @doc "Generates a Path struct (for Line, Area, Arc, Symbol)"
  def generate_path(shape, data \\ nil)
  def generate_path(%Line{} = shape, data), do: Line.generate_path(shape, data)
  def generate_path(%Area{} = shape, data), do: Area.generate_path(shape, data)
  def generate_path(%Arc{} = shape, data), do: Arc.generate_path(shape, data)
  def generate_path(%Symbol{} = shape, data), do: Symbol.generate_path(shape, data)

  @doc "Generates an SVG element with the shape"
  def to_element(shape, data, attrs \\ [])
  def to_element(%Line{} = shape, data, attrs), do: Line.to_element(shape, data, attrs)
  def to_element(%Area{} = shape, data, attrs), do: Area.to_element(shape, data, attrs)
  def to_element(%Arc{} = shape, data, attrs), do: Arc.to_element(shape, data, attrs)
end
