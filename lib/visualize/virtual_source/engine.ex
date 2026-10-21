defmodule Visualize.VirtualSource.Engine do
  @moduledoc """
  Virtual sources where feeds run (spec/15 §14, D-194): a **value** the board process holds
  beside its feed monitor and calls from its own callbacks, as it holds the monitor
  (spec/08 §11.4, D-140).

  `new/2` defines the sources — every input resolved, cycles refused by name, ranks
  assigned. `push/4` shows the engine the feeds' latest deliveries: a feed that changed
  marks the sources that read it, and the first mark makes a **pulse** due `debounce:`
  milliseconds later. `run/2` runs a due pulse: the marked sources in rank order, each at
  most once, every call bounded (`Visualize.VirtualSource.Sandbox.run/3`). A source that
  fails keeps its last good output, and the pulse goes no further along it.

      iex> alias Visualize.VirtualSource
      iex> alias Visualize.VirtualSource.Engine
      iex> alias Visualize.Data.{Delivery, Schema}
      iex> count = VirtualSource.new!(id: :count, from: [hosts: nil],
      ...>   schema: %{n: %{type: :number}}, elixir: "fn %{hosts: rows} -> [%{n: Enum.count(rows)}] end")
      iex> {:ok, engine} = Engine.new(%{[:count] => count}, feeds: [:hosts], debounce: 0)
      iex> hosts = Schema.new!(%{host: %{type: :category}})
      iex> engine = Engine.push(engine, %{hosts: Delivery.new([%{host: "a"}, %{host: "b"}])}, %{hosts: hosts}, 0)
      iex> engine = Engine.run(engine, 0)
      iex> Engine.outputs(engine)[["count"]].rows
      [%{"n" => 2}]
      iex> Engine.status(engine)
      %{["count"] => :live}

  """

  alias Visualize.Chart.Names
  alias Visualize.Data.{Delivery, Schema, Table}
  alias Visualize.Feed
  alias Visualize.Feed.Window
  alias Visualize.VirtualSource
  alias Visualize.VirtualSource.Sandbox
  alias Visualize.VirtualSource.Sandbox.Cache
  alias Visualize.VirtualSource.Sandbox.Names, as: Spelling

  defstruct sources: %{},
            feeds: MapSet.new(),
            inputs: %{},
            ranks: %{},
            order: [],
            readers: %{},
            functions: %{},
            compiled: %{},
            cache: %Cache{},
            outputs: %{},
            faults: %{},
            runs: %{},
            seen: %{},
            feed_schemas: %{},
            checked: %{},
            marked: MapSet.new(),
            due: nil,
            debounce: 0,
            run_opts: []

  @type path :: [atom(), ...]
  @type ref :: {:feed, term()} | {:source, path()}

  @type t :: %__MODULE__{}

  @typedoc "A definition fault: the source's path, where in it, and why (spec/15 §14.1)."
  @type error :: {path(), list(), term()}

  @typedoc "A source's fault (spec/15 §14.3): its kind and its detail, never a value."
  @type fault :: %{kind: atom(), detail: term()}

  # -- defining (spec/15 §14.1) ------------------------------------------------------------

  @doc """
  The engine over virtual sources by path, defined (spec/15 §14.1): `{:ok, engine}`, or
  `{:error, errors}` — every input that resolves to nothing, every host function the
  registry lacks, then every cycle by name. Options: `feeds:` (the feeds' names, `[]`),
  `functions:` (the registry, `%{}`), `debounce:` (milliseconds, `0`), `max_reductions:`,
  `timeout:` and `max_heap:` (each call's limits, spec/08 §10.5.4).
  """
  @spec new(%{path() => VirtualSource.t()}, keyword()) :: {:ok, t()} | {:error, [error(), ...]}
  def new(sources, opts \\ []) when is_map(sources) do
    opts =
      Keyword.validate!(opts,
        feeds: [],
        functions: %{},
        debounce: 0,
        max_reductions: 100_000_000,
        timeout: 30_000,
        max_heap: 10_000_000
      )

    feeds = MapSet.new(opts[:feeds])
    functions = opts[:functions]
    # A path is its names' strings (D-195): a host may key its sources by atom paths.
    sources = Map.new(sources, fn {path, source} -> {Enum.map(path, &Names.name/1), source} end)
    paths = Map.keys(sources)

    {inputs, errors} =
      Enum.reduce(sources, {%{}, []}, fn {path, source}, {inputs, errors} ->
        {resolved, faults} = references(source, path, paths, feeds, functions)
        {Map.put(inputs, path, resolved), errors ++ faults}
      end)

    errors = if errors == [], do: cycles(inputs), else: errors

    case Enum.sort(errors) do
      [] ->
        engine = %__MODULE__{
          sources: sources,
          feeds: feeds,
          inputs: inputs,
          functions: functions,
          debounce: opts[:debounce],
          run_opts: Keyword.take(opts, [:max_reductions, :timeout, :max_heap])
        }

        {:ok, engine |> rank() |> compile()}

      errors ->
        {:error, errors}
    end
  end

  # Every input resolved from the scope its source stands in: a virtual source from the
  # inside out, else a feed (spec/08 §10.5.9).
  defp references(source, path, paths, feeds, functions) do
    scope = Enum.drop(path, -1)

    {resolved, faults} =
      source.from
      |> Enum.with_index()
      |> Enum.map_reduce([], fn {{name, window}, i}, faults ->
        case lookup(paths, feeds, scope, name) do
          {:ok, ref} -> {{VirtualSource.key(name), name, ref, window}, faults}
          :error -> {nil, [{path, [:from, i], {:unknown_input, name}} | faults]}
        end
      end)

    faults =
      case source.function do
        # A host function is found by its name's spelling (D-195).
        name when (is_atom(name) and name != nil) or is_binary(name) ->
          if Visualize.Chart.Names.key(functions, name) == :error,
            do: [{path, [:function], {:undeclared, :function, name}} | faults],
            else: faults

        _otherwise ->
          faults
      end

    {resolved, Enum.reverse(faults)}
  end

  # A feed's own name is a feed (spec/08 §10.5.6); a short id or a path a virtual source,
  # else — a short id — the feed of its spelling. A host names its feeds by atom or string.
  defp lookup(_paths, feeds, _scope, {:feed, name}), do: feed(feeds, name)

  defp lookup(paths, feeds, scope, name) do
    case VirtualSource.resolve(paths, scope, name) do
      {:ok, path} -> {:ok, {:source, path}}
      :error when is_list(name) -> :error
      :error -> feed(feeds, name)
    end
  end

  defp feed(feeds, name) do
    case Enum.find(feeds, &Visualize.Chart.Names.same?(&1, name)) do
      nil -> :error
      feed -> {:ok, {:feed, feed}}
    end
  end

  @doc """
  What a name read from a scope names (spec/15 §14.5): `{:source, path}` for a virtual
  source, resolved from the inside out, else `{:feed, name}` for a name `feeds` holds,
  else `:error`.
  """
  @spec resolve(t(), [atom()], term()) :: ref() | :error
  def resolve(%__MODULE__{sources: sources, feeds: feeds}, scope, name) do
    case lookup(Map.keys(sources), feeds, scope, name) do
      {:ok, ref} -> ref
      :error -> :error
    end
  end

  # A cycle named: each strongly connected component that holds one, at its first member.
  defp cycles(inputs) do
    graph = :digraph.new()

    for {path, _inputs} <- inputs, do: :digraph.add_vertex(graph, path)

    for {path, refs} <- inputs,
        {_key, _name, {:source, from}, _window} <- refs,
        do: :digraph.add_edge(graph, from, path)

    components = :digraph_utils.cyclic_strong_components(graph)
    :digraph.delete(graph)

    for component <- components do
      [first | _] = members = Enum.sort(component)
      {first, [:from], {:cycle, members}}
    end
  end

  # Ranks: a source over feeds alone is 0, any other one more than its greatest input.
  # The pulse order is by rank, then path.
  defp rank(engine) do
    ranks =
      Enum.reduce(Map.keys(engine.inputs), %{}, fn path, ranks -> rank_of(engine, path, ranks) end)

    readers =
      Enum.reduce(engine.inputs, %{}, fn {path, refs}, readers ->
        Enum.reduce(refs, readers, fn {_key, _name, ref, _window}, acc ->
          Map.update(acc, ref, [path], &[path | &1])
        end)
      end)

    order = Enum.sort_by(Map.keys(ranks), &{Map.fetch!(ranks, &1), &1})
    %{engine | ranks: ranks, order: order, readers: readers}
  end

  defp rank_of(engine, path, ranks) do
    case Map.fetch(ranks, path) do
      {:ok, _rank} ->
        ranks

      :error ->
        sources = for {_key, _name, {:source, from}, _window} <- engine.inputs[path], do: from
        ranks = Enum.reduce(sources, ranks, &rank_of(engine, &1, &2))
        rank = sources |> Enum.map(&(Map.fetch!(ranks, &1) + 1)) |> Enum.max(fn -> 0 end)
        Map.put(ranks, path, rank)
    end
  end

  # Every stored function compiled once into the cache; a host's captured by name.
  defp compile(engine) do
    Enum.reduce(engine.sources, engine, fn
      {path, %{elixir: text}}, engine when is_binary(text) ->
        case Cache.compile(engine.cache, text, engine.run_opts) do
          {:ok, compiled, cache} ->
            %{engine | cache: cache, compiled: Map.put(engine.compiled, path, compiled.fun)}

          {:error, faults, cache} ->
            %{engine | cache: cache} |> fault(path, :restricted, faults)
        end

      {path, %{function: name}}, engine ->
        {:ok, function} = Visualize.Chart.Names.key(engine.functions, name)
        module = Map.fetch!(engine.functions, function)

        %{
          engine
          | compiled: Map.put(engine.compiled, path, Function.capture(module, function, 1))
        }
    end)
  end

  # -- pulses (spec/15 §14.2) --------------------------------------------------------------

  @doc """
  The feeds' latest deliveries and their schemas shown to the engine at the owner's
  monotonic millisecond `now` (spec/15 §14.2): every source that reads a feed whose
  delivery is not the one last seen is marked, and the first mark makes the next pulse
  due `debounce` later.
  """
  @spec push(t(), %{term() => Delivery.t()}, %{term() => Schema.t()}, integer()) :: t()
  def push(%__MODULE__{} = engine, deliveries, schemas, now) do
    feeds = for {{:feed, name}, _readers} <- engine.readers, do: name

    Enum.reduce(feeds, engine, fn name, engine ->
      delivery = Map.get(deliveries, name)

      engine = %{engine | feed_schemas: put_present(engine.feed_schemas, name, schemas[name])}

      if delivery == Map.get(engine.seen, name) do
        engine
      else
        %{engine | seen: Map.put(engine.seen, name, delivery)} |> mark({:feed, name}, now)
      end
    end)
  end

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  defp mark(engine, ref, now) do
    case Map.get(engine.readers, ref, []) do
      [] ->
        engine

      readers ->
        due = engine.due || now + engine.debounce
        %{engine | marked: Enum.into(readers, engine.marked), due: due}
    end
  end

  @doc "The monotonic millisecond the next pulse is due, or `nil` (spec/15 §14.2)."
  @spec due(t()) :: integer() | nil
  def due(%__MODULE__{due: due}), do: due

  @doc """
  The due pulse run at `now` (spec/15 §14.2): the marked sources in rank order, each at
  most once; a changed answer marks its readers, which run later in the same pulse. The
  engine is returned as it is when no pulse is due.
  """
  @spec run(t(), integer()) :: t()
  def run(%__MODULE__{due: due} = engine, now) when is_integer(due) and now >= due do
    engine =
      Enum.reduce(engine.order, engine, fn path, engine ->
        if MapSet.member?(engine.marked, path), do: compute(engine, path, now), else: engine
      end)

    %{engine | marked: MapSet.new(), due: nil}
  end

  def run(%__MODULE__{} = engine, _now), do: engine

  # One source run: its inputs gathered and windowed, checked in context, called bounded,
  # its answer held to its schema. A changed answer marks its readers.
  defp compute(engine, path, now) do
    source = Map.fetch!(engine.sources, path)

    with {:ok, inputs} <- gather(engine, path),
         {:ok, engine} <- in_context(engine, path, source, inputs),
         {:ok, fun} <- function(engine, path) do
      engine = %{engine | runs: Map.update(engine.runs, path, 1, &(&1 + 1))}

      case call(source, fun, inputs, engine.run_opts) do
        {:ok, rows} -> answered(engine, path, source, rows, now)
        {:error, kind, detail} -> fault(engine, path, kind, detail)
      end
    else
      :waiting -> engine
      {:restricted, engine} -> engine
      :no_function -> engine
    end
  end

  # Every input's delivery and schema, or `:waiting` while one has none (spec/15 §14.2).
  defp gather(engine, path) do
    Enum.reduce_while(engine.inputs[path], {:ok, []}, fn {key, name, ref, window}, {:ok, acc} ->
      case input(engine, ref) do
        {%Delivery{} = delivery, %Schema{} = schema} ->
          rows = delivery |> Delivery.source() |> Table.rows() |> window(window, schema)
          {:cont, {:ok, acc ++ [%{key: key, name: name, rows: rows, schema: schema}]}}

        _missing ->
          {:halt, :waiting}
      end
    end)
  end

  defp input(engine, {:feed, name}), do: {engine.seen[name], engine.feed_schemas[name]}

  defp input(engine, {:source, path}),
    do: {engine.outputs[path], Map.fetch!(engine.sources, path).schema}

  # Validated given its inputs' schemas before it first runs, and again when one of their
  # versions changes (spec/15 §14.2); a refusal is the fault `:restricted`.
  defp in_context(engine, path, source, inputs) do
    versions = Enum.map(inputs, & &1.schema.version)

    result =
      case Map.fetch(engine.checked, path) do
        {:ok, {^versions, result}} ->
          result

        _stale ->
          schemas = Map.new(inputs, &{&1.name, &1.schema})
          VirtualSource.validate(source, inputs: schemas, functions: engine.functions)
      end

    engine = %{engine | checked: Map.put(engine.checked, path, {versions, result})}

    case result do
      :ok -> {:ok, engine}
      {:error, errors} -> {:restricted, fault(engine, path, :restricted, errors)}
    end
  end

  defp function(engine, path) do
    case Map.fetch(engine.compiled, path) do
      {:ok, fun} -> {:ok, fun}
      :error -> :no_function
    end
  end

  # -- windows (spec/08 §10.5.6) -----------------------------------------------------------

  defp window(rows, nil, _schema), do: rows

  defp window(rows, %{last: n}, schema) do
    rows = newest_first_order(rows, schema)

    case Schema.identity(schema) do
      [] ->
        Enum.take(rows, -n)

      _identity ->
        keep =
          rows
          |> Enum.with_index()
          |> Enum.group_by(fn {row, _i} -> Schema.identity(schema, row) end, fn {_row, i} -> i end)
          |> Enum.reject(fn {identity, _indices} -> identity == nil end)
          |> Enum.flat_map(fn {_identity, indices} -> Enum.take(indices, -n) end)
          |> MapSet.new()

        for {row, i} <- Enum.with_index(rows), MapSet.member?(keep, i), do: row
    end
  end

  defp window(rows, box, schema) do
    rows |> Delivery.new() |> Feed.finish(schema, window: box, supports: []) |> Table.rows()
  end

  # In the window field's order, ties and rows without a reading kept where they stand.
  defp newest_first_order(rows, schema) do
    case Feed.window_field(schema) do
      nil ->
        rows

      field ->
        if Enum.all?(rows, &(Window.position(Table.get(&1, field)) != nil)),
          do: Enum.sort_by(rows, &Window.position(Table.get(&1, field))),
          else: rows
    end
  end

  # -- calling (spec/08 §10.5.7, spec/15 §14.4) --------------------------------------------

  defp rows(%{elixir: elixir}, rows) when is_binary(elixir) and is_list(rows),
    do: Enum.map(rows, &spelled/1)

  defp rows(_source, rows), do: rows

  # An input's key as the function reads it: a stored function's by the rule its literals
  # follow, a host's function's its string — the host's rows as it gave them (D-195).
  defp input_key(%{elixir: elixir}, key) when is_binary(elixir), do: Spelling.spelling(key)
  defp input_key(_source, key), do: Names.name(key)

  defp spelled(row) when is_map(row) and not is_struct(row),
    do: Map.new(row, fn {k, v} -> {Spelling.spelling(k), Spelling.spelling(v)} end)

  defp spelled(row), do: row

  # A stored function reads its inputs, its rows' fields and their category values as it
  # reads its own literals — a word's atom, else the string (spec/08 §10.5.6, D-195); a
  # host's function its rows as given.
  defp call(%{per: nil} = source, fun, inputs, opts) do
    argument = Map.new(inputs, &{input_key(source, &1.key), rows(source, &1.rows)})
    source |> answer(Sandbox.run(fun, [argument], opts))
  end

  # Per identity: one call per entity, every call in one bounded batch, each answer given
  # its entity's identity.
  defp call(source, fun, inputs, opts) do
    name = VirtualSource.identity_input(source)
    identity_input = Enum.find(inputs, &(&1.name == name))
    groups = entities(identity_input.rows, identity_input.schema)

    argument = fn rows ->
      case inputs do
        [_one] ->
          rows(source, rows)

        _several ->
          Map.new(inputs, fn input ->
            {input_key(source, input.key),
             rows(source, if(input.name == name, do: rows, else: input.rows))}
          end)
      end
    end

    batch = fn ->
      Enum.map(groups, fn {identity, rows} -> {identity, fun.(argument.(rows))} end)
    end

    with {:ok, answers} <- Sandbox.run(batch, [], opts) do
      answer(source, join(answers, identity_input.schema, source.schema))
    end
  end

  # A source's rows are keyed by their fields' strings, whichever function answered them,
  # so every output reads alike (D-195).
  defp answer(_source, {:ok, rows}) when is_list(rows), do: {:ok, Enum.map(rows, &keyed/1)}

  defp answer(_source, result), do: result

  defp keyed(row) when is_map(row) and not is_struct(row),
    do: Map.new(row, fn {k, v} -> {Names.name(k), v} end)

  defp keyed(row), do: row

  defp entities(rows, schema) do
    {order, groups} =
      Enum.reduce(rows, {[], %{}}, fn row, {order, groups} ->
        case Schema.identity(schema, row) do
          nil ->
            {order, groups}

          identity ->
            if Map.has_key?(groups, identity),
              do: {order, Map.update!(groups, identity, &[row | &1])},
              else: {[identity | order], Map.put(groups, identity, [row])}
        end
      end)

    for identity <- Enum.reverse(order), do: {identity, Enum.reverse(groups[identity])}
  end

  defp join(answers, input, output) do
    fields = Schema.identity(output)

    answers
    |> Enum.reduce_while({:ok, []}, fn {identity, answer}, {:ok, acc} ->
      case entity_rows(answer) do
        {:ok, rows} -> {:cont, {:ok, [Enum.map(rows, &{identity, &1}) | acc]}}
        :error -> {:halt, {:error, :nonconforming, {nil, nil, :not_a_list}}}
      end
    end)
    |> case do
      {:ok, nested} ->
        nested |> Enum.reverse() |> Enum.concat() |> identify(input, fields)

      error ->
        error
    end
  end

  defp entity_rows(row) when is_map(row) and not is_struct(row), do: {:ok, [row]}
  defp entity_rows(rows) when is_list(rows), do: {:ok, rows}
  defp entity_rows(_other), do: :error

  # Each row given its entity's identity, under the output's spelling of each field; a row
  # that names another value for one does not conform.
  defp identify(pairs, input, fields) do
    pairs
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {{identity, row}, i}, {:ok, acc} ->
      case stamp(row, identity, input, fields) do
        {:ok, row} -> {:cont, {:ok, [row | acc]}}
        {:error, field} -> {:halt, {:error, :nonconforming, {i, field, :identity}}}
      end
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      error -> error
    end
  end

  defp stamp(row, _identity, _input, _fields) when not is_map(row) or is_struct(row),
    do: {:ok, row}

  defp stamp(row, identity, input, fields) do
    Enum.reduce_while(fields, {:ok, row}, fn field, {:ok, row} ->
      value = identity_value(identity, input, field)

      case Table.get(row, field) do
        nil -> {:cont, {:ok, Map.put(row, field, value)}}
        ^value -> {:cont, {:ok, row}}
        _other -> {:halt, {:error, field}}
      end
    end)
  end

  defp identity_value(identity, input, field) do
    case Schema.identity(input) do
      [_one] ->
        identity

      several ->
        input_field = Enum.find(several, &(to_string(&1) == to_string(field)))
        Map.get(identity, input_field)
    end
  end

  # -- answers and faults (spec/15 §14.3) --------------------------------------------------

  defp answered(engine, path, source, rows, now) do
    case VirtualSource.conform(source, rows) do
      {:ok, rows} ->
        previous = engine.outputs[path]
        changed? = previous == nil or previous.rows != rows
        delivery = Delivery.new(rows, schema: Schema.version(source.schema))

        engine = %{
          engine
          | outputs: Map.put(engine.outputs, path, if(changed?, do: delivery, else: previous)),
            faults: Map.delete(engine.faults, path)
        }

        if changed?, do: mark(engine, {:source, path}, now), else: engine

      {:error, detail} ->
        fault(engine, path, :nonconforming, detail)
    end
  end

  # The last good output stays, and nothing is marked: the pulse stops here.
  defp fault(engine, path, kind, detail),
    do: %{engine | faults: Map.put(engine.faults, path, %{kind: kind, detail: detail})}

  # -- reading it --------------------------------------------------------------------------

  @doc "Every source's last good output, a `%Visualize.Data.Delivery{}`, by path."
  @spec outputs(t()) :: %{path() => Delivery.t()}
  def outputs(%__MODULE__{outputs: outputs}), do: outputs

  @doc "Every source's output schema, by path."
  @spec schemas(t()) :: %{path() => Schema.t()}
  def schemas(%__MODULE__{sources: sources}),
    do: Map.new(sources, fn {path, source} -> {path, source.schema} end)

  @doc """
  Every source's state by path (spec/15 §14.3): `:loading` before its first answer,
  `:live` after, and `{:down, {:virtual_source, id, kind}}` while it fails.
  """
  @spec status(t()) :: %{path() => :loading | :live | {:down, term()}}
  def status(%__MODULE__{} = engine) do
    Map.new(engine.sources, fn {path, source} ->
      state =
        case {Map.fetch(engine.faults, path), Map.has_key?(engine.outputs, path)} do
          {{:ok, %{kind: kind}}, _output} -> {:down, {:virtual_source, source.id, kind}}
          {:error, true} -> :live
          {:error, false} -> :loading
        end

      {path, state}
    end)
  end

  @doc "Every failing source's fault by path, `%{kind: kind, detail: detail}` (spec/15 §14.3)."
  @spec faults(t()) :: %{path() => fault()}
  def faults(%__MODULE__{faults: faults}), do: faults

  @doc "How many times each source has run, by path."
  @spec runs(t()) :: %{path() => non_neg_integer()}
  def runs(%__MODULE__{} = engine),
    do: Map.new(engine.sources, fn {path, _source} -> {path, Map.get(engine.runs, path, 0)} end)
end
