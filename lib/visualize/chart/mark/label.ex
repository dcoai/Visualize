defmodule Visualize.Chart.Mark.Label do
  @moduledoc false
  # A mark's inline label (spec/14 §5.5): one text per element at its anchor point, in the
  # label's style, `{:field, f}` read from the datum.

  alias Visualize.Chart.{Schema, Style, Var}
  alias Visualize.Chart.Text
  alias Visualize.Data.Table
  alias Visualize.IR.Element

  @inset 4
  # Types whose generator draws its own label (spec/14 §5.5).
  @own_label [:rule, :x_band]

  @doc false
  # The text of the label's parts for a datum.
  @spec text(String.t() | [term()], map()) :: String.t()
  def text(text, datum), do: text |> Text.parse!() |> Enum.map_join("", &part(&1, datum))

  defp part(string, _datum) when is_binary(string), do: string
  defp part(%Var{name: name}, _datum), do: Style.unresolved!(name)

  defp part({:field, field}, datum) do
    case Table.get(datum, field) do
      nil -> ""
      value -> to_string(value)
    end
  end

  @doc false
  # The label's resolved style.
  @spec style(map()) :: map()
  def style(%{label: label, frame: frame, mode: mode}) do
    name = Map.get(label, :style, Schema.default(:mark_label, :style))
    Style.resolve(Style.node(frame.styles, name), frame.theme, mode)
  end

  @doc false
  # One text element per child with an anchor point, or nothing without a label.
  @spec elements([map()], map()) :: [Element.t()]
  def elements(_children, %{label: nil}), do: []
  def elements(_children, %{type: type}) when type in @own_label, do: []

  def elements(children, %{label: label} = ctx) do
    style = style(ctx)
    anchor = Map.get(label, :anchor, Schema.default(:mark_label, :anchor))
    dx = Map.get(label, :dx, 0)
    dy = Map.get(label, :dy, 0)

    for %{anchor: {px, py}, datum: datum} <- children do
      {x, y, baseline, text_anchor} = place(anchor, px, py)
      attrs = %{x: x + dx, y: y + dy} |> put_unless_nil(:dy, baseline)
      base = %{class: "mark-label", text_anchor: text_anchor}

      Element.new(:text,
        attrs: attrs,
        style: Map.merge(base, style),
        content: text(label.text, datum)
      )
    end
  end

  defp place(:top, px, py), do: {px, py - @inset, nil, :middle}
  defp place(:bottom, px, py), do: {px, py + @inset, "0.71em", :middle}
  defp place(:left, px, py), do: {px - @inset, py, "0.32em", :end}
  defp place(:right, px, py), do: {px + @inset, py, "0.32em", :start}
  defp place(named, px, py), do: {px, py, "0.32em", named}

  defp put_unless_nil(map, _key, nil), do: map
  defp put_unless_nil(map, key, value), do: Map.put(map, key, value)
end
