defmodule Visualize.SVG.Renderer do
  @moduledoc """
  Renders SVG elements to strings or iolists.

  Optimized for efficient string building using iolists.
  """

  alias Visualize.SVG.Element

  @self_closing_tags ~w(circle ellipse line path polygon polyline rect image use)a

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

  defp render_attrs(attrs) when map_size(attrs) == 0, do: []

  defp render_attrs(attrs) do
    attrs
    |> Enum.sort_by(fn {k, _} -> Atom.to_string(k) end)
    |> Enum.map(fn {key, value} ->
      [" ", attr_name(key), "=\"", escape_attr(value), "\""]
    end)
  end

  defp render_content(nil), do: []
  defp render_content(text), do: escape_html(text)

  defp render_children([]), do: []

  defp render_children(children) do
    Enum.map(children, &render_element/1)
  end

  # Convert Elixir-style snake_case to SVG kebab-case for certain attributes
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
