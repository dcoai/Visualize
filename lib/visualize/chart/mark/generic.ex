defmodule Visualize.Chart.Mark.Generic do
  @moduledoc false
  # The generic marks (spec/14 §5.6): what a layout's rows need — a path as it is, a
  # rectangle, a circle, and an arc over `Visualize.Shape.Pie`. Children are
  # `%{element, datum, style, anchor}` as in `Visualize.Chart.Mark.Shapes`.

  alias Visualize.Chart.Mark.{Channels, Shapes}
  alias Visualize.Chart.Style
  alias Visualize.IR.{Element, Path}
  alias Visualize.Shape.{Arc, Pie}

  @doc false
  @spec elements(map()) :: [map()]
  def elements(%{type: :path} = ctx), do: path(ctx)
  def elements(%{type: :rect} = ctx), do: rect(ctx)
  def elements(%{type: :circle} = ctx), do: circle(ctx)
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
        anchor: {x + width / 2, y + height / 2}
      }
    end)
  end

  # A rect's `value` reaches the colour scale as its fill (spec/14 §5.2); the pixel row
  # already carries the scale's output when the frame declares `color`.
  defp value_fill(_ctx, nil), do: %{}

  defp value_fill(%{frame: frame, mode: mode}, colour) do
    if Style.colour?(colour), do: %{fill: Style.colour(colour, frame.theme, mode)}, else: %{}
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
        anchor: {row.x, row.y}
      }
    end)
  end

  # -- arc -----------------------------------------------------------------------------

  defp arc(ctx) do
    inner = Shapes.option(ctx, :inner_radius, 0)
    outer = Shapes.option(ctx, :outer_radius, Shapes.outer_radius(ctx))
    rows = ctx |> Channels.pixels() |> Channels.placed([:value])

    arcs =
      Pie.new()
      |> Pie.value(& &1.value)
      |> Pie.start_angle(Shapes.option(ctx, :start_angle, 0))
      |> Pie.end_angle(Shapes.option(ctx, :end_angle, 2 * :math.pi()))
      |> Pie.pad_angle(Shapes.option(ctx, :pad_angle, 0))
      |> Pie.generate(rows)

    generator =
      Arc.new()
      |> Arc.inner_radius(fn a -> Map.get(a.data, :inner) || inner end)
      |> Arc.outer_radius(fn a -> Map.get(a.data, :outer) || outer end)
      |> Arc.corner_radius(Shapes.option(ctx, :corner_radius, 0))

    Enum.map(arcs, fn arc ->
      %{
        element: Element.path(Arc.generate_path(generator, arc)),
        datum: arc.data.datum,
        style: %{},
        anchor: Arc.centroid(generator, arc)
      }
    end)
  end
end
