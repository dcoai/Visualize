defmodule Visualize.Shape do
  @moduledoc """
  Shape generators for creating SVG paths from data.

  Provides generators for common chart elements:
  - Lines and areas for time series
  - Arcs for pie and donut charts
  - Symbols for scatter plots
  - Stacks for stacked bar/area charts
  - Bands (state timelines), rules and x-bands (annotations) as element lists
  - Percentile bands (median plus inner and outer bands) as a map of paths
  - Roses (one arc sector per datum over a radial scale) as a list of paths

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

  alias Visualize.Shape.{
    Arc,
    Area,
    Band,
    Line,
    Needle,
    PercentileBand,
    Pie,
    Rose,
    Rule,
    Stack,
    Symbol,
    XBand
  }

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

  # Element-producing marks (spec/04 §11–13)
  @doc "Creates a new band (state timeline) generator"
  defdelegate band(), to: Band, as: :new

  @doc "Creates a new rule (vertical annotation) generator"
  defdelegate rule(), to: Rule, as: :new

  @doc "Creates a new x-band (shaded interval annotation) generator"
  defdelegate x_band(), to: XBand, as: :new

  @doc "Creates a new percentile-band generator (spec/04 §14)"
  defdelegate percentile_band(), to: PercentileBand, as: :new

  @doc "Creates a new rose generator (spec/04 §15)"
  defdelegate rose(), to: Rose, as: :new

  @doc "Creates a new needle generator (spec/04 §16)"
  defdelegate needle(), to: Needle, as: :new

  # Common configuration functions that work across generators

  @doc "Sets the x accessor"
  def x(%Line{} = shape, accessor), do: Line.x(shape, accessor)
  def x(%Area{} = shape, accessor), do: Area.x(shape, accessor)
  def x(%Rule{} = shape, accessor), do: Rule.x(shape, accessor)
  def x(%PercentileBand{} = shape, accessor), do: PercentileBand.x(shape, accessor)

  @doc "Sets the y accessor"
  def y(%Line{} = shape, accessor), do: Line.y(shape, accessor)
  def y(%Area{} = shape, accessor), do: Area.y(shape, accessor)
  def y(%Band{} = shape, accessor), do: Band.y(shape, accessor)

  @doc "Sets the x0 accessor (for areas, bands and x-bands)"
  def x0(%Area{} = shape, accessor), do: Area.x0(shape, accessor)
  def x0(%Band{} = shape, accessor), do: Band.x0(shape, accessor)
  def x0(%XBand{} = shape, accessor), do: XBand.x0(shape, accessor)

  @doc "Sets the x1 accessor (for areas, bands and x-bands)"
  def x1(%Area{} = shape, accessor), do: Area.x1(shape, accessor)
  def x1(%Band{} = shape, accessor), do: Band.x1(shape, accessor)
  def x1(%XBand{} = shape, accessor), do: XBand.x1(shape, accessor)

  @doc "Sets the y0 accessor (baseline for areas; extent for rules and x-bands)"
  def y0(%Area{} = shape, accessor), do: Area.y0(shape, accessor)
  def y0(%Rule{} = shape, accessor), do: Rule.y0(shape, accessor)
  def y0(%XBand{} = shape, accessor), do: XBand.y0(shape, accessor)

  @doc "Sets the y1 accessor (for areas; extent for rules and x-bands)"
  def y1(%Area{} = shape, accessor), do: Area.y1(shape, accessor)
  def y1(%Rule{} = shape, accessor), do: Rule.y1(shape, accessor)
  def y1(%XBand{} = shape, accessor), do: XBand.y1(shape, accessor)

  @doc "Sets the height accessor (for bands)"
  def height(%Band{} = shape, accessor), do: Band.height(shape, accessor)

  @doc "Sets the fill accessor (for bands and x-bands)"
  def fill(%Band{} = shape, accessor), do: Band.fill(shape, accessor)
  def fill(%XBand{} = shape, accessor), do: XBand.fill(shape, accessor)

  @doc "Sets the x scale (for rules and x-bands); `nil` means pixel values"
  def scale(%Rule{} = shape, scale), do: Rule.scale(shape, scale)
  def scale(%XBand{} = shape, scale), do: XBand.scale(shape, scale)
  def scale(%Rose{} = shape, scale), do: Rose.scale(shape, scale)
  def scale(%Needle{} = shape, scale), do: Needle.scale(shape, scale)

  @doc "Sets the sector-centre accessor (for roses), in the scale's domain units"
  def angle(%Rose{} = shape, accessor), do: Rose.angle(shape, accessor)
  def angle(%Needle{} = shape, accessor), do: Needle.angle(shape, accessor)

  @doc "Sets the sector-width accessor (for roses), in the scale's domain units"
  def width(%Rose{} = shape, accessor), do: Rose.width(shape, accessor)

  @doc "Sets the label accessor (for rules and x-bands); `nil` clears it"
  def label(%Rule{} = shape, accessor), do: Rule.label(shape, accessor)
  def label(%XBand{} = shape, accessor), do: XBand.label(shape, accessor)

  @doc "Sets the median accessor (for percentile bands); `nil` clears it"
  def median(%PercentileBand{} = shape, accessor), do: PercentileBand.median(shape, accessor)

  @doc "Sets the inner `{lo, hi}` band (for percentile bands); `nil` clears it"
  def inner(%PercentileBand{} = shape, pair), do: PercentileBand.inner(shape, pair)

  @doc "Sets the outer `{lo, hi}` band (for percentile bands); `nil` clears it"
  def outer(%PercentileBand{} = shape, pair), do: PercentileBand.outer(shape, pair)

  @doc "Sets the curve interpolation type"
  def curve(shape, type, opts \\ [])
  def curve(%Line{} = shape, type, opts), do: Line.curve(shape, type, opts)
  def curve(%Area{} = shape, type, opts), do: Area.curve(shape, type, opts)
  def curve(%PercentileBand{} = shape, type, opts), do: PercentileBand.curve(shape, type, opts)

  @doc "Sets the defined predicate"
  def defined(%Line{} = shape, pred), do: Line.defined(shape, pred)
  def defined(%Area{} = shape, pred), do: Area.defined(shape, pred)
  def defined(%PercentileBand{} = shape, pred), do: PercentileBand.defined(shape, pred)

  @doc "Sets the value accessor (for pie and stack)"
  def value(%Pie{} = shape, accessor), do: Pie.value(shape, accessor)
  def value(%Stack{} = shape, accessor), do: Stack.value(shape, accessor)

  @doc "Sets the keys for stack generator"
  def keys(%Stack{} = shape, keys), do: Stack.keys(shape, keys)

  @doc "Sets the order for stack generator"
  def order(%Stack{} = shape, order), do: Stack.order(shape, order)

  @doc "Sets the offset for stack generator"
  def offset(%Stack{} = shape, offset), do: Stack.offset(shape, offset)

  @doc "Sets the inner radius (for arcs and roses)"
  def inner_radius(%Arc{} = shape, radius), do: Arc.inner_radius(shape, radius)
  def inner_radius(%Rose{} = shape, radius), do: Rose.inner_radius(shape, radius)

  @doc "Sets the outer radius (for arcs and roses)"
  def outer_radius(%Arc{} = shape, radius), do: Arc.outer_radius(shape, radius)
  def outer_radius(%Rose{} = shape, radius), do: Rose.outer_radius(shape, radius)

  @doc "Sets the corner radius (for arcs)"
  def corner_radius(%Arc{} = shape, radius), do: Arc.corner_radius(shape, radius)

  @doc "Sets the pad radius (for arcs)"
  def pad_radius(%Arc{} = shape, radius), do: Arc.pad_radius(shape, radius)

  @doc "Sets the start angle (for arcs and pies)"
  def start_angle(%Arc{} = shape, angle), do: Arc.start_angle(shape, angle)
  def start_angle(%Pie{} = shape, angle), do: Pie.start_angle(shape, angle)

  @doc "Sets the end angle (for arcs and pies)"
  def end_angle(%Arc{} = shape, angle), do: Arc.end_angle(shape, angle)
  def end_angle(%Pie{} = shape, angle), do: Pie.end_angle(shape, angle)

  @doc "Sets the pad angle (for arcs, pies and roses)"
  def pad_angle(%Arc{} = shape, angle), do: Arc.pad_angle(shape, angle)
  def pad_angle(%Pie{} = shape, angle), do: Pie.pad_angle(shape, angle)
  def pad_angle(%Rose{} = shape, angle), do: Rose.pad_angle(shape, angle)

  @doc "Sets the data comparator (for pies); `nil` clears it"
  def sort(%Pie{} = shape, comparator), do: Pie.sort(shape, comparator)

  @doc "Sets the value comparator (for pies); `nil` clears it"
  def sort_values(%Pie{} = shape, comparator), do: Pie.sort_values(shape, comparator)

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
  For Band, Rule, XBand: returns a list of `Visualize.IR.Element`
  For PercentileBand: returns `%{outer:, inner:, median:}` of path strings
  For Rose: returns a list of path strings, one per datum
  """
  def generate(shape, data \\ nil)
  def generate(%Line{} = shape, data), do: Line.generate(shape, data)
  def generate(%Area{} = shape, data), do: Area.generate(shape, data)
  def generate(%Arc{} = shape, data), do: Arc.generate(shape, data)
  def generate(%Pie{} = shape, data), do: Pie.generate(shape, data)
  def generate(%Symbol{} = shape, data), do: Symbol.generate(shape, data)
  def generate(%Stack{} = shape, data), do: Stack.generate(shape, data)
  def generate(%Band{} = shape, data), do: Band.generate(shape, data)
  def generate(%Rule{} = shape, data), do: Rule.generate(shape, data)
  def generate(%XBand{} = shape, data), do: XBand.generate(shape, data)
  def generate(%PercentileBand{} = shape, data), do: PercentileBand.generate(shape, data)
  def generate(%Rose{} = shape, data), do: Rose.generate(shape, data)

  @doc """
  Generates a Path struct (for Line, Area, Arc, Symbol, Band), a map of them for
  PercentileBand, or a list of them for Rose.

  Use this for backend-agnostic path generation, then render
  with `Visualize.Render.to_string/2` or create an element with
  `Visualize.IR.Element.path/2`.
  """
  def generate_path(shape, data \\ nil)
  def generate_path(%Line{} = shape, data), do: Line.generate_path(shape, data)
  def generate_path(%Area{} = shape, data), do: Area.generate_path(shape, data)
  def generate_path(%Arc{} = shape, data), do: Arc.generate_path(shape, data)
  def generate_path(%Symbol{} = shape, data), do: Symbol.generate_path(shape, data)
  def generate_path(%Band{} = shape, data), do: Band.generate_path(shape, data)

  def generate_path(%PercentileBand{} = shape, data),
    do: PercentileBand.generate_path(shape, data)

  def generate_path(%Rose{} = shape, data), do: Rose.generate_path(shape, data)
end
