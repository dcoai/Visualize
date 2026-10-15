defmodule Visualize.Chart.Mark.Generic do
  @moduledoc false
  # The generic marks (spec/14 §5.6): what a layout's rows need — a path as it is, a
  # rectangle, a circle, and an arc over `Visualize.Shape.Pie`. Children are
  # `%{element, datum, style, anchor}` as in `Visualize.Chart.Mark.Shapes`.

  alias Visualize.Chart.Mark.{Channels, Label, Shapes}
  alias Visualize.Chart.Style
  alias Visualize.IR.{Element, Path}
  alias Visualize.Shape.{Arc, Pie}

  @doc false
  @spec elements(map()) :: [map()]
  def elements(%{type: :path} = ctx), do: path(ctx)
  def elements(%{type: :rect} = ctx), do: rect(ctx)
  def elements(%{type: :circle} = ctx), do: circle(ctx)
  def elements(%{type: :text} = ctx), do: text(ctx)
  def elements(%{type: :arc} = ctx), do: arc(ctx)

  # -- path ----------------------------------------------------------------------------

  defp path(ctx) do
    ctx
    |> Channels.pixels()
    |> Channels.placed([:path])
    |> Enum.map(fn row ->
      path = row.path

      is_struct(path, Path) ||
        raise ArgumentError,
              "a :path mark draws a Visualize.IR.Path per row; got #{inspect(path)} " <>
                "(spec/14 §5.2)"

      %{element: Element.path(path), datum: row.datum, style: %{}, anchor: first_point(path)}
    end)
  end

  defp first_point(%Path{commands: [{:M, x, y} | _]}), do: {x, y}
  defp first_point(_path), do: nil

  # -- rect ----------------------------------------------------------------------------

  defp rect(ctx) do
    corner = Shapes.option(ctx, :corner_radius, 0)

    ctx
    |> Channels.pixels()
    |> Channels.placed([:x0, :x1, :y0, :y1])
    |> Enum.map(fn row ->
      x = min(row.x0, row.x1)
      y = min(row.y0, row.y1)
      width = abs(row.x1 - row.x0)
      height = abs(row.y1 - row.y0)
      element = Element.rect(x, y, width, height)

      element =
        if corner > 0, do: Element.set_attrs(element, %{rx: corner, ry: corner}), else: element

      %{
        element: element,
        datum: row.datum,
        style: value_fill(ctx, Map.get(row, :value)),
        anchor: {x + width / 2, y + height / 2},
        bounds: {x, y, width, height}
      }
    end)
  end

  # -- text ----------------------------------------------------------------------------

  # A text per datum at its position (spec/14 §5.2, #134): the mark's inline label's text
  # read from the datum, else `value` as a string; anchored as the label says about the
  # position, in the label's style — the label's whole job done by the mark itself.
  defp text(ctx) do
    ctx
    |> Channels.pixels([:value])
    |> Channels.placed([:x, :y])
    |> Enum.map(fn row ->
      content =
        case ctx.label do
          %{text: text} -> Label.text(text, row.datum)
          nil -> row |> Map.get(:value) |> to_content()
        end

      element = Label.element(ctx, {row.x, row.y}, %{datum: row.datum}, content, "mark-text")
      %{element: element, datum: row.datum, style: %{}, anchor: {row.x, row.y}}
    end)
  end

  defp to_content(nil), do: ""
  defp to_content(value), do: to_string(value)

  # A rect's `value` reaches the colour scale as its fill (spec/14 §5.2); the pixel row
  # already carries the scale's output when the frame declares `color`.
  defp value_fill(_ctx, nil), do: %{}

  defp value_fill(%{frame: frame, mode: mode}, colour) do
    if Style.color?(colour), do: %{fill: Style.color(colour, frame.theme, mode)}, else: %{}
  end

  # -- circle --------------------------------------------------------------------------

  defp circle(ctx) do
    radius = Shapes.option(ctx, :radius, 3)

    ctx
    |> Channels.pixels()
    |> Channels.placed([:x, :y])
    |> Enum.map(fn row ->
      r = Map.get(row, :value) || radius

      %{
        element: Element.circle(row.x, row.y, r),
        datum: row.datum,
        style: %{},
        anchor: {row.x, row.y},
        extent: 2 * r
      }
    end)
  end

  # -- arc -----------------------------------------------------------------------------

  # The pie over `value`, or each datum's own `start` and `end` when the mark gives both
  # (spec/14 §5.6, D-69); the radii are the `inner`/`outer` channels, else the options.
  defp arc(ctx) do
    inner = Shapes.option(ctx, :inner_radius, 0)
    outer = Shapes.option(ctx, :outer_radius, Shapes.outer_radius(ctx))
    pad = Shapes.option(ctx, :pad_angle, 0)

    generator =
      Arc.new()
      |> Arc.inner_radius(fn a -> Map.get(a, :inner) || inner end)
      |> Arc.outer_radius(fn a -> Map.get(a, :outer) || outer end)
      |> Arc.corner_radius(Shapes.option(ctx, :corner_radius, 0))

    if Channels.has?(ctx, :start) and Channels.has?(ctx, :end),
      do: angled_arcs(ctx, generator, pad),
      else: pie_arcs(ctx, generator, pad)
  end

  # The pie pads its slices itself, so the arc's own pad angle stays at its default.
  defp pie_arcs(ctx, generator, pad) do
    rows = ctx |> Channels.pixels() |> Channels.placed([:value])

    arcs =
      Pie.new()
      |> Pie.value(& &1.value)
      |> Pie.start_angle(Shapes.option(ctx, :start_angle, 0))
      |> Pie.end_angle(Shapes.option(ctx, :end_angle, 2 * :math.pi()))
      |> Pie.pad_angle(pad)
      |> Pie.generate(rows)

    radii = generator |> Arc.inner_radius(&generator.inner_radius.(&1.data))
    radii = Arc.outer_radius(radii, &generator.outer_radius.(&1.data))
    Enum.map(arcs, &arc_child(radii, &1, &1.data.datum))
  end

  # No pie: every datum placed on both angles is the direct call over its own row.
  defp angled_arcs(ctx, generator, pad) do
    rows = ctx |> Channels.pixels() |> Channels.placed([:start, :end])

    angled =
      generator
      |> Arc.start_angle(& &1.start)
      |> Arc.end_angle(&Map.fetch!(&1, :end))
      |> Arc.pad_angle(pad)

    Enum.map(rows, &arc_child(angled, &1, &1.datum))
  end

  defp arc_child(generator, data, datum) do
    %{
      element: Element.path(Arc.generate_path(generator, data)),
      datum: datum,
      style: %{},
      anchor: Arc.centroid(generator, data),
      radii: Arc.radii(generator, data),
      span: Arc.angles(generator, data) |> then(fn {a0, a1} -> a1 - a0 end)
    }
  end
end
