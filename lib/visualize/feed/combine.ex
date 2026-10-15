defmodule Visualize.Feed.Combine do
  @moduledoc """
  One feed over several, routed by window: live data and its history in one slot
  (spec/08 §11.5, D-140, D-159).

  The feeds are listed freshest first — say an in-process `:telemetry` feed holding the
  last hour, then a metresis feed holding everything. A fetch asks the first for the
  window; what it served starts at its delivery's `window` (else its earliest row), and
  the part of the window before that goes to the next feed, and so on. Each later feed's
  rows are trimmed to the half-open window it was asked for, `[from, served)`, so a row
  at a seam comes from the fresher feed alone. The schema must have a window field to
  route by, `:time` or `:number` (spec/08 §11.2, D-154).

  The combination's schema is the first feed's, whole: its version, labels and facts
  (D-159). Every later feed's schema must be compatible with it
  (`Visualize.Data.Schema.compatibility/2`): the same fields by name, compared as
  strings, of the same types, in units that convert — and the same window field, since
  each later feed is asked for a window over its own. Its versions may differ, as a
  process's live feed and a store's history always do. A later feed's rows are read in
  the first schema's words before routing: re-keyed to its spellings, numbers converted
  into its units, and columns only the later schema describes dropped. The first feed's
  rows are never touched.

  A combination honors `:window`, and pushes when its first feed does: its pushes name
  the first's version and pass through unchanged. A budget is passed to every part as a
  request and left to the monitor.

  ## Examples

      iex> alias Visualize.Feed.Signals
      iex> signal = Visualize.Signals.new(:discrete, [:t, :n])
      iex> live = Signals.new(signal, tick: 9, limit: 3)
      iex> history = Signals.new(signal, tick: 9)
      iex> {:ok, delivery} = Visualize.Feed.fetch(Visualize.Feed.Combine.new([live, history]), [2, 9], nil)
      iex> {Enum.map(delivery.rows, & &1.t), delivery.window, delivery.capped}
      {[2, 3, 4, 5, 6, 7, 8, 9], [2, 9], false}

  """

  @behaviour Visualize.Feed

  alias Visualize.Data.{Delivery, Schema, Table}
  alias Visualize.Feed
  alias Visualize.Feed.Window
  alias Visualize.Unit

  @enforce_keys [:feeds]
  defstruct [:feeds]

  @type t :: %__MODULE__{feeds: [Feed.t(), ...]}

  @typedoc """
  A later feed whose schema is not compatible with the first's: its index in the list,
  the field as the first schema spells it, and why (spec/08 §10.1).
  """
  @type incompatibility ::
          {pos_integer(), Schema.name(),
           Schema.incompatibility() | {:window, Schema.name(), Schema.name() | nil}}

  @doc "One feed over several, freshest first."
  @spec new([Feed.t(), ...]) :: t()
  def new([_ | _] = feeds), do: %__MODULE__{feeds: feeds}

  @doc """
  The first feed's `{version, schema}` with the combination's supports:
  `{:error, {:combine_schema, incompatibilities}}` listing every field of every later
  feed whose schema is not compatible with the first's, each `{position, field, reason}`,
  and `{position, window_field, {:window, first, later}}` for a later feed windowing over
  another field (`nil` for none);
  `{:error, :combine_window_field}` when the schema has no window field; and the first
  error of a feed that cannot describe.
  """
  @impl Feed
  def describe(%__MODULE__{feeds: feeds}) do
    with {:ok, {version, schema, supports}, _readings} <- resolve(feeds),
         do: {version, schema, supports}
  end

  # The combination's description and, per feed, how its rows read as the first's.
  defp resolve(feeds) do
    with {:ok, [{version, schema, supports} | _] = described} <- describe_all(feeds, []),
         :ok <- compatible(described),
         :ok <- has_window(schema) do
      time = Feed.window_field(schema)
      readings = Enum.map(described, &reading(&1, version, schema, time))
      {:ok, {version, schema, [:window | Enum.filter(supports, &(&1 == :push))]}, readings}
    end
  end

  defp describe_all([], acc), do: {:ok, Enum.reverse(acc)}

  defp describe_all([feed | rest], acc) do
    case Feed.describe(feed) do
      {:error, reason} -> {:error, reason}
      described -> describe_all(rest, [described | acc])
    end
  end

  defp compatible([{_version, first, _supports} | later]) do
    time = Feed.window_field(first)

    faults =
      later
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {{_version, schema, _supports}, position} ->
        fields =
          case Schema.compatibility(first, schema) do
            :ok -> []
            {:error, faults} -> faults
          end

        (fields ++ same_window(time, Feed.window_field(schema)))
        |> Enum.sort_by(fn {field, _reason} -> to_string(field) end)
        |> Enum.map(fn {field, reason} -> {position, field, reason} end)
      end)

    if faults == [], do: :ok, else: {:error, {:combine_schema, faults}}
  end

  # Routing asks a later feed for a window over its own window field, so it must be the
  # first's, compared as a string (spec/08 §11.5). A first schema with no window field is
  # `has_window/1`'s to refuse.
  defp same_window(nil, _theirs), do: []

  defp same_window(ours, theirs) do
    if theirs != nil and to_string(theirs) == to_string(ours),
      do: [],
      else: [{ours, {:window, ours, theirs}}]
  end

  defp has_window(schema),
    do: if(Feed.window_field(schema), do: :ok, else: {:error, :combine_window_field})

  # How a feed's rows read as the first schema's (spec/08 §11.5): `:same` for a feed of
  # the first's version, whose rows are the first's words already; otherwise its
  # described columns by name as a string, each to the first's spelling and the unit
  # conversion its numbers need, the names only it describes, and the window field's
  # conversion, both ways.
  defp reading({version, _schema, _supports}, version, _first, _time), do: :same

  defp reading({_version, %Schema{fields: theirs} = schema, _supports}, _, first, time) do
    columns =
      Map.new(first.fields, fn {name, description} ->
        {to_string(name), {name, conversion(description, Schema.fetch(schema, name))}}
      end)

    only_theirs =
      for {name, _} <- theirs,
          not Map.has_key?(columns, to_string(name)),
          into: MapSet.new(),
          do: to_string(name)

    window =
      case Map.fetch!(columns, to_string(time)) do
        {_name, {from, to}} -> {{to, from}, {from, to}}
        {_name, nil} -> nil
      end

    %{columns: columns, only_theirs: only_theirs, window: window}
  end

  # `{from, to}` when a number field's units differ; compatibility made sure they convert.
  defp conversion(%{type: :number, unit: to}, {:ok, %{unit: from}}) when from != to,
    do: {from, to}

  defp conversion(_ours, _theirs), do: nil

  @impl Feed
  def fetch(%__MODULE__{feeds: feeds}, window, budget) do
    with {:ok, {version, schema, _supports}, readings} <- resolve(feeds) do
      time = Feed.window_field(schema)
      # A box is routed by its window field's range alone; its region and `latest` are
      # finished over the union (spec/08 §11.5, D-168).
      [from, to] = Window.range(window, time) || [nil, nil]
      parts = Enum.zip(feeds, readings)
      route(parts, time, from, to, budget, [], true, version)
    end
  end

  # Each feed is asked for `[from, upper]`, `upper` what the fresher feeds served (the
  # window's `to` for the first). `parts` is built oldest first, since the route goes back
  # in time.
  defp route([], _time, from, _upper, _budget, parts, _first?, version),
    do: combined(parts, from, version)

  defp route([{feed, reading} | rest], time, from, upper, budget, parts, first?, version) do
    case Feed.fetch(feed, asked(reading, [from, upper]), budget) do
      {:error, reason} ->
        {:error, reason}

      {:ok, delivery} ->
        delivery = read(delivery, reading)
        rows = delivery |> Table.rows() |> seam(time, from, upper, first?)
        served = served_from(delivery, rows, time)
        parts = [%{rows: rows, delivery: delivery, from: served} | parts]

        if covered?(served, from),
          do: combined(parts, from, version),
          else: route(rest, time, from, served || upper, budget, parts, false, version)
    end
  end

  # The window asked of a feed in its own units, and its delivery in the first's words.
  defp asked(%{window: {to_theirs, _to_ours}}, window), do: bounds(window, to_theirs)
  defp asked(_reading, window), do: window

  defp read(delivery, :same), do: delivery

  defp read(%Delivery{} = delivery, reading) do
    rows = delivery |> Table.rows() |> Enum.map(&row(&1, reading))

    window =
      case reading.window do
        {_to_theirs, to_ours} -> bounds(delivery.window, to_ours)
        nil -> delivery.window
      end

    %{delivery | rows: rows, window: window}
  end

  defp bounds(nil, _units), do: nil
  defp bounds([from, to], units), do: [value(from, units), value(to, units)]

  defp row(row, %{columns: columns, only_theirs: only_theirs}) when is_map(row) do
    Enum.reduce(row, %{}, fn {key, v}, acc ->
      spelled = spelled(key)

      case Map.fetch(columns, spelled) do
        {:ok, {name, units}} ->
          Map.put(acc, name, value(v, units))

        :error ->
          if MapSet.member?(only_theirs, spelled), do: acc, else: Map.put(acc, key, v)
      end
    end)
  end

  defp spelled(key) when is_atom(key), do: Atom.to_string(key)
  defp spelled(key), do: key

  defp value(v, {from, to}) when is_number(v), do: Unit.convert(v, from, to)
  defp value(v, _units), do: v

  # The freshest feed keeps its own end; every later part is strictly before what the
  # fresher ones served.
  defp seam(rows, time, from, upper, true), do: Window.trim(rows, time, [from, upper])
  defp seam(rows, time, from, upper, false), do: Window.before(rows, time, from, upper)

  defp served_from(%Delivery{window: [served, _to]}, _rows, _time) when served != nil,
    do: served

  defp served_from(_delivery, rows, time),
    do: Enum.reduce(rows, nil, &Window.earliest(&2, Table.get(&1, time)))

  defp covered?(nil, _from), do: false
  defp covered?(_served, nil), do: false
  defp covered?(served, from), do: Window.compare(served, from) != :gt

  defp combined([oldest | _] = parts, from, version) do
    freshest = List.last(parts)

    capped =
      if from == nil, do: oldest.delivery.capped, else: not covered?(oldest.from, from)

    {:ok,
     Delivery.new(Enum.flat_map(parts, & &1.rows),
       window: [Window.latest(oldest.from, from), window_to(freshest.delivery)],
       resolution: freshest.delivery.resolution,
       capped: capped,
       schema: version
     )}
  end

  defp window_to(%Delivery{window: [_from, to]}), do: to
  defp window_to(_delivery), do: nil

  @impl Feed
  def subscribe(%__MODULE__{feeds: [first | _]}, pid), do: Feed.subscribe(first, pid)

  @impl Feed
  def unsubscribe(%__MODULE__{feeds: [first | _]}, ref), do: Feed.unsubscribe(first, ref)
end
