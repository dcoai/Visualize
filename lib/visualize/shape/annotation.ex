defmodule Visualize.Shape.Annotation do
  @moduledoc false
  # What `Visualize.Shape.Rule` and `Visualize.Shape.XBand` share (spec/04 §12–13, D-27):
  # the text-valued accessor, the optional scale, and the label element.

  alias Visualize.IR.Element
  alias Visualize.Shape.Line

  @typedoc "An accessor whose value is text (or a fill): function, atom field, or string."
  @type text_accessor :: (any() -> String.t() | nil) | atom() | String.t()

  @label_style %{
    font_size: 10,
    font_family: "sans-serif",
    text_anchor: :start,
    fill: :current_color
  }

  @doc false
  @spec text(text_accessor() | nil) :: (any() -> String.t() | nil) | nil
  def text(nil), do: nil
  def text(accessor) when is_function(accessor, 1), do: accessor
  def text(field) when is_atom(field), do: Visualize.Data.Table.accessor(field)
  def text(constant) when is_binary(constant), do: fn _d -> constant end

  @doc false
  @spec value(Line.accessor(), any()) :: number()
  def value(accessor, d), do: Line.normalize_accessor(accessor).(d)

  # A domain value through the scale; the value itself when there is no scale.
  @doc false
  @spec position(struct() | nil, any()) :: number()
  def position(nil, value), do: value
  def position(scale, value), do: Visualize.Scale.apply(scale, value)

  @doc false
  @spec fill_style(map(), (any() -> String.t() | nil) | nil, any()) :: map()
  def fill_style(style, nil, _d), do: style

  def fill_style(style, fill, d) do
    case fill.(d) do
      nil -> style
      value -> Map.put(style, :fill, value)
    end
  end

  # The label to the right of the annotation's upper end, inside the plot; `[]` without one.
  @doc false
  @spec label((any() -> String.t() | nil) | nil, any(), number(), number()) :: [Element.t()]
  def label(nil, _d, _x, _top), do: []

  def label(accessor, d, x, top) do
    case accessor.(d) do
      nil -> []
      text -> [Element.text(text, x: x, y: top, dx: 3, dy: 10, style: @label_style)]
    end
  end
end
