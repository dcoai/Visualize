defmodule Visualize.Chart.Summary.Identities do
  @moduledoc false
  # The keyboard's points of a mark that draws no number (spec/14 §21.5, #765, D-198): a
  # grid of states, a status grid, a row of glyphs. Each of its rows with an identity —
  # the slot's declared one (D-167), else the inference a pick uses — is a point at the
  # center of what it draws, read as its identity and its tooltip's text. A mark that
  # places both axes on band scales is a grid, and each point carries its column and row.

  alias Visualize.Chart.Frame
  alias Visualize.Chart.Frame.Scales
  alias Visualize.Chart.Mark.Channels
  alias Visualize.Data.Table
  alias Visualize.Event

  @doc false
  # The mark's rows as `{series, point}`: the point's `said` (identity, then the
  # tooltip's text), its `position` (`nil` when unplaced), its `row` and `ordinal` in the
  # mark's rows, and its grid `cell` axis readings (`{x, y}`) when the mark is a grid.
  # `[]` for a row that names nothing. `ctx` is the frame and the mark, with the update's
  # placement of them when there is one (#811).
  @spec entries(%{frame: Frame.t(), mark: map()}, [map()], map() | nil) :: [{String.t(), map()}]
  def entries(%{frame: %Frame{} = frame, mark: mark} = ctx, rows, schemas) do
    schema = Event.schema_of(schemas, mark)
    name = series_name(mark)
    grid? = grid?(frame, mark)

    for {{row, position}, ordinal} <- Enum.with_index(Enum.zip(rows, positions(ctx, rows))),
        identity = Event.identity(mark, row, schema),
        identity != nil do
      said =
        Enum.join(
          Enum.reject([identity_text(identity), tooltip_text(mark, row)], &is_nil/1),
          ", "
        )

      {name, %{said: said, position: position, row: row, ordinal: ordinal, grid?: grid?}}
    end
  end

  # A mark is named by its `id`, else the slot it draws, else its type.
  defp series_name(%{id: id}) when id != nil, do: to_string(id)
  defp series_name(%{data: %{source: slot}}), do: to_string(slot)
  defp series_name(%{data: slot}) when is_binary(slot) or is_atom(slot), do: to_string(slot)
  defp series_name(mark), do: to_string(Map.get(mark, :type))

  # Both position axes on band scales: a grid of cells, reached in two dimensions.
  defp grid?(%Frame{kind: :cartesian, scales: scales}, mark) do
    channels = Map.get(mark, :channels, %{})

    Enum.all?([[:x, :x0], [:y, :y0]], fn pair ->
      case Enum.find(pair, &Map.has_key?(channels, &1)) do
        nil ->
          false

        channel ->
          match?(
            %Visualize.Scale.Band{},
            Map.get(scales, Scales.scale_for(:cartesian, mark, channel))
          )
      end
    end)
  end

  defp grid?(_frame, _mark), do: false

  # The center of what each row draws, in the chart's pixels: the middle of `x0` and `x1`
  # and of `y0` and `y1` for a rectangle, its `x` and `y` otherwise; none outside a
  # cartesian frame.
  defp positions(%{frame: %Frame{kind: kind}}, rows) when kind != :cartesian,
    do: Enum.map(rows, fn _row -> nil end)

  defp positions(%{frame: frame} = ctx, rows) do
    [bx, by, _w, _h] = frame.box
    left = bx * frame.size.width + frame.margin.left
    top = by * frame.size.height + frame.margin.top

    ctx
    |> Map.put(:rows, rows)
    |> Channels.pixels()
    |> Enum.map(fn pixel ->
      with x when is_number(x) <- center(pixel, :x, :x0, :x1),
           y when is_number(y) <- center(pixel, :y, :y0, :y1) do
        {left + x, top + y}
      else
        _unplaced -> nil
      end
    end)
  end

  defp center(pixel, one, a, b) do
    case {Map.get(pixel, one), Map.get(pixel, a), Map.get(pixel, b)} do
      {v, _, _} when is_number(v) -> v
      {_, v0, v1} when is_number(v0) and is_number(v1) -> (v0 + v1) / 2
      _none -> nil
    end
  end

  # An identity as words: `host mx1`, or a composite's fields in name order.
  defp identity_text({field, value}), do: "#{field} #{value}"

  defp identity_text(identity) when is_map(identity),
    do: identity |> Enum.sort() |> Enum.map_join(", ", fn {f, v} -> "#{f} #{v}" end)

  # The mark's tooltip template with the row's fields in it, as `TooltipHook` writes it,
  # trimmed, since a field with no value leaves its space behind;
  # `nil` without a template.
  defp tooltip_text(%{tooltip: %{template: template}}, row) when is_binary(template) do
    ~r/\{([^}]+)\}/
    |> Regex.replace(template, fn _all, field ->
      case Table.get(row, field) do
        nil -> ""
        value -> to_string(value)
      end
    end)
    |> String.trim()
  end

  defp tooltip_text(_mark, _row), do: nil
end
