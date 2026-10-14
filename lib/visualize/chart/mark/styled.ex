defmodule Visualize.Chart.Mark.Styled do
  @moduledoc false
  # A mark's style, and a style chosen by data (spec/14 §3.6, #637, D-171).
  #
  # `parts/5` is what the element builders read of a style node: the node, its resolved
  # element style split into the static part and the `{:field, f}` bindings, and the paint.
  # A mark whose stack holds `{:scale, name, field}` entries has one such set of parts per
  # datum: `prepare/1` resolves them once for every distinct choice the mark's rows make,
  # and `at/2` answers the mark's context with a datum's parts in place — the context as it
  # is for a mark that lays no scale, so such a mark draws byte for byte as before. Who
  # asks with which datum is §3.2's binding rule: an element-per-datum mark with each
  # element's, a path-per-series mark with the series' first.

  alias Visualize.Chart.Style
  alias Visualize.Data.Table
  alias Visualize.Scale
  alias Visualize.Scale.Ordinal
  alias Visualize.Theme

  @stroked [:line, :rule]

  @doc false
  # The parts of a style node for a mark of `type` at one-based `index` among the marks.
  @spec parts(map(), atom(), pos_integer(), Theme.t(), Theme.mode()) :: map()
  def parts(style_node, type, index, theme, mode) do
    {static, bound} = split(Style.resolve(style_node, theme, mode))

    %{
      style_node: style_node,
      static: static,
      bound: bound,
      paint: paint(type, style_node, index, theme, mode)
    }
  end

  @doc false
  # The context with `scaled`: `nil` for a mark whose stack lays no scale, else its entries
  # and the parts of every distinct choice its rows make, keyed by the choice.
  @spec prepare(map()) :: map()
  def prepare(ctx) do
    case Style.scaled(Map.get(ctx.mark, :style)) do
      [] ->
        Map.put(ctx, :scaled, nil)

      entries ->
        table =
          ctx.rows
          |> Enum.map(&picks(entries, &1, ctx.frame))
          |> Enum.uniq()
          |> Map.new(&{&1, chosen(ctx, entries, &1)})

        Map.put(ctx, :scaled, %{entries: entries, table: table})
    end
  end

  @doc false
  # The context with the datum's parts in place of the mark's.
  @spec at(map(), term()) :: map()
  def at(%{scaled: nil} = ctx, _datum), do: ctx

  def at(%{scaled: %{entries: entries, table: table}} = ctx, datum) do
    picks = picks(entries, datum, ctx.frame)
    parts = Map.get_lazy(table, picks, fn -> chosen(ctx, entries, picks) end)
    Map.merge(ctx, parts)
  end

  @doc false
  # What a datum's parts change on its element over the mark's group: every resolved key
  # that differs from the mark's own, and the paint when it does — nothing for a mark that
  # lays no scale.
  @spec over(map(), map()) :: map()
  def over(%{scaled: nil}, _own), do: %{}

  def over(ctx, own) do
    changed =
      for {key, value} <- own.static,
          Map.get(ctx.static, key) != value,
          into: %{},
          do: {key, value}

    case own.paint do
      {_key, {:field, _}} -> changed
      paint when paint == ctx.paint -> changed
      {key, colour} -> Map.put_new(changed, key, colour)
    end
  end

  # The style name each entry picks for the datum, in the entries' order.
  defp picks(entries, datum, frame), do: Enum.map(entries, &pick(&1, datum, frame))

  # The scale's output for the datum's reading, or `nil` to lay nothing: a missing scale or
  # reading, and a reading an ordinal scale's domain does not hold — its `unknown` is a
  # colour scale's neutral, never a style (spec/14 §3.6).
  defp pick({:scale, name, field}, datum, frame) do
    with %{} = scale <- Map.get(frame.scales, name),
         reading when reading != nil <- Table.get(datum, field),
         true <- placed?(scale, reading),
         style when is_atom(style) and style != nil <- Scale.apply(scale, reading) do
      style
    else
      _none -> nil
    end
  end

  defp placed?(%Ordinal{domain: domain}, reading), do: reading in domain

  defp placed?(_scale, _reading), do: true

  defp chosen(ctx, entries, picks) do
    chosen = entries |> Enum.zip(picks) |> Map.new()
    node = Style.node(ctx.frame.styles, Map.get(ctx.mark, :style), &Map.get(chosen, &1))
    parts(node, ctx.type, ctx.index, ctx.frame.theme, ctx.mode)
  end

  defp split(style) do
    {bound, static} = Enum.split_with(style, fn {_key, value} -> match?({:field, _}, value) end)
    {Map.new(static), Map.new(bound)}
  end

  # The paint: the style's value for the paint key, else the theme's series colour for
  # the mark's position (spec/14 §5.6). A `{:field, f}` there is bound per element.
  defp paint(type, style_node, index, theme, mode) do
    key = if type in @stroked, do: :stroke, else: :fill

    case Map.get(style_node, key) do
      nil -> {key, Theme.resolve(theme, {:series, index}, mode)}
      {:field, _} = ref -> {key, ref}
      value -> {key, Style.value(key, value, theme, mode)}
    end
  end
end
