defmodule Visualize.Board.Budget do
  @moduledoc """
  Each bound slot's budget, derived from what its cell draws at its size, and each feed's,
  the largest of its slots' (spec/15 §8.2, #864, D-226).

  A mark that reads a slot needs rows by its type at its plot width `w` — the width of its
  frame's box at the cell's size less the frame's left and right margins, in whole pixels:

  | Marks | Rows |
  |---|---|
  | `:line`, `:area`, `:percentile_band` | `4 × w`, M4's lossless bound |
  | `:rect`, `:band`, `:rose` | `ceil(w / 2)`, a bar per two pixels |
  | any other mark that draws rows | `w` |
  | `:tiles` | none |

  A slot's budget is the largest of its marks' needs — marks on one slot read the same
  rows — or the design's `budget` where it declares one (spec/14 §2.10), and never more
  than the board's ceiling. A feed is asked the largest budget of the slots it fills.

  Everything here is pure, read from the design without applying it, so the board process
  that holds the feeds never pays for a cell's chart.

  ## Examples

      iex> chart = Visualize.Chart.from_map!(%{
      ...>   version: 3,
      ...>   sources: %{primary: %{fields: [:t, :v]}},
      ...>   frames: %{main: %{kind: :cartesian, margin: %{left: 40, right: 20}}},
      ...>   marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v}}]
      ...> })
      iex> Visualize.Board.Budget.slot(chart, %{}, "primary", {560, 200}, nil)
      2000
      iex> Visualize.Board.Budget.slot(chart, %{}, "primary", {560, 200}, 500)
      500

  """

  alias Visualize.Chart
  alias Visualize.Chart.{Frame, Names, Schema, Var}

  # Rows per pixel of plot width by mark type (spec/15 §8.2): a continuous shape is M4's
  # first, last, minimum and maximum per pixel column; a bar is one per two pixels.
  @continuous [:line, :area, :percentile_band]
  @bars [:rect, :band, :rose]
  @rowless [:tiles]

  @typedoc "A slot's or a feed's budget: rows, or `nil` for no bound."
  @type t :: pos_integer() | nil

  @doc """
  A slot's budget in a cell of `size` (`{width, height}`, pixels): the design's `budget`
  where it declares one, else the largest of the needs of the marks that read the slot,
  capped by `ceiling`. A slot no mark reads, with no integer declared, is the ceiling.
  `vars` are the cell's variables, which a frame's box, cell or margin may read.
  """
  @spec slot(Chart.t(), map(), String.t(), {number(), number()}, t()) :: t()
  def slot(%Chart{} = chart, vars, slot, size, ceiling) do
    widths = widths(chart, vars, slot, size)

    chart.budget
    |> declared(widths)
    |> Kernel.||(derived(widths))
    |> capped(ceiling)
  end

  @doc """
  Every bound slot's budget, by `{cell, slot}`: each slot of `needs` (a cell's slots by
  name) that `slot_refs` binds — to a feed, `{:feed, name}`, or to a virtual source,
  `{:source, path}` — in its cell's box of `boxes` (`Visualize.Board.boxes/2`), its
  component's chart and variables from `components`. A budget is what the cell draws,
  whoever produces the rows (spec/15 §8.2, D-230).

      iex> chart = Visualize.Chart.from_map!(%{
      ...>   version: 3,
      ...>   sources: %{primary: %{fields: [:t, :v]}},
      ...>   frames: %{main: %{kind: :cartesian, margin: %{left: 40, right: 20}}},
      ...>   marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v}}]
      ...> })
      iex> components = %{a: %{chart: chart, vars: %{}}, b: %{chart: chart, vars: %{}}}
      iex> needs = %{a: ["primary"], b: ["primary"]}
      iex> refs = %{{:a, "primary"} => {:feed, :f}, {:b, "primary"} => {:source, ["s"]}}
      iex> boxes = %{a: {0, 0, 560, 200}, b: {0, 0, 160, 200}}
      iex> Visualize.Board.Budget.slots(components, needs, refs, boxes, nil)
      %{{:a, "primary"} => 2000, {:b, "primary"} => 400}

  """
  @spec slots(map(), %{term() => [String.t()]}, map(), map(), t()) :: %{
          {term(), String.t()} => t()
        }
  def slots(components, needs, slot_refs, boxes, ceiling) do
    for {cell, slots} <- needs,
        slot <- slots,
        bound?(Map.fetch(slot_refs, {cell, slot})),
        %{chart: chart, vars: vars} = Map.fetch!(components, cell),
        {_x, _y, w, h} = Map.fetch!(boxes, cell),
        into: %{},
        do: {{cell, slot}, slot(chart, vars, slot, {w, h}, ceiling)}
  end

  @doc """
  Each feed's budget, the largest of the feed-bound slots' it fills (`nil`, no bound, the
  largest of all): a feed of `feeds` that no slot binds, or that a virtual source reads
  (`read`), is asked the ceiling. A slot of `budgets` bound to a virtual source is in no
  feed's: its source's inputs are asked the ceiling, and its output is reduced to the
  slot's budget where it is handed (spec/15 §8.2, D-230).

      iex> refs = %{
      ...>   {:a, "p"} => {:feed, :f},
      ...>   {:b, "p"} => {:feed, :f},
      ...>   {:c, "p"} => {:source, ["s"]}
      ...> }
      iex> budgets = %{{:a, "p"} => 300, {:b, "p"} => 800, {:c, "p"} => 2000}
      iex> Visualize.Board.Budget.feeds([:f, :g], budgets, refs, [], 5000)
      %{f: 800, g: 5000}

  """
  @spec feeds([term()], %{{term(), String.t()} => t()}, map(), [term()], t()) :: %{
          term() => t()
        }
  def feeds(feeds, budgets, slot_refs, read, ceiling) do
    by_feed =
      for(
        {key, budget} <- budgets,
        {:feed, feed} <- [Map.fetch!(slot_refs, key)],
        do: {feed, budget}
      )
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    Map.new(feeds, fn feed ->
      asked = Map.get(by_feed, feed, [])
      own = if asked == [] or feed in read, do: [ceiling | asked], else: asked
      {feed, largest(own)}
    end)
  end

  # A slot is bound when the binding resolves it to a feed or to a virtual source; an
  # unbound one is down (`{:down, {:unbound, slot}}`) and draws nothing.
  defp bound?({:ok, {:feed, _feed}}), do: true
  defp bound?({:ok, {:source, _path}}), do: true
  defp bound?(:error), do: false

  defp largest(budgets), do: if(nil in budgets, do: nil, else: Enum.max(budgets))

  # -- the derivation ---------------------------------------------------------------------

  # The design's own: rows, or rows per pixel of the widest plot of the slot's marks
  # (spec/14 §2.10); per pixel with no mark is no derivation.
  defp declared(n, _widths) when is_integer(n), do: n
  defp declared({:per_px, _k}, []), do: nil

  defp declared({:per_px, k}, widths),
    do: max(1, ceil(k * (widths |> Enum.map(&elem(&1, 1)) |> Enum.max())))

  defp declared(nil, _widths), do: nil

  defp derived(widths) do
    case for({type, w} <- widths, type not in @rowless, do: need(type, w)) do
      [] -> nil
      needs -> Enum.max(needs)
    end
  end

  defp need(type, w) when type in @continuous, do: 4 * w
  defp need(type, w) when type in @bars, do: ceil(w / 2)
  defp need(_type, w), do: w

  defp capped(budget, nil), do: budget
  defp capped(nil, ceiling), do: ceiling
  defp capped(budget, ceiling), do: min(budget, ceiling)

  # Each mark reading the slot, as `{type, plot width}`: its frame's box at the size less
  # the frame's left and right margins, whole pixels, at least one (spec/15 §8.2).
  defp widths(%Chart{marks: marks} = chart, vars, slot, {width, height}) do
    for %{type: type} = mark <- marks,
        reads?(mark, slot),
        node = frame_node(chart, mark),
        is_map(node),
        do: {type, plot_width(chart, vars, node, width, height)}
  end

  defp reads?(mark, slot) do
    case Map.get(mark, :data) do
      %{source: source} -> same?(source, slot)
      source -> same?(source, slot)
    end
  end

  defp same?(name, slot) when is_binary(name) or is_atom(name),
    do: Names.same?(name, slot)

  defp same?(_other, _slot), do: false

  # The frame a mark is drawn in: the one it names, else the design's only one.
  defp frame_node(%Chart{frames: frames}, mark) when is_map(frames) do
    case Map.get(mark, :frame) do
      nil when map_size(frames) == 1 -> frames |> Map.values() |> hd()
      nil -> nil
      name -> Enum.find_value(frames, fn {n, node} -> if same?(n, name), do: node end)
    end
  end

  defp frame_node(_chart, _mark), do: nil

  defp plot_width(chart, vars, node, width, height) do
    margin = margin(chart, vars, node)
    [_x, _y, fraction, _h] = box(chart, vars, node, width, height)
    max(1, ceil(fraction * width - margin.left - margin.right))
  end

  # The frame's box as `Frame.new/2` reads it, its parts read at the cell's variables; a
  # part no variable makes readable is the whole cell.
  defp box(chart, vars, node, width, height) do
    node =
      for {k, v} <- Map.take(node, [:box, :cell, :span]),
          into: %{},
          do: {k, value(chart, vars, v)}

    layout = value(chart, vars, chart.layout)

    if readable?(node) and (layout == nil or is_map(layout)),
      do: Frame.box_of(node, layout, {width, height}),
      else: [0, 0, 1, 1]
  end

  # A cell of whole numbers with a span of two, or no cell and a box of four numbers or
  # none: what `Frame.box_of/3` reads without raising.
  defp readable?(node) do
    case {Map.get(node, :cell), Map.get(node, :span), Map.get(node, :box)} do
      {nil, _span, nil} -> true
      {nil, _span, [_, _, _, _] = box} -> Enum.all?(box, &is_number/1)
      {[c, r], nil, _box} -> is_integer(c) and is_integer(r)
      {[c, r], [a, d], _box} -> Enum.all?([c, r, a, d], &is_integer/1)
      _other -> false
    end
  end

  # The frame's margin as `Frame.new/2` fills it: the frame's default when it gives none,
  # else each side it lacks `0`; a side no variable makes a number is the side's default.
  defp margin(chart, vars, node) do
    given =
      case value(chart, vars, Map.get(node, :margin)) do
        margin when is_map(margin) and not is_struct(margin) -> margin
        _none -> Schema.default(:frame, :margin)
      end

    Map.new([:left, :right], fn side ->
      case value(chart, vars, Map.get(given, side, Schema.default(:margin, side))) do
        n when is_number(n) -> {side, n}
        _other -> {side, Schema.default(:margin, side)}
      end
    end)
  end

  # A variable read at the cell's variables, else its declared default (spec/15 §5).
  defp value(chart, vars, %Var{name: name}) do
    case Names.key(vars, name) do
      {:ok, key} -> Map.fetch!(vars, key)
      :error -> default(chart, name)
    end
  end

  defp value(_chart, _vars, value), do: value

  defp default(%Chart{vars: decls}, name) do
    with {:ok, key} <- Names.key(decls, name),
         %{default: default} <- Map.fetch!(decls, key) do
      default
    else
      _none -> nil
    end
  end
end
