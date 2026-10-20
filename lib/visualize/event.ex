defmodule Visualize.Event do
  @moduledoc """
  The one shape of every interaction the library delivers (spec/10 §19, D-170).

  A host receives each as `{:visualize_event, id, %Visualize.Event{}}`, `id` the chart's or
  the board's component id: a mark's declared event on a plain chart through
  `Visualize.Components.Chart`, and on a board a mark's event, a drill, a host-owned brush
  and a selection change through `Visualize.Components.Board` (spec/15 §9.2).

      def handle_info({:visualize_event, "sales", %Visualize.Event{event: "point_click", row: row}}, socket) do
        {:noreply, assign(socket, picked: row)}
      end

  Every field is always present:

    * `event` - a string for an event a design declares (a mark's tooltip `event`,
      spec/14 §5.7, an atom there delivered as its string), an atom for one the runtime
      raises: `:drill`, `:brush`, `:select`
    * `cell` - the board cell's name; `nil` outside a board and for the board's own events
    * `frame` - the design's frame the item was drawn in, or `nil`
    * `item` - `{mark, identity}`: the mark's `id`, else its type, and the row's identity —
      the declared one (D-167), bare for one field and a map for several, else the
      inference a board's pick uses — or `nil` when the row names nothing
    * `path` - the items from the innermost out to the frame: `[item]`, or `[]`
    * `row` - the row the clicked element was drawn from, typed as the source holds it
    * `at` - the pointer in the frame's plot area, `%{x, y}` in pixels, or `nil`
    * `value` - the event's data: `%{}` for a declared event, the runtime event's own
    * `modifiers` - the keys held: `:shift`, `:alt`, `:ctrl` and `:meta`, in that order

  A click arrives from `TooltipHook` as the wire event `visualize_event` (spec/10 §12.3),
  carrying the clicked element's key and the token of the drawing it landed on.
  `decode/1` reads it and `resolve/3` resolves it against the applied chart that was drawn,
  or drops it: a click never names a row other than the one drawn.
  """

  import Visualize.Chart.Names, only: [is_name: 1]

  alias Visualize.Chart
  alias Visualize.Chart.{Applied, Frame, Mark, Names}
  alias Visualize.Data.{Schema, Table}

  defstruct event: nil,
            cell: nil,
            frame: nil,
            item: nil,
            path: [],
            row: nil,
            at: nil,
            value: %{},
            modifiers: []

  @type modifier :: :shift | :alt | :ctrl | :meta
  @type item :: {atom() | String.t(), term()}

  @type t :: %__MODULE__{
          event: String.t() | atom(),
          cell: atom() | nil,
          frame: atom() | nil,
          item: item() | nil,
          path: [item()],
          row: map() | nil,
          at: %{x: number(), y: number()} | nil,
          value: map(),
          modifiers: [modifier()]
        }

  @typedoc """
  A click as `decode/1` reads it from the wire: the declared name, the frame's name as
  sent, the mark's position among its frame's marks, the row's ordinal in the mark's
  realized rows, the drawing's token, the pointer in the chart's user units and the
  modifiers.
  """
  @type click :: %{
          event: String.t(),
          frame: String.t() | nil,
          mark: non_neg_integer(),
          row: non_neg_integer(),
          drawn: String.t() | nil,
          at: %{x: number(), y: number()} | nil,
          modifiers: [modifier()]
        }

  @modifiers [shift: "shift", alt: "alt", ctrl: "ctrl", meta: "meta"]
  @not_names [nil, true, false]

  @doc """
  The wire's `visualize_event` params as a click (spec/10 §19.2): `{:ok, click}`, or
  `:error` for params of any other shape. No atom is created: the frame stays the string
  it was sent as, and a modifier other than the four is dropped.

      iex> Visualize.Event.decode(%{"event" => "point_click", "frame" => "main", "mark" => 1,
      ...>   "row" => 4, "drawn" => "7", "at" => %{"x" => 12.5, "y" => 3}, "modifiers" => ["shift", "hyper"]})
      {:ok, %{event: "point_click", frame: "main", mark: 1, row: 4, drawn: "7",
              at: %{x: 12.5, y: 3}, modifiers: [:shift]}}
      iex> Visualize.Event.decode(%{"event" => "point_click", "mark" => -1, "row" => 0})
      :error
  """
  @spec decode(map()) :: {:ok, click()} | :error
  def decode(%{"event" => event, "mark" => mark, "row" => row} = params)
      when is_binary(event) and event != "" and is_integer(mark) and mark >= 0 and
             is_integer(row) and row >= 0 do
    with {:ok, frame} <- optional_string(Map.get(params, "frame")),
         {:ok, drawn} <- optional_string(Map.get(params, "drawn")),
         {:ok, at} <- point(Map.get(params, "at")),
         {:ok, modifiers} <- modifiers(Map.get(params, "modifiers", [])) do
      {:ok,
       %{
         event: event,
         frame: frame,
         mark: mark,
         row: row,
         drawn: drawn,
         at: at,
         modifiers: modifiers
       }}
    end
  end

  def decode(_params), do: :error

  defp optional_string(nil), do: {:ok, nil}
  defp optional_string(value) when is_binary(value), do: {:ok, value}
  defp optional_string(_value), do: :error

  defp point(nil), do: {:ok, nil}

  defp point(%{"x" => x, "y" => y}) when is_number(x) and is_number(y),
    do: {:ok, %{x: x, y: y}}

  defp point(_value), do: :error

  defp modifiers(names) when is_list(names) do
    if Enum.all?(names, &is_binary/1),
      do: {:ok, for({atom, name} <- @modifiers, name in names, do: atom)},
      else: :error
  end

  defp modifiers(_names), do: :error

  @doc "As `resolve/3` with `[]` options."
  @spec resolve(click(), Applied.t()) :: {:ok, t()} | :error
  def resolve(click, %Applied{} = applied), do: resolve(click, applied, [])

  @doc """
  A click resolved against the drawing of an applied chart (spec/10 §19.2, D-170):
  `{:ok, event}`, or `:error` when the click's `drawn` is not the drawing's token, or the
  applied chart has no frame of the click's name, no mark at its position, no row at its
  ordinal of that mark's realized rows (`Visualize.Chart.Mark.rows/3` over the applied
  chart's sources), or when that mark declares no event of the click's name.

  The row is the realized row, typed as the source holds it; the item is the slot's
  declared identity, else the inference of `identity/3`; `at` is the pointer less the
  frame's box and margins, in its plot area.

  ## Options

    * `:drawn` - the token of the drawing the caller holds, `nil` by default; a click
      carrying another is dropped, never resolved against newer rows
    * `:cell` - the event's `cell` (default `nil`)
  """
  @spec resolve(click(), Applied.t(), keyword()) :: {:ok, t()} | :error
  def resolve(%{drawn: drawn} = click, %Applied{} = applied, opts) do
    with true <- drawn == Keyword.get(opts, :drawn),
         %Frame{} = frame <- frame_named(applied, click.frame),
         mark when is_map(mark) <- Enum.at(frame.marks, click.mark) do
      rows = Mark.rows(frame, mark, applied.sources)
      schema = schema_of(applied.schemas, mark)
      origin = origin(frame)
      build(click, mark, rows, schema, frame.name, origin, Keyword.take(opts, [:cell]))
    else
      _dropped -> :error
    end
  end

  # The applied chart's frame whose name the click sent as a string; a hand-assembled
  # applied chart with no `frames` has its one frame.
  defp frame_named(%Applied{frames: frames, frame: frame}, name) do
    frames = if frames in [nil, %{}], do: %{frame.name => frame}, else: frames
    Enum.find_value(frames, fn {key, frame} -> if to_string(key) == name, do: frame end)
  end

  # Where a frame's plot area starts in the chart's user units (spec/14 §4.2).
  defp origin(%Frame{box: [bx, by | _], size: size, margin: margin}),
    do: {bx * size.width + margin.left, by * size.height + margin.top}

  @doc false
  # The event of a click on the drawing `rows` were drawn as (D-170): the mark must declare
  # the click's name and have a row at its ordinal. `origin` is the plot area's corner in
  # the chart's user units. A board's cell resolves through it against its compiled chart.
  @spec build(
          click(),
          map(),
          [map()],
          Schema.t() | nil,
          atom(),
          {number(), number()},
          keyword()
        ) ::
          {:ok, t()} | :error
  def build(click, mark, rows, schema, frame, {ox, oy}, opts) do
    with true <- declares?(mark, click.event),
         row when is_map(row) <- Enum.at(rows, click.row) do
      row = Keyword.get(opts, :row, & &1).(row)
      item = item(mark, identity(mark, row, schema))

      {:ok,
       %__MODULE__{
         event: click.event,
         cell: Keyword.get(opts, :cell),
         frame: frame,
         item: item,
         path: List.wrap(item),
         row: row,
         at: click.at && %{x: click.at.x - ox, y: click.at.y - oy},
         value: %{},
         modifiers: click.modifiers
       }}
    else
      _dropped -> :error
    end
  end

  defp declares?(mark, name), do: name in declared_names(mark)

  # The events a mark's tooltip declares, as strings: a click's `event` and a secondary
  # gesture's `context_event` (spec/14 §5.7, D-199).
  defp declared_names(mark) do
    case Map.get(mark, :tooltip) do
      tooltip when is_map(tooltip) ->
        for key <- [:event, :context_event],
            event = Map.get(tooltip, key),
            is_binary(event) or (is_atom(event) and event not in @not_names),
            do: name(event)

      _none ->
        []
    end
  end

  @doc """
  The event names a chart's marks declare (spec/14 §5.7), as strings, sorted and unique:
  each mark's `event` and `context_event` (D-199).

      iex> chart = Visualize.Chart.from_map!(%{version: 2, sources: %{s: %{fields: [:x, :y]}},
      ...>   frames: %{main: %{kind: :cartesian, scales: %{x: %{kind: :linear}, y: %{kind: :linear}}}},
      ...>   marks: [%{type: :circle, data: :s, channels: %{x: :x, y: :y}, tooltip: %{event: :point_click}},
      ...>           %{type: :line, data: :s, channels: %{x: :x, y: :y}, tooltip: %{event: "line_click"}}]})
      iex> Visualize.Event.declared(chart)
      ["line_click", "point_click"]
  """
  @spec declared(Chart.t() | Applied.t()) :: [String.t()]
  def declared(%Applied{chart: chart}), do: declared(chart)

  def declared(%Chart{marks: marks}) do
    marks
    |> List.wrap()
    |> Enum.flat_map(&declared_names/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  A declared event name as the event's string (spec/14 §5.7): an atom's name, or the
  string itself.

      iex> Visualize.Event.name(:point_click)
      "point_click"
      iex> Visualize.Event.name("point_click")
      "point_click"
  """
  @spec name(atom() | String.t()) :: String.t()
  def name(name) when is_binary(name), do: name
  def name(name) when is_atom(name) and name not in @not_names, do: Atom.to_string(name)

  @doc """
  A row's identity in the board's selection form (spec/15 §13.2, D-167): `{field, value}`
  for one field, a map for a composite declared identity, or `nil`.

  The identity the schema declares comes first, and a row that lacks it names nothing
  rather than being guessed at. When the schema declares none — or there is no schema — it
  is inferred: the mark's `series` channel when it reads a field, else the first field by
  name that the schema types `:category` and the row has a value for.

      iex> schema = Visualize.Data.Schema.new!(%{svc: %{type: :category}, v: %{type: :number}})
      iex> Visualize.Event.identity(%{type: :circle}, %{svc: "api", v: 3}, schema)
      {"svc", "api"}
      iex> Visualize.Event.identity(%{type: :line, channels: %{series: :host}}, %{host: "mx1"}, nil)
      {"host", "mx1"}
      iex> Visualize.Event.identity(%{type: :circle}, %{v: 3}, nil)
      nil
  """
  @spec identity(map(), map(), Schema.t() | nil) :: Visualize.Board.identity() | nil
  def identity(mark, row, %Schema{} = schema) when is_map(row) do
    case Schema.identity(schema) do
      [] -> series_identity(mark, row) || category_identity(schema, row)
      fields -> declared_identity(fields, Schema.identity(schema, row))
    end
  end

  def identity(mark, row, nil) when is_map(row), do: series_identity(mark, row)

  # The declared identity as a selection names it: the pair for one field, the map for
  # several, `nil` for a row that lacks it; a field is named by its string (D-195).
  defp declared_identity(_fields, nil), do: nil
  defp declared_identity([field], value), do: {Names.name(field), value}
  defp declared_identity(_fields, values), do: Names.keys(values)

  defp series_identity(mark, row) do
    case mark |> Map.get(:channels, %{}) |> series_channel() do
      {:field, field} when is_name(field) -> pair(field, row)
      field when is_name(field) and field not in @not_names -> pair(field, row)
      _other -> nil
    end
  end

  defp series_channel(channels) when is_map(channels), do: Map.get(channels, :series)
  defp series_channel(_channels), do: nil

  defp category_identity(%Schema{fields: fields}, row) do
    fields
    |> Enum.filter(fn {_name, field} -> Map.get(field, :type) == :category end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.sort()
    |> Enum.find_value(&pair(&1, row))
  end

  defp pair(field, row) do
    case Table.get(row, field) do
      nil -> nil
      value -> {Names.name(field), value}
    end
  end

  @doc """
  An event's item (spec/10 §19.1): `{mark, identity}`, the mark's `id`, else its type,
  and the identity bare for one field, or `nil` for a `nil` identity.

      iex> Visualize.Event.item(%{type: :circle, id: :point}, {:service, "api"})
      {:point, "api"}
      iex> Visualize.Event.item(%{type: :circle}, %{host: "mx1", iface: "eth0"})
      {:circle, %{host: "mx1", iface: "eth0"}}
      iex> Visualize.Event.item(%{type: :circle}, nil)
      nil
  """
  @spec item(map(), Visualize.Board.identity() | nil) :: item() | nil
  def item(_mark, nil), do: nil
  def item(mark, {_field, value}), do: {mark_name(mark), value}
  def item(mark, identity) when is_map(identity), do: {mark_name(mark), identity}

  defp mark_name(%{id: id}) when id != nil, do: id
  defp mark_name(mark), do: Map.get(mark, :type)

  # The schema of the slot a mark reads.
  @doc false
  @spec schema_of(map() | nil, map()) :: Schema.t() | nil
  def schema_of(schemas, mark) when is_map(schemas) do
    case Map.get(schemas, slot_of(mark)) do
      %Schema{} = schema -> schema
      _none -> nil
    end
  end

  def schema_of(nil, _mark), do: nil

  defp slot_of(%{data: %{source: slot}}) when is_name(slot), do: slot
  defp slot_of(%{data: slot}) when is_name(slot), do: slot
  defp slot_of(_mark), do: nil
end
