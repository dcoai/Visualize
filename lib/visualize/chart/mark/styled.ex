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
  #
  # A generator (spec/14 §3.13, D-177) is per datum too: a stack entry, or a color in a style
  # the stack reaches. `prepare/1` calls every generator the mark's rows reach — its stack's
  # and its inline label's — once per distinct `(name, arguments)`, before anything is drawn,
  # and a datum's choice is the styles its field entries name with the keys of the calls it
  # reaches, so each distinct choice is resolved once from that memo.

  alias Visualize.Chart.Style
  alias Visualize.Chart.Style.Generated
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
  # The context with `by_data` and `generated`. `by_data` is `nil` for a mark whose stack
  # names no style by data and reaches no generator, else its entries, the names a value
  # may spell, the generator calls each choice of field styles reaches, and the parts of
  # every distinct choice its rows make, keyed by the choice. `generated` is the memo of
  # every generator the mark's rows reach — its inline label's too — and the path its
  # faults are reported at.
  @spec prepare(map()) :: map()
  def prepare(ctx) do
    styles = ctx.frame.styles
    stack = Map.get(ctx.mark, :style)
    entries = Style.by_data(stack)
    names = names(styles)
    path = path(ctx)
    reach = %{[] => Generated.reached(styles, stack, %{})}
    label = label_stack(ctx)

    if entries == [] and reach[[]] == [] and not generates?(styles, label) do
      ctx
      |> Map.put(:by_data, nil)
      |> Map.put(:generated, %{memo: %{}, path: path})
    else
      picks = Enum.map(ctx.rows, &picks(entries, &1, names))
      reach = reach(reach, styles, stack, entries, Enum.uniq(picks))
      choices = Enum.zip_with(picks, ctx.rows, &choice(reach, &1, &2))
      memo = memo(ctx, choices, label)
      ctx = Map.put(ctx, :generated, %{memo: memo, path: path})

      by_data =
        if entries == [] and reach[[]] == [] do
          nil
        else
          table =
            choices
            |> Enum.zip(ctx.rows)
            |> Enum.uniq_by(&elem(&1, 0))
            |> Map.new(fn {choice, row} -> {choice, chosen(ctx, entries, choice, row)} end)

          %{entries: entries, names: names, reach: reach, table: table}
        end

      Map.put(ctx, :by_data, by_data)
    end
  end

  @doc false
  # The context with the datum's parts in place of the mark's.
  @spec at(map(), term()) :: map()
  def at(%{by_data: nil} = ctx, _datum), do: ctx

  def at(%{by_data: by_data} = ctx, datum) do
    %{entries: entries, names: names, reach: reach, table: table} = by_data
    picks = picks(entries, datum, names)
    reach = reach(reach, ctx.frame.styles, Map.get(ctx.mark, :style), entries, [picks])
    choice = choice(reach, picks, datum)
    parts = Map.get_lazy(table, choice, fn -> chosen(ctx, entries, choice, datum) end)
    Map.merge(ctx, parts)
  end

  # The calls each choice of field styles reaches, for every choice not yet in `reach`.
  defp reach(reach, styles, stack, entries, picks) do
    Enum.reduce(picks, reach, fn picks, reach ->
      Map.put_new_lazy(reach, picks, fn ->
        Generated.reached(styles, stack, Map.new(Enum.zip(entries, picks)))
      end)
    end)
  end

  # A datum's choice: the style names its field entries pick, and the key of each call that
  # reaches — the generator's name and the datum's arguments.
  defp choice(reach, picks, datum) do
    {picks,
     Enum.map(Map.fetch!(reach, picks), fn {_place, call} -> Generated.key(call, datum) end)}
  end

  # Every distinct call of the rows' choices and of their inline label, made once.
  defp memo(ctx, choices, label) do
    label_keys =
      case Generated.reached(ctx.frame.styles, label, %{}) do
        [] -> []
        calls -> for row <- ctx.rows, {_place, call} <- calls, do: Generated.key(call, row)
      end

    keys = Enum.flat_map(choices, &elem(&1, 1)) ++ label_keys
    Generated.memo(ctx.frame.generated || Generated.new(), ctx.frame.theme, keys)
  end

  defp label_stack(%{label: nil}), do: nil

  defp label_stack(%{label: label}),
    do: Map.get(label, :style, Visualize.Chart.Schema.default(:mark_label, :style))

  defp generates?(_styles, nil), do: false
  defp generates?(styles, stack), do: Generated.reached(styles, stack, %{}) != []

  # Where the mark's faults are reported (spec/14 §3.13): its path in the design.
  defp path(%{frame: frame, mark: mark}) do
    case Enum.find_index(frame.marks, &(&1 == mark)) do
      nil -> [:style]
      i -> [:marks, Enum.at(frame.mark_paths, i, i), :style]
    end
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
  # Laid over `base`, the style the site's containers lay (spec/14 §3.8). A generator in it
  # is resolved for the datum — with no datum, its field arguments `nil` — from the mark's
  # memo (spec/14 §3.13); `suffix` is the stack's place under the mark, for its faults.
  @spec node(map(), term(), map() | nil, map(), list()) :: map()
  def node(%{frame: frame} = ctx, stack, datum, base, suffix \\ []) do
    styles = frame.styles

    if Style.by_data(stack) == [] and Generated.reached(styles, stack, %{}) == [] do
      Style.over(base, styles, stack)
    else
      names = names(styles)
      generated = Map.get(ctx, :generated, %{memo: %{}, path: [:style]})
      opts = [memo: generated.memo, path: Enum.drop(generated.path, -1) ++ suffix]
      Style.over(base, styles, stack, &pick(&1, datum, names, frame, opts))
    end
  end

  @doc false
  # Whether a stack is resolved per datum: it names a style by data or reaches a generator.
  @spec per_datum?(map(), term()) :: boolean()
  def per_datum?(%{frame: frame}, stack),
    do: Style.by_data(stack) != [] or Generated.reached(frame.styles, stack, %{}) != []

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

  # `pick/3` for a stack that may hold generators: a field entry as there, with no datum
  # nothing; a generator's checked result (spec/14 §3.13).
  defp pick({:field, _}, nil, _names, _frame, _opts), do: nil
  defp pick({:field, _} = entry, datum, names, _frame, _opts), do: pick(entry, datum, names)

  defp pick({:colour, call}, datum, _names, frame, opts),
    do: Generated.resolve(frame, :leaf, call, datum, opts)

  defp pick(call, datum, _names, frame, opts),
    do: Generated.resolve(frame, :entry, call, datum, opts)

  defp chosen(ctx, entries, {picks, _keys}, datum) do
    chosen = entries |> Enum.zip(picks) |> Map.new()
    opts = [memo: ctx.generated.memo, path: ctx.generated.path]

    pick = fn
      {:field, _} = entry -> Map.get(chosen, entry)
      {:colour, call} -> Generated.resolve(ctx.frame, :leaf, call, datum, opts)
      call -> Generated.resolve(ctx.frame, :entry, call, datum, opts)
    end

    node =
      ctx.frame.styles
      |> Style.node(Map.get(ctx.mark, :style), pick, ctx.base)
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
