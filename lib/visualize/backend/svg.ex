defmodule Visualize.Backend.SVG do
  @moduledoc """
  SVG rendering backend.

  Converts IR elements and paths to SVG strings/iolists.
  """

  @behaviour Visualize.Backend

  alias Visualize.IR.{Element, Paint, Path, Transform}
  alias Visualize.SVG.Renderer

  # ============================================================
  # Backend Callbacks
  # ============================================================

  # The one `d` serialization is `Visualize.IR.Path.to_string/1` (D-12).
  @impl true
  @spec path_data(Path.t()) :: String.t()
  def path_data(%Path{} = path), do: Path.to_string(path)

  @impl true
  @spec render_path(Path.t(), keyword()) :: iolist()
  def render_path(%Path{} = path, opts \\ []) do
    d = path_data(path)
    style = Keyword.get(opts, :style, %{})
    attrs = style_to_attrs(style) |> Map.put(:d, d)
    render_svg_tag(:path, attrs, [], nil)
  end

  @impl true
  @spec render_element(Element.t(), keyword()) :: iolist()
  def render_element(%Element{} = element, _opts \\ []) do
    do_render_element(element, %{})
  end

  @impl true
  @spec render_scene([Element.t()], keyword()) :: iolist()
  def render_scene(elements, opts \\ []) do
    rendered = Enum.map(elements, &render_element(&1, opts))

    if Keyword.get(opts, :wrap, true) do
      wrap_root(rendered, opts)
    else
      rendered
    end
  end

  @impl true
  @spec wrap_root(iolist(), keyword()) :: iolist()
  def wrap_root(content, opts) do
    width = Keyword.get(opts, :width, 800)
    height = Keyword.get(opts, :height, 600)
    view_box = Keyword.get(opts, :view_box, "0 0 #{width} #{height}")

    attrs = %{
      xmlns: "http://www.w3.org/2000/svg",
      width: width,
      height: height,
      view_box: view_box
    }

    render_svg_tag(:svg, attrs, [content], nil)
  end

  @doc false
  # One step of `Visualize.Render.Segments` (spec/09 §1.4, #813, D-203): a group or the
  # root as its start tag, its end tag and the children written between them, and any
  # other element — one that names its identity or is clipped, whatever its type — as the
  # text `render_element/2` writes for it. The parts concatenate to `render_element/2`. A
  # group passes its children the stroke they inherit, so a stroked text under it paints
  # its stroke first (§2.5, D-235).
  @spec segment(Element.t(), map()) ::
          {:leaf, iodata()} | {:node, iodata(), iodata(), [Element.t()], map()}
  def segment(%Element{attrs: %{"data-vis-id" => _}} = element, inherited),
    do: {:leaf, do_render_element(element, inherited)}

  def segment(%Element{clip: %{}} = element, inherited),
    do: {:leaf, do_render_element(element, inherited)}

  def segment(%Element{type: :group, style: %{vector_effect: effect} = style} = group, inherited) do
    children =
      Enum.map(group.children, fn child ->
        %{child | style: Map.put_new(child.style, :vector_effect, effect)}
      end)

    segment(%{group | style: Map.delete(style, :vector_effect), children: children}, inherited)
  end

  def segment(%Element{type: :group, children: [_ | _] = children} = group, inherited) do
    attrs =
      group.style
      |> style_to_attrs()
      |> Map.merge(group.attrs)
      |> maybe_add_transform(group.transform)

    {:node, ["<g", Renderer.render_attrs(attrs), ">"], "</g>", children,
     within(inherited, group.style)}
  end

  def segment(%Element{type: :root, attrs: attrs, children: [_ | _] = children}, inherited) do
    svg_attrs = Map.merge(%{xmlns: "http://www.w3.org/2000/svg"}, attrs)
    {:node, ["<svg", Renderer.render_attrs(svg_attrs), ">"], "</svg>", children, inherited}
  end

  def segment(%Element{} = element, inherited),
    do: {:leaf, do_render_element(element, inherited)}

  # ============================================================
  # Element Rendering
  # ============================================================

  # A clipped element (spec/02 §2.1, spec/09 §2.3): its definition — a clipPath holding
  # the shape, or a mask of everything but it — then the element referring to it. It is
  # matched before every other clause, so a clipped group keeps its clip (D-209).
  defp do_render_element(%Element{clip: %{shape: shape, keep: keep}} = element, inherited) do
    {tag, attrs, children, reference} = clip_definition(shape, keep)

    [
      render_svg_tag(tag, attrs, Enum.map(children, &do_render_element(&1, inherited)), nil),
      do_render_element(Element.set_attrs(%{element | clip: nil}, reference), inherited)
    ]
  end

  defp do_render_element(
         %Element{
           type: :path,
           path: path,
           style: style,
           transform: transform,
           attrs: extra_attrs
         },
         _inherited
       ) do
    attrs =
      extra_attrs
      |> Map.merge(style_to_attrs(style))
      |> Map.put(:d, path_data(path))
      |> maybe_add_transform(transform)

    render_svg_tag(:path, attrs, [], nil)
  end

  # `vector-effect` does not inherit (spec/09 §2.5, spec/14 §3.9): a group's is written on
  # each child that does not set its own, never on the group.
  defp do_render_element(
         %Element{type: :group, style: %{vector_effect: effect} = style} = group,
         inherited
       ) do
    children =
      Enum.map(group.children, fn child ->
        %{child | style: Map.put_new(child.style, :vector_effect, effect)}
      end)

    do_render_element(
      %{group | style: Map.delete(style, :vector_effect), children: children},
      inherited
    )
  end

  defp do_render_element(
         %Element{
           type: :group,
           children: children,
           style: style,
           transform: transform,
           attrs: extra_attrs
         },
         inherited
       ) do
    attrs =
      style_to_attrs(style)
      |> Map.merge(extra_attrs)
      |> maybe_add_transform(transform)

    child_content = Enum.map(children, &do_render_element(&1, within(inherited, style)))
    render_svg_tag(:g, attrs, child_content, nil)
  end

  # A title or desc is its content, escaped, under its attrs (the id); no style (D-56).
  defp do_render_element(%Element{type: type, attrs: attrs, content: content}, _inherited)
       when type in [:title, :desc, :style] do
    render_svg_tag(type, attrs, [], content || "")
  end

  # A root's `view_box` attr renders as `viewBox` through the shared attribute names
  # (D-11); its style and transform are ignored.
  defp do_render_element(%Element{type: :root, attrs: attrs, children: children}, inherited) do
    svg_attrs = Map.merge(%{xmlns: "http://www.w3.org/2000/svg"}, attrs)
    child_content = Enum.map(children, &do_render_element(&1, inherited))
    render_svg_tag(:svg, svg_attrs, child_content, nil)
  end

  defp do_render_element(
         %Element{
           type: :rect,
           attrs: attrs,
           style: style,
           transform: transform
         },
         _inherited
       ) do
    all_attrs =
      Map.merge(attrs, style_to_attrs(style))
      |> maybe_add_transform(transform)

    render_svg_tag(:rect, all_attrs, [], nil)
  end

  defp do_render_element(
         %Element{
           type: :circle,
           attrs: attrs,
           style: style,
           transform: transform
         },
         _inherited
       ) do
    all_attrs =
      Map.merge(attrs, style_to_attrs(style))
      |> maybe_add_transform(transform)

    render_svg_tag(:circle, all_attrs, [], nil)
  end

  defp do_render_element(
         %Element{
           type: :ellipse,
           attrs: attrs,
           style: style,
           transform: transform
         },
         _inherited
       ) do
    all_attrs =
      Map.merge(attrs, style_to_attrs(style))
      |> maybe_add_transform(transform)

    render_svg_tag(:ellipse, all_attrs, [], nil)
  end

  defp do_render_element(
         %Element{type: :line, attrs: attrs, style: style, transform: transform},
         _inherited
       ) do
    all_attrs =
      Map.merge(attrs, style_to_attrs(style))
      |> maybe_add_transform(transform)

    render_svg_tag(:line, all_attrs, [], nil)
  end

  defp do_render_element(
         %Element{
           type: :polyline,
           attrs: attrs,
           style: style,
           transform: transform
         },
         _inherited
       ) do
    points_str = format_points(attrs[:points])

    all_attrs =
      %{points: points_str}
      |> Map.merge(style_to_attrs(style))
      |> maybe_add_transform(transform)

    render_svg_tag(:polyline, all_attrs, [], nil)
  end

  defp do_render_element(
         %Element{
           type: :polygon,
           attrs: attrs,
           style: style,
           transform: transform
         },
         _inherited
       ) do
    points_str = format_points(attrs[:points])

    all_attrs =
      %{points: points_str}
      |> Map.merge(style_to_attrs(style))
      |> maybe_add_transform(transform)

    render_svg_tag(:polygon, all_attrs, [], nil)
  end

  # A stroked text paints its stroke under its fill, its own stroke or its groups' (§2.5,
  # D-235): `paint-order` on the text alone, since it inherits and a group's other shapes
  # paint their outlines over their fills.
  defp do_render_element(
         %Element{
           type: :text,
           attrs: attrs,
           style: style,
           content: content,
           children: children,
           transform: transform
         } = text,
         inherited
       ) do
    all_attrs =
      Map.merge(attrs, style_to_attrs(style))
      |> maybe_add_transform(transform)
      |> paint_order(text, inherited)

    render_svg_tag(
      :text,
      all_attrs,
      Enum.map(children, &do_render_element(&1, inherited)),
      content
    )
  end

  # A line of a text (spec/14 §7.1): its attrs and its content, no style of its own.
  defp do_render_element(%Element{type: :tspan, attrs: attrs, content: content}, _inherited),
    do: render_svg_tag(:tspan, attrs, [], content || "")

  defp do_render_element(
         %Element{
           type: :image,
           attrs: attrs,
           style: style,
           transform: transform
         },
         _inherited
       ) do
    all_attrs =
      Map.merge(attrs, style_to_attrs(style))
      |> maybe_add_transform(transform)

    render_svg_tag(:image, all_attrs, [], nil)
  end

  defp do_render_element(%Element{type: :defs, children: children}, inherited) do
    child_content = Enum.map(children, &do_render_element(&1, inherited))
    render_svg_tag(:defs, %{}, child_content, nil)
  end

  defp do_render_element(%Element{type: :clip_path, attrs: attrs, children: children}, inherited) do
    child_content = Enum.map(children, &do_render_element(&1, inherited))
    render_svg_tag(:clipPath, attrs, child_content, nil)
  end

  defp do_render_element(
         %Element{type: :linear_gradient, attrs: attrs, children: children},
         inherited
       ) do
    child_content = Enum.map(children, &do_render_element(&1, inherited))
    render_svg_tag(:linearGradient, attrs, child_content, nil)
  end

  defp do_render_element(
         %Element{type: :radial_gradient, attrs: attrs, children: children},
         inherited
       ) do
    child_content = Enum.map(children, &do_render_element(&1, inherited))
    render_svg_tag(:radialGradient, attrs, child_content, nil)
  end

  # A hatch's tile (spec/09 §2.3, #673).
  defp do_render_element(%Element{type: :pattern, attrs: attrs, children: children}, inherited) do
    child_content = Enum.map(children, &do_render_element(&1, inherited))
    render_svg_tag(:pattern, attrs, child_content, nil)
  end

  defp do_render_element(%Element{type: :filter, attrs: attrs, children: children}, inherited) do
    child_content = Enum.map(children, &do_render_element(&1, inherited))
    render_svg_tag(:filter, attrs, child_content, nil)
  end

  defp do_render_element(%Element{type: :fe_drop_shadow, attrs: attrs}, _inherited),
    do: render_svg_tag(:feDropShadow, attrs, [], nil)

  defp do_render_element(%Element{type: :fe_gaussian_blur, attrs: attrs}, _inherited),
    do: render_svg_tag(:feGaussianBlur, attrs, [], nil)

  defp do_render_element(%Element{type: :stop, attrs: attrs, style: style}, _inherited) do
    all_attrs = Map.merge(attrs, style_to_attrs(style))
    render_svg_tag(:stop, all_attrs, [], nil)
  end

  # ============================================================
  # SVG Tag Rendering
  # ============================================================

  # Attribute names, ordering, escaping and self-closing tags are those of
  # `Visualize.SVG.Renderer`, so the IR backend and the HEEx bridge emit one markup.
  defp render_svg_tag(tag, attrs, [], nil) do
    if Renderer.self_closing?(tag) do
      ["<", Atom.to_string(tag), Renderer.render_attrs(attrs), "/>"]
    else
      ["<", Atom.to_string(tag), Renderer.render_attrs(attrs), "></", Atom.to_string(tag), ">"]
    end
  end

  defp render_svg_tag(tag, attrs, children, content) do
    tag_str = Atom.to_string(tag)

    [
      "<",
      tag_str,
      Renderer.render_attrs(attrs),
      ">",
      render_content(content),
      children,
      "</",
      tag_str,
      ">"
    ]
  end

  defp render_content(nil), do: []
  defp render_content(text), do: Renderer.escape_text(text)

  # ============================================================
  # Style and Transform Helpers
  # ============================================================

  # A line height is the frame's to apply (spec/14 §7.1), never an attribute; a motion is
  # a class the frame wrote in `:css`, and in any other SVG the end state (spec/09 §2.5);
  # a blend and an effect are `effects/2`'s.
  @not_attributes [
    :line_height,
    :transition,
    :animation,
    :enter,
    :exit,
    :blend,
    :effect,
    :effect_radius,
    :effect_offset,
    :effect_color
  ]

  @doc false
  # Whether a style key is the frame's or `effects/2`'s, never an attribute of its own; and
  # the attributes a blend and an effect write. Shared with `Visualize.SVG.Element.from_ir/1`
  # (spec/02 §5.1, D-211).
  @spec not_attribute?(atom()) :: boolean()
  def not_attribute?(key), do: key in @not_attributes

  @doc false
  @spec effect_attrs(map()) :: map()
  def effect_attrs(style), do: effects(%{}, style)

  defp style_to_attrs(style) when map_size(style) == 0, do: %{}

  # One pass over the style (#812): each key an attribute, a `nil` left out, and the
  # blend and effect laid over them as `effects/2` writes them.
  defp style_to_attrs(style) do
    attrs =
      for {key, value} <- style,
          value != nil and key not in @not_attributes,
          into: %{},
          do: attribute(key, value)

    effects(attrs, style)
  end

  defp attribute(:fill, :none), do: {:fill, "none"}
  defp attribute(:fill, :current_color), do: {:fill, "currentColor"}
  defp attribute(:stroke, :none), do: {:stroke, "none"}
  defp attribute(:stroke, :current_color), do: {:stroke, "currentColor"}
  defp attribute(key, %Paint{} = paint) when key in [:fill, :stroke], do: {key, Paint.url(paint)}
  defp attribute(:text_anchor, :start), do: {:text_anchor, "start"}
  defp attribute(:text_anchor, :middle), do: {:text_anchor, "middle"}
  defp attribute(:text_anchor, :end), do: {:text_anchor, "end"}
  defp attribute(:stroke_linecap, v), do: {:stroke_linecap, Atom.to_string(v)}
  defp attribute(:stroke_linejoin, v), do: {:stroke_linejoin, Atom.to_string(v)}

  defp attribute(:dominant_baseline, v) when is_atom(v),
    do: {:dominant_baseline, Atom.to_string(v)}

  defp attribute(:vector_effect, :non_scaling_stroke), do: {:vector_effect, "non-scaling-stroke"}
  defp attribute(key, value), do: {key, value}

  # A blend is an inline style (spec/09 §2.5), an effect a filter reference to the filter
  # the frame declared for its pair (spec/14 §2.7); the radius alone says nothing.
  defp effects(attrs, style) do
    blend = Map.get(style, :blend)
    effect = Map.get(style, :effect)

    attrs
    |> then(
      &if(blend in [nil, :normal],
        do: &1,
        else: Map.put(&1, :style, "mix-blend-mode: #{Visualize.Backend.Canvas.blend_word(blend)}")
      )
    )
    |> then(
      &if(effect in [nil, :none],
        do: &1,
        else:
          Map.put(
            &1,
            :filter,
            "url(##{effect_id(effect, style[:effect_radius], style[:effect_offset], style[:effect_color])})"
          )
      )
    )
  end

  @doc false
  # A clip's definition, as its tag, its attributes and the IR elements it holds, and the
  # attribute that refers to it (spec/09 §2.3): for `:inside` a clipPath holding the shape,
  # for `:outside` a mask of everything — a white square of ±100000 — but the shape, in
  # black. The shape is in the referring element's user space (D-211). Shared with
  # `Visualize.SVG.Element.from_ir/1`, so the two bridges write one definition.
  @spec clip_definition(Element.t(), :inside | :outside) ::
          {atom(), map(), [Element.t()], %{atom() => String.t()}}
  def clip_definition(shape, keep) do
    h = shape |> :erlang.phash2() |> Integer.to_string(36) |> String.downcase()

    case keep do
      :inside ->
        id = "vis-clip-#{h}"
        {:clipPath, %{id: id}, [shape], %{clip_path: "url(##{id})"}}

      :outside ->
        id = "vis-mask-#{h}"
        extent = %{x: -100_000, y: -100_000, width: 200_000, height: 200_000}
        white = Element.rect(extent.x, extent.y, extent.width, extent.height, %{fill: "white"})

        {:mask, Map.merge(%{id: id, mask_units: "userSpaceOnUse"}, extent),
         [white, %{shape | style: %{fill: "black"}}], %{mask: "url(##{id})"}}
    end
  end

  @doc false
  # The id of the filter an effect shares (spec/14 §2.7): its type and radius, and for a
  # shadow with an offset or a color a hash of the two (#674), so a shadow with neither
  # keeps the id it always had.
  @spec effect_id(atom(), number() | nil, [number()] | nil, String.t() | nil) :: String.t()
  def effect_id(effect, radius, offset \\ nil, color \\ nil)

  def effect_id(:shadow, radius, offset, color) when offset != nil or color != nil do
    h = {offset, color} |> :erlang.phash2() |> Integer.to_string(36) |> String.downcase()
    "vis-effect-shadow-#{radius || 3}-#{h}"
  end

  def effect_id(effect, radius, _offset, _color), do: "vis-effect-#{effect}-#{radius || 3}"

  defp paint_order(attrs, text, inherited) do
    if Element.stroke_first?(text, inherited),
      do: Map.put(attrs, :paint_order, "stroke"),
      else: attrs
  end

  @doc false
  # The style a group's children inherit, as far as an SVG writer reads it: the stroke, the
  # group's own when it sets one, else the one the group inherits (§2.5, D-235). Shared with
  # `Visualize.SVG.Element.from_ir/1`.
  @spec within(map(), map()) :: map()
  def within(_inherited, %{stroke: stroke}) when not is_nil(stroke), do: %{stroke: stroke}
  def within(inherited, _style), do: inherited

  defp maybe_add_transform(attrs, nil), do: attrs
  defp maybe_add_transform(attrs, %Transform{operations: []}), do: attrs

  # The one transform serialization is `Visualize.IR.Transform.to_string/1`.
  defp maybe_add_transform(attrs, %Transform{} = transform),
    do: Map.put(attrs, :transform, Transform.to_string(transform))

  # ============================================================
  # Point Data
  # ============================================================

  @doc false
  # `points` for `:polyline`/`:polygon`: `x,y` pairs joined by single spaces, numbers
  # formatted as path data is; a binary is emitted verbatim.
  def format_points(points) when is_list(points) do
    points
    |> Enum.map(fn {x, y} -> "#{format_num(x)},#{format_num(y)}" end)
    |> Enum.join(" ")
  end

  def format_points(points) when is_binary(points), do: points

  defp format_num(n), do: Path.format_number(n)
end

# Protocol implementations for IR.Element
defimpl String.Chars, for: Visualize.IR.Element do
  def to_string(element) do
    element
    |> Visualize.Backend.SVG.render_element([])
    |> IO.iodata_to_binary()
  end
end

# Conditionally implement Phoenix.HTML.Safe if Phoenix is available
if Code.ensure_loaded?(Phoenix.HTML.Safe) do
  defimpl Phoenix.HTML.Safe, for: Visualize.IR.Element do
    def to_iodata(element) do
      Visualize.Backend.SVG.render_element(element, [])
    end
  end
end
