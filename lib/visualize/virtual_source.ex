defmodule Visualize.VirtualSource do
  @moduledoc """
  A virtual source: a source computed from other sources by a function, rows in and rows
  out (spec/08 §10.5, #643, D-194).

  It is data — `id`, its inputs (`from`), its output's `schema`, and its function as source
  text (`elixir`, checked by `Visualize.VirtualSource.Sandbox`) or a host function's name
  (`function`, defined with `Visualize.VirtualSources.defsource/2`) — so a board holds it
  and a codec writes it. With `per:` the function runs once per entity of one input and
  its rows are joined back by that input's declared identity (D-167).

      iex> {:ok, health} =
      ...>   Visualize.VirtualSource.new(
      ...>     id: :health,
      ...>     from: [hosts: {:window, last: 20}],
      ...>     per: :identity,
      ...>     schema: %{
      ...>       host: %{type: :category, identity: true},
      ...>       state: %{type: :category, values: [:ok, :warning, :error]}
      ...>     },
      ...>     elixir: "fn rows -> %{state: :ok} end"
      ...>   )
      iex> health.from
      [{"hosts", %{last: 20}}]
      iex> Visualize.VirtualSource.conform(health, [%{host: "a", state: :ok}])
      {:ok, [%{host: "a", state: :ok}]}
      iex> Visualize.VirtualSource.conform(health, [%{host: "a", state: :unknown}])
      {:error, {0, "state", :not_in_values}}
      iex> Visualize.VirtualSource.resolve([[:health], [:ops, :health]], [:ops], :health)
      {:ok, ["ops", "health"]}

  """

  alias Visualize.Chart.{Names, Words}
  alias Visualize.Chart.Validator, as: ChartValidator
  alias Visualize.Data.{Schema, Table}
  alias Visualize.Feed.Window
  alias Visualize.VirtualSource.Sandbox

  @keys [:id, :from, :schema, :elixir, :function, :per]
  @not_names [nil, true, false]

  @enforce_keys [:id, :from, :schema]
  defstruct [:id, :from, :schema, elixir: nil, function: nil, per: nil]

  @typedoc "What an input names (spec/08 §10.5.6): a short id or a feed, a feed, a path."
  @type name :: atom() | String.t() | [atom(), ...]

  @typedoc "How much of an input the function needs (spec/08 §10.5.6)."
  @type window ::
          nil
          | %{last: pos_integer()}
          | %{optional(:ranges) => map(), optional(:latest) => boolean()}

  @type t :: %__MODULE__{
          id: atom(),
          from: [{name(), window()}, ...],
          schema: Schema.t(),
          elixir: String.t() | nil,
          function: atom() | nil,
          per: nil | :identity | {:identity, name()}
        }

  @typedoc "A fault: the path from the source to the value, and why (spec/14 §10.1)."
  @type error :: {list(), term()}

  # -- construction (spec/08 §10.5.5) ------------------------------------------------------

  @doc """
  A virtual source of its map form or a keyword list of the same keys, checked alone
  (spec/08 §10.5.5): `{:ok, source}`, or `{:error, errors}` with every fault by path.
  `{:window, opts}` is read as the window map `opts` makes.
  """
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, [error(), ...]}
  def new(source) when is_list(source) do
    if Keyword.keyword?(source),
      do: new(Map.new(source)),
      else: {:error, [{[], {:type, :virtual_source}}]}
  end

  def new(source) when is_map(source) and not is_struct(source) do
    source = source |> Map.update(:from, nil, &read_from/1) |> named()

    errors =
      for(key <- Map.keys(source), key not in @keys, do: {[key], :unknown_key}) ++
        id(source) ++
        from(Map.get(source, :from)) ++
        schema(source) ++
        function(source) ++
        per(Map.get(source, :per), Map.get(source, :from))

    case Enum.sort_by(errors, &elem(&1, 0)) do
      [] ->
        {:ok,
         %__MODULE__{
           id: source.id,
           from: source.from,
           schema: Schema.new!(source.schema),
           elixir: Map.get(source, :elixir),
           function: Map.get(source, :function),
           per: Map.get(source, :per)
         }}

      errors ->
        {:error, errors}
    end
  end

  def new(_other), do: {:error, [{[], {:type, :virtual_source}}]}

  @doc "The virtual source, or `ArgumentError` naming every fault."
  @spec new!(map() | keyword()) :: t()
  def new!(source) do
    case new(source) do
      {:ok, source} ->
        source

      {:error, errors} ->
        raise ArgumentError,
              "not a virtual source:\n" <>
                Enum.map_join(errors, "\n", &("  " <> format_error(&1)))
    end
  end

  # A source's names are strings (spec/08 §10.5.10, D-195): its id, its inputs' names and
  # paths, its identity input, its function and its output's fields, whichever spelling the
  # host gave; a field's category values are read by the library's words, as JSON's are.
  @doc false
  # Also a board's step for the sources it holds as maps (`Visualize.Board.Names`).
  @spec named(map()) :: map()
  def named(source) when is_map(source) and not is_struct(source) do
    Enum.reduce(
      [
        id: &Names.name/1,
        from: &named_inputs/1,
        per: &named_per/1,
        function: &Names.name/1,
        schema: &named_schema/1
      ],
      source,
      fn {key, fun}, source ->
        if Map.has_key?(source, key), do: Map.update!(source, key, fun), else: source
      end
    )
  end

  def named(other), do: other

  defp named_inputs(inputs) when is_list(inputs) do
    Enum.map(inputs, fn
      {name, window} -> {input(name), named_window(window)}
      other -> other
    end)
  end

  defp named_inputs(other), do: other

  # A window's ranges are keyed by its input's fields, their strings.
  defp named_window(%{ranges: ranges} = window) when is_map(ranges) and not is_struct(ranges),
    do: %{window | ranges: Names.keys(ranges)}

  defp named_window(window), do: window

  # A short id — a virtual source's id or a feed's name — is a name's string, whichever
  # spelling gave it; a feed's own name, which no virtual source may shadow, is
  # `{:feed, name}`; a full path is a list of names (spec/08 §10.5.6, D-195).
  defp input(path) when is_list(path), do: Enum.map(path, &Names.name/1)
  defp input({:feed, name}), do: {:feed, Names.name(name)}
  defp input(name), do: Names.name(name)

  defp named_per({:identity, name}), do: {:identity, input(name)}
  defp named_per(other), do: other

  defp named_schema(fields) when is_map(fields) and not is_struct(fields) do
    Map.new(fields, fn
      {name, description} when is_map(description) and not is_struct(description) ->
        {Names.name(name), Map.new(description, &named_attribute/1)}

      {name, description} ->
        {Names.name(name), description}
    end)
  end

  defp named_schema(other), do: other

  # A value entry's value is read as a bare value is; its name and color are as given
  # (spec/08 §10.1, D-224).
  defp named_attribute({:values, values}) when is_list(values),
    do: {:values, Enum.map(values, &named_value/1)}

  defp named_attribute({:order, values}), do: {:order, Words.term(values)}

  defp named_attribute({:status, status}) when is_map(status) and not is_struct(status),
    do: {:status, Map.new(status, fn {k, v} -> {Words.term(k), v} end)}

  defp named_attribute(attribute), do: attribute

  defp named_value(%{value: value} = entry) when not is_struct(entry),
    do: %{entry | value: Words.term(value)}

  defp named_value(value), do: Words.term(value)

  # The proposal's `{:window, opts}` is the map `opts` makes; anything else as it is.
  defp read_from(inputs) when is_list(inputs) do
    Enum.map(inputs, fn
      {name, {:window, opts}} when is_list(opts) or is_map(opts) -> {name, Map.new(opts)}
      input -> input
    end)
  end

  defp read_from(other), do: other

  defp id(%{id: id}) when is_binary(id) and id != "", do: []
  defp id(%{id: id}) when is_atom(id) and id not in @not_names, do: []
  defp id(%{id: _id}), do: [{[:id], {:type, :name}}]
  defp id(_source), do: [{[:id], :required}]

  defp from(nil), do: [{[:from], :required}]

  defp from([_ | _] = inputs) do
    each =
      inputs
      |> Enum.with_index()
      |> Enum.flat_map(fn
        {{name, window}, i} -> input_name(name, i) ++ window(window, [:from, i, :window])
        {_other, i} -> [{[:from, i], {:type, :input}}]
      end)

    each ++ duplicate_keys(inputs)
  end

  defp from(_other), do: [{[:from], {:type, :inputs}}]

  defp input_name(name, _i) when is_atom(name) and name not in @not_names, do: []
  defp input_name(name, _i) when is_binary(name) and name != "", do: []
  defp input_name({:feed, name}, _i) when is_binary(name) and name != "", do: []

  defp input_name([_ | _] = path, i) do
    if Enum.all?(path, &Names.name?/1),
      do: [],
      else: [{[:from, i], {:type, :input_name}}]
  end

  defp input_name(_name, i), do: [{[:from, i], {:type, :input_name}}]

  defp window(nil, _path), do: []

  defp window(%{last: last} = window, path) when map_size(window) == 1 do
    if is_integer(last) and last > 0, do: [], else: [{path ++ [:last], {:type, :pos_integer}}]
  end

  # A box's own faults are its input's schema's to find (in context, `validate/2`).
  defp window(window, path) when is_map(window) and not is_struct(window) do
    if window |> Map.keys() |> Enum.all?(&(&1 in [:ranges, :latest])),
      do: [],
      else: [{path, {:type, :input_window}}]
  end

  defp window(_other, path), do: [{path, {:type, :input_window}}]

  # Two inputs read under one key: the function could not tell them apart.
  defp duplicate_keys(inputs) do
    inputs
    |> Enum.with_index()
    |> Enum.reduce({MapSet.new(), []}, fn
      {{name, _window}, i}, {seen, errors} ->
        case key(name) do
          nil ->
            {seen, errors}

          key ->
            if MapSet.member?(seen, key),
              do: {seen, [{[:from, i], {:duplicate_input, key}} | errors]},
              else: {MapSet.put(seen, key), errors}
        end

      _other, acc ->
        acc
    end)
    |> elem(1)
  end

  defp schema(%{schema: fields}) when is_map(fields) and not is_struct(fields) do
    case Schema.new(fields) do
      {:ok, _schema} -> []
      {:error, errors} -> Enum.map(errors, fn {path, reason} -> {[:schema | path], reason} end)
    end
  end

  defp schema(%{schema: _other}), do: [{[:schema], {:type, :schema}}]
  defp schema(_source), do: [{[:schema], :required}]

  # One function: stored source text, checked; or a host function's name.
  defp function(source) do
    case {Map.get(source, :elixir), Map.get(source, :function)} do
      {nil, nil} -> [{[:elixir], :required}]
      {elixir, nil} -> elixir(elixir, [])
      {nil, name} when is_binary(name) and name != "" -> []
      {nil, name} when is_atom(name) and name not in @not_names -> []
      {nil, _name} -> [{[:function], {:type, :name}}]
      {_elixir, _name} -> [{[:function], {:exclusive, :elixir}}]
    end
  end

  defp elixir(elixir, opts) when is_binary(elixir) do
    case Sandbox.check(elixir, opts) do
      {:ok, _quoted} -> []
      {:error, faults} -> for {line, reason} <- faults, do: {[:elixir], {:check, line, reason}}
    end
  end

  defp elixir(_other, _opts), do: [{[:elixir], {:type, :string}}]

  defp per(nil, _from), do: []

  defp per(:identity, [_, _ | _]), do: [{[:per], {:per, :ambiguous}}]
  defp per(:identity, _from), do: []

  defp per({:identity, name}, from) when is_list(from) do
    if Enum.any?(from, &match?({^name, _window}, &1)),
      do: [],
      else: [{[:per], {:per, {:unknown_input, name}}}]
  end

  defp per({:identity, _name}, _from), do: []
  defp per(_other, _from), do: [{[:per], {:enum, [:identity]}}]

  # -- in context (spec/08 §10.5.5) --------------------------------------------------------

  @doc """
  `:ok`, or every fault of the source given what it reads (spec/08 §10.5.5): `inputs:`, a
  map from an input's name to its `%Visualize.Data.Schema{}` where it is known;
  `functions:`, the host functions' registry (`Visualize.VirtualSources.registry/1`), or
  `nil` to leave the name unchecked; and `vars:`, the names of the variables the source's
  scope declares, or `nil` to leave a stored function's literal reads of them unchecked
  (D-228).
  """
  @spec validate(t(), keyword()) :: :ok | {:error, [error(), ...]}
  def validate(%__MODULE__{} = source, opts \\ []) do
    opts = Keyword.validate!(opts, inputs: %{}, functions: nil, vars: nil)
    inputs = opts[:inputs]

    errors =
      elixir_check(source, inputs, opts[:vars]) ++
        functions_check(source, opts[:functions]) ++
        boxes(source, inputs) ++ identity_check(source, inputs)

    case Enum.sort_by(errors, &elem(&1, 0)) do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  # With every input's schema known, a map read names one of their fields or the output's;
  # with the scope's variables known, a literal read of one names one of them.
  defp elixir_check(%{elixir: nil}, _inputs, _vars), do: []

  defp elixir_check(source, inputs, vars) do
    fields =
      if Enum.all?(source.from, fn {name, _window} -> fetch_input(inputs, name) != :error end) do
        Enum.flat_map(source.from, fn {name, _window} ->
          Map.keys(fetch_input!(inputs, name).fields)
        end) ++
          Map.keys(source.schema.fields)
      end

    if fields == nil and vars == nil,
      do: [],
      else: elixir(source.elixir, fields: fields, vars: vars)
  end

  # An input's schema by its name's spelling: a host keys `inputs:` by atom or string, a
  # source names an input by its string, its path or `{:feed, name}` (D-195).
  defp fetch_input(inputs, name) do
    spelled = name |> key() |> to_string()

    case Enum.find(inputs, fn {k, _v} -> to_string(key(k) || k) == spelled end) do
      nil -> :error
      {_k, schema} -> {:ok, schema}
    end
  end

  defp fetch_input!(inputs, name) do
    {:ok, schema} = fetch_input(inputs, name)
    schema
  end

  defp functions_check(%{function: nil}, _functions), do: []
  defp functions_check(_source, nil), do: []

  defp functions_check(%{function: name}, functions) do
    # A host function is found by its name's spelling (D-195).
    if Visualize.Chart.Names.key(functions, name) != :error,
      do: [],
      else: [{[:function], {:undeclared, :function, name}}]
  end

  defp boxes(source, inputs) do
    source.from
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {{name, %{} = window}, i} when not is_map_key(window, :last) ->
        case fetch_input(inputs, name) do
          {:ok, schema} -> box(window, schema, [:from, i, :window])
          :error -> []
        end

      _other ->
        []
    end)
  end

  defp box(window, schema, path) do
    case Window.check(window, schema) do
      :ok -> []
      {:error, faults} -> for {at, reason} <- faults, do: {path ++ at, reason}
    end
  end

  # Per identity, the output's identity is the input's: the same fields, of the same types.
  defp identity_check(%{per: nil}, _inputs), do: []

  defp identity_check(source, inputs) do
    case fetch_input(inputs, identity_input(source)) do
      {:ok, input} -> same_identity(input, source.schema)
      :error -> []
    end
  end

  defp same_identity(input, output) do
    ours = Schema.identity(input)
    theirs = Schema.identity(output)
    names = fn fields -> fields |> Enum.map(&to_string/1) |> Enum.sort() end

    cond do
      ours == [] ->
        [{[:per], {:per, :no_identity}}]

      names.(ours) != names.(theirs) ->
        [{[:schema], {:per, {:identity, names.(ours), names.(theirs)}}}]

      true ->
        for field <- theirs,
            {:ok, a} = Schema.fetch(input, field, :type),
            {:ok, b} = Schema.fetch(output, field, :type),
            a != b,
            do: {[:schema, field], {:per, {:identity_type, field, a, b}}}
    end
  end

  # -- reading it --------------------------------------------------------------------------

  @doc """
  The key an input is read under (spec/08 §10.5.6): its name, or a path's last atom.

      iex> Visualize.VirtualSource.key([:ops, :health])
      :health
      iex> Visualize.VirtualSource.key("vm.memory.total")
      "vm.memory.total"
  """
  @spec key(name()) :: atom() | String.t() | nil
  def key([_ | _] = path), do: List.last(path)
  def key({:feed, name}), do: name
  def key(name) when is_atom(name) or is_binary(name), do: name
  def key(_other), do: nil

  @doc """
  The name of the input a `per` source's entities come from — the only input under
  `:identity`, the one named under `{:identity, input}` — or `nil` without `per`
  (spec/08 §10.5.7).
  """
  @spec identity_input(t()) :: name() | nil
  def identity_input(%__MODULE__{per: nil}), do: nil
  def identity_input(%__MODULE__{per: :identity, from: [{name, _window} | _]}), do: name
  def identity_input(%__MODULE__{per: {:identity, name}}), do: name

  @doc """
  An answer held to the source's schema (spec/08 §10.5.7): `{:ok, rows}`, or
  `{:error, {index, field, reason}}` for the first row that does not hold — never the value.
  """
  @spec conform(t(), term()) ::
          {:ok, [map()]} | {:error, {non_neg_integer() | nil, term(), term()}}
  def conform(%__MODULE__{schema: schema}, rows) when is_list(rows) do
    identity = Schema.identity(schema)

    rows
    |> Enum.with_index()
    |> Enum.find_value({:ok, rows}, fn {row, i} ->
      case row_fault(row, schema, identity) do
        nil -> nil
        {field, reason} -> {:error, {i, field, reason}}
      end
    end)
  end

  def conform(%__MODULE__{}, _other), do: {:error, {nil, nil, :not_a_list}}

  defp row_fault(row, _schema, _identity) when not is_map(row) or is_struct(row),
    do: {nil, :not_a_row}

  defp row_fault(row, schema, identity) do
    undescribed(row, schema) || missing_identity(row, identity) ||
      Enum.find_value(row, fn {key, value} -> value_fault(schema, key, value) end)
  end

  defp undescribed(row, schema) do
    Enum.find_value(Map.keys(row), fn key ->
      if (is_atom(key) or is_binary(key)) and Schema.fetch(schema, key) != :error,
        do: nil,
        else: {Names.name(key), :undescribed}
    end)
  end

  defp missing_identity(row, identity) do
    Enum.find_value(identity, fn field ->
      if Table.get(row, field) == nil, do: {field, :no_identity}
    end)
  end

  defp value_fault(_schema, _key, nil), do: nil

  defp value_fault(schema, key, value) do
    {:ok, description} = Schema.fetch(schema, key)
    name = spelled(schema, key)

    cond do
      not typed?(description.type, value) -> {name, {:type, description.type}}
      not member?(Schema.values(schema, key), value) -> {name, :not_in_values}
      true -> nil
    end
  end

  defp spelled(%Schema{fields: fields}, key) do
    if Map.has_key?(fields, key),
      do: key,
      else: Enum.find(Map.keys(fields), &(to_string(&1) == to_string(key)))
  end

  defp typed?(:number, value), do: is_number(value)
  defp typed?(:time, value), do: Window.instant?(value)
  defp typed?(:text, value), do: is_binary(value)

  defp typed?(:category, value),
    do: is_binary(value) or is_number(value) or (is_atom(value) and not is_boolean(value))

  # A category value is one whichever spelling the function or the schema gives it (D-195).
  # Compared with the bare values, an entry's by its value (D-224).
  defp member?(nil, _value), do: true
  defp member?(values, value), do: Enum.any?(values, &Names.same?(&1, value))

  # -- paths (spec/08 §10.5.9) -------------------------------------------------------------

  @doc """
  A path shown dotted (spec/08 §10.5.9).

      iex> Visualize.VirtualSource.dotted([:ops, :health])
      "ops.health"
  """
  @spec dotted([atom()]) :: String.t()
  def dotted(path) when is_list(path), do: Enum.map_join(path, ".", &to_string/1)

  @doc """
  What a reference names (spec/08 §10.5.9), given every definition's path (a list, or a
  map keyed by path) and the scope it is read from: a short id from the inside out — the
  scope, then each container around it — a full path exactly. `{:ok, path}` or `:error`;
  a string is a feed's name and is never resolved.

      iex> paths = [[:health], [:ops, :health], [:ops, :box, :load]]
      iex> Visualize.VirtualSource.resolve(paths, [:ops, :box], :health)
      {:ok, ["ops", "health"]}
      iex> Visualize.VirtualSource.resolve(paths, [:other], :health)
      {:ok, ["health"]}
      iex> Visualize.VirtualSource.resolve(paths, [], [:ops, :box, :load])
      {:ok, ["ops", "box", "load"]}
      iex> Visualize.VirtualSource.resolve(paths, [:ops], {:feed, "health"})
      :error
  """
  @spec resolve([[atom()]] | map(), [atom()], name()) :: {:ok, [atom()]} | :error
  def resolve(paths, scope, ref) when is_map(paths), do: resolve(Map.keys(paths), scope, ref)

  def resolve(paths, scope, ref)
      when is_list(paths) and is_list(scope) and (is_binary(ref) or (is_atom(ref) and ref != nil)) do
    # Every name by its string (D-195): a host may give paths and a scope of atoms.
    ref = Names.name(ref)
    scope = Enum.map(scope, &Names.name/1)
    known = MapSet.new(paths, &spelled_path/1)

    Enum.find_value(length(scope)..0//-1, :error, fn n ->
      path = Enum.take(scope, n) ++ [ref]
      if MapSet.member?(known, path), do: {:ok, path}
    end)
  end

  def resolve(paths, _scope, [_ | _] = ref) when is_list(paths) do
    ref = spelled_path(ref)
    if ref in Enum.map(paths, &spelled_path/1), do: {:ok, ref}, else: :error
  end

  def resolve(_paths, _scope, _ref), do: :error

  defp spelled_path(path) when is_list(path), do: Enum.map(path, &Names.name/1)
  defp spelled_path(other), do: other

  # -- forms (spec/08 §10.5.10) ------------------------------------------------------------

  @doc """
  The source's map form (spec/08 §10.5.10): `new(to_map(source))` is `{:ok, source}`.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = source) do
    %{
      id: source.id,
      from: source.from,
      schema: source.schema.fields,
      elixir: source.elixir,
      function: source.function,
      per: source.per
    }
  end

  @doc """
  One fault as a line a person reads, the root named `virtual source` (spec/08 §10.5.5).

      iex> Visualize.VirtualSource.format_error({[:per], {:per, :ambiguous}})
      "per: is :identity over several inputs: name the input, {:identity, input}"
  """
  @spec format_error(error()) :: String.t()
  def format_error({[], reason}), do: "virtual source: " <> ChartValidator.Words.words(reason)
  def format_error(error), do: ChartValidator.format(error)
end
