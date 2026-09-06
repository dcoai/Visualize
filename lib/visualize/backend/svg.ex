defmodule Visualize.Backend.SVG do
  @moduledoc """
  SVG rendering backend.

  Converts IR elements and paths to SVG strings/iolists.
  """

  @behaviour Visualize.Backend

  alias Visualize.IR.{Element, Path, Transform}
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

  defp do_render_element(%Element{type: :path, path: path, style: style, transform: transform}) do
    attrs =
      style_to_attrs(style)
      |> Map.put(:d, path_data(path))
      |> maybe_add_transform(transform)

    render_svg_tag(:path, attrs, [], nil)
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
         transform: transform
       }) do
    all_attrs =
      Map.merge(attrs, style_to_attrs(style))
      |> maybe_add_transform(transform)

    render_svg_tag(:text, all_attrs, [], content)
  end

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
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.map(fn
      {:fill, :none} -> {:fill, "none"}
      {:fill, :current_color} -> {:fill, "currentColor"}
      {:stroke, :none} -> {:stroke, "none"}
      {:stroke, :current_color} -> {:stroke, "currentColor"}
      {:text_anchor, :start} -> {:text_anchor, "start"}
      {:text_anchor, :middle} -> {:text_anchor, "middle"}
      {:text_anchor, :end} -> {:text_anchor, "end"}
      {:stroke_linecap, v} -> {:stroke_linecap, Atom.to_string(v)}
      {:stroke_linejoin, v} -> {:stroke_linejoin, Atom.to_string(v)}
      {:dominant_baseline, v} when is_atom(v) -> {:dominant_baseline, Atom.to_string(v)}
      {k, v} -> {k, v}
    end)
    |> Map.new()
  end

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
