defmodule Visualize.Feed.Conformance do
  @moduledoc """
  The feed conformance kit: the contract of spec/08 §10–§11 as checks every provider runs
  (spec/08 §12, D-145).

  `check/3` runs one of six checks against a feed and answers its **findings**,
  `{check, reason}` terms, `[]` for a feed that passes; `check/2` runs them all and
  `format/1` words a finding. `use Visualize.Feed.Conformance, opts` inside a module that
  uses `ExUnit.Case` writes one test per check that fails with the findings:

      defmodule MyApp.FeedTest do
        use ExUnit.Case, async: true

        use Visualize.Feed.Conformance,
          feed: MyApp.Feed.new(),
          windows: [nil, [10, 20]],
          push: &MyApp.Feed.emit/1
      end

  The kit drives the feed through `Visualize.Feed` alone and calls every callback in a
  process of its own, so a callback that raises is a finding (`{:raised, call, reason}`),
  not a crash of the check. It references no ExUnit function itself: `describe`, `test`
  and `flunk` appear only in the code `use` writes into the caller's module.

  ## Options

    * `feed:` — the feed (to `use`: an expression, evaluated in each test).
    * `windows:` — the windows fetched, `[nil]` by default; a feed naming `:window` needs one
      with a bound.
    * `budgets:` — the budgets each window is fetched with, `[nil, 5]`.
    * `push:` — a function of the feed that makes it push; a feed naming `:push` needs one.
    * `down:` — a feed of the same provider that cannot answer, held to error values.
    * `timeout:` — milliseconds a callback may take, and the wait for a first push (`1000`).
    * `quiet:` — milliseconds of silence that end a push (`100`).
    * `name:` — to `use` only: the `describe` block's name, `"feed conformance"`.

  ## Examples

      iex> signal = Visualize.Signals.new(:discrete, [:t, :n], window: 3)
      iex> feed = Visualize.Feed.Signals.new(signal, tick: 10)
      iex> Visualize.Feed.Conformance.check(feed, windows: [nil, [2, 6]])
      []

  """

  alias Visualize.Data.{Delivery, Schema, Table}
  alias Visualize.Feed
  alias Visualize.Feed.Conformance.{Box, Words}
  alias Visualize.Feed.Window

  @checks [:describe, :deliveries, :supports, :push, :errors, :unsubscribe]

  @defaults [windows: [nil], budgets: [nil, 5], push: nil, down: nil, timeout: 1000, quiet: 100]

  @titles %{
    describe: "a valid schema and a stable version",
    deliveries: "deliveries are well formed and honest",
    supports: "the declared capabilities are true",
    push: "the schema arrives before the data",
    errors: "errors are values, not crashes",
    unsubscribe: "unsubscribing stops pushes"
  }

  # A window no feed can read as one of its own (spec/08 §12.3, `:errors`).
  @unreadable [
    [:not, :a_time],
    [~U[2000-01-01 00:00:00Z], ~U[2000-01-02 00:00:00Z]],
    [0, 1],
    [0, ~U[2000-01-01 00:00:00Z]],
    %{ranges: %{"no such field" => [0, 1]}, latest: true}
  ]

  @spans %{second: 1, minute: 60, hour: 3600, day: 86_400, week: 604_800}

  @typedoc "One of the six checks."
  @type check :: :describe | :deliveries | :supports | :push | :errors | :unsubscribe

  @typedoc "A fault one check found: `{check, reason}` (spec/08 §12.3)."
  @type finding :: {check(), term()}

  @doc """
  One ExUnit test per check, in a `describe` block, written into a module that uses
  `ExUnit.Case` (spec/08 §12.1). `feed:` and `down:` are expressions evaluated in each
  test, in the test process.
  """
  defmacro __using__(opts) do
    opts = Keyword.validate!(opts, [:feed, name: "feed conformance"] ++ @defaults)
    feed = Keyword.get(opts, :feed) || raise(ArgumentError, "the conformance kit needs feed:")
    name = Keyword.fetch!(opts, :name)
    is_binary(name) || raise ArgumentError, "the conformance kit's name: is a string literal"

    {down, opts} = opts |> Keyword.drop([:feed, :name]) |> Keyword.pop(:down)

    tests =
      for check <- @checks do
        # Only the errors check reads `down:`, so only its test evaluates the expression.
        opts = if check == :errors, do: [{:down, down} | opts], else: opts

        quote do
          test unquote("#{check}: #{@titles[check]}") do
            case Visualize.Feed.Conformance.check(unquote(check), unquote(feed), unquote(opts)) do
              [] ->
                :ok

              findings ->
                flunk(Enum.map_join(findings, "\n", &Visualize.Feed.Conformance.format/1))
            end
          end
        end
      end

    quote do
      describe unquote(name) do
        unquote({:__block__, [], tests})
      end
    end
  end

  @doc "The six checks, in the order `check/2` runs them."
  @spec checks() :: [check(), ...]
  def checks, do: @checks

  @doc "Every check's findings for a feed, concatenated in the order of `checks/0`."
  @spec check(Feed.t(), keyword()) :: [finding()]
  def check(feed, opts) when is_list(opts), do: Enum.flat_map(@checks, &check(&1, feed, opts))

  @doc """
  One check's findings for a feed, `[]` when it passes (spec/08 §12.3). Raises
  `ArgumentError` for an unknown check or option.
  """
  @spec check(check(), Feed.t(), keyword()) :: [finding()]
  def check(check, feed, opts) when check in @checks and is_list(opts) do
    o = opts |> Keyword.validate!(@defaults) |> Map.new()
    for reason <- run(check, feed, o), do: {check, reason}
  end

  def check(check, _feed, _opts),
    do:
      raise(
        ArgumentError,
        "not a conformance check: #{inspect(check)}, one of #{inspect(@checks)}"
      )

  # -- describe ------------------------------------------------------------------------------

  defp run(:describe, feed, o) do
    with {:ok, {version, schema, supports}} <- described(feed, o) do
      schema_faults(version, schema) ++
        window_field(schema, supports) ++
        case described(feed, o) do
          {:ok, {^version, ^schema, _supports}} -> []
          {:ok, {other, _schema, _supports}} -> [{:unstable, version, other}]
          faults -> faults
        end
    end
  end

  # -- deliveries ----------------------------------------------------------------------------

  defp run(:deliveries, feed, o) do
    with {:ok, described} <- described(feed, o) do
      for window <- o.windows, budget <- o.budgets do
        probe(feed, {window, budget}, described, o)
      end
      |> List.flatten()
    end
  end

  # -- supports ------------------------------------------------------------------------------

  defp run(:supports, feed, o) do
    with {:ok, {_version, schema, supports}} <- described(feed, o) do
      if supports -- Feed.capabilities() == [] and
           Enum.uniq(supports) == supports do
        window_honored(feed, supports, Feed.window_field(schema), o) ++
          Box.region(&fetched(feed, &1, o), supports, schema, o) ++
          Box.latest(&fetched(feed, &1, o), supports, schema, o) ++
          budget_honored(feed, supports, o) ++ push_honored(feed, supports, o)
      else
        [{:supports, supports}]
      end
    end
  end

  # -- push ----------------------------------------------------------------------------------

  defp run(:push, feed, o) do
    with {:ok, {_version, _schema, supports}} <- described(feed, o),
         true <- pushes?(supports) || [],
         true <- o.push != nil || [{:no_probe, :push}],
         {:ok, ref} <- subscribed(feed, o) do
      handshake =
        receive do
          {:visualize_feed, ^ref, message} -> message
        after
          0 -> :nothing
        end

      pushed = stimulate(feed, o)
      messages = collect(ref, System.monotonic_time(:millisecond) + o.timeout, o.quiet, false, [])
      unsubscribed(feed, ref, o)
      flush(ref)

      sequence(handshake, messages, o) ++ pushed
    end
  end

  # -- errors --------------------------------------------------------------------------------

  defp run(:errors, feed, o) do
    unreadable =
      for window <- @unreadable do
        case call(fn -> Feed.fetch(feed, window, nil) end, {:fetch, window, nil}, o) do
          {:ok, {:ok, %Delivery{}}} -> []
          {:ok, {:error, _reason}} -> []
          {:ok, other} -> [{:not_a_value, {:fetch, window, nil}, other}]
          {:error, fault} -> [fault]
        end
      end

    List.flatten(unreadable) ++ unknown_ref(feed, o) ++ down(o.down, o)
  end

  # -- unsubscribe ---------------------------------------------------------------------------

  defp run(:unsubscribe, feed, o) do
    with {:ok, {_version, _schema, supports}} <- described(feed, o) do
      if pushes?(supports), do: silenced(feed, o), else: unknown_ref(feed, o)
    end
  end

  # -- describing ----------------------------------------------------------------------------

  # The feed's description, or the findings that stop a check that needs one.
  defp described(feed, o) do
    case call(fn -> Feed.describe(feed) end, :describe, o) do
      {:ok, {version, %Schema{}, supports} = answer}
      when is_binary(version) and is_list(supports) ->
        {:ok, answer}

      {:ok, {:error, reason}} ->
        [{:describe_error, reason}]

      {:ok, other} ->
        [{:not_described, other}]

      {:error, fault} ->
        [fault]
    end
  end

  # The schema is one `Schema.new/1` accepts, and the version is its content hash. A
  # field's measure that the vocabulary refuses is its own finding, naming the field
  # (D-157); the schema's other faults stay together.
  defp schema_faults(version, %Schema{fields: fields}) do
    case Schema.new(fields) do
      {:ok, %Schema{version: ^version}} ->
        []

      {:ok, %Schema{version: computed}} ->
        [{:version, version, computed}]

      {:error, errors} ->
        {measures, others} = Enum.split_with(errors, &measure?/1)
        invalid = if others == [], do: [], else: [{:schema_invalid, others}]
        invalid ++ for({[field, _key], reason} <- measures, do: {:measure, field, reason})
    end
  end

  defp measure?({[_field, :unit], {:unit, _code, _reason}}), do: true
  defp measure?({[_field, :quantity], {:unknown_quantity, _quantity}}), do: true
  defp measure?({[_field, :quantity], {:quantity, _quantity, _code}}), do: true
  defp measure?(_error), do: false

  # A feed that honors windows names the field they are over (spec/08 §10.1, D-154): one
  # `window: true`, or a single `:time` field.
  defp window_field(schema, supports) do
    if is_list(supports) and :window in supports and Feed.window_field(schema) == nil,
      do: [{:no_window_field, Enum.sort(for({name, %{type: :time}} <- schema.fields, do: name))}],
      else: []
  end

  defp pushes?(supports), do: :push in supports

  # -- one probe of the deliveries check -----------------------------------------------------

  defp probe(feed, {window, _budget} = request, {_version, schema, _supports} = described, o) do
    case Window.check(window, schema) do
      :ok -> probed(feed, request, described, o)
      {:error, faults} -> [{:probe, window, faults}]
    end
  end

  defp probed(feed, request, {version, schema, supports}, o) do
    with {:ok, delivery, rows} <- fetched(feed, request, o) do
      time = Feed.window_field(schema)
      served = delivery.window

      honest =
        version(delivery, request, version) ++
          fields(rows, request, schema) ++
          times(rows, request, time, Feed.window_type(schema)) ++
          instants(rows, request, schema, time) ++
          identities(rows, request, schema) ++
          outside(rows, request, time, served) ++
          resolution(rows, request, schema, time, delivery.resolution)

      # The clauses that compare against a second fetch need the rows' window field to
      # hold values of its type.
      if Enum.any?(honest, &(elem(&1, 0) == :window_value)) do
        honest
      else
        honest ++
          complete(feed, request, delivery, rows, time, o) ++
          capped(feed, request, delivery, rows, time, o) ++
          reduced(feed, request, delivery, rows, supports, time, o)
      end
    end
  end

  # `{:ok, delivery, rows}`, the rows read and well formed, or the findings that end the probe.
  defp fetched(feed, {window, budget} = request, o) do
    case call(fn -> Feed.fetch(feed, window, budget) end, {:fetch, window, budget}, o) do
      {:ok, {:ok, %Delivery{} = delivery}} ->
        case well_formed(delivery, request, o) do
          {[], rows} -> {:ok, delivery, rows}
          {faults, _rows} -> faults
        end

      {:ok, {:error, reason}} ->
        [{:fetch_error, request, reason}]

      {:ok, other} ->
        [{:not_a_delivery, request, other}]

      {:error, fault} ->
        [fault]
    end
  end

  # A delivery's fields of their kinds (spec/08 §10.4), and its rows read as maps.
  defp well_formed(%Delivery{} = d, request, o) do
    {rows, row_faults} = read_rows(d.rows, request, o)

    faults =
      row_faults ++
        malformed(:window, served_window?(d.window), d.window, request) ++
        malformed(:capped, is_boolean(d.capped), d.capped, request) ++
        malformed(:reduced_by, d.reduced_by in [nil, :feed, :visualize], d.reduced_by, request) ++
        malformed(:schema, is_nil(d.schema) or is_binary(d.schema), d.schema, request) ++
        malformed(:resolution, resolution?(d.resolution), d.resolution, request) ++
        if(d.reduced_by == :visualize, do: [{:reduced_by, request, :visualize}], else: [])

    {faults, rows}
  end

  defp malformed(_field, true, _value, _request), do: []
  defp malformed(field, false, value, request), do: [{:malformed, request, field, value}]

  # Rows are read in a process of their own: a source `Table.rows/1` cannot read raises.
  defp read_rows(%Delivery{} = rows, request, _o), do: {[], [{:malformed, request, :rows, rows}]}

  defp read_rows(source, request, o) do
    case call(fn -> Table.rows(source) end, :rows, o) do
      {:ok, rows} when is_list(rows) ->
        case Enum.find(rows, &(not is_map(&1))) do
          nil -> {rows, []}
          row -> {[], [{:malformed, request, :rows, row}]}
        end

      _raised ->
        {[], [{:malformed, request, :rows, source}]}
    end
  end

  defp served_window?(nil), do: true

  defp served_window?([from, to]),
    do: bound?(from) and bound?(to) and (from == nil or to == nil or ordered?(from, to))

  defp served_window?(_other), do: false

  defp bound?(value), do: value == nil or Window.time?(value)

  defp ordered?(from, to), do: kind(from) == kind(to) and Window.compare(from, to) != :gt

  defp resolution?(nil), do: true
  defp resolution?(r) when is_number(r), do: r > 0
  defp resolution?(r) when is_boolean(r), do: false
  defp resolution?(r), do: is_atom(r)

  defp version(%Delivery{schema: version}, _request, version), do: []

  defp version(%Delivery{schema: named}, request, described),
    do: [{:version, request, named, described}]

  defp fields(rows, request, schema) do
    rows
    |> Stream.flat_map(&Map.keys/1)
    |> Stream.uniq()
    |> Enum.reject(&described?(schema, &1))
    |> Enum.map(&{:undescribed_field, request, &1})
  end

  # A field name is an atom or a string; a row keyed otherwise holds an undescribed field.
  defp described?(schema, field) when is_atom(field) or is_binary(field),
    do: match?({:ok, _}, Schema.fetch(schema, field))

  defp described?(_schema, _field), do: false

  # The window field holds values of its type: instants for `:time`, numbers for
  # `:number` (spec/08 §12.3, D-154), or `nil`.
  defp times(_rows, _request, nil, _type), do: []

  defp times(rows, request, time, type) do
    case Enum.find(rows, &(not of_type?(Table.get(&1, time), type))) do
      nil -> []
      row -> [{:window_value, request, Table.get(row, time)}]
    end
  end

  defp of_type?(nil, _type), do: true
  defp of_type?(value, :time), do: Window.instant?(value)
  defp of_type?(value, :number), do: is_number(value)

  # Every other `:time` field holds instants as a time scale reads them, or `nil`: a tick
  # written under `:time` is caught here rather than in a frame (D-154).
  defp instants(rows, request, schema, time) do
    for {field, %{type: :time}} <- Enum.sort(schema.fields),
        field != time,
        row = Enum.find(rows, &(not instant_or_nil?(Table.get(&1, field)))),
        row != nil,
        do: {:not_an_instant, request, field, Table.get(row, field)}
  end

  # Every row has a value for each field the schema declares identity (spec/08 §12.3,
  # D-167): a row that does not say what it is about cannot be grouped with its entity.
  defp identities(rows, request, schema) do
    for field <- Schema.identity(schema),
        Enum.any?(rows, &(Table.get(&1, field) == nil)),
        do: {:no_identity, request, field}
  end

  defp instant_or_nil?(nil), do: true
  defp instant_or_nil?(value), do: Table.temporal?(value)

  # Every row's time within the window the delivery says it served.
  defp outside(_rows, _request, nil, _served), do: []
  defp outside(_rows, _request, _time, nil), do: []

  defp outside(rows, request, time, served) do
    case Enum.find(rows, &outside?(Table.get(&1, time), served)) do
      nil -> []
      row -> [{:outside_served, request, Table.get(row, time), served}]
    end
  end

  # A row with no time is held to no window; a time of another kind than a bound is outside.
  defp outside?(nil, _window), do: false
  defp outside?(time, window), do: not inside?(time, window)

  defp inside?(_time, nil), do: true

  defp inside?(time, [from, to]),
    do:
      (from == nil or kind(from) == kind(time)) and (to == nil or kind(to) == kind(time)) and
        Window.within?(time, [from, to])

  defp kind(value) when is_number(value), do: :number
  defp kind(%module{}), do: module
  defp kind(_other), do: :other

  # The served window covers what the feed holds in it: every row an open fetch serves
  # within both windows, up to the earlier end, is in the delivery.
  defp complete(
         _feed,
         {_window, budget},
         %Delivery{reduced_by: by, window: served},
         _rows,
         time,
         _o
       )
       when budget != nil or by != nil or served == nil or time == nil,
       do: []

  defp complete(
         feed,
         {window, _budget} = request,
         %Delivery{window: [_from, to] = served},
         rows,
         time,
         o
       ) do
    case open(feed, window, time, to, o) do
      {:ok, open} ->
        span = intersect(served, open.window)
        held = MapSet.new(rows)

        missing =
          Enum.count(open.rows, fn row ->
            not MapSet.member?(held, row) and not outside?(Table.get(row, time), span) and
              Table.get(row, time) != nil
          end)

        if missing > 0, do: [{:missing, request, missing, served}], else: []

      faults ->
        faults
    end
  end

  # `capped` is true only with a shortfall, and false only when the feed held nothing
  # between the asked `from` and where it served from. Of a box, the asked window is its
  # window field's range (spec/08 §12.3, D-168).
  defp capped(feed, {%{} = box, budget} = request, delivery, rows, time, o) when time != nil do
    case Window.range(box, time) do
      [_from, _to] = range ->
        Enum.map(capped(feed, {range, budget}, delivery, rows, time, o, box), fn
          {:capped, _request, served} -> {:capped, request, served}
          {:uncapped, _request, count} -> {:uncapped, request, count}
          finding -> finding
        end)

      _none ->
        []
    end
  end

  defp capped(feed, request, delivery, rows, time, o),
    do: capped(feed, request, delivery, rows, time, o, nil)

  defp capped(_feed, {nil, _budget}, _delivery, _rows, _time, _o, _box), do: []
  defp capped(_feed, {[nil, _to], _budget}, _delivery, _rows, _time, _o, _box), do: []
  defp capped(_feed, _request, _delivery, _rows, nil, _o, _box), do: []

  defp capped(
         _feed,
         {[from, _to], _budget} = request,
         %Delivery{capped: true, window: served},
         _rows,
         _time,
         _o,
         _box
       ) do
    case served do
      [start, _end] when start != nil ->
        if comparable?(start, from) and Window.compare(start, from) == :gt,
          do: [],
          else: [{:capped, request, served}]

      _no_start ->
        [{:capped, request, served}]
    end
  end

  defp capped(feed, {[from, to], _budget} = request, %Delivery{} = delivery, rows, time, o, box) do
    start = start(delivery, rows, time)

    case open(feed, box || [from, to], time, later(end_of(delivery.window), to), o) do
      {:ok, open} ->
        before =
          Enum.count(open.rows, fn row ->
            t = Table.get(row, time)
            t != nil and inside?(t, [from, to]) and (start == nil or before?(t, start))
          end)

        if before > 0, do: [{:uncapped, request, before}], else: []

      faults ->
        faults
    end
  end

  # Where a delivery starts: its served window's `from`, else its earliest row.
  defp start(%Delivery{window: [from, _to]}, _rows, _time) when from != nil, do: from

  defp start(_delivery, rows, time) do
    rows
    |> Enum.map(&Table.get(&1, time))
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(nil, &earlier/2)
  end

  defp end_of([_from, to]), do: to
  defp end_of(nil), do: nil

  defp before?(time, start), do: comparable?(time, start) and Window.compare(time, start) == :lt

  # Window arithmetic over the times a feed served, which a broken feed may not give of one
  # kind: a bound of another kind than the other is kept, never compared.
  defp comparable?(a, b), do: Window.time?(a) and Window.time?(b) and kind(a) == kind(b)

  defp earlier(nil, b), do: b
  defp earlier(a, nil), do: a
  defp earlier(a, b), do: if(comparable?(a, b) and Window.compare(b, a) == :lt, do: b, else: a)

  defp later(nil, b), do: b
  defp later(a, nil), do: a
  defp later(a, b), do: if(comparable?(a, b) and Window.compare(b, a) == :gt, do: b, else: a)

  defp intersect(window, nil), do: window
  defp intersect([f1, t1], [f2, t2]), do: [later(f1, f2), earlier(t1, t2)]

  # The open fetch, `[nil, to]` with no budget, read and well formed: of a box, the box
  # with its window field's range opened at `from`, its region and `latest` kept.
  defp open(feed, window, time, to, o) do
    request = {opened(window, time, to), nil}

    case fetched(feed, request, o) do
      {:ok, delivery, rows} -> {:ok, %{delivery | rows: rows}}
      faults -> faults
    end
  end

  defp opened(%{} = box, time, to) do
    ranges = Map.get(box, :ranges, %{})
    others = Map.reject(ranges, fn {field, _range} -> to_string(field) == to_string(time) end)
    Map.put(box, :ranges, Map.put(others, time, [nil, to]))
  end

  defp opened(_window, _time, to), do: [nil, to]

  # `reduced_by` agrees with the rows served with the budget and without it.
  defp reduced(_feed, {_window, nil} = request, %Delivery{reduced_by: :feed}, _rows, _s, _t, _o),
    do: [{:reduced_by, request, :feed}]

  defp reduced(_feed, {_window, nil}, _delivery, _rows, _supports, _time, _o), do: []

  defp reduced(feed, {window, _budget} = request, %Delivery{} = delivery, rows, supports, time, o) do
    case fetched(feed, {window, nil}, o) do
      {:ok, whole, all} ->
        upper = earlier(end_of(delivery.window), end_of(whole.window))
        count = counted(rows, time, upper)
        total = counted(all, time, upper)

        cond do
          delivery.reduced_by == :feed and (:budget not in supports or count >= total) ->
            [{:reduced_by, request, :feed}]

          delivery.reduced_by == nil and count < total ->
            [{:unrecorded_reduction, request, count, total}]

          true ->
            []
        end

      faults ->
        faults
    end
  end

  # Rows up to a time, so a row that arrived between two fetches is not counted.
  defp counted(rows, nil, _upper), do: length(rows)
  defp counted(rows, _time, nil), do: length(rows)

  defp counted(rows, time, upper),
    do: Enum.count(rows, &(not outside?(Table.get(&1, time), [nil, upper])))

  # No two consecutive distinct times of one series closer than the resolution.
  defp resolution(_rows, _request, _schema, nil, _resolution), do: []
  defp resolution(_rows, _request, _schema, _time, nil), do: []

  defp resolution(rows, request, schema, time, resolution) do
    categories = Enum.sort(for {name, %{type: :category}} <- schema.fields, do: name)

    rows
    |> Enum.group_by(
      fn row -> Enum.map(categories, &Table.get(row, &1)) end,
      &Table.get(&1, time)
    )
    |> Map.values()
    |> Enum.flat_map(&gaps/1)
    |> Enum.find_value([], fn {gap, kind} ->
      case spacing(resolution, kind) do
        nil -> nil
        step -> if gap < step * (1 - 1.0e-9), do: [{:resolution, request, gap, resolution}]
      end
    end)
  end

  defp gaps(times) do
    times =
      times
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq_by(&Window.position/1)
      |> Enum.sort_by(&Window.position/1)

    times
    |> Enum.zip(Enum.drop(times, 1))
    |> Enum.map(fn {a, b} -> {seconds(a, b), kind(a)} end)
  end

  # The gap in the window field's own units: seconds for date-times, the values for numbers.
  defp seconds(a, b) when is_number(a), do: b - a
  defp seconds(%DateTime{} = a, b), do: (Window.position(b) - Window.position(a)) / 1_000_000
  defp seconds(%NaiveDateTime{} = a, b), do: Window.position(b) - Window.position(a)
  defp seconds(%Date{} = a, b), do: (Window.position(b) - Window.position(a)) * 86_400

  defp spacing(resolution, _kind) when is_number(resolution), do: resolution
  defp spacing(resolution, :number) when is_atom(resolution), do: nil
  defp spacing(resolution, _kind), do: Map.get(@spans, resolution)

  # -- the supports check --------------------------------------------------------------------

  defp window_honored(feed, supports, time, o) do
    bounded = for w <- o.windows, bounded?(Window.range(w, time)), do: w

    cond do
      :window not in supports ->
        []

      bounded == [] ->
        [{:no_probe, :window}]

      true ->
        for window <- bounded, budget <- o.budgets do
          window_kept(feed, {window, budget}, time, o)
        end
        |> List.flatten()
    end
  end

  defp bounded?([from, to]), do: from != nil or to != nil
  defp bounded?(_none), do: false

  defp window_kept(feed, {asked, _budget} = request, time, o) do
    window = Window.range(asked, time)

    case fetched(feed, request, o) do
      {:ok, delivery, rows} ->
        served =
          if served_within?(delivery.window, window),
            do: [],
            else: [{:window_served, request, delivery.window}]

        rows =
          case time && Enum.find(rows, &outside?(Table.get(&1, time), window)) do
            nil -> []
            row -> [{:window_row, request, Table.get(row, time)}]
          end

        served ++ rows

      # A probe the feed cannot answer is the deliveries check's to report.
      _faults ->
        []
    end
  end

  # A served window within the asked one: each bound the request gives is met or narrowed.
  defp served_within?([sf, st], [af, at]),
    do:
      (af == nil or (sf != nil and not before?(sf, af) and comparable?(sf, af))) and
        (at == nil or (st != nil and not before?(at, st) and comparable?(st, at)))

  defp served_within?(_served, _asked), do: false

  defp budget_honored(feed, supports, o) do
    budgets = Enum.reject(o.budgets, &is_nil/1)

    cond do
      :budget not in supports ->
        []

      budgets == [] ->
        [{:no_probe, :budget}]

      true ->
        for window <- o.windows, budget <- budgets do
          case fetched(feed, {window, budget}, o) do
            {:ok, _delivery, rows} when length(rows) > budget ->
              [{:over_budget, {window, budget}, length(rows)}]

            _within_or_unanswered ->
              []
          end
        end
        |> List.flatten()
    end
  end

  defp push_honored(feed, supports, o) do
    if :push in supports do
      probe = if o.push, do: [], else: [{:no_probe, :push}]

      case subscribed(feed, o) do
        {:ok, ref} ->
          unsubscribed(feed, ref, o)
          flush(ref)
          probe

        [{:subscribe_error, reason}] ->
          [{:push_refused, reason} | probe]

        faults ->
          faults ++ probe
      end
    else
      me = self()

      case call(fn -> Feed.subscribe(feed, me) end, :subscribe, o) do
        {:ok, {:error, _reason}} ->
          []

        {:ok, {:ok, ref} = answer} when is_reference(ref) ->
          unsubscribed(feed, ref, o)
          flush(ref)
          [{:push_undeclared, answer}]

        {:ok, answer} ->
          [{:push_undeclared, answer}]

        {:error, fault} ->
          [fault]
      end
    end
  end

  # -- pushes --------------------------------------------------------------------------------

  # The kit's own process subscribed: `{:ok, ref}` or the findings.
  defp subscribed(feed, o) do
    me = self()

    case call(fn -> Feed.subscribe(feed, me) end, :subscribe, o) do
      {:ok, {:ok, ref}} when is_reference(ref) -> {:ok, ref}
      {:ok, {:error, reason}} -> [{:subscribe_error, reason}]
      {:ok, other} -> [{:not_a_value, :subscribe, other}]
      {:error, fault} -> [fault]
    end
  end

  defp unsubscribed(feed, ref, o) do
    case call(fn -> Feed.unsubscribe(feed, ref) end, :unsubscribe, o) do
      {:ok, :ok} -> []
      {:ok, other} -> [{:unsubscribe, other}]
      {:error, fault} -> [fault]
    end
  end

  # The `push:` function run; `[]`, or the findings of a raise or a hang.
  defp stimulate(_feed, %{push: nil}), do: [{:no_probe, :push}]

  defp stimulate(feed, %{push: push} = o) do
    case call(fn -> push.(feed) end, :push, o) do
      {:ok, _any} -> []
      {:error, fault} -> [fault]
    end
  end

  # The messages under a reference, in arrival order: until the deadline while no delivery
  # has arrived, then until `quiet` passes with none.
  defp collect(ref, deadline, quiet, delivered?, acc) do
    wait = if delivered?, do: quiet, else: max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:visualize_feed, ^ref, message} ->
        collect(ref, deadline, quiet, delivered? or match?({:delivery, _}, message), [
          message | acc
        ])
    after
      wait -> Enum.reverse(acc)
    end
  end

  defp flush(ref) do
    receive do
      {:visualize_feed, ^ref, _message} -> flush(ref)
    after
      0 -> :ok
    end
  end

  # The handshake first, then every delivery after the schema it names.
  defp sequence(handshake, messages, o) do
    {known, faults} =
      case handshake do
        {:schema, version, %Schema{} = schema} ->
          {%{version => schema}, pushed_schema(version, schema)}

        other ->
          {%{}, [{:handshake, other}]}
      end

    {_known, faults, delivered?} =
      Enum.reduce(messages, {known, faults, false}, fn
        {:schema, version, %Schema{} = schema}, {known, faults, delivered?} ->
          {Map.put(known, version, schema), faults ++ pushed_schema(version, schema), delivered?}

        {:delivery, %Delivery{} = delivery}, {known, faults, _delivered?} ->
          {known, faults ++ pushed_delivery(delivery, known, o), true}

        other, {known, faults, delivered?} ->
          {known, faults ++ [{:not_a_message, other}], delivered?}
      end)

    if delivered?, do: faults, else: faults ++ [{:no_delivery, o.timeout}]
  end

  defp pushed_schema(version, %Schema{} = schema) do
    case schema_faults(version, schema) do
      [] -> []
      [{:version, given, computed}] -> [{:schema_message, given, computed}]
      faults -> faults
    end
  end

  defp pushed_delivery(%Delivery{} = delivery, known, o) do
    {faults, rows} = well_formed(delivery, :push, o)

    case Map.fetch(known, delivery.schema) do
      {:ok, schema} when faults == [] ->
        outside(rows, :push, Feed.window_field(schema), delivery.window)

      {:ok, _schema} ->
        faults

      :error ->
        faults ++ [{:before_schema, delivery.schema}]
    end
  end

  # Subscribed, the handshake taken, unsubscribed: nothing more arrives.
  defp silenced(feed, o) do
    with {:ok, ref} <- subscribed(feed, o) do
      flush(ref)
      answer = unsubscribed(feed, ref, o)
      pushed = stimulate(feed, o)
      after_ = collect(ref, System.monotonic_time(:millisecond) + o.quiet, o.quiet, true, [])
      flush(ref)

      answer ++
        pushed ++
        if(after_ == [], do: [], else: [{:pushed_after_unsubscribe, length(after_)}])
    end
  end

  # -- errors --------------------------------------------------------------------------------

  defp unknown_ref(feed, o) do
    case call(fn -> Feed.unsubscribe(feed, make_ref()) end, :unsubscribe, o) do
      {:ok, :ok} -> []
      {:ok, other} -> [{:unsubscribe, other}]
      {:error, fault} -> [fault]
    end
  end

  defp down(nil, _o), do: []

  defp down(feed, o) do
    me = self()

    describe =
      case call(fn -> Feed.describe(feed) end, :describe, o) do
        {:ok, {:error, _reason}} -> []
        {:ok, {_v, _s, _supports} = answer} -> [{:answered_down, :describe, answer}]
        {:ok, other} -> [{:not_a_value, :describe, other}]
        {:error, fault} -> [fault]
      end

    fetch =
      case call(fn -> Feed.fetch(feed, nil, nil) end, {:fetch, nil, nil}, o) do
        {:ok, {:error, _reason}} -> []
        {:ok, {:ok, _delivery} = answer} -> [{:answered_down, {:fetch, nil, nil}, answer}]
        {:ok, other} -> [{:not_a_value, {:fetch, nil, nil}, other}]
        {:error, fault} -> [fault]
      end

    subscribe =
      case call(fn -> Feed.subscribe(feed, me) end, :subscribe, o) do
        {:ok, {:error, _reason}} ->
          []

        {:ok, {:ok, ref} = answer} ->
          flush(ref)
          [{:answered_down, :subscribe, answer}]

        {:ok, other} ->
          [{:not_a_value, :subscribe, other}]

        {:error, fault} ->
          [fault]
      end

    describe ++ fetch ++ subscribe ++ unknown_ref(feed, o)
  end

  # -- isolation -----------------------------------------------------------------------------

  # A callback run in a process of its own, monitored, with the caller in `$callers`:
  # `{:ok, answer}`, or `{:error, finding}` for a raise, an exit or a hang (spec/08 §12.2).
  defp call(fun, call, o) do
    parent = self()
    tag = make_ref()
    callers = [parent | Process.get(:"$callers", [])]

    {pid, monitor} =
      spawn_monitor(fn ->
        Process.put(:"$callers", callers)
        send(parent, {tag, fun.()})
      end)

    receive do
      {^tag, answer} ->
        Process.demonitor(monitor, [:flush])
        {:ok, answer}

      {:DOWN, ^monitor, :process, ^pid, reason} ->
        {:error, {:raised, call, reason}}
    after
      o.timeout ->
        Process.exit(pid, :kill)
        Process.demonitor(monitor, [:flush])
        {:error, {:timeout, call}}
    end
  end

  # -- words ---------------------------------------------------------------------------------

  @doc """
  One finding as a line a person reads.

      iex> Visualize.Feed.Conformance.format({:supports, {:over_budget, {nil, 5}, 9}})
      "supports: asked for at most 5 rows (window nil), the feed names :budget and served 9"
  """
  @spec format(finding()) :: String.t()
  def format({check, reason}), do: "#{check}: #{Words.words(reason)}"
end
