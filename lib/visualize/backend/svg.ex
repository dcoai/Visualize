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

  # The one `d` serialisation is `Visualize.IR.Path.to_string/1` (D-12).
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
    do_render_element(element)
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

  # ============================================================
  # Element Rendering
  # ============================================================

  defp do_render_element(%Element{
         type: :path,
         path: path,
         style: style,
         transform: transform,
         attrs: extra_attrs
       }) do
    attrs =
      extra_attrs
      |> Map.merge(style_to_attrs(style))
      |> Map.put(:d, path_data(path))
      |> maybe_add_transform(transform)

    render_svg_tag(:path, attrs, [], nil)
  end

  # `vector-effect` does not inherit (spec/09 §2.5, spec/14 §3.9): a group's is written on
  # each child that does not set its own, never on the group.
  defp do_render_element(%Element{type: :group, style: %{vector_effect: effect} = style} = group) do
    children =
      Enum.map(group.children, fn child ->
        %{child | style: Map.put_new(child.style, :vector_effect, effect)}
      end)

    do_render_element(%{group | style: Map.delete(style, :vector_effect), children: children})
  end

  defp do_render_element(%Element{
         type: :group,
         children: children,
         style: style,
         transform: transform,
         attrs: extra_attrs
       }) do
    attrs =
      style_to_attrs(style)
      |> Map.merge(extra_attrs)
      |> maybe_add_transform(transform)

    child_content = Enum.map(children, &do_render_element/1)
    render_svg_tag(:g, attrs, child_content, nil)
  end

  # A clipped element (spec/02 §2.1, spec/09 §2.3): its definition — a clipPath holding
  # the shape, or a mask of everything but it — then the element referring to it.
  defp do_render_element(%Element{clip: %{shape: shape, keep: keep}} = element) do
    id =
      "vis-#{if(keep == :inside, do: "clip", else: "mask")}-#{Integer.to_string(:erlang.phash2(shape), 36) |> String.downcase()}"

    bare = %{element | clip: nil}

    case keep do
      :inside ->
        [
          render_svg_tag(:clipPath, %{id: id}, [do_render_element(shape)], nil),
          do_render_element(Element.set_attrs(bare, %{clip_path: "url(##{id})"}))
        ]

      :outside ->
        extent = %{x: -100_000, y: -100_000, width: 200_000, height: 200_000}
        white = Element.rect(extent.x, extent.y, extent.width, extent.height, %{fill: "white"})

        [
          render_svg_tag(
            :mask,
            Map.merge(%{id: id, mask_units: "userSpaceOnUse"}, extent),
            [do_render_element(white), do_render_element(%{shape | style: %{fill: "black"}})],
            nil
          ),
          do_render_element(Element.set_attrs(bare, %{mask: "url(##{id})"}))
        ]
    end
  end

  # A title or desc is its content, escaped, under its attrs (the id); no style (D-56).
  defp do_render_element(%Element{type: type, attrs: attrs, content: content})
       when type in [:title, :desc, :style] do
    render_svg_tag(type, attrs, [], content || "")
  end

  # A root's `view_box` attr renders as `viewBox` through the shared attribute names
  # (D-11); its style and transform are ignored.
  defp do_render_element(%Element{type: :root, attrs: attrs, children: children}) do
    svg_attrs = Map.merge(%{xmlns: "http://www.w3.org/2000/svg"}, attrs)
    child_content = Enum.map(children, &do_render_element/1)
    render_svg_tag(:svg, svg_attrs, child_content, nil)
  end

  defp do_render_element(%Element{
         type: :rect,
         attrs: attrs,
         style: style,
         transform: transform
       }) do
    all_attrs =
      Map.merge(attrs, style_to_attrs(style))
      |> maybe_add_transform(transform)

    render_svg_tag(:rect, all_attrs, [], nil)
  end

  defp do_render_element(%Element{
         type: :circle,
         attrs: attrs,
         style: style,
         transform: transform
       }) do
    all_attrs =
      Map.merge(attrs, style_to_attrs(style))
      |> maybe_add_transform(transform)

    render_svg_tag(:circle, all_attrs, [], nil)
  end

  defp do_render_element(%Element{
         type: :ellipse,
         attrs: attrs,
         style: style,
         transform: transform
       }) do
    all_attrs =
      Map.merge(attrs, style_to_attrs(style))
      |> maybe_add_transform(transform)

    render_svg_tag(:ellipse, all_attrs, [], nil)
  end

  defp do_render_element(%Element{type: :line, attrs: attrs, style: style, transform: transform}) do
    all_attrs =
      Map.merge(attrs, style_to_attrs(style))
      |> maybe_add_transform(transform)

    render_svg_tag(:line, all_attrs, [], nil)
  end

  defp do_render_element(%Element{
         type: :polyline,
         attrs: attrs,
         style: style,
         transform: transform
       }) do
    points_str = format_points(attrs[:points])

    all_attrs =
      %{points: points_str}
      |> Map.merge(style_to_attrs(style))
      |> maybe_add_transform(transform)

    render_svg_tag(:polyline, all_attrs, [], nil)
  end

  defp do_render_element(%Element{
         type: :polygon,
         attrs: attrs,
         style: style,
         transform: transform
       }) do
    points_str = format_points(attrs[:points])

    all_attrs =
      %{points: points_str}
      |> Map.merge(style_to_attrs(style))
      |> maybe_add_transform(transform)

    render_svg_tag(:polygon, all_attrs, [], nil)
  end

  defp do_render_element(%Element{
         type: :text,
         attrs: attrs,
         style: style,
         content: content,
         children: children,
         transform: transform
       }) do
    all_attrs =
      Map.merge(attrs, style_to_attrs(style))
      |> maybe_add_transform(transform)

    render_svg_tag(:text, all_attrs, Enum.map(children, &do_render_element/1), content)
  end

  # A line of a text (spec/14 §7.1): its attrs and its content, no style of its own.
  defp do_render_element(%Element{type: :tspan, attrs: attrs, content: content}),
    do: render_svg_tag(:tspan, attrs, [], content || "")

  defp do_render_element(%Element{
         type: :image,
         attrs: attrs,
         style: style,
         transform: transform
       }) do
    all_attrs =
      Map.merge(attrs, style_to_attrs(style))
      |> maybe_add_transform(transform)

    render_svg_tag(:image, all_attrs, [], nil)
  end

  defp do_render_element(%Element{type: :defs, children: children}) do
    child_content = Enum.map(children, &do_render_element/1)
    render_svg_tag(:defs, %{}, child_content, nil)
  end

  defp do_render_element(%Element{type: :clip_path, attrs: attrs, children: children}) do
    child_content = Enum.map(children, &do_render_element/1)
    render_svg_tag(:clipPath, attrs, child_content, nil)
  end

  defp do_render_element(%Element{type: :linear_gradient, attrs: attrs, children: children}) do
    child_content = Enum.map(children, &do_render_element/1)
    render_svg_tag(:linearGradient, attrs, child_content, nil)
  end

  defp do_render_element(%Element{type: :radial_gradient, attrs: attrs, children: children}) do
    child_content = Enum.map(children, &do_render_element/1)
    render_svg_tag(:radialGradient, attrs, child_content, nil)
  end

  # A hatch's tile (spec/09 §2.3, #673).
  defp do_render_element(%Element{type: :pattern, attrs: attrs, children: children}) do
    child_content = Enum.map(children, &do_render_element/1)
    render_svg_tag(:pattern, attrs, child_content, nil)
  end

  defp do_render_element(%Element{type: :filter, attrs: attrs, children: children}) do
    child_content = Enum.map(children, &do_render_element/1)
    render_svg_tag(:filter, attrs, child_content, nil)
  end

  defp do_render_element(%Element{type: :fe_drop_shadow, attrs: attrs}),
    do: render_svg_tag(:feDropShadow, attrs, [], nil)

  defp do_render_element(%Element{type: :fe_gaussian_blur, attrs: attrs}),
    do: render_svg_tag(:feGaussianBlur, attrs, [], nil)

  defp do_render_element(%Element{type: :stop, attrs: attrs, style: style}) do
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

  defp style_to_attrs(style) when map_size(style) == 0, do: %{}

  defp style_to_attrs(style) do
    style
    |> effects()
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.map(fn
      {:fill, :none} -> {:fill, "none"}
      {:fill, :current_color} -> {:fill, "currentColor"}
      {:stroke, :none} -> {:stroke, "none"}
      {:stroke, :current_color} -> {:stroke, "currentColor"}
      {key, %Paint{} = paint} when key in [:fill, :stroke] -> {key, Paint.url(paint)}
      {:text_anchor, :start} -> {:text_anchor, "start"}
      {:text_anchor, :middle} -> {:text_anchor, "middle"}
      {:text_anchor, :end} -> {:text_anchor, "end"}
      {:stroke_linecap, v} -> {:stroke_linecap, Atom.to_string(v)}
      {:stroke_linejoin, v} -> {:stroke_linejoin, Atom.to_string(v)}
      {:dominant_baseline, v} when is_atom(v) -> {:dominant_baseline, Atom.to_string(v)}
      {:vector_effect, :non_scaling_stroke} -> {:vector_effect, "non-scaling-stroke"}
      {k, v} -> {k, v}
    end)
    |> Map.new()
  end

  # A blend is an inline style (spec/09 §2.5), an effect a filter reference to the filter
  # the frame declared for its pair (spec/14 §2.7); the radius alone says nothing.
  defp effects(style) do
    # A line height is the frame's to apply (spec/14 §7.1), never an attribute; a motion is
    # a class the frame wrote in `:css`, and in any other SVG the end state (spec/09 §2.5).
    style = Map.drop(style, [:line_height, :transition])
    {blend, style} = Map.pop(style, :blend)
    {effect, style} = Map.pop(style, :effect)
    {radius, style} = Map.pop(style, :effect_radius)
    {offset, style} = Map.pop(style, :effect_offset)
    {color, style} = Map.pop(style, :effect_color)

    style
    |> then(
      &if(blend in [nil, :normal], do: &1, else: Map.put(&1, :style, "mix-blend-mode: #{blend}"))
    )
    |> then(
      &if(effect in [nil, :none],
        do: &1,
        else: Map.put(&1, :filter, "url(##{effect_id(effect, radius, offset, color)})")
      )
    )
  end

  @doc false
  # The id of the filter an effect shares (spec/14 §2.7): its type and radius, and for a
  # shadow with an offset or a colour a hash of the two (#674), so a shadow with neither
  # keeps the id it always had.
  @spec effect_id(atom(), number() | nil, [number()] | nil, String.t() | nil) :: String.t()
  def effect_id(effect, radius, offset \\ nil, color \\ nil)

  def effect_id(:shadow, radius, offset, color) when offset != nil or color != nil do
    h = {offset, color} |> :erlang.phash2() |> Integer.to_string(36) |> String.downcase()
    "vis-effect-shadow-#{radius || 3}-#{h}"
  end

  def effect_id(effect, radius, _offset, _color), do: "vis-effect-#{effect}-#{radius || 3}"

  defp maybe_add_transform(attrs, nil), do: attrs
  defp maybe_add_transform(attrs, %Transform{operations: []}), do: attrs

  # The one transform serialisation is `Visualize.IR.Transform.to_string/1`.
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
