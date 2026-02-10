defmodule Visualize.SVG.Element do
  @moduledoc """
  Represents an SVG element as an Elixir data structure.

  Elements can be nested and rendered to SVG strings or used directly
  in LiveView templates.
  """

  alias Visualize.IR

  defstruct [:tag, :attrs, :children, :content]

  @type t :: %__MODULE__{
          tag: atom(),
          attrs: map(),
          children: [t()],
          content: String.t() | nil
        }

  @doc """
  Creates a new SVG element.

  ## Examples

      iex> Visualize.SVG.Element.new(:rect, %{x: 0, y: 0, width: 100, height: 50})
      %Visualize.SVG.Element{tag: :rect, attrs: %{x: 0, y: 0, width: 100, height: 50}, children: [], content: nil}

  """
  @spec new(atom(), map()) :: t()
  def new(tag, attrs \\ %{}) do
    %__MODULE__{
      tag: tag,
      attrs: attrs,
      children: [],
      content: nil
    }
  end

  @doc """
  Sets attributes on an element.
  """
  @spec attrs(t(), map() | keyword()) :: t()
  def attrs(%__MODULE__{} = element, new_attrs) when is_map(new_attrs) do
    %{element | attrs: Map.merge(element.attrs, new_attrs)}
  end

  def attrs(%__MODULE__{} = element, new_attrs) when is_list(new_attrs) do
    attrs(element, Map.new(new_attrs))
  end

  @doc """
  Appends a child element. Also accepts IR.Element which will be converted.
  """
  @spec append(t(), t() | IR.Element.t() | [t() | IR.Element.t()]) :: t()
  def append(%__MODULE__{} = parent, %__MODULE__{} = child) do
    %{parent | children: parent.children ++ [child]}
  end

  def append(%__MODULE__{} = parent, %IR.Element{} = ir_child) do
    svg_child = from_ir(ir_child)
    %{parent | children: parent.children ++ [svg_child]}
  end

  def append(%__MODULE__{} = parent, children) when is_list(children) do
    svg_children = Enum.map(children, fn
      %__MODULE__{} = el -> el
      %IR.Element{} = ir -> from_ir(ir)
    end)
    %{parent | children: parent.children ++ svg_children}
  end

  @doc """
  Converts an IR.Element to an SVG.Element.
  """
  @spec from_ir(IR.Element.t()) :: t()
  def from_ir(%IR.Element{} = ir) do
    tag = ir_type_to_tag(ir.type)
    attrs = build_attrs(ir)
    children = Enum.map(ir.children, &from_ir/1)
    content = ir.content

    %__MODULE__{
      tag: tag,
      attrs: attrs,
      children: children,
      content: content
    }
  end

  defp ir_type_to_tag(:group), do: :g
  defp ir_type_to_tag(:root), do: :svg
  defp ir_type_to_tag(:clip_path), do: :clipPath
  defp ir_type_to_tag(:linear_gradient), do: :linearGradient
  defp ir_type_to_tag(:radial_gradient), do: :radialGradient
  defp ir_type_to_tag(type), do: type

  defp build_attrs(%IR.Element{} = ir) do
    # Start with geometric attrs
    attrs = ir.attrs

    # Add path data if present
    attrs = if ir.path do
      Map.put(attrs, :d, IR.Path.to_string(ir.path))
    else
      attrs
    end

    # Add transform if present
    attrs = if ir.transform do
      Map.put(attrs, :transform, IR.Transform.to_string(ir.transform))
    else
      attrs
    end

    # Convert style to SVG attributes
    style_attrs = style_to_attrs(ir.style)
    Map.merge(attrs, style_attrs)
  end

  defp style_to_attrs(style) when map_size(style) == 0, do: %{}
  defp style_to_attrs(style) do
    style
    |> Enum.map(fn {key, value} ->
      svg_key = style_key_to_svg(key)
      svg_value = style_value_to_svg(value)
      {svg_key, svg_value}
    end)
    |> Map.new()
  end

  defp style_key_to_svg(:stroke_width), do: :"stroke-width"
  defp style_key_to_svg(:stroke_linecap), do: :"stroke-linecap"
  defp style_key_to_svg(:stroke_linejoin), do: :"stroke-linejoin"
  defp style_key_to_svg(:stroke_dasharray), do: :"stroke-dasharray"
  defp style_key_to_svg(:fill_opacity), do: :"fill-opacity"
  defp style_key_to_svg(:stroke_opacity), do: :"stroke-opacity"
  defp style_key_to_svg(:font_size), do: :"font-size"
  defp style_key_to_svg(:font_family), do: :"font-family"
  defp style_key_to_svg(:font_weight), do: :"font-weight"
  defp style_key_to_svg(:text_anchor), do: :"text-anchor"
  defp style_key_to_svg(:dominant_baseline), do: :"dominant-baseline"
  defp style_key_to_svg(:stop_color), do: :"stop-color"
  defp style_key_to_svg(:stop_opacity), do: :"stop-opacity"
  defp style_key_to_svg(key), do: key

  defp style_value_to_svg(:none), do: "none"
  defp style_value_to_svg(:current_color), do: "currentColor"
  defp style_value_to_svg(:start), do: "start"
  defp style_value_to_svg(:middle), do: "middle"
  defp style_value_to_svg(:end), do: "end"
  defp style_value_to_svg(:butt), do: "butt"
  defp style_value_to_svg(:round), do: "round"
  defp style_value_to_svg(:square), do: "square"
  defp style_value_to_svg(:miter), do: "miter"
  defp style_value_to_svg(:bevel), do: "bevel"
  defp style_value_to_svg(:bold), do: "bold"
  defp style_value_to_svg(value), do: value

  @doc """
  Sets text content for the element.
  """
  @spec content(t(), String.t()) :: t()
  def content(%__MODULE__{} = element, text) do
    %{element | content: text}
  end

  @doc """
  Common SVG element constructors.
  """
  def svg(attrs \\ %{}), do: new(:svg, Map.merge(%{xmlns: "http://www.w3.org/2000/svg"}, to_map(attrs)))
  def g(attrs \\ %{}), do: new(:g, to_map(attrs))
  def rect(attrs \\ %{}), do: new(:rect, to_map(attrs))
  def circle(attrs \\ %{}), do: new(:circle, to_map(attrs))
  def ellipse(attrs \\ %{}), do: new(:ellipse, to_map(attrs))
  def line(attrs \\ %{}), do: new(:line, to_map(attrs))
  def polyline(attrs \\ %{}), do: new(:polyline, to_map(attrs))
  def polygon(attrs \\ %{}), do: new(:polygon, to_map(attrs))
  def path(attrs \\ %{}), do: new(:path, to_map(attrs))
  def text(attrs \\ %{}), do: new(:text, to_map(attrs))
  def tspan(attrs \\ %{}), do: new(:tspan, to_map(attrs))
  def defs(attrs \\ %{}), do: new(:defs, to_map(attrs))
  def clipPath(attrs \\ %{}), do: new(:clipPath, to_map(attrs))
  def linearGradient(attrs \\ %{}), do: new(:linearGradient, to_map(attrs))
  def radialGradient(attrs \\ %{}), do: new(:radialGradient, to_map(attrs))
  def stop(attrs \\ %{}), do: new(:stop, to_map(attrs))
  def title(attrs \\ %{}), do: new(:title, to_map(attrs))

  defp to_map(attrs) when is_map(attrs), do: attrs
  defp to_map(attrs) when is_list(attrs), do: Map.new(attrs)
end
