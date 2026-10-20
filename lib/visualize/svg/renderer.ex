defmodule Visualize.SVG.Renderer do
  @moduledoc """
  Renders SVG elements to strings or iolists.

  Optimized for efficient string building using iolists.
  """

  alias Visualize.SVG.Element

  @self_closing_tags ~w(circle ellipse line path polygon polyline rect image use stop feDropShadow feGaussianBlur)a

  # SVG attribute names that are camel-cased rather than hyphenated (D-11). Every other
  # snake_case key is a presentation attribute and hyphenates.
  @camel_case %{
    view_box: "viewBox",
    preserve_aspect_ratio: "preserveAspectRatio",
    gradient_units: "gradientUnits",
    gradient_transform: "gradientTransform",
    pattern_units: "patternUnits",
    pattern_transform: "patternTransform",
    clip_path_units: "clipPathUnits",
    mask_units: "maskUnits",
    std_deviation: "stdDeviation",
    marker_width: "markerWidth",
    marker_height: "markerHeight",
    marker_units: "markerUnits",
    ref_x: "refX",
    ref_y: "refY",
    spread_method: "spreadMethod",
    text_length: "textLength",
    length_adjust: "lengthAdjust"
  }

  @doc """
  Renders an SVG element tree to an iolist.

  Using iolists is more efficient than string concatenation
  and works well with Phoenix/LiveView.
  """
  @spec render(Element.t()) :: iolist()
  def render(%Element{} = element) do
    render_element(element)
  end

  @doc """
  Renders an SVG element tree to a string.
  """
  @spec render_to_string(Element.t()) :: String.t()
  def render_to_string(%Element{} = element) do
    element
    |> render()
    |> IO.iodata_to_binary()
  end

  @doc """
  The SVG attribute name for an attribute key, shared by every SVG serializer (D-11).

  A snake_case key hyphenates (`:stroke_width` → `"stroke-width"`) unless it names one of
  the camel-cased SVG attributes (`:view_box` → `"viewBox"`, `:preserve_aspect_ratio`,
  `:gradient_units`, `:pattern_units`, `:clip_path_units`, `:marker_width`,
  `:marker_height`, `:ref_x`, `:ref_y`, …); an already camel-cased atom and a binary key
  pass through unchanged.

  ## Examples

      iex> Visualize.SVG.Renderer.attribute_name(:stroke_width)
      "stroke-width"
      iex> Visualize.SVG.Renderer.attribute_name(:view_box)
      "viewBox"
      iex> Visualize.SVG.Renderer.attribute_name(:viewBox)
      "viewBox"

  """
  @spec attribute_name(atom() | String.t()) :: String.t()
  def attribute_name(key) when is_atom(key) do
    case Map.fetch(@camel_case, key) do
      {:ok, name} -> name
      :error -> key |> Atom.to_string() |> :binary.replace("_", "-", [:global])
    end
  end

  def attribute_name(key) when is_binary(key), do: key

  @doc false
  # Attributes with a `nil` value are omitted; the rest are emitted sorted by their SVG
  # name, values escaped. `Visualize.Backend.SVG` renders through this too.
  def render_attrs(attrs) when map_size(attrs) == 0, do: []

  def render_attrs(attrs) do
    named = for {key, value} <- attrs, value != nil, do: {attribute_name(key), value}

    for {name, value} <- List.keysort(named, 0),
        do: [" ", name, "=\"", escape_attr(value), "\""]
  end

  @doc false
  # Text content escapes `&`, `<` and `>` only. Most text has none of them, and is
  # returned as it is without being copied (#812).
  def escape_text(text) when is_binary(text) do
    case :binary.match(text, ["&", "<", ">"]) do
      :nomatch ->
        text

      _found ->
        text
        |> String.replace("&", "&amp;")
        |> String.replace("<", "&lt;")
        |> String.replace(">", "&gt;")
    end
  end

  def escape_text(text), do: to_string(text)

  @doc false
  def self_closing?(tag), do: tag in @self_closing_tags

  defp render_element(%Element{tag: tag, attrs: attrs, children: [], content: nil})
       when tag in @self_closing_tags do
    ["<", Atom.to_string(tag), render_attrs(attrs), "/>"]
  end

  defp render_element(%Element{tag: tag, attrs: attrs, children: children, content: content}) do
    tag_str = Atom.to_string(tag)

    [
      "<",
      tag_str,
      render_attrs(attrs),
      ">",
      render_content(content),
      render_children(children),
      "</",
      tag_str,
      ">"
    ]
  end

  defp render_content(nil), do: []
  defp render_content(text), do: escape_text(text)

  defp render_children([]), do: []

  defp render_children(children) do
    Enum.map(children, &render_element/1)
  end

  # A value with nothing to escape, which is nearly every value, is returned as it is.
  defp escape_attr(value) when is_binary(value) do
    case :binary.match(value, ["&", "\"", "<", ">"]) do
      :nomatch ->
        value

      _found ->
        value
        |> String.replace("&", "&amp;")
        |> String.replace("\"", "&quot;")
        |> String.replace("<", "&lt;")
        |> String.replace(">", "&gt;")
    end
  end

  defp escape_attr(value) when is_number(value), do: to_string(value)
  defp escape_attr(value) when is_atom(value), do: Atom.to_string(value)
  defp escape_attr(value), do: to_string(value)
end

defimpl String.Chars, for: Visualize.SVG.Element do
  def to_string(element) do
    Visualize.SVG.Renderer.render_to_string(element)
  end
end

# Conditionally implement Phoenix.HTML.Safe if Phoenix is available
if Code.ensure_loaded?(Phoenix.HTML.Safe) do
  defimpl Phoenix.HTML.Safe, for: Visualize.SVG.Element do
    def to_iodata(element) do
      Visualize.SVG.Renderer.render(element)
    end
  end
end
