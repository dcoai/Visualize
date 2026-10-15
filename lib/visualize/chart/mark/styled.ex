defmodule Visualize.Chart.Mark.Styled do
  @moduledoc false
  # A mark's style, and a style named by data (spec/14 §3.6, #644, D-171).
  #
  # `parts/5` is what the element builders read of a style node: the node, its resolved
  # element style split into the static part and the `{:field, f}` bindings, and the paint.
  # A mark whose stack holds `{:field, f}` entries has one such set of parts per datum:
  # `prepare/1` resolves them once for every distinct choice the mark's rows make, and
  # `at/2` answers the mark's context with a datum's parts in place — the context as it is
  # for a mark whose stack names no style by data, so such a mark draws byte for byte as
  # before. Who asks with which datum is §3.2's binding rule: an element-per-datum mark with
  # each element's, a path-per-series mark with the series' first.

  alias Visualize.Chart.Style
  alias Visualize.Data.Table
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
  # The context with `by_data`: `nil` for a mark whose stack names no style by data, else
  # its entries, the names a value may spell, and the parts of every distinct choice its
  # rows make, keyed by the choice.
  @spec prepare(map()) :: map()
  def prepare(ctx) do
    case Style.by_data(Map.get(ctx.mark, :style)) do
      [] ->
        Map.put(ctx, :by_data, nil)

      entries ->
        names = names(ctx.frame.styles)

        table =
          ctx.rows
          |> Enum.map(&picks(entries, &1, names))
          |> Enum.uniq()
          |> Map.new(&{&1, chosen(ctx, entries, &1)})

        Map.put(ctx, :by_data, %{entries: entries, names: names, table: table})
    end
  end

  @doc false
  # The context with the datum's parts in place of the mark's.
  @spec at(map(), term()) :: map()
  def at(%{by_data: nil} = ctx, _datum), do: ctx

  def at(%{by_data: %{entries: entries, names: names, table: table}} = ctx, datum) do
    picks = picks(entries, datum, names)
    parts = Map.get_lazy(table, picks, fn -> chosen(ctx, entries, picks) end)
    Map.merge(ctx, parts)
  end

  @doc false
  # What a datum's parts change on its element over the mark's group: every resolved key
  # that differs from the mark's own, and the paint when it does — nothing for a mark whose
  # stack names no style by data.
  @spec over(map(), map()) :: map()
  def over(%{by_data: nil}, _own), do: %{}

  def over(ctx, own) do
    changed =
      for {key, value} <- own.static,
          Map.get(ctx.static, key) != value,
          into: %{},
          do: {key, value}

    case own.paint do
      {_key, {:field, _}} -> changed
      paint when paint == ctx.paint -> changed
      {key, color} -> Map.put_new(changed, key, color)
    end
  end

  @doc false
  # The style node of a stack at a site that has a datum (spec/14 §3.6): each `{:field, f}`
  # entry laid with the style the datum's value names, read against `styles`; a datum of
  # `nil` lays none.
  # Laid over `base`, the style the site's containers lay (spec/14 §3.8).
  @spec node(%{atom() => map()}, term(), map() | nil, map()) :: map()
  def node(styles, stack, nil, base), do: Style.over(base, styles, stack)

  def node(styles, stack, datum, base) do
    case Style.by_data(stack) do
      [] ->
        Style.over(base, styles, stack)

      _entries ->
        names = names(styles)
        Style.node(styles, stack, &pick(&1, datum, names), base)
    end
  end

  # The names a value may give for a style: each name as itself and as its text, so a
  # feed's `"warning"` names `:warning` without the value being made into an atom.
  defp names(styles) do
    Enum.reduce(Map.keys(styles), %{}, fn name, names ->
      names |> Map.put(name, name) |> Map.put(Atom.to_string(name), name)
    end)
  end

  # The style name each entry names for the datum, in the entries' order.
  defp picks(entries, datum, names), do: Enum.map(entries, &pick(&1, datum, names))

  # The style the datum's value names, or `nil` to lay nothing: a missing value, and one
  # that names no declared style and no palette entry (spec/14 §3.6).
  defp pick({:field, field}, datum, names), do: Map.get(names, Table.get(datum, field))

  defp chosen(ctx, entries, picks) do
    chosen = entries |> Enum.zip(picks) |> Map.new()

    node =
      ctx.frame.styles
      |> Style.node(Map.get(ctx.mark, :style), &Map.get(chosen, &1), ctx.base)
      |> Style.drawn(ctx.type)

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
