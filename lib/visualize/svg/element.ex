defmodule Visualize.SVG.Element do
  @moduledoc """
  Represents an SVG element as an Elixir data structure.

  Elements can be nested and rendered to SVG strings or used directly
  in LiveView templates.
  """

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
  Appends a child element.
  """
  @spec append(t(), t() | [t()]) :: t()
  def append(%__MODULE__{} = parent, %__MODULE__{} = child) do
    %{parent | children: parent.children ++ [child]}
  end

  def append(%__MODULE__{} = parent, children) when is_list(children) do
    %{parent | children: parent.children ++ children}
  end

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
