defmodule Visualize.Chart.Migration.FilledLines do
  @moduledoc false
  # The 2 -> 3 step's second half (spec/14 §5.6, §9, #659, D-172): a version 2 line whose
  # style gave a fill drew the area under it, and a version 3 line draws no fill. So each
  # such line gets an `:area` mark just before it, with its data, frame, scales, channels and
  # that fill, and every mark of the frame the insertion moves keeps the series color its
  # position gave it. The design's styles are already in their parts (`canonical/1` ran
  # first); a line's style is read by the walk that never raises, so a design the validator
  # will refuse — a cycle, a variable — is rewritten no further and refused as it is.

  alias Visualize.Chart.Style
  alias Visualize.Chart.Style.Parts
  alias Visualize.Chart.Validator.Domain
  alias Visualize.Theme

  @stroked [:line, :rule]
  # What of a line's style the area under it takes besides the fill: what the old
  # `line-fill` path shared with its line through their group.
  @shared [:curve, :opacity, :blend, :effect, :class]
  @carried [:data, :frame, :scales, :render]

  @doc false
  @spec rewrite(map()) :: map()
  def rewrite(%{marks: marks} = design) when is_list(marks) do
    styles = Style.all(plain(design[:styles]), theme(design[:theme]))
    parts = Enum.map(marks, &parts(&1, styles))

    case Enum.any?(Enum.zip(marks, parts), &filled?/1) do
      false -> design
      true -> %{design | marks: rewritten(marks, parts, styles, design)}
    end
  end

  def rewrite(design), do: design

  defp rewritten(marks, parts, styles, design) do
    one_frame? = map_size(plain(design[:frames])) <= 1
    pairs = Enum.zip(marks, parts)

    {out, _positions} =
      Enum.reduce(pairs, {[], %{}}, fn {mark, part}, {out, positions} ->
        group = if one_frame?, do: :one, else: frame_of(mark)
        old = old_position(pairs, mark, one_frame?)
        {inserted, positions} = insert(mark, part, group, positions)
        new = Map.get(positions, group, 0) + 1
        positions = Map.put(positions, group, new)
        {out ++ inserted ++ [pinned(mark, styles, old, new)], positions}
      end)

    out
  end

  # The area under a filled line, which takes a position in its frame before the line.
  defp insert(mark, part, group, positions) do
    if filled?({mark, part}) do
      {[area(mark, part)], Map.update(positions, group, 1, &(&1 + 1))}
    else
      {[], positions}
    end
  end

  # One-based position among the marks of the frame, before any insertion.
  defp old_position(pairs, mark, one_frame?) do
    pairs
    |> Enum.map(&elem(&1, 0))
    |> Enum.filter(&(one_frame? or frame_of(&1) == frame_of(mark)))
    |> Enum.find_index(&(&1 == mark))
    |> Kernel.+(1)
  end

  # A mark whose style gives no paint draws `{:series, i}` for its position (spec/14
  # §3.3): moved, it is given that color, laid last in its stack.
  defp pinned(mark, _styles, old, old), do: mark

  defp pinned(%{type: type} = mark, styles, old, _new) when type != :tiles do
    key = if type in @stroked, do: :stroke, else: :fill

    if Map.has_key?(Style.drawn(Domain.cascade(Map.get(mark, :style), styles), type), key),
      do: mark,
      else:
        Map.put(
          mark,
          :style,
          List.wrap(Map.get(mark, :style)) ++ [%{key => %{type: :solid, color: {:series, old}}}]
        )
  end

  defp pinned(mark, _styles, _old, _new), do: mark

  defp area(line, part) do
    channels = line |> Map.get(:channels, %{}) |> plain() |> Map.take([:x, :y, :series])
    style = part |> Map.take(@shared) |> Map.put(:fill, part.fill)

    line
    |> Map.take(@carried)
    |> Map.merge(%{type: :area, channels: channels, style: style})
  end

  defp parts(%{type: :line} = mark, styles), do: Domain.parts(Map.get(mark, :style), styles)
  defp parts(_mark, _styles), do: %{}

  # A fill a version 2 line drew: one that projects to a paint other than none.
  defp filled?({%{type: :line}, %{fill: fill}}),
    do: Map.get(Parts.project(%{fill: fill}), :fill) not in [nil, :none]

  defp filled?(_pair), do: false

  defp frame_of(mark) when is_map(mark), do: Map.get(mark, :frame)
  defp frame_of(_mark), do: nil

  defp theme(name) when is_atom(name) and name != nil, do: Theme.builtin(name) || Theme.default()

  defp theme(%{styles: styles}) when is_map(styles) and not is_struct(styles),
    do: Theme.build(Theme.default(), styles: styles)

  defp theme(_theme), do: Theme.default()

  defp plain(map) when is_map(map) and not is_struct(map), do: map
  defp plain(_other), do: %{}
end
