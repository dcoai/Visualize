defmodule Visualize.Chart.Compiled.Window do
  @moduledoc false
  # The streaming window of a compiled chart (spec/14 §12.5): the viewport scale
  # windowed to `[hi − span, hi]`, the rows a mark draws restricted to it, and the
  # incremental canvas state carried between ticks.

  alias Visualize.Chart
  alias Visualize.Chart.Frame
  alias Visualize.Chart.Frame.Scales
  alias Visualize.Data.Table
  alias Visualize.{Incremental, Scale}
  alias Visualize.IR.Element

  @typedoc """
  The window state: the scale and the span from the design; `hi` the window's upper end
  as a value of the scale; `drawn` the upper end the incremental canvas was last shifted
  to, in the window's units; `incremental` the `Visualize.Incremental` state once the
  canvas layer has been drawn.
  """
  @type t :: %{
          scale: atom(),
          span: number(),
          hi: term(),
          drawn: number() | nil,
          incremental: Incremental.t() | nil
        }

  @doc false
  # The window of a chart with a viewport, or `nil`.
  @spec new(Chart.t()) :: t() | nil
  def new(%Chart{frame: node}) do
    case Map.get(node, :viewport) do
      nil ->
        nil

      %{scale: scale, span: span} ->
        %{scale: scale, span: span, hi: nil, drawn: nil, incremental: nil}
    end
  end

  @doc false
  # The window's upper end for a tick: `now` when given, else the newest value the marks
  # bind to the scale over the sources; `nil` when nothing is bound.
  @spec hi(t(), Chart.t(), Frame.t(), map(), term()) :: term()
  def hi(_window, _chart, _frame, _sources, now) when now != nil, do: now

  def hi(%{scale: scale}, %Chart{marks: marks}, frame, sources, nil) do
    marks
    |> Enum.flat_map(fn mark ->
      rows = Visualize.Chart.Mark.rows(frame, mark, sources)
      for field <- fields(frame.kind, mark, scale), row <- rows, do: Table.get(row, field)
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.max_by(&units/1, fn -> nil end)
  end

  @doc false
  # The frame with the viewport scale's domain set to the window ending at `hi`.
  @spec apply(t(), Frame.t(), term()) :: Frame.t()
  def apply(_window, frame, nil), do: frame

  def apply(%{scale: name, span: span}, frame, hi) do
    scale = Frame.scale(frame, name)
    Frame.put_scale(frame, name, Scale.domain(scale, [subtract(hi, span), hi]))
  end

  @doc false
  # The sources a mark draws from within the window: its source's rows whose reading of
  # the channel naming the viewport scale lies in `[hi − span, hi]`. A mark that reads
  # its source through transforms, or has no channel on the scale, draws every row.
  @spec sources(t(), Frame.t(), map(), map(), term()) :: map()
  def sources(_window, _frame, _mark, sources, nil), do: sources

  def sources(%{scale: scale, span: span}, frame, %{data: name} = mark, sources, hi)
      when is_atom(name) do
    case {fields(frame.kind, mark, scale), Map.fetch(sources, name)} do
      {[field | _], {:ok, source}} ->
        lo = units(subtract(hi, span))
        top = units(hi)

        rows =
          source
          |> Table.rows()
          |> Enum.filter(fn row ->
            case Table.get(row, field) do
              nil -> false
              value -> units(value) >= lo and units(value) <= top
            end
          end)

        Map.put(sources, name, rows)

      _ ->
        sources
    end
  end

  def sources(_window, _frame, _mark, sources, _hi), do: sources

  @doc false
  # The sources a mark draws into a strip of the incremental canvas (spec/14 §12.5,
  # D-108): its source's rows whose reading lies within the strip's range — the region's
  # `x` and `x + width` in plot pixels mapped back through the window — widened by three
  # rows each side in reading order, so a path enters and leaves the strip on its own
  # line. A mark with no channel on the scale draws every row, as `sources/5` has it.
  @neighbours 3
  @spec strip(t(), Frame.t(), map(), map(), term(), {number(), number(), number(), number()}) ::
          map()
  def strip(
        %{scale: scale, span: span},
        frame,
        %{data: name} = mark,
        sources,
        hi,
        {rx, _ry, rw, _rh}
      )
      when is_atom(name) do
    case {fields(frame.kind, mark, scale), Map.fetch(sources, name)} do
      {[field | _], {:ok, source}} ->
        lo = units(subtract(hi, span))
        top = units(hi)
        width = frame.plot.width
        x0 = lo + rx / width * span
        x1 = lo + (rx + rw) / width * span

        # The window's rows in reading order; the neighbours are the window's too. One
        # pass keeps them, their count, and whether they arrived ordered — a streaming
        # source's do, and only an unordered one is sorted (spec/14 §12.5, #404).
        {read, count, ordered?} = window_rows(source, field, lo, top)
        read = if ordered?, do: read, else: Enum.sort_by(read, &elem(&1, 0))

        Map.put(sources, name, span_rows(read, count, x0, x1))

      _ ->
        sources
    end
  end

  def strip(_window, _frame, _mark, sources, _hi, _bounds), do: sources

  # The window's rows in reading order as `{reading, row}`, their count, and whether the
  # readings arrived ordered: one pass, nothing built for a row outside the window.
  defp window_rows(source, field, lo, top) do
    {read, count, ordered?, _last} =
      source
      |> Table.rows()
      |> Enum.reduce({[], 0, true, nil}, fn row, {acc, count, ordered?, previous} ->
        case Table.get(row, field) do
          nil ->
            {acc, count, ordered?, previous}

          value ->
            reading = units(value)

            if reading >= lo and reading <= top do
              {[{reading, row} | acc], count + 1,
               ordered? and (previous == nil or previous <= reading), reading}
            else
              {acc, count, ordered?, previous}
            end
        end
      end)

    {Enum.reverse(read), count, ordered?}
  end

  # The rows between two readings, widened by `@neighbours` each side in reading order:
  # one pass over the window's rows, taking from the first index kept to the last.
  defp span_rows(read, count, x0, x1) do
    {first, last} =
      read
      |> Enum.with_index()
      |> Enum.reduce({nil, nil}, fn {{v, _row}, i}, {first, last} ->
        {if(first == nil and v >= x0, do: i, else: first), if(v <= x1, do: i, else: last)}
      end)

    if first == nil or last == nil do
      []
    else
      from = max(0, first - @neighbours)
      to = min(count - 1, last + @neighbours)

      if to < from,
        do: [],
        else: read |> Enum.slice(from..to) |> Enum.map(&elem(&1, 1))
    end
  end

  @doc false
  # The incremental payload of a tick over the canvas layer's element (in plot
  # coordinates): a full redraw on the first tick, when the window jumped, or when
  # `full?` says the old pixels are stale — the whole window — else a scroll by the
  # window's movement, rounded to whole pixels, each exposed strip built by `strip_fn`
  # over its bounds (D-108), `"none"` when it moved by less than one.
  @spec scroll(t(), Frame.t(), Element.t(), (tuple() -> [Element.t()]), term(), boolean()) ::
          {map(), t()}
  def scroll(%{span: span} = window, frame, whole_fn, strip_fn, hi, full?) do
    plot = frame.plot

    # The whole window is a function the full-redraw branch calls and a scroll never does
    # (spec/14 §12.5, #404): a scroll builds its strip and nothing else.
    build = fn _data, opts ->
      case Map.get(opts, :clip_region) do
        nil -> whole_fn.()
        bounds -> Element.group(strip_fn.(bounds))
      end
    end

    state = %{state(window, plot) | build_element: build}
    top = units(hi)

    if window.drawn == nil or full? do
      {_event, payload, state} = Incremental.initial_render(state)
      {payload, %{window | hi: hi, drawn: top, incremental: state}}
    else
      dx = round((top - window.drawn) * plot.width / span)
      {_event, payload, state} = Incremental.scroll(state, {dx, 0})
      drawn = if payload.mode == "full", do: top, else: window.drawn + dx * span / plot.width
      {payload, %{window | hi: hi, drawn: drawn, incremental: state}}
    end
  end

  defp state(%{incremental: nil}, plot) do
    Incremental.new(
      canvas_size: {plot.width, plot.height},
      data: [],
      x_accessor: fn _ -> 0 end,
      y_accessor: fn _ -> 0 end,
      build_element: fn _data, _opts -> Element.group([]) end,
      margin: %{top: 0, right: 0, bottom: 0, left: 0}
    )
  end

  defp state(%{incremental: state}, _plot), do: state

  # -- values ---------------------------------------------------------------------------

  # The fields of a mark's channels that name the scale (spec/14 §4.3).
  defp fields(kind, mark, scale) do
    for {channel, value} <- Map.get(mark, :channels, %{}),
        Scales.scale_for(kind, mark, channel) == scale,
        field = field(value),
        field != nil,
        do: field
  end

  defp field({:field, field}), do: field
  defp field(field) when is_atom(field), do: field
  defp field(_number), do: nil

  # A value in the window's units: a number as it is, a temporal value in seconds.
  defp units(value) when is_number(value), do: value
  defp units(%DateTime{} = t), do: DateTime.to_unix(t, :microsecond) / 1_000_000

  defp units(%NaiveDateTime{} = t),
    do: NaiveDateTime.diff(t, ~N[1970-01-01 00:00:00], :microsecond) / 1_000_000

  defp units(value) do
    raise ArgumentError,
          "a viewport windows numbers, DateTimes and NaiveDateTimes, got: #{inspect(value)}"
  end

  defp subtract(value, span) when is_number(value), do: value - span

  defp subtract(%DateTime{} = t, span),
    do: DateTime.add(t, -round(span * 1_000_000), :microsecond)

  defp subtract(%NaiveDateTime{} = t, span),
    do: NaiveDateTime.add(t, -round(span * 1_000_000), :microsecond)

  defp subtract(value, _span), do: units(value)
end
