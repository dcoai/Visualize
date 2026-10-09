defmodule Visualize.Chart.Mark.Label do
  @moduledoc false
  # A mark's inline label (spec/14 §5.5): one text per element at its anchor point, in the
  # label's style, `{:field, f}` read from the datum.

  alias Visualize.Chart.Frame.{Defs, Position}
  alias Visualize.Chart.Label.Polar
  alias Visualize.Chart.{Schema, Style, Var}
  alias Visualize.Chart.Text
  alias Visualize.Color
  alias Visualize.Data.Table
  alias Visualize.IR.Element
  alias Visualize.Theme

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
            Map.take(child, [:bounds, :radii, :span, :extent, :under]),
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

    # The text fitted to the element's own width (spec/14 §5.5, #138), and on a rectangle
    # it sits on to the element's height (#497), or nothing.
    fit = Map.get(label, :fit, Schema.default(:mark_label, :fit))
    width = extent(shape, {x + dx, y + dy}, centre)
    font_size = font_size(style_node, frame.theme)

    case fit(fit, content, width, font_size) |> held(fit, bounds, anchor, font_size) do
      nil ->
        nil

      content ->
        style = inked(style, style_node, Map.get(shape, :under), frame.theme)

        Element.new(:text, attrs: attrs, style: Map.merge(base, style), content: content)
        |> Polar.rotate(rotation)
        |> Position.apply(style_node, outward(anchor))
    end
  end

  # Every colour key the label's style writes as `:contrast`, inked against the colour under
  # the label rather than the background `Style.resolve/3` assumed (spec/14 §5.5, D-123).
  defp inked(style, style_node, under, theme) do
    Enum.reduce([:fill, :stroke], style, fn key, acc ->
      if Map.get(style_node, key) == :contrast,
        do: Map.put(acc, key, Theme.ink(theme, under)),
        else: acc
    end)
  end

  @doc false
  # The children with the colour under each one's label as `:under`, read from its bound
  # element, when the label's style inks by `:contrast`; the children as they are otherwise.
  @spec under([map()], [Element.t()], map()) :: [map()]
  def under(children, _bound, %{label: nil}), do: children

  def under(children, bound, %{label: label, frame: frame} = ctx) do
    node = Style.node(frame.styles, Map.get(label, :style, Schema.default(:mark_label, :style)))

    if Enum.any?([:fill, :stroke], &(Map.get(node, &1) == :contrast)),
      do: Enum.zip_with(children, bound, &Map.put(&1, :under, under(&2, ctx))),
      else: children
  end

  @doc false
  # The colour under a mark's label (spec/14 §5.5, D-123): the fill its element is drawn
  # with — the element's own once bound, else the mark group's — as a literal, composited
  # over the theme's background by its `fill_opacity` × `opacity`; `nil` when the element
  # has no fill or one `Visualize.Color.parse/1` does not read.
  @spec under(Element.t(), map()) :: Color.t() | nil
  def under(%Element{style: style}, %{frame: frame, static: static, paint: paint}) do
    group =
      case paint do
        {:fill, {:field, _}} -> Map.get(static, :fill)
        {:fill, colour} -> colour
        {:stroke, _} -> Map.get(static, :fill)
      end

    case style |> Map.get(:fill, group) |> literal(frame) |> parse() do
      nil ->
        nil

      colour ->
        alpha =
          opacity(Map.get(style, :fill_opacity, Map.get(static, :fill_opacity))) *
            opacity(Map.get(style, :opacity, Map.get(static, :opacity))) * colour.opacity

        over(colour, alpha, parse(frame.theme.background))
    end
  end

  # A fill as the literal it is drawn in: a CSS reference by its fallback, a paint by its
  # first stop, a string as itself.
  defp literal("var(" <> rest, _frame) do
    case String.split(rest, ",", parts: 2) do
      [_name, fallback] -> fallback |> String.trim() |> String.replace_suffix(")", "")
      _no_fallback -> nil
    end
  end

  defp literal(string, _frame) when is_binary(string), do: string
  defp literal({:paint, name}, frame), do: Defs.literal(name, frame)
  defp literal(_none, _frame), do: nil

  defp parse(nil), do: nil
  defp parse(string), do: Color.parse(string)

  defp opacity(n) when is_number(n), do: min(max(n, 0), 1)
  defp opacity(_absent), do: 1

  defp over(colour, alpha, background) when alpha >= 1 or background == nil,
    do: %{colour | opacity: 1.0}

  defp over(colour, alpha, background),
    do: %{Color.interpolate_rgb(background, colour, alpha) | opacity: 1.0}

  # The width an element offers its label: a rectangle's, a circle's diameter, a sector's
  # arc length at the label's own radius; `nil` for a type with no extent.
  defp extent(%{bounds: {_x, _y, w, _h}}, _point, _centre), do: w
  defp extent(%{extent: w}, _point, _centre), do: w

  defp extent(%{span: span}, {x, y}, {cx, cy}),
    do: span * :math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy))

  defp extent(_shape, _point, _centre), do: nil

  # The characters that fit a width: the inverse of `Text.width/2`, the estimate the
  # legend's layout makes too (§4.5).
  @em_per_char Text.width("x", 1)

  defp fit(:none, content, _width, _font_size), do: content
  defp fit(_fit, content, nil, _font_size), do: content

  defp fit(fit, content, width, font_size) do
    room = trunc(width / (@em_per_char * font_size))
    length = String.length(content)

    cond do
      length <= room -> content
      fit == :hide -> nil
      room <= 1 -> nil
      true -> String.slice(content, 0, room - 1) <> "…"
    end
  end

  # A label on a rectangle — at any anchor but an edge anchor, which sits outside it — is
  # drawn only where the rectangle is as tall as the label's font size, under a `fit` that
  # is not `:none` (spec/14 §5.5, #497): a thin or zero-area cell has no room for a line.
  @edge_anchors [:x0, :x1, :y0, :y1]

  defp held(nil, _fit, _bounds, _anchor, _font_size), do: nil
  defp held(content, :none, _bounds, _anchor, _font_size), do: content
  defp held(content, _fit, nil, _anchor, _font_size), do: content
  defp held(content, _fit, _bounds, anchor, _font_size) when anchor in @edge_anchors, do: content
  defp held(_content, _fit, {_x, _y, _w, h}, _anchor, font_size) when h < font_size, do: nil
  defp held(content, _fit, _bounds, _anchor, _font_size), do: content

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
