defmodule Visualize.Backend.SVG do
  @moduledoc """
  SVG rendering backend.

  Converts IR elements and paths to SVG strings/iolists.
  """

  @behaviour Visualize.Backend

  alias Visualize.IR.{Element, Path, Transform}

  @self_closing_tags ~w(circle ellipse line path polygon polyline rect image use stop)a

  # ============================================================
  # Backend Callbacks
  # ============================================================

  @impl true
  @spec path_data(Path.t()) :: String.t()
  def path_data(%Path{commands: commands}) do
    commands
    |> Enum.map(&command_to_string/1)
    |> Enum.join("")
  end

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
      viewBox: view_box
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

  defp do_render_element(%Element{type: :root, attrs: attrs, children: children}) do
    svg_attrs =
      %{xmlns: "http://www.w3.org/2000/svg"}
      |> Map.merge(%{
        width: attrs[:width],
        height: attrs[:height],
        viewBox: attrs[:view_box]
      })

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

  defp render_svg_tag(tag, attrs, children, content)
       when tag in @self_closing_tags and children == [] and content == nil do
    ["<", Atom.to_string(tag), render_attrs(attrs), "/>"]
  end

  defp render_svg_tag(tag, attrs, children, content) do
    tag_str = Atom.to_string(tag)

    [
      "<",
      tag_str,
      render_attrs(attrs),
      ">",
      render_content(content),
      children,
      "</",
      tag_str,
      ">"
    ]
  end

  defp render_attrs(attrs) when map_size(attrs) == 0, do: []

  defp render_attrs(attrs) do
    attrs
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.sort_by(fn {k, _} -> Atom.to_string(k) end)
    |> Enum.map(fn {key, value} ->
      [" ", attr_name(key), "=\"", escape_attr(value), "\""]
    end)
  end

  defp render_content(nil), do: []
  defp render_content(text), do: escape_html(text)

  # ============================================================
  # Attribute Helpers
  # ============================================================

  defp attr_name(key) do
    key
    |> Atom.to_string()
    |> String.replace("_", "-")
  end

  defp escape_attr(value) when is_binary(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("\"", "&quot;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp escape_attr(value) when is_number(value), do: to_string(value)
  defp escape_attr(value) when is_atom(value), do: Atom.to_string(value)
  defp escape_attr(value), do: to_string(value)

  defp escape_html(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp escape_html(text), do: to_string(text)

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

  defp maybe_add_transform(attrs, %Transform{operations: []}) do
    attrs
  end

  defp maybe_add_transform(attrs, %Transform{operations: ops}) do
    transform_str =
      ops
      |> Enum.map(&transform_to_string/1)
      |> Enum.join(" ")

    Map.put(attrs, :transform, transform_str)
  end

  defp transform_to_string({:translate, x, y}), do: "translate(#{format_num(x)},#{format_num(y)})"
  defp transform_to_string({:rotate, angle}), do: "rotate(#{format_num(angle)})"

  defp transform_to_string({:rotate, angle, cx, cy}),
    do: "rotate(#{format_num(angle)},#{format_num(cx)},#{format_num(cy)})"

  defp transform_to_string({:scale, sx, sy}), do: "scale(#{format_num(sx)},#{format_num(sy)})"
  defp transform_to_string({:skew_x, angle}), do: "skewX(#{format_num(angle)})"
  defp transform_to_string({:skew_y, angle}), do: "skewY(#{format_num(angle)})"

  defp transform_to_string({:matrix, a, b, c, d, e, f}),
    do:
      "matrix(#{format_num(a)},#{format_num(b)},#{format_num(c)},#{format_num(d)},#{format_num(e)},#{format_num(f)})"

  # ============================================================
  # Path Command Conversion
  # ============================================================

  defp command_to_string({:M, x, y}), do: "M#{format_num(x)},#{format_num(y)}"
  defp command_to_string({:m, dx, dy}), do: "m#{format_num(dx)},#{format_num(dy)}"
  defp command_to_string({:L, x, y}), do: "L#{format_num(x)},#{format_num(y)}"
  defp command_to_string({:l, dx, dy}), do: "l#{format_num(dx)},#{format_num(dy)}"
  defp command_to_string({:H, x}), do: "H#{format_num(x)}"
  defp command_to_string({:h, dx}), do: "h#{format_num(dx)}"
  defp command_to_string({:V, y}), do: "V#{format_num(y)}"
  defp command_to_string({:v, dy}), do: "v#{format_num(dy)}"

  defp command_to_string({:C, x1, y1, x2, y2, x, y}) do
    "C#{format_num(x1)},#{format_num(y1)},#{format_num(x2)},#{format_num(y2)},#{format_num(x)},#{format_num(y)}"
  end

  defp command_to_string({:c, dx1, dy1, dx2, dy2, dx, dy}) do
    "c#{format_num(dx1)},#{format_num(dy1)},#{format_num(dx2)},#{format_num(dy2)},#{format_num(dx)},#{format_num(dy)}"
  end

  defp command_to_string({:S, x2, y2, x, y}) do
    "S#{format_num(x2)},#{format_num(y2)},#{format_num(x)},#{format_num(y)}"
  end

  defp command_to_string({:s, dx2, dy2, dx, dy}) do
    "s#{format_num(dx2)},#{format_num(dy2)},#{format_num(dx)},#{format_num(dy)}"
  end

  defp command_to_string({:Q, x1, y1, x, y}) do
    "Q#{format_num(x1)},#{format_num(y1)},#{format_num(x)},#{format_num(y)}"
  end

  defp command_to_string({:q, dx1, dy1, dx, dy}) do
    "q#{format_num(dx1)},#{format_num(dy1)},#{format_num(dx)},#{format_num(dy)}"
  end

  defp command_to_string({:T, x, y}), do: "T#{format_num(x)},#{format_num(y)}"
  defp command_to_string({:t, dx, dy}), do: "t#{format_num(dx)},#{format_num(dy)}"

  defp command_to_string({:A, rx, ry, rot, large, sweep, x, y}) do
    "A#{format_num(rx)},#{format_num(ry)},#{format_num(rot)},#{large},#{sweep},#{format_num(x)},#{format_num(y)}"
  end

  defp command_to_string({:a, rx, ry, rot, large, sweep, dx, dy}) do
    "a#{format_num(rx)},#{format_num(ry)},#{format_num(rot)},#{large},#{sweep},#{format_num(dx)},#{format_num(dy)}"
  end

  defp command_to_string(:Z), do: "Z"

  # ============================================================
  # Number Formatting
  # ============================================================

  defp format_num(n) when is_integer(n), do: Integer.to_string(n)

  defp format_num(n) when is_float(n) do
    n
    |> Float.round(4)
    |> Float.to_string()
    |> String.trim_trailing("0")
    |> String.trim_trailing(".")
  end

  defp format_points(points) when is_list(points) do
    points
    |> Enum.map(fn {x, y} -> "#{format_num(x)},#{format_num(y)}" end)
    |> Enum.join(" ")
  end

  defp format_points(points) when is_binary(points), do: points
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
