defmodule Visualize.Chart.Frame.Lines do
  @moduledoc false
  # A text's lines (spec/14 §7.1): one pass over the frame's tree turning every `:text`
  # whose content holds a newline into one `tspan` per line, each restarting at the
  # text's `x` and sitting `line_height` em below the last. A text of one line is left
  # as it is, so nothing changes for a text without a newline.
  #
  # The line height is the text's effective one, its own over its groups', nearest first
  # (D-210): a mark carries its style on its group and its texts inherit it, as a canvas
  # reads every inherited key (D-111).

  alias Visualize.Chart.Schema
  alias Visualize.IR.Element

  @doc false
  @spec split(Element.t()) :: Element.t()
  def split(%Element{} = element), do: split(element, nil)

  defp split(%Element{type: :text, content: content} = text, inherited)
       when is_binary(content) do
    case String.split(content, "\n") do
      [_one] ->
        text

      lines ->
        x = Map.get(text.attrs, :x, 0)

        gap =
          "#{line_height(text, inherited) || Schema.default(:style, :line_height) || 1.2}em"

        tspans =
          lines
          |> Enum.with_index()
          |> Enum.map(fn
            {line, 0} -> Element.tspan(line, %{x: x})
            {line, _i} -> Element.tspan(line, %{x: x, dy: gap})
          end)

        %{text | content: nil, children: tspans}
    end
  end

  defp split(%Element{children: []} = element, _inherited), do: element

  defp split(%Element{children: children} = element, inherited) do
    inherited = line_height(element, inherited)
    %{element | children: Enum.map(children, &split(&1, inherited))}
  end

  defp line_height(%Element{style: style}, inherited),
    do: Map.get(style, :line_height) || inherited
end
