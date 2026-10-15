defmodule Visualize.Data.Schema do
  @moduledoc """
  A feed's schema: what each of its fields means (spec/08 §10.1, D-136).

  A schema maps a field — named as the feed's rows name it, an atom or a string — to a
  **description**: its `type`, and as much of `unit`, `quantity`, `label`, `order`,
  `status`, `polarity`, `target`, `continuity`, `window`, `metric_kind`, `bounds` and
  `identity` as the feed knows. It says what
  the numbers *are*, whoever draws them, and never how they are drawn: a description has
  no colour key, since colour is the theme's to choose from the meaning (#533). A `:time`
  field holds instants; a feed whose clock is a number describes it `:number` and
  `window: true`, the field its windows are over (D-154). A numeric field may say how it
  was measured, `metric_kind: :gauge | :counter | :rate`, which refines what its
  quantity's additivity allows, and where its values lie, `bounds: [min, max]`, a display
  hint over its quantity's (D-155). A `unit` is a UCUM code `Visualize.Unit` reads and a
  `quantity` one of `Visualize.Quantity.all/0`, and when both are given the unit measures
  the quantity (D-157). A field whose value names the thing a row is about says
  `identity: true`, several such fields together naming it (D-167); `identity/2` gives a
  row's identity under the schema.

  A schema is identified by its `version`, a content hash (spec/08 §10.2): the same
  schema has the same version on every node and under every release, and any change of
  content is a new version. A `Visualize.Data.Delivery` names the version its rows were
  produced under; `Visualize.Data.Schema.Cache` holds schemas by `{feed, version}`.
  Schemas of different versions may still describe the same data in different words,
  and `compatibility/2` says when one's rows read as the other's (D-159).

  ## Examples

      iex> {:ok, schema} =
      ...>   Visualize.Data.Schema.new(%{
      ...>     t: %{type: :time},
      ...>     latency: %{type: :number, unit: "s", quantity: :duration, label: "Request time"},
      ...>     state: %{type: :category, order: ["ok", "warn", "fail"],
      ...>              status: %{"ok" => :good, "warn" => :warning, "fail" => :bad}}
      ...>   })
      iex> Visualize.Data.Schema.fetch(schema, "latency", :unit)
      {:ok, "s"}
      iex> String.length(Visualize.Data.Schema.version(schema))
      64
      iex> Visualize.Data.Schema.new(%{state: %{type: :category, colors: %{"ok" => "#0a0"}}})
      {:error, [{[:state, :colors], {:color_key, :colors}}]}

  """

  alias Visualize.Data.Table
  alias Visualize.{Quantity, Unit}

  @enforce_keys [:fields, :version]
  defstruct [:fields, :version]

  @typedoc "A field name, as the feed's rows spell it."
  @type name :: atom() | String.t()

  @typedoc "What one field means (spec/08 §10.1)."
  @type description :: %{
          required(:type) => :time | :number | :category | :text,
          optional(:unit) => String.t(),
          optional(:quantity) => atom(),
          optional(:label) => String.t(),
          optional(:order) => [String.t() | atom() | number(), ...],
          optional(:status) => %{term() => atom()},
          optional(:polarity) => :higher_is_better | :lower_is_better | :neutral,
          optional(:target) => number(),
          optional(:continuity) => number(),
          optional(:window) => boolean(),
          optional(:metric_kind) => :gauge | :counter | :rate,
          optional(:bounds) => [number() | nil],
          optional(:identity) => boolean()
        }

  @type t :: %__MODULE__{fields: %{name() => description()}, version: String.t()}

  @typedoc "A fault of `new/1`: the path from the schema to the value, and why."
  @type error :: {[name() | atom() | non_neg_integer() | term()], term()}

  @attributes [
    :type,
    :unit,
    :quantity,
    :label,
    :order,
    :status,
    :polarity,
    :target,
    :continuity,
    :window,
    :metric_kind,
    :bounds,
    :identity
  ]
  @types [:time, :number, :category, :text]
  @polarities [:higher_is_better, :lower_is_better, :neutral]
  @metric_kinds [:gauge, :counter, :rate]
  # spelling: allow — a feed schema refuses a color key in either spelling.
  @color_keys [:color, :colour, :colors, :colours, :palette, :fill, :stroke]

  # The keys a field's type takes; every other key but `type`, `label` and `continuity` is
  # `{:invalid_for, type}` on it. `window` is a clock's: a `:time` or a `:number` field's.
  @numeric [:unit, :quantity, :polarity, :target, :metric_kind, :bounds]
  @categorical [:order, :status]
  @clocks [:time, :number]
  # `identity` names a thing, which a `:time` field never does: it says when (D-167).
  @identities [:category, :text, :number]

  # The first line of the canonical encoding, naming the encoding itself (spec/08 §10.2).
  @encoding "visualize.schema/1\n"

  @not_names [nil, true, false]

  @doc "The thirteen description keys, `:type` first (spec/08 §10.1)."
  @spec attributes() :: [atom(), ...]
  def attributes, do: @attributes

  @doc false
  # The three polarities, which a colour scale over a ramp reads too (spec/14 §4.3, D-143).
  @spec polarities() :: [atom(), ...]
  def polarities, do: @polarities

  @doc """
  The schema of a map of field descriptions, or every fault of it by path (spec/08 §10.1).

      iex> Visualize.Data.Schema.new(%{v: %{type: :category, unit: "s"}})
      {:error, [{[:v, :unit], {:invalid_for, :category}}]}

      iex> Visualize.Data.Schema.new(%{v: %{type: :number, unit: "By", quantity: :duration}})
      {:error, [{[:v, :quantity], {:quantity, :duration, "By"}}]}
  """
  @spec new(term()) :: {:ok, t()} | {:error, [error(), ...]}
  def new(fields) when is_map(fields) and not is_struct(fields) do
    errors =
      Enum.flat_map(fields, fn {name, description} -> field(name, description) end) ++
        duplicates(Map.keys(fields)) ++ windows(fields)

    case Enum.sort_by(errors, &elem(&1, 0)) do
      [] ->
        fields = Map.new(fields, fn {name, d} -> {name, declared(d)} end)
        {:ok, %__MODULE__{fields: fields, version: hash(fields)}}

      errors ->
        {:error, errors}
    end
  end

  def new(_other), do: {:error, [{[], {:type, :schema}}]}

  @doc "The schema of a map of field descriptions, or `ArgumentError` naming every fault."
  @spec new!(term()) :: t()
  def new!(fields) do
    case new(fields) do
      {:ok, schema} ->
        schema

      {:error, errors} ->
        raise ArgumentError,
              "not a schema:\n" <> Enum.map_join(errors, "\n", &("  " <> format_error(&1)))
    end
  end

  @doc """
  The schema's version: the SHA-256 of its canonical encoding as 64 lowercase hex digits
  (spec/08 §10.2), computed once by `new/1`.
  """
  @spec version(t()) :: String.t()
  def version(%__MODULE__{version: version}), do: version

  @doc """
  A field's description, by either spelling of its name (spec/08 §6.2).

      iex> schema = Visualize.Data.Schema.new!(%{"v" => %{type: :number}})
      iex> Visualize.Data.Schema.fetch(schema, :v)
      {:ok, %{type: :number}}
      iex> Visualize.Data.Schema.fetch(schema, :w)
      :error
  """
  @spec fetch(t(), name()) :: {:ok, description()} | :error
  def fetch(%__MODULE__{fields: fields}, name) when is_atom(name) or is_binary(name) do
    case Map.fetch(fields, name) do
      {:ok, description} -> {:ok, description}
      :error -> Map.fetch(fields, other_spelling(fields, name))
    end
  end

  @doc "One attribute of a field's description; `:error` when the field or the attribute is absent."
  @spec fetch(t(), name(), atom()) :: {:ok, term()} | :error
  def fetch(%__MODULE__{} = schema, name, key) when is_atom(key) do
    with {:ok, description} <- fetch(schema, name), do: Map.fetch(description, key)
  end

  @doc """
  The fields the schema declares `identity: true`, as it spells them, ordered by name as a
  string; `[]` when it declares none (spec/08 §10.1, D-167).

      iex> schema = Visualize.Data.Schema.new!(%{
      ...>   iface: %{type: :category, identity: true},
      ...>   host: %{type: :category, identity: true},
      ...>   bytes: %{type: :number}
      ...> })
      iex> Visualize.Data.Schema.identity(schema)
      [:host, :iface]
  """
  @spec identity(t()) :: [name()]
  def identity(%__MODULE__{fields: fields}) do
    for({name, %{identity: true}} <- fields, do: name)
    |> Enum.sort_by(&to_string/1)
  end

  @doc """
  A row's identity under the schema (spec/08 §10.1, D-167): the bare value of the one
  identity field, a map from field to value, keyed as the schema spells them, for several,
  and `nil` when the schema declares none or the row has no value for one of them. Each
  field is read by either spelling of its name.

      iex> one = Visualize.Data.Schema.new!(%{id: %{type: :category, identity: true}, x: %{type: :number}})
      iex> Visualize.Data.Schema.identity(one, %{"id" => "frog-1", "x" => 3})
      "frog-1"
      iex> two = Visualize.Data.Schema.new!(%{host: %{type: :category, identity: true},
      ...>   iface: %{type: :category, identity: true}})
      iex> Visualize.Data.Schema.identity(two, %{host: "mx1", iface: "eth0", bytes: 9})
      %{host: "mx1", iface: "eth0"}
      iex> Visualize.Data.Schema.identity(two, %{host: "mx1"})
      nil
  """
  @spec identity(t(), map()) :: term()
  def identity(%__MODULE__{} = schema, row) when is_map(row) do
    case identity(schema) do
      [] -> nil
      [field] -> Table.get(row, field)
      fields -> composite(fields, row)
    end
  end

  defp composite(fields, row) do
    values = Map.new(fields, &{&1, Table.get(row, &1)})
    if Enum.any?(values, fn {_field, value} -> value == nil end), do: nil, else: values
  end

  @typedoc "Why a field of one schema cannot read another's rows (spec/08 §10.1, D-159)."
  @type incompatibility ::
          :missing
          | {:type, atom(), atom()}
          | {:unit, term(), term()}
          | {:identity, boolean(), boolean()}

  @doc """
  Whether `other`'s rows read as `schema`'s (spec/08 §10.1, D-159): for each field of
  `schema`, `other` has a field of the same name compared as strings, of the same type,
  and for a `:number` field a unit that converts into `schema`'s — two absent units
  agree, one absent facing a present one does not. `{:error, faults}` lists every fault,
  `field` spelt as `schema` spells it, ordered by its name as a string. Labels and facts
  are not compared, and `other`'s extra fields are not faults — except identity (D-167):
  a field one schema declares `identity: true` and the other does not is `{:identity, a,
  b}`, `a` and `b` whether each declares it, even a field only `other` has, since
  `other`'s rows read as `schema`'s would merge the things `other` tells apart.

      iex> live = Visualize.Data.Schema.new!(%{t: %{type: :time}, value: %{type: :number, unit: "ms"}})
      iex> history = Visualize.Data.Schema.new!(%{"t" => %{type: :time}, "value" => %{type: :number, unit: "s", label: "Load"}})
      iex> Visualize.Data.Schema.compatibility(live, history)
      :ok
      iex> bytes = Visualize.Data.Schema.new!(%{"value" => %{type: :number, unit: "By"}})
      iex> Visualize.Data.Schema.compatibility(live, bytes)
      {:error, [{:t, :missing}, {:value, {:unit, "ms", "By"}}]}
      iex> hosts = Visualize.Data.Schema.new!(%{host: %{type: :category, identity: true}})
      iex> ifaces = Visualize.Data.Schema.new!(%{host: %{type: :category, identity: true},
      ...>   iface: %{type: :category, identity: true}})
      iex> Visualize.Data.Schema.compatibility(hosts, ifaces)
      {:error, [{:iface, {:identity, false, true}}]}
  """
  @spec compatibility(t(), t()) :: :ok | {:error, [{name(), incompatibility()}, ...]}
  def compatibility(%__MODULE__{fields: fields} = schema, %__MODULE__{} = other) do
    ours =
      Enum.flat_map(fields, fn {name, description} ->
        case fetch(other, name) do
          {:ok, theirs} ->
            compatible(name, description, theirs) ++ same_identity(name, description, theirs)

          :error ->
            [{name, :missing}]
        end
      end)

    # An identity field only `other` has: its rows tell apart what `schema`'s do not.
    theirs =
      for name <- identity(other),
          fetch(schema, name) == :error,
          do: {name, {:identity, false, true}}

    case Enum.sort_by(ours ++ theirs, fn {name, _reason} -> to_string(name) end) do
      [] -> :ok
      faults -> {:error, faults}
    end
  end

  defp same_identity(name, ours, theirs) do
    case {Map.get(ours, :identity, false), Map.get(theirs, :identity, false)} do
      {same, same} -> []
      {a, b} -> [{name, {:identity, a, b}}]
    end
  end

  defp compatible(name, %{type: ours}, %{type: theirs}) when ours != theirs,
    do: [{name, {:type, ours, theirs}}]

  defp compatible(name, %{type: :number} = ours, theirs) do
    case {Map.get(ours, :unit), Map.get(theirs, :unit)} do
      {same, same} ->
        []

      {to, from} when to == nil or from == nil ->
        [{name, {:unit, to, from}}]

      {to, from} ->
        case Unit.conversion(from, to) do
          {:ok, _conversion} -> []
          {:error, _reason} -> [{name, {:unit, to, from}}]
        end
    end
  end

  defp compatible(_name, _ours, _theirs), do: []

  # The key of `fields` spelled as `name` is in the other spelling; never creates an atom.
  defp other_spelling(_fields, name) when is_atom(name), do: Atom.to_string(name)

  defp other_spelling(fields, name) do
    Enum.find(Map.keys(fields), fn key -> is_atom(key) and Atom.to_string(key) == name end)
  end

  # -- checks ---------------------------------------------------------------------------

  defp field(name, _description) when not (is_atom(name) or is_binary(name)) or name == "",
    do: [{[name], {:type, :name}}]

  defp field(name, _description) when name in @not_names, do: [{[name], {:type, :name}}]

  defp field(name, description) when is_map(description) and not is_struct(description) do
    type = Map.get(description, :type)

    missing = if Map.has_key?(description, :type), do: [], else: [{[name, :type], :required}]

    keys = Enum.flat_map(description, fn {key, value} -> key(name, type, key, value) end)

    missing ++ keys ++ unordered(name, description) ++ measure(name, description, keys)
  end

  defp field(name, _description), do: [{[name], {:type, :description}}]

  # Every state `status` names is one of `order`'s, when the description gives both.
  defp unordered(name, %{order: order, status: status}) when is_list(order) and is_map(status) do
    for {state, _role} <- status,
        state not in order,
        do: {[name, :status, state], :not_in_order}
  end

  defp unordered(_name, _description), do: []

  # Two spellings of one column (spec/08 §6.2) are one field named twice: reported at the
  # later spelling by term order, which is the string.
  defp duplicates(names) do
    strings = for name <- names, is_binary(name), into: MapSet.new(), do: name

    for name <- names,
        is_atom(name) and name not in @not_names,
        spelled = Atom.to_string(name),
        MapSet.member?(strings, spelled),
        do: {[spelled], {:duplicate_field, name}}
  end

  # A feed's windows are over one field: a second `window: true` is reported at the later
  # field by term order, naming the first. A field whose type takes no `window` is
  # reported for that alone.
  defp windows(fields) do
    case for({name, %{type: type, window: true}} when type in @clocks <- fields, do: name) do
      [_ | [_ | _]] = names ->
        [first | rest] = Enum.sort(names)
        for name <- rest, do: {[name, :window], {:duplicate_window, first}}

      _one_or_none ->
        []
    end
  end

  defp key(name, _type, key, _value) when key in @color_keys,
    do: [{[name, key], {:color_key, key}}]

  defp key(name, _type, key, _value) when key not in @attributes,
    do: [{[name, key], :unknown_key}]

  defp key(name, _type, :type, value) do
    if value in @types, do: [], else: [{[name, :type], {:enum, @types}}]
  end

  defp key(name, type, key, _value) when key in @numeric and type in @types and type != :number,
    do: [{[name, key], {:invalid_for, type}}]

  defp key(name, type, key, _value)
       when key in @categorical and type in @types and type != :category,
       do: [{[name, key], {:invalid_for, type}}]

  defp key(name, type, :window, _value) when type in @types and type not in @clocks,
    do: [{[name, :window], {:invalid_for, type}}]

  defp key(name, type, :identity, _value) when type in @types and type not in @identities,
    do: [{[name, :identity], {:invalid_for, type}}]

  defp key(name, _type, :unit, value), do: unit(value, [name, :unit])

  defp key(name, _type, :quantity, value) when not is_atom(value) or value in @not_names,
    do: [{[name, :quantity], {:type, :name}}]

  defp key(name, _type, :quantity, value) do
    if value in Quantity.all(),
      do: [],
      else: [{[name, :quantity], {:unknown_quantity, value}}]
  end

  defp key(name, _type, :label, value) do
    if is_binary(value), do: [], else: [{[name, :label], {:type, :string}}]
  end

  defp key(name, _type, :order, value), do: order(value, [name, :order])

  defp key(name, _type, :status, value) do
    if is_map(value) and not is_struct(value) and
         Enum.all?(value, fn {state, role} -> state?(state) and role?(role) end),
       do: [],
       else: [{[name, :status], {:type, :status}}]
  end

  defp key(name, _type, :polarity, value) do
    if value in @polarities, do: [], else: [{[name, :polarity], {:enum, @polarities}}]
  end

  defp key(name, _type, :target, value) do
    if is_number(value), do: [], else: [{[name, :target], {:type, :number}}]
  end

  defp key(name, _type, :continuity, value) do
    if is_number(value) and value > 0, do: [], else: [{[name, :continuity], {:type, :positive}}]
  end

  defp key(name, _type, :metric_kind, value) do
    if value in @metric_kinds, do: [], else: [{[name, :metric_kind], {:enum, @metric_kinds}}]
  end

  defp key(name, _type, :bounds, value) do
    if bounds?(value), do: [], else: [{[name, :bounds], {:type, :bounds}}]
  end

  defp key(name, _type, :window, value) do
    if is_boolean(value), do: [], else: [{[name, :window], {:type, :boolean}}]
  end

  defp key(name, _type, :identity, value) do
    if is_boolean(value), do: [], else: [{[name, :identity], {:type, :boolean}}]
  end

  # `identity: false` is the description that says nothing, kept as that one schema
  # (spec/08 §10.1, D-167).
  defp declared(%{identity: false} = description), do: Map.delete(description, :identity)
  defp declared(description), do: description

  # A unit is a UCUM code `Visualize.Unit` reads (spec/05 §4.1, D-157).
  defp unit(value, path) when is_binary(value) and value != "" do
    case Unit.parse(value) do
      {:ok, _components} -> []
      {:error, reason} -> [{path, {:unit, value, reason}}]
    end
  end

  defp unit(_value, path), do: [{path, {:type, :unit}}]

  # A numeric field giving a unit and a quantity, each good on its own, gives a unit of
  # that quantity (spec/05 §4.2, D-157): the pair is `Visualize.Quantity.resolve/1`'s, so
  # its fault is the one an axis's measure reports.
  defp measure(name, %{type: :number, unit: unit, quantity: quantity}, faults) do
    reported? = Enum.any?(faults, &match?({[_, key], _} when key in [:unit, :quantity], &1))

    case reported? || Quantity.resolve(%{unit: unit, quantity: quantity}) do
      {:error, reason} -> [{[name, :quantity], reason}]
      _good_or_reported -> []
    end
  end

  defp measure(_name, _description, _faults), do: []

  defp order([_ | _] = states, path) do
    if Enum.all?(states, &state?/1) do
      states
      |> Enum.with_index()
      |> Enum.reduce({MapSet.new(), []}, fn {state, i}, {seen, errors} ->
        if MapSet.member?(seen, state),
          do: {seen, [{path ++ [i], :duplicate} | errors]},
          else: {MapSet.put(seen, state), errors}
      end)
      |> elem(1)
      |> Enum.reverse()
    else
      [{path, {:type, :order}}]
    end
  end

  defp order(_other, path), do: [{path, {:type, :order}}]

  # `[min, max]`, each a number or `nil`, the first below the second when both are given.
  defp bounds?([min, max]) when is_number(min) and is_number(max), do: min < max
  defp bounds?([min, max]), do: (is_number(min) or min == nil) and (is_number(max) or max == nil)
  defp bounds?(_other), do: false

  defp state?(v), do: is_binary(v) or is_number(v) or (is_atom(v) and v not in @not_names)
  defp role?(v), do: is_atom(v) and v not in @not_names

  # -- the content hash (spec/08 §10.2) -------------------------------------------------

  defp hash(fields) do
    named = Map.new(fields, fn {name, description} -> {to_string(name), description} end)

    :sha256
    |> :crypto.hash([@encoding | encode(named)])
    |> Base.encode16(case: :lower)
  end

  # A tagged, length-prefixed encoding of our own: never `term_to_binary/2`, whose
  # external format is not promised across OTP releases; never a map's iteration order.
  defp encode(atom) when is_atom(atom), do: tagged("a", Atom.to_string(atom))
  defp encode(string) when is_binary(string), do: tagged("s", string)
  defp encode(int) when is_integer(int), do: ["i", Integer.to_string(int), ";"]

  defp encode(float) when is_float(float),
    do: ["f", :erlang.float_to_binary(float, [:short]), ";"]

  defp encode(list) when is_list(list),
    do: ["l", Integer.to_string(length(list)), ":" | Enum.map(list, &encode/1)]

  defp encode(map) when is_map(map) do
    entries =
      map
      |> Enum.map(fn {k, v} -> {IO.iodata_to_binary(encode(k)), encode(v)} end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {k, v} -> [k, v] end)

    ["m", Integer.to_string(map_size(map)), ":" | entries]
  end

  defp tagged(tag, bytes), do: [tag, Integer.to_string(byte_size(bytes)), ":", bytes]

  # -- formatting -----------------------------------------------------------------------

  @doc """
  One fault of `new/1` as a line a person reads.

      iex> Visualize.Data.Schema.format_error({[:latency, :unit], {:invalid_for, :category}})
      "latency.unit: is not a key a :category field takes"
  """
  @spec format_error(error()) :: String.t()
  def format_error({path, reason}), do: "#{format_path(path)}: #{words(reason)}"

  defp format_path([]), do: "schema"

  defp format_path(path) do
    Enum.map_join(path, ".", fn
      i when is_integer(i) -> "[#{i}]"
      k when is_atom(k) or is_binary(k) -> to_string(k)
      other -> inspect(other)
    end)
    |> String.replace(".[", "[")
  end

  defp words({:color_key, key}) do
    "#{inspect(key)} names a colour, which a schema never does: describe the meaning " <>
      "(status, order, polarity, quantity) and the theme chooses the colour"
  end

  defp words({:type, :schema}), do: "must be a map from field names to descriptions"
  defp words({:type, :name}), do: "must be a name: an atom or a non-empty string"
  defp words({:type, :description}), do: "must be a map of description keys"
  defp words({:type, :unit}), do: "must be a unit: a non-empty string, a UCUM code"

  defp words({:unit, _code, reason}),
    do: "#{Unit.format_error(reason)} (spec/05 §4.1)"

  defp words({:unknown_quantity, quantity}),
    do: "#{inspect(quantity)} is not a quantity: one of Visualize.Quantity.all/0 (spec/05 §4.2)"

  defp words({:quantity, quantity, code}),
    do: "unit #{inspect(code)} does not measure #{inspect(quantity)} (spec/05 §4.2)"

  defp words({:type, :string}), do: "must be a string"
  defp words({:type, :number}), do: "must be a number"

  defp words({:type, :positive}),
    do: "must be a positive number, in the window field's units (seconds for a time)"

  defp words({:type, :boolean}), do: "must be true or false"

  defp words({:type, :bounds}),
    do: "must be [min, max], each a number or nil, min below max when both are given"

  defp words({:type, :order}),
    do: "must be a non-empty list of states: strings, atoms or numbers"

  defp words({:type, :status}), do: "must be a map from a state to a role atom"

  defp words({:duplicate_field, name}),
    do: "names the same column as #{inspect(name)}: a field is described once"

  defp words({:duplicate_window, other}),
    do: "is a second window field beside #{inspect(other)}: a feed's windows are over one field"

  defp words(:unknown_key),
    do: "is not a description key; the keys are #{Enum.map_join(@attributes, ", ", &inspect/1)}"

  defp words(:required), do: "is required"
  defp words({:enum, allowed}), do: "must be one of #{Enum.map_join(allowed, ", ", &inspect/1)}"
  defp words({:invalid_for, type}), do: "is not a key a #{inspect(type)} field takes"
  defp words(:duplicate), do: "is listed twice"
  defp words(:not_in_order), do: "is a state the field's order does not list"
end
