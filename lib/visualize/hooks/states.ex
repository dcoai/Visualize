defmodule Visualize.Hooks.States do
  @moduledoc false
  # A view state as data for a hook (spec/10 §4.4, #638, D-171): the palette's entry of that
  # name, as the frame's design and theme resolve it, in `:literal` mode, written as a JSON
  # object of SVG presentation attributes the hook lays over its overlay shape's defaults.
  # The hooks draw in overlays outside the chart, where neither the style stack nor the
  # theme's custom properties reach, so the server hands them the resolved values (D-75).

  alias Visualize.Chart.{Frame, Style}
  alias Visualize.IR.Path
  alias Visualize.SVG.Renderer

  # The keys an overlay shape draws, in the order they are written.
  @keys [
    :fill,
    :fill_opacity,
    :stroke,
    :stroke_width,
    :stroke_opacity,
    :stroke_dasharray,
    :stroke_linecap,
    :stroke_linejoin,
    :opacity
  ]

  @doc false
  # `%{"data-vis-<state>" => json}` for the state's style under the frame.
  @spec attrs(Frame.t(), :hover | :focused) :: %{String.t() => String.t()}
  def attrs(%Frame{styles: styles, theme: theme}, state) when state in [:hover, :focused] do
    style = styles |> Style.node(state) |> Style.resolve(theme, :literal)

    pairs =
      for key <- @keys,
          text = text(Map.get(style, key)),
          text != nil,
          do: string(Renderer.attribute_name(key)) <> ":" <> string(text)

    %{"data-vis-#{state}" => "{" <> Enum.join(pairs, ",") <> "}"}
  end

  # A value an overlay can draw, as its attribute text; `nil` for one it cannot — absent, a
  # binding with no datum to read, a paint with no `defs` to point at.
  defp text(value) when is_binary(value), do: value
  defp text(value) when is_number(value), do: Path.format_number(value)
  defp text(nil), do: nil
  defp text(value) when is_atom(value), do: Atom.to_string(value)
  defp text(_binding_or_paint), do: nil

  # A JSON string: the two characters JSON escapes by name, and every control character.
  defp string(text) do
    escaped =
      for <<c::utf8 <- text>>, into: "" do
        case c do
          ?" -> ~S(\")
          ?\\ -> ~S(\\)
          c when c < 0x20 -> "\\u" <> String.pad_leading(Integer.to_string(c, 16), 4, "0")
          c -> <<c::utf8>>
        end
      end

    ~s(") <> escaped <> ~s(")
  end
end
