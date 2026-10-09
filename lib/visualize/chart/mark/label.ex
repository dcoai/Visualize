defmodule Visualize.Chart.Mark.Label do
  @moduledoc false
  # A mark's inline label (spec/14 §5.5): one text per element at its anchor point, in the
  # label's style, `{:field, f}` read from the datum.

  alias Visualize.Chart.Frame.Position
  alias Visualize.Chart.Label.Polar
  alias Visualize.Chart.{Schema, Style, Var}
  alias Visualize.Chart.Text
  alias Visualize.Data.Table
  alias Visualize.IR.Element

  @inset 4
  # Types whose generator draws its own label (spec/14 §5.5); a `:text` mark is its label.
  @own_label [:rule, :x_band, :text]

  @doc false
  # The text of the label's parts for a datum.
  @spec text(String.t() | [term()], map()) :: String.t()
  def text(text, datum), do: text |> Text.parse!() |> Enum.map_join("", &part(&1, datum))

  defp part(string, _datum) when is_binary(string), do: string
  defp part(%Var{name: name}, _datum), do: Style.unresolved!(name)

  defp part({:field, field}, datum) do
    case Table.get(datum, field) do
      nil -> ""
      value -> to_string(value)
    end
  end

  @doc false
  # The label's resolved style.
  @spec style(map()) :: map()
  def style(%{label: label, frame: frame, mode: mode}) do
    name = Map.get(label || %{}, :style, Schema.default(:mark_label, :style))
    Style.resolve(Style.node(frame.styles, name), frame.theme, mode)
  end

  @doc false
  # One text element per child with an anchor point, or nothing without a label.
  @spec elements([map()], map()) :: [Element.t()]
  def elements(_children, %{label: nil}), do: []
  def elements(_children, %{type: type}) when type in @own_label, do: []

  def elements(children, %{label: label} = ctx) do
    for %{anchor: point, datum: datum} = child <- children,
        element =
          element(
            ctx,
            point,
            Map.take(child, [:bounds, :radii, :span, :extent]),
            text(label.text, datum),
            "mark-label"
          ),
        element != nil,
        do: element
  end

  @doc false
  # The texts a `:rule` or an `:x_band` generator drew into its per-datum groups, lifted out
  # into the mark's labels group (spec/14 §5.5, #485): `{elements without them, texts}`.
  # Every other type's labels are `elements/2`'s, so nothing is lifted.
  @spec lift([Element.t()], map()) :: {[Element.t()], [Element.t()]}
  def lift(elements, %{type: type}) when type in [:rule, :x_band] do
    elements
    |> Enum.map(fn %Element{children: children} = element ->
      {texts, rest} = Enum.split_with(children, &(&1.type == :text))
      {%{element | children: rest}, texts}
    end)
    |> Enum.unzip()
    |> then(fn {elements, texts} -> {elements, List.flatten(texts)} end)
  end

  def lift(elements, _ctx), do: {elements, []}

  @doc false
  # One text at a point — or, for an edge anchor, at an edge of the element's bounds —
  # anchored, offset and styled as the mark's label says (spec/14 §5.5). A `:text` mark
  # draws its element through this too (#134), with no label node to read past its style.
  @spec element(map(), {number(), number()}, map() | nil, String.t(), String.t()) ::
          Element.t() | nil
  def element(%{frame: frame} = ctx, {px, py}, shape, content, class) do
    shape = shape || %{}
    bounds = Map.get(shape, :bounds)
    label = ctx.label || %{}
    style = style(%{ctx | label: label})

    style_node =
      Style.node(frame.styles, Map.get(label, :style, Schema.default(:mark_label, :style)))

    anchor = Map.get(label, :anchor, default_anchor(ctx))
    dx = Map.get(label, :dx, 0)
    dy = Map.get(label, :dy, 0)
    centre = centre(ctx)

    {x, y, baseline, text_anchor} =
      case anchor do
        polar when polar in [:outward, :inward] ->
          Polar.place(
            polar,
            {px, py},
            centre,
            Map.get(shape, :radii),
            @inset + Map.get(label, :dr, 0)
          )

        _ ->
          place(anchor, px, py, bounds)
      end

    attrs = %{x: x + dx, y: y + dy} |> put_unless_nil(:dy, baseline)

    {rotation, text_anchor} =
      Polar.rotation(Map.get(label, :rotate), {x + dx, y + dy}, centre, text_anchor)

    base = %{class: class, text_anchor: text_anchor}

    # The text fitted to the element's own width (spec/14 §5.5, #138), or nothing.
    fit = Map.get(label, :fit, Schema.default(:mark_label, :fit))
    width = extent(shape, {x + dx, y + dy}, centre)

    case fit(fit, content, width, font_size(style_node, frame.theme)) do
      nil ->
        nil

      content ->
        Element.new(:text, attrs: attrs, style: Map.merge(base, style), content: content)
        |> Polar.rotate(rotation)
        |> Position.apply(style_node, outward(anchor))
    end
  end

  # The width an element offers its label: a rectangle's, a circle's diameter, a sector's
  # arc length at the label's own radius; `nil` for a type with no extent.
  defp extent(%{bounds: {_x, _y, w, _h}}, _point, _centre), do: w
  defp extent(%{extent: w}, _point, _centre), do: w

  defp extent(%{span: span}, {x, y}, {cx, cy}),
    do: span * :math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy))

  defp extent(_shape, _point, _centre), do: nil

  # 0.6 × the font size per character is the estimate the legend's layout makes (§4.5).
  @per_char 0.6

  defp fit(:none, content, _width, _font_size), do: content
  defp fit(_fit, content, nil, _font_size), do: content

  defp fit(fit, content, width, font_size) do
    room = trunc(width / (@per_char * font_size))
    length = String.length(content)

    cond do
      length <= room -> content
      fit == :hide -> nil
      room <= 1 -> nil
      true -> String.slice(content, 0, room - 1) <> "…"
    end
  end

  defp font_size(style_node, theme) do
    case Style.value(:font_size, Map.get(style_node, :font_size, :label_size), theme, :literal) do
      n when is_number(n) -> n
      _other -> theme.label_size
    end
  end

  # The centre a polar anchor and a polar rotation are about (spec/14 §5.5): the group's
  # origin for a centred mark or in a polar frame, the plot's middle otherwise.
  @centred [:rose, :arc, :needle]
  # A needle's label sits beyond its tip (spec/14 §5.2, #392); every other mark's above.
  defp default_anchor(%{type: :needle}), do: :outward
  defp default_anchor(_ctx), do: Schema.default(:mark_label, :anchor)

  defp centre(%{type: type, frame: %{kind: kind, plot: plot}}) do
    if type in @centred or kind == :polar, do: {0, 0}, else: {plot.width / 2, plot.height / 2}
  end

  # The outward direction of an anchor (spec/14 §5.5): the side the label sits on.
  defp outward(:top), do: {0, -1}
  defp outward(:bottom), do: {0, 1}
  defp outward(:left), do: {-1, 0}
  defp outward(:right), do: {1, 0}
  defp outward(:start), do: {1, 0}
  defp outward(:end), do: {-1, 0}
  defp outward(:x0), do: {-1, 0}
  defp outward(:x1), do: {1, 0}
  defp outward(:y1), do: {0, -1}
  defp outward(:y0), do: {0, 1}
  defp outward(_middle), do: nil

  # An edge anchor on an element with bounds sits 4 outside the midpoint of that edge
  # (#134); on any other element it is the cartesian anchor of the same side.
  defp place(:x0, _px, _py, {x, y, _w, h}), do: place(:left, x, y + h / 2, nil)
  defp place(:x1, _px, _py, {x, y, w, h}), do: place(:right, x + w, y + h / 2, nil)
  defp place(:y1, _px, _py, {x, y, w, _h}), do: place(:top, x + w / 2, y, nil)
  defp place(:y0, _px, _py, {x, y, w, h}), do: place(:bottom, x + w / 2, y + h, nil)
  defp place(:x0, px, py, nil), do: place(:left, px, py, nil)
  defp place(:x1, px, py, nil), do: place(:right, px, py, nil)
  defp place(:y1, px, py, nil), do: place(:top, px, py, nil)
  defp place(:y0, px, py, nil), do: place(:bottom, px, py, nil)
  defp place(:top, px, py, _bounds), do: {px, py - @inset, nil, :middle}
  defp place(:bottom, px, py, _bounds), do: {px, py + @inset, "0.71em", :middle}
  defp place(:left, px, py, _bounds), do: {px - @inset, py, "0.32em", :end}
  defp place(:right, px, py, _bounds), do: {px + @inset, py, "0.32em", :start}
  defp place(named, px, py, _bounds), do: {px, py, "0.32em", named}

  defp put_unless_nil(map, _key, nil), do: map
  defp put_unless_nil(map, key, value), do: Map.put(map, key, value)
end
