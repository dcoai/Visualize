defmodule Visualize.Chart.Mark.Series do
  @moduledoc false
  # The `series` channel on every mark that draws rows (spec/14 §5.2, §5.6, D-126): which
  # series each element belongs to, the `data-series` it carries so `LegendHook` hides the
  # whole series (spec/10 §14), and the series' colour it is painted in. A `:line` or an
  # `:area` also splits its rows by the channel; that is its generator's, not this.

  alias Visualize.Chart.Mark.Channels
  alias Visualize.Chart.Style
  alias Visualize.IR.Element
  alias Visualize.Scale
  alias Visualize.Theme

  # The generators that set the paint on an element inside the datum's group, not on the
  # group: their series colour goes there through `over/3`.
  @painted_inside [:rule, :x_band]

  @doc false
  # The mark's series values in order of first appearance, each with its one-based
  # position: `%{value => j}`, or `nil` for a mark without the channel.
  @spec index(map()) :: %{term() => pos_integer()} | nil
  def index(ctx) do
    if Channels.has?(ctx, :series) do
      ctx.rows
      |> Enum.map(&Channels.reading(ctx, :series, &1))
      |> Enum.uniq()
      |> Enum.with_index(1)
      |> Map.new()
    end
  end

  @doc false
  # Each child with its series value as `:series`, read from its datum; the children as
  # they are for a mark without the channel.
  @spec annotate([map()], map()) :: [map()]
  def annotate(children, %{series: nil}), do: children

  def annotate(children, ctx) do
    Enum.map(children, &Map.put(&1, :series, Channels.reading(ctx, :series, &1.datum)))
  end

  @doc false
  # The element with the series' `data-series`, `to_string/1` of the value; unchanged for
  # a child of no series, or one whose reading is `nil`.
  @spec stamp(Element.t(), term()) :: Element.t()
  def stamp(element, nil), do: element
  def stamp(element, value), do: Element.set_attrs(element, %{"data-series" => to_string(value)})

  @doc false
  # The series' paint for a child as `%{key => colour}`: nothing when the mark has no
  # series, when its generator paints inside the datum's group, or when the element or the
  # child's own style already sets the paint key — anything more specific wins.
  @spec paint(map(), map()) :: map()
  def paint(_child, %{series: nil}), do: %{}
  def paint(_child, %{type: type}) when type in @painted_inside, do: %{}

  def paint(%{element: element, style: style, series: value}, %{paint: {key, _}} = ctx) do
    if Map.has_key?(element.style, key) or Map.has_key?(style, key),
      do: %{},
      else: %{key => colour(ctx, value)}
  end

  @doc false
  # The paint a `:rule` or an `:x_band` sets on its line or rectangle: the series' colour
  # for the datum in place of the mark's paint, unless that paint is a binding.
  @spec over(map(), map(), term()) :: term()
  def over(%{series: nil}, _datum, paint), do: paint
  def over(_ctx, _datum, {:field, _} = paint), do: paint
  def over(ctx, datum, _paint), do: colour(ctx, Channels.reading(ctx, :series, datum))

  # The colour scale's value for the series, else the theme's colour for its position
  # (spec/14 §5.6).
  defp colour(%{frame: frame, mode: mode, series: index}, value) do
    case Map.get(frame.scales, :color) do
      nil -> Theme.resolve(frame.theme, {:series, Map.fetch!(index, value)}, mode)
      scale -> scale |> Scale.apply(value) |> colour_or_slot(frame, mode, index, value)
    end
  end

  defp colour_or_slot(nil, frame, mode, index, value),
    do: Theme.resolve(frame.theme, {:series, Map.fetch!(index, value)}, mode)

  defp colour_or_slot(colour, frame, mode, _index, _value),
    do: Style.colour(colour, frame.theme, mode)
end
