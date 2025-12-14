defmodule Visualize.SVG do
  @moduledoc """
  Main SVG module providing a fluent API for building SVG documents.

  ## Examples

      iex> alias Visualize.SVG
      iex> SVG.new(width: 400, height: 300)
      ...> |> SVG.append(:rect, x: 10, y: 10, width: 100, height: 50, fill: "blue")
      ...> |> SVG.append(:circle, cx: 200, cy: 150, r: 40, fill: "red")
      ...> |> SVG.render()

  """

  alias Visualize.SVG.{Element, Renderer}

  @doc """
  Creates a new SVG root element.
  """
  @spec new(keyword()) :: Element.t()
  def new(attrs \\ []) do
    Element.svg(Map.new(attrs))
  end

  @doc """
  Appends a child element to the SVG.

  Can take either an Element struct or a tag atom with attributes.
  """
  @spec append(Element.t(), Element.t() | atom(), keyword() | map()) :: Element.t()
  def append(parent, %Element{} = child) do
    Element.append(parent, child)
  end

  def append(parent, tag, attrs \\ []) when is_atom(tag) do
    child = Element.new(tag, to_map(attrs))
    Element.append(parent, child)
  end

  @doc """
  Appends multiple children at once.
  """
  @spec append_all(Element.t(), [Element.t()]) :: Element.t()
  def append_all(parent, children) when is_list(children) do
    Enum.reduce(children, parent, &Element.append(&2, &1))
  end

  @doc """
  Creates a group element with optional attributes.
  """
  @spec group(keyword()) :: Element.t()
  def group(attrs \\ []), do: Element.g(to_map(attrs))

  @doc """
  Wraps elements in a group with a transform.
  """
  @spec translate(Element.t() | [Element.t()], number(), number()) :: Element.t()
  def translate(elements, x, y) do
    group(transform: "translate(#{x},#{y})")
    |> append_elements(elements)
  end

  @doc """
  Renders the SVG element tree to an iolist (efficient for Phoenix).
  """
  @spec render(Element.t()) :: iolist()
  def render(%Element{} = element) do
    Renderer.render(element)
  end

  @doc """
  Renders the SVG element tree to a string.
  """
  @spec to_string(Element.t()) :: String.t()
  def to_string(%Element{} = element) do
    Renderer.render_to_string(element)
  end

  # Helper element constructors that return Elements
  @doc "Creates a rect element"
  def rect(attrs \\ []), do: Element.rect(to_map(attrs))

  @doc "Creates a circle element"
  def circle(attrs \\ []), do: Element.circle(to_map(attrs))

  @doc "Creates a line element"
  def line(attrs \\ []), do: Element.line(to_map(attrs))

  @doc "Creates a path element"
  def path(attrs \\ []), do: Element.path(to_map(attrs))

  @doc "Creates a text element"
  def text(content, attrs \\ []) do
    Element.text(to_map(attrs))
    |> Element.content(content)
  end

  @doc "Creates a polyline element"
  def polyline(attrs \\ []), do: Element.polyline(to_map(attrs))

  @doc "Creates a polygon element"
  def polygon(attrs \\ []), do: Element.polygon(to_map(attrs))

  defp append_elements(parent, %Element{} = element) do
    Element.append(parent, element)
  end

  defp append_elements(parent, elements) when is_list(elements) do
    Enum.reduce(elements, parent, fn el, acc -> Element.append(acc, el) end)
  end

  defp to_map(attrs) when is_map(attrs), do: attrs
  defp to_map(attrs) when is_list(attrs), do: Map.new(attrs)
end
