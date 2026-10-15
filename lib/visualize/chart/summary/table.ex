defmodule Visualize.Chart.Summary.Table do
  @moduledoc false
  # The data-table fallback of a chart (spec/14 §21.3, D-142): the rows each data mark
  # draws as an HTML `<table>`, every value written as the summary writes it, for a host to
  # place beside the chart. `Visualize.Chart.Summary.table/2` is the public face.

  alias Visualize.Chart.{Applied, Frame, Mark, Summary, Text}
  alias Visualize.Chart.Frame.Scales
  alias Visualize.Chart.Mark.Channels
  alias Visualize.Data.Table

  # The marks that annotate data rather than draw it, as the summary counts them.
  @auxiliary [:rule, :band, :x_band, :text, :tiles]

  # The channels a table's columns come from, in column order: what a row is, where it is,
  # then what it measures.
  @columns [
    :series,
    :x,
    :x0,
    :x1,
    :y,
    :y0,
    :y1,
    :angle,
    :r,
    :start,
    :end,
    :inner,
    :outer,
    :value,
    :median
  ]

  # The hierarchy layouts, whose `field` sizes each node.
  @hierarchies [:tree, :cluster, :pack, :partition, :treemap]

  # The rows a table holds before it says how many it left out.
  @limit 1000

  # Visually hidden, still read: the clip pattern every screen-reader-only class uses.
  @hidden "position:absolute;width:1px;height:1px;padding:0;margin:-1px;overflow:hidden;" <>
            "clip:rect(0,0,0,0);white-space:nowrap;border:0"

  @doc false
  @spec html(Applied.t(), keyword()) :: String.t()
  def html(%Applied{} = applied, opts) do
    name = Keyword.get_lazy(opts, :caption, fn -> Summary.new(applied).name end)
    limit = Keyword.get(opts, :limit, @limit)
    tables = applied |> tables(limit) |> Enum.uniq_by(&{&1.columns, &1.rows, &1.total})
    many? = length(tables) > 1

    style = if Keyword.get(opts, :hidden, true), do: [~s( style="), @hidden, ~s(")], else: []
    id = if id = Keyword.get(opts, :id), do: [~s( id="), escape(id), ~s(")], else: []

    IO.iodata_to_binary([
      ~s(<div class="),
      escape(Keyword.get(opts, :class, "vis-data-table")),
      ~s("),
      id,
      style,
      ">",
      Enum.map(tables, &table(&1, name, many?)),
      "</div>"
    ])
  end

  defp tables(%Applied{frames: frames, frame: frame, sources: sources}, limit) do
    frames = if frames == %{} or is_nil(frames), do: [frame], else: Map.values(frames)

    for frame <- Enum.sort_by(frames, &{&1.z, to_string(&1.name)}),
        mark <- frame.marks,
        Map.get(mark, :type) not in @auxiliary,
        table = mark_table(frame, mark, sources, limit),
        do: table
  end

  # One mark's rows under the columns that say them: a stacked mark's series, position and
  # own value; a hierarchy's names and the field it is sized by; any other mark's fields
  # that a scale maps, with its series and the fields its inline label reads. A position
  # a layout computed in pixels is not data, and a mark with no column says nothing.
  # Only the rows the table shows are written: a mark of 50,000 rows is cut to the limit
  # before a value is formatted.
  defp mark_table(frame, mark, sources, limit) do
    ctx = %{frame: frame, mark: mark}

    case columns(ctx) do
      [] ->
        nil

      columns ->
        rows = Mark.rows(frame, mark, sources)
        shown = Enum.take(rows, limit)

        %{
          source: source(mark),
          columns: Enum.map(columns, & &1.title),
          rows: Enum.map(shown, fn row -> Enum.map(columns, &cell(&1, row)) end),
          total: length(rows)
        }
    end
  end

  defp columns(%{frame: frame, mark: mark} = ctx) do
    labeled = label_columns(mark)
    steps = steps(mark)

    cond do
      Enum.any?(steps, &(&1.op == :stack)) ->
        key = %{title: "series", read: &Table.get(&1, :key), format: &Summary.plain/1}
        at = Enum.find_value([:x, :x0, :y0], &channel_column(ctx, &1))

        value = %{
          title: "value",
          read: &Table.get(&1, :value),
          format: Summary.formatter(frame, scale(ctx, :y1))
        }

        Enum.reject([key, at, value], &is_nil/1)

      layout = Enum.find(steps, &(&1.op in @hierarchies and Map.get(&1, :field))) ->
        sized = %{
          title: humanize(layout.field),
          read: &Table.get(&1, layout.field),
          format: &Summary.plain/1
        }

        labeled ++ [sized]

      true ->
        channels = for channel <- @columns, column = channel_column(ctx, channel), do: column
        Enum.uniq_by(labeled ++ channels, & &1.title)
    end
  end

  defp channel_column(%{frame: frame, mark: mark} = ctx, channel) do
    spec = Map.get(Map.get(mark, :channels, %{}), channel)
    field = field(spec)
    scale = scale(ctx, channel)
    raw? = channel == :series or (mark.type in [:arc, :rose] and channel == :value)

    if field && (raw? or Map.has_key?(frame.scales, scale)) do
      format = if raw?, do: &Summary.plain/1, else: Summary.formatter(frame, scale)
      %{title: humanize(field), read: &Channels.reading(ctx, channel, &1), format: format}
    end
  end

  defp label_columns(%{label: %{text: text}}) do
    for {:field, field} <- Text.parse!(text),
        do: %{title: humanize(field), read: &Table.get(&1, field), format: &Summary.plain/1}
  end

  defp label_columns(_mark), do: []

  defp cell(%{read: read, format: format}, row) do
    case read.(row) do
      nil -> ""
      value -> format.(value)
    end
  end

  defp table(%{source: source, columns: columns, rows: shown, total: total}, name, many?) do
    caption = if many?, do: "#{name}: #{source}", else: name

    caption =
      if total > length(shown),
        do: "#{caption} (the first #{length(shown)} of #{total} rows)",
        else: caption

    [
      "<table><caption>",
      escape(caption),
      "</caption><thead><tr>",
      Enum.map(columns, &[~s(<th scope="col">), escape(&1), "</th>"]),
      "</tr></thead><tbody>",
      Enum.map(shown, fn cells ->
        ["<tr>", Enum.map(cells, &["<td>", escape(&1), "</td>"]), "</tr>"]
      end),
      "</tbody></table>"
    ]
  end

  defp scale(%{frame: %Frame{kind: kind}, mark: mark}, channel),
    do: Scales.scale_for(kind, mark, channel)

  defp steps(%{data: %{transforms: steps}}) when is_list(steps), do: steps
  defp steps(_mark), do: []

  defp source(%{data: %{source: name}}), do: humanize(name)
  defp source(%{data: name}) when is_atom(name), do: humanize(name)

  defp field(field) when is_atom(field) and field not in [nil, true, false], do: field
  defp field({:field, field}) when is_atom(field), do: field
  defp field(_spec), do: nil

  defp humanize(atom), do: atom |> Atom.to_string() |> String.replace("_", " ")

  @doc false
  # Text escaped for HTML content and attribute values alike.
  @spec escape(String.t()) :: String.t()
  def escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end
end
