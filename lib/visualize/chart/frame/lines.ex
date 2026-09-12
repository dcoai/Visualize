defmodule Visualize.Chart.Frame.Lines do
  @moduledoc false
  # A text's lines (spec/14 §7.1): one pass over the frame's tree turning every `:text`
  # whose content holds a newline into one `tspan` per line, each restarting at the
  # text's `x` and sitting `line_height` em below the last. A text of one line is left
  # as it is, so nothing changes for a text without a newline.

  alias Visualize.Chart.Schema
  alias Visualize.IR.Element

  @doc false
  @spec split(Element.t()) :: Element.t()
  def split(%Element{type: :text, content: content} = text) when is_binary(content) do
    case String.split(content, "\n") do
      [_one] ->
        text

      lines ->
        x = Map.get(text.attrs, :x, 0)

        gap =
          "#{Map.get(text.style, :line_height) || Schema.default(:style, :line_height) || 1.2}em"

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

  def split(%Element{children: []} = element), do: element

  def split(%Element{children: children} = element),
    do: %{element | children: Enum.map(children, &split/1)}
end
