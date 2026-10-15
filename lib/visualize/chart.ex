defmodule Visualize.Chart do
  @moduledoc """
  A chart as a design map (spec/14).

  The nested map is the chart: it names its sources, its frame, its marks and its
  labels without a function anywhere in it, so a design can be stored, diffed, built by
  a tool and bound to different data. This struct is a view of that map — one field per
  design-level key (spec/14 §2.1) — and `from_map/1` and `to_map/1` are exact inverses:
  the nested nodes are stored as the author wrote them, and a reader takes any default
  from `Visualize.Chart.Schema` (D-59). `from_json/1` and `to_json/1` are the same round
  trip over a JSON document, behind the optional `Jason` dependency (spec/14 §11).

  A design is a template: its sources are typed slots and its variables are terms.
  `apply/2` resolves the variables, binds the slots from a pool of named sources and
  realizes the frame into a `Visualize.Chart.Applied` that `render/2` draws (spec/14 §7.3);
  `compose/2` merges fragments by the schema's merge rules and `stack/1` layers them (§8).

  ## Examples

      iex> {:ok, chart} =
      ...>   Visualize.Chart.from_map(%{
      ...>     version: 2,
      ...>     sources: %{primary: %{fields: [:t, :v]}},
      ...>     frames: %{main: %{kind: :cartesian, scales: %{x: %{kind: :time}, y: %{kind: :linear}}}},
      ...>     marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v}}]
      ...>   })
      iex> chart.marks
      [%{type: :line, data: :primary, channels: %{x: :t, y: :v}}]
      iex> Visualize.Chart.from_map(%{version: 2, frames: %{main: %{kind: :cartesian}}, marks: [%{}]})
      {:error, [{[:marks, 0, :data], :required}, {[:marks, 0, :type], :required}]}

  """

  # Jason is optional (spec/14 §11.1, D-50): the calls stay direct and a missing Jason is
  # reported as a value by the two JSON functions, never as a compile warning.
  @compile {:no_warn_undefined, Jason}

  # `apply/2` is a function of this module (spec/14 §7.3), never the kernel's.
  import Kernel, except: [apply: 2]

  alias Visualize.Chart.{
    Applied,
    Codec,
    Compiled,
    Compose,
    Composite,
    Fact,
    Facts,
    Fragment,
    Frame,
    Limits,
    Migration,
    Schema,
    Stack,
    Summary,
    Template,
    Text,
    Types,
    Use,
    Validator,
    Var
  }

  alias Visualize.Chart.Codec.Tags
  alias Visualize.Chart.Frame.Scales
  alias Visualize.Chart.Style.Generated
  alias Visualize.Data.Schema.Cache

  alias Visualize.IR.{Element, Transform}

  @design_keys [
    :version,
    :meta,
    :sources,
    :vars,
    :theme,
    :styles,
    :defs,
    :defaults,
    :layout,
    :interaction,
    :frames,
    :marks,
    :labels
  ]

  defstruct version: 3,
            meta: %{},
            sources: %{},
            vars: %{},
            theme: :default,
            styles: %{},
            defs: %{},
            defaults: nil,
            layout: %{},
            interaction: %{},
            frames: nil,
            marks: [],
            labels: []

  @type t :: %__MODULE__{
          version: pos_integer(),
          meta: map(),
          sources: %{atom() => map()},
          vars: %{atom() => map()},
          theme: atom() | map(),
          styles: %{atom() => map()},
          defs: %{atom() => map()},
          defaults: map() | nil,
          layout: map(),
          interaction: map(),
          frames: %{atom() => map()} | nil,
          marks: [map()],
          labels: [map()]
        }

  @typedoc """
  A layer of a stack (spec/14 §8.2): a fragment, a chart, or a `{name, layer}` pair whose
  name `stack/1` ignores and `explain/1` reports.
  """
  @type layer :: t() | map() | {term(), t() | map()}

  @typedoc """
  One leaf of a stack, with the layer that set it and the layers it overrode (spec/14 §17.1).

  `layer` is a layer's name, or its zero-based position in the list when it was given
  without one; `overrode` reads lowest first and is `[]` where nothing was overridden.
  """
  @type provenance :: %{
          path: Validator.path(),
          value: term(),
          layer: term(),
          overrode: [term()]
        }

  @typedoc """
  One variable a design still demands, and where it stands (spec/14 §17.2).

  `default` is the declaration's from the stacked `vars` node, `nil` where no layer
  declares one, and `required` is `true` exactly then. A use's `expects` is the schema's
  type at that path (`t:Visualize.Chart.Schema.type/0`) and its `layer` is named as
  `explain/1` names one.
  """
  @type free_var :: %{
          name: atom(),
          default: term(),
          required: boolean(),
          uses: [%{path: Validator.path(), expects: Schema.type(), layer: term()}]
        }

  @typedoc "What a scale's kind needs of a field it reads (spec/14 §7.4, D-153)."
  @type need :: :time | :number | :category

  @typedoc """
  What is known of a slot's fields' types (spec/14 §7.4): its `Visualize.Data.Schema`, what
  they mean, or a map from field to type, how rows write them.
  """
  @type field_types :: Visualize.Data.Schema.t() | %{optional(atom() | String.t()) => atom()}

  @doc """
  The chart of a design map, or every fault in it.

  A version newer than this library reads is refused first, before anything of the map is
  read (spec/14 §9.1); then the map is held to the sanity limits (§9.2), migrated to the
  current version (§9) and validated (§10). Design-level keys absent from the map take the
  defaults of spec/14 §2.1.

  `limits:` tightens the limits for a design from elsewhere — a keyword list or map over
  `Visualize.Chart.Limits.defaults/0`, which apply when it is not given; the host knows
  its inputs and holds the number. Raises `ArgumentError` for a name that is not a limit
  or a value that is not a positive integer.

  `generators:` names the generator modules (`Visualize.Generators`, spec/14 §3.13) the
  design's generator names are checked against, beside `config :visualize, generators:`;
  a name neither defines is `{:undeclared, :generator, name}`.

      iex> Visualize.Chart.from_map(%{version: 4, frames: %{main: %{}}})
      {:error, [{[:version], {:newer_schema, 4, 3}}]}
  """
  @spec from_map(term(), keyword()) :: {:ok, t()} | {:error, [Validator.error(), ...]}
  def from_map(map, opts \\ []) do
    limits = opts |> Keyword.get(:limits, []) |> Limits.new()

    with :ok <- readable(map),
         :ok <- within(Limits.structure(map, limits)) do
      read(map, limits, Keyword.take(opts, [:urls, :generators]))
    end
  end

  # The steps after the document's structure is known to be within its limits: shared
  # by `from_json/2`, which checks the structure on the parsed JSON before decoding it.
  defp read(map, limits, checks) do
    with {:ok, map} <- Migration.migrate(map),
         :ok <- within(Limits.counts(map, limits)),
         :ok <- Validator.validate(map, :design, checks) do
      {:ok, struct(__MODULE__, Map.take(map, @design_keys))}
    end
  end

  defp readable(%{version: v}), do: readable_version(v)
  defp readable(%{"version" => v}), do: readable_version(v)
  defp readable(_map), do: :ok

  defp readable_version(v) do
    with {:error, reason} <- Migration.readable(v), do: {:error, [{[:version], reason}]}
  end

  defp within([]), do: :ok
  defp within(errors), do: {:error, errors}

  defp version(%{"version" => v}), do: v
  defp version(_term), do: nil

  @doc "As `from_map/2`, raising `ArgumentError` with the formatted errors."
  @spec from_map!(term(), keyword()) :: t()
  def from_map!(map, opts \\ []) do
    case from_map(map, opts) do
      {:ok, chart} ->
        chart

      {:error, errors} ->
        raise ArgumentError,
              "invalid design:\n" <> Enum.map_join(errors, "\n", &("  " <> Validator.format(&1)))
    end
  end

  @doc "The design map of a chart: every design-level key, nested nodes as stored."
  @spec to_map(t()) :: map()
  # A design that declares no defaults carries no key for them (spec/14 §3.8), so its map
  # and its JSON are what they were before defaults existed.
  def to_map(%__MODULE__{defaults: nil} = chart),
    do: chart |> Map.from_struct() |> Map.delete(:defaults)

  def to_map(%__MODULE__{} = chart), do: Map.from_struct(chart)

  @doc """
  The chart of a JSON document (spec/14 §11), with `limits:`, `urls:` and `generators:` as
  `from_map/2` takes them.

  The parsed document's `"version"` is checked, and its nesting and the size of its lists
  and maps held to the limits, **before** the codec decodes a key (spec/14 §9.1, §9.2): a
  newer or an oversized document is refused without an atom made from it, and a path in
  such an error holds the document's own key strings. Then its tags are held to the one
  table (spec/14 §11.2, D-182): an unknown tag is `{:unknown_tag, tag}` and a retired one
  `{:retired_tag, tag, why}`, at the path of its object. A document that does not parse is
  `{:error, [{[], {:json, message}}]}`; without `Jason` the result is
  `{:error, {:missing_dependency, :jason}}`.
  """
  @spec from_json(String.t(), keyword()) ::
          {:ok, t()} | {:error, [Validator.error(), ...] | {:missing_dependency, :jason}}
  def from_json(json, opts \\ []) when is_binary(json) do
    if Code.ensure_loaded?(Jason) do
      limits = opts |> Keyword.get(:limits, []) |> Limits.new()

      case Jason.decode(json) do
        {:ok, term} ->
          with :ok <- readable(term),
               :ok <- within(Limits.structure(term, limits)),
               {:ok, term} <- Tags.read(term, version(term)) do
            read(Codec.decode(term), limits, Keyword.take(opts, [:urls, :generators]))
          end

        {:error, error} ->
          {:error, [{[], {:json, Exception.message(error)}}]}
      end
    else
      {:error, {:missing_dependency, :jason}}
    end
  end

  @doc "The JSON document of a chart (spec/14 §11), or `{:error, {:missing_dependency, :jason}}`."
  @spec to_json(t()) :: {:ok, String.t()} | {:error, {:missing_dependency, :jason}}
  def to_json(%__MODULE__{} = chart) do
    if Code.ensure_loaded?(Jason) do
      {:ok, json} = chart |> to_map() |> Codec.encode() |> Jason.encode()
      {:ok, json}
    else
      {:error, {:missing_dependency, :jason}}
    end
  end

  @doc "A variable term for the name (spec/14 §7.1)."
  @spec var(atom()) :: Var.t()
  def var(name) when is_atom(name), do: %Var{name: name}

  @doc """
  A fact of the feed's schema bound to slot `source`: the attribute `key` of `field`
  (spec/14 §7.4). Allowed wherever a value can appear, and in a text as
  `\#{fact(:source, :field, :key)}`; `apply/2` replaces it by the attribute, and a
  schema that does not give it fails application.
  """
  @spec fact(atom(), atom(), atom()) :: Fact.t()
  def fact(source, field, key) when is_atom(source) and is_atom(field) and is_atom(key),
    do: %Fact{source: source, field: field, key: key}

  @doc """
  Each slot's requirements of its feed's schema (spec/14 §7.4): its `requires` with every
  attribute a fact of it reads, as `%{slot => %{field => [key, …]}}` in the order of
  `Visualize.Data.Schema.attributes/0`. A slot with none is absent. A picker tests a
  feed's schema against it before offering the feed (§7.2).

      iex> design = %{
      ...>   sources: %{s: %{fields: [:v], requires: %{v: [:label]}}},
      ...>   labels: [%{anchor: :title, text: [Visualize.Chart.fact(:s, :v, :unit)]}]
      ...> }
      iex> Visualize.Chart.contract(design)
      %{s: %{v: [:unit, :label]}}
  """
  @spec contract(t() | map()) :: %{atom() => %{atom() => [atom()]}}
  def contract(%__MODULE__{} = chart), do: chart |> to_map() |> Facts.contract()
  def contract(design) when is_map(design), do: Facts.contract(design)

  @doc """
  `:ok`, or every field a mark reads through a scale whose known type the scale's kind
  cannot take (spec/14 §7.4, D-153): `{:type_mismatch, slot, field, expected, given}` at
  the read's path, ordered by path.

  A read is a channel naming a scale, a style's `{:field, f}` color or an offset's field,
  over rows that are the slot's own. A time scale needs `:time`; band and ordinal need
  `:category`; every other kind needs `:number`. `types` maps a slot to what is known of
  its fields. A `Visualize.Data.Schema` says what they mean: `:text` satisfies a category,
  and `:time` is instants (D-154), which no numeric scale takes. A map from field to
  type, as `Visualize.Data.Table.column_types/1` reads it from rows, says how they are
  written: `:time` is instants there too, and a category takes anything. A
  slot it does not hold, and a field it does not type, are not checked. Pure and total
  over any map, so a tool calls it before `apply/2` to show a wrong binding without
  drawing.

      iex> design = %{
      ...>   sources: %{primary: %{fields: [:t, :v]}},
      ...>   frames: %{main: %{kind: :cartesian,
      ...>     scales: %{x: %{kind: :linear}, y: %{kind: :linear}}}},
      ...>   marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v}}]
      ...> }
      iex> Visualize.Chart.check_types(design, %{primary: %{t: :time, v: :number}})
      {:error, [{[:marks, 0, :channels, :x], {:type_mismatch, :primary, :t, :number, :time}}]}
      iex> schema = Visualize.Data.Schema.new!(%{t: %{type: :time}, v: %{type: :category}})
      iex> Visualize.Chart.check_types(design, %{primary: schema})
      {:error, [{[:marks, 0, :channels, :x], {:type_mismatch, :primary, :t, :number, :time}},
                {[:marks, 0, :channels, :y], {:type_mismatch, :primary, :v, :number, :category}}]}
      iex> Visualize.Chart.check_types(design, %{primary: %{t: :number, v: :number}})
      :ok
  """
  @spec check_types(t() | map(), %{atom() => field_types()}) ::
          :ok | {:error, [Validator.error(), ...]}
  def check_types(%__MODULE__{} = chart, types), do: chart |> to_map() |> check_types(types)

  def check_types(design, types) when is_map(design) and is_map(types) do
    case design |> Types.reads() |> Types.faults(types) |> Enum.sort_by(&elem(&1, 0)) do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  @doc """
  The type a source's `types` declares for a field (spec/14 §2.3, #369), or `nil` when
  the design, the source or the type is absent.

      iex> design = %{sources: %{s: %{fields: [:t, :v], types: %{t: :time}}}}
      iex> Visualize.Chart.column_type(design, :s, :t)
      :time
      iex> Visualize.Chart.column_type(design, :s, :v)
      nil
      iex> Visualize.Chart.column_type(design, :other, :t)
      nil
  """
  @spec column_type(t() | map(), atom(), atom()) :: atom() | nil
  def column_type(%__MODULE__{sources: sources}, source, field),
    do: column_type(%{sources: sources}, source, field)

  def column_type(design, source, field) when is_map(design) do
    case design do
      %{sources: %{^source => %{types: %{^field => type}}}} when is_atom(type) -> type
      _other -> nil
    end
  end

  # -- use sites and composites (spec/14 §19) --------------------------------------------

  @doc """
  A fragment with its variables substituted at a use site (spec/14 §19.4, D-102): a
  literal sets, another `var/1` renames. See `Visualize.Chart.Use.bind/2`.
  """
  @spec bind(term(), %{atom() => term()}) :: term()
  defdelegate bind(fragment, vars), to: Use

  @doc """
  A fragment with paths removed at a use site (spec/14 §19.5). See `Visualize.Chart.Use.mask/2`.
  """
  @spec mask(map(), [Use.path() | atom()] | :all) :: map()
  defdelegate mask(fragment, paths), to: Use

  @doc """
  One use site resolved through a fetch — `ref → local → mask → bind` (spec/14 §19.3).
  See `Visualize.Chart.Use.resolve/2`.
  """
  @spec resolve(Use.t(), (Fragment.id() -> {:ok, map()} | :error)) ::
          {:ok, map()} | {:missing, Fragment.id(), map()}
  defdelegate resolve(use, fetch), to: Use

  @doc """
  A composite resolved through a fetch and stacked: a flat design (spec/14 §19.6, D-103).
  A design that is not a composite flattens to itself. See `Visualize.Chart.Composite.flatten/2`.
  """
  @spec flatten(map(), (Fragment.id() -> {:ok, map()} | :error)) ::
          {:ok, map(), Composite.report()} | {:error, {:cycle, [Fragment.id()]}}
  defdelegate flatten(fragment, fetch), to: Composite

  @doc """
  The design applied to its data (spec/14 §7.3): variables resolved, slots bound, the
  frame realized.

  The design is a chart or a design map, which goes through `from_map/1` first. Three
  steps follow, each reporting every fault it finds by path and stopping before the
  next: every variable is replaced by the value `vars:` gives it, else by its declared
  default (`{:unresolved, :var, name}` where it stood; `{:undeclared, :var, name}` at
  `[:vars, name]` for a value no declaration carries); every slot binds to the pool's
  entry under its own name, else its default (`{:unbound, :source, name}` at
  `[:sources, name]`), and every field it declares must be a key of some row of the
  bound source (`{:missing_field, field}` there); then the result is validated and
  `Visualize.Chart.Frame.new/2` realizes its frame, inferring every `:auto` domain.

  ## Options

    * `:sources` - the pool: a map from name to anything `Visualize.Data.Table.rows/1`
      reads (default `%{}`)
    * `:vars` - a map from variable name to value (default `%{}`)
    * `:theme` - a `%Visualize.Theme{}`, as `Visualize.Chart.Frame.new/2` takes it
    * `:size` - the host's container as `{width, height}` (default `{600, 400}`, spec/14
      §4.2); a design records no size
    * `:now` - the instant a `:window` step measures its durations back from (spec/14
      §5.4.1); without it each such step takes the newest reading of its own column
    * `:system` - the unit system the axes show their measures in, `:metric`, `:us`,
      `:uk` or `:as_posted` (default): the viewer's preference, never the design's
      (spec/14 §4.4, D-156)
    * `:schemas` - a `Visualize.Data.Schema.Cache` of feeds' schemas by version
      (default empty), read for every slot whose contract is not empty (spec/14 §7.4)
    * `:describe` - `(feed -> {:ok, schema} | {:error, reason})`, asked once for a
      version the cache lacks (default `nil`)
    * `:generators` - the generator modules (`Visualize.Generators`, spec/14 §3.13) the
      design's names are checked against and its frames call, beside
      `config :visualize, generators:` (default `[]`)
    * `:assigns` - the host's assigns, the viewer's, which every generator's context
      carries (default `%{}`)

  Raises `ArgumentError` as `Visualize.Chart.Frame.new/2` does, for a value a scale
  cannot take or a theme name it cannot resolve.

  ## Examples

      iex> design = %{
      ...>   version: 2,
      ...>   sources: %{primary: %{fields: [:t, :v], default: :uptime}},
      ...>   vars: %{unit: %{default: "%"}},
      ...>   frames: %{main: %{kind: :cartesian, scales: %{x: %{kind: :linear}, y: %{kind: :linear}}}},
      ...>   marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v}}],
      ...>   labels: [%{anchor: {:axis, :y}, text: ["unit: ", Visualize.Chart.var(:unit)]}]
      ...> }
      iex> {:ok, applied} = Visualize.Chart.apply(design, sources: %{uptime: %{t: [1, 2], v: [3, 9]}})
      iex> applied.chart.labels
      [%{anchor: {:axis, :y}, text: "unit: %"}]
      iex> Visualize.Chart.Frame.scale(applied.frame, :y).domain
      [3, 9]
      iex> Visualize.Chart.apply(design, sources: %{primary: %{t: [1, 2]}}, vars: %{unit: "kg"})
      {:error, [{[:sources, :primary], {:missing_field, :v}}]}

  """
  @spec apply(t() | map(), keyword()) :: {:ok, Applied.t()} | {:error, [Validator.error(), ...]}
  def apply(design, opts \\ [])

  def apply(%__MODULE__{} = chart, opts) do
    pool = opts |> Keyword.get(:sources, %{}) |> Map.new()
    vars = opts |> Keyword.get(:vars, %{}) |> Map.new()

    cache = Keyword.get_lazy(opts, :schemas, &Cache.new/0)

    modules = Keyword.get(opts, :generators, [])

    with {:ok, resolved} <- Template.resolve(chart, vars),
         {:ok, sources} <- Template.bind(resolved, pool),
         {:ok, resolved, described} <- Facts.apply(resolved, pool, cache, opts[:describe]),
         :ok <- Validator.validate(to_map(resolved), :design, generators: modules) do
      # What a generator's context carries (spec/14 §3.13): the variables' values at
      # application — each given value, else its default — and the host's assigns.
      generated =
        Generated.new(modules, values(chart, vars), Keyword.get(opts, :assigns, %{}))

      chart = resolved

      shared =
        [sources: sources, schemas: described.schemas, generated: generated] ++
          Keyword.take(opts, [:theme, :now, :size, :system])

      frames = realize_frames(chart, shared)

      frame = frames |> Map.values() |> Enum.min_by(& &1.name)

      {:ok,
       struct!(
         %Applied{chart: chart, sources: sources, frame: frame, frames: frames},
         described
       )}
    end
  end

  def apply(map, opts) when is_map(map) do
    with {:ok, chart} <- from_map(map, Keyword.take(opts, [:generators])),
         do: __MODULE__.apply(chart, opts)
  end

  # Each variable's value at application: the one given, else its declared default.
  defp values(%__MODULE__{vars: declared}, given) do
    defaults =
      for {name, node} <- declared || %{}, is_map(node), into: %{} do
        {name, Map.get(node, :default)}
      end

    Map.merge(defaults, Map.take(given, Map.keys(defaults)))
  end

  # Every frame realized, and a scale adopted from another frame realized again over one
  # domain (spec/14 §4.3, #384). Two passes, because a shared domain is inferred over the
  # channels of every frame taking part and a frame is realized over its own marks: the
  # first pass gives each its own extent, and the second gives every frame of a group the
  # union of them through the `domains:` option, which skips the inference.
  defp realize_frames(%__MODULE__{} = chart, shared) do
    frames =
      Map.new(chart.frames, fn {name, _} -> {name, Frame.new(chart, [frame: name] ++ shared)} end)

    case Scales.adoptions(chart) do
      groups when map_size(groups) == 0 ->
        frames

      groups ->
        given = united(groups, frames)

        Map.new(frames, fn {name, frame} ->
          case Map.fetch(given, name) do
            {:ok, domains} -> {name, Frame.new(chart, [frame: name, domains: domains] ++ shared)}
            :error -> {name, frame}
          end
        end)
    end
  end

  # The domain of each adoption group, by the frame and the name each member reads it as.
  defp united(groups, frames) do
    for {_owner, members} <- groups,
        domains = for({f, s} <- members, scale = scale(frames, f, s), do: scale.domain),
        domains != [],
        united = Scales.unite(domains),
        {frame, name} <- members,
        reduce: %{} do
      acc -> Map.update(acc, frame, %{name => united}, &Map.put(&1, name, united))
    end
  end

  defp scale(frames, frame, name) do
    with %Frame{scales: scales} <- Map.get(frames, frame), do: Map.get(scales, name)
  end

  @doc """
  The fragments folded left to right through `compose/2` (spec/14 §8); `{:ok, %{}}` for
  an empty list.
  """
  @spec compose([t() | map()]) :: {:ok, map()} | {:error, [Validator.error(), ...]}
  def compose(fragments) when is_list(fragments) do
    Enum.reduce_while(fragments, {:ok, %{}}, fn fragment, {:ok, acc} ->
      case compose(acc, fragment) do
        {:ok, merged} -> {:cont, {:ok, merged}}
        {:error, errors} -> {:halt, {:error, errors}}
      end
    end)
  end

  @doc """
  The second fragment merged over the first by the merge rule of every key (spec/14 §8).

  A fragment is a design map — it need not carry `version` or `frame` — or a chart,
  taken as its map. Lists of nodes concatenate, name-keyed declarations unite (a name
  the two declare differently is `:conflict` at its path), scalars are the later's, and
  a node both give as a map merges key by key by its own rules. Nothing is validated:
  the result is a fragment too, and becomes a chart through `from_map/1` or `apply/2`.

  ## Examples

      iex> house = %{styles: %{series: %{stroke_width: 2}}, labels: [%{anchor: :caption, text: ["© house"]}]}
      iex> chart = %{version: 2, frames: %{main: %{kind: :cartesian}}, labels: [%{anchor: :title, text: ["Uptime"]}]}
      iex> {:ok, design} = Visualize.Chart.compose(house, chart)
      iex> Enum.map(design.labels, & &1.anchor)
      [:caption, :title]
      iex> Visualize.Chart.compose(house, %{styles: %{series: %{stroke_width: 3}}})
      {:error, [{[:styles, :series], :conflict}]}

  """
  @spec compose(t() | map(), t() | map()) :: {:ok, map()} | {:error, [Validator.error(), ...]}
  def compose(a, b), do: Compose.merge(fragment(a), fragment(b))

  @doc """
  The layers cascaded left to right, the later layer the higher (spec/14 §8.2).

  `stack([])` is `%{}` and `stack([a])` is `a` itself, taken as its map: the cascade
  cannot fail, so there is no tuple to unwrap.

  ## Examples

      iex> theme = %{version: 2, theme: :default, frames: %{main: %{kind: :cartesian}}}
      iex> house = %{theme: :dark, frames: %{main: %{margin: %{top: 800, bottom: 400}}}}
      iex> panel = %{frames: %{main: %{margin: %{top: 600, bottom: 300}}}}
      iex> design = Visualize.Chart.stack([theme, house, panel])
      iex> {design.theme, design.frames.main.kind, design.frames.main.margin}
      {:dark, :cartesian, %{top: 600, bottom: 300}}

  """
  @spec stack([layer()]) :: map()
  def stack(layers) when is_list(layers), do: Enum.reduce(layers, %{}, &stack(&2, &1))

  @doc """
  The higher fragment cascaded over the lower by the merge rule of every key (spec/14 §8.2).

  For every key the higher layer wins. Lists of nodes append, except that a higher element
  whose *identity* equals a lower element's replaces it in place — a mark's and a label's
  `id`, an axis's `{scale, side}` — which is what lets a layer restyle the shared frame's
  x-axis rather than draw a second one; a name-keyed declaration both layers carry is the
  higher layer's entry *whole*, where `compose/2` reports `:conflict`, since derivation
  within a style is `extends` (spec/14 §3.5) and never the cascade; and a node both layers
  give as a map cascades key by key, so a panel's frame adds its scales to a shared
  frame's and takes precedence on the frame's scalars. Nothing is validated or defaulted:
  the result is a fragment too, and a layer of another stack.

  `compose/2` is the other operation over fragments and is unchanged: it assembles parts
  that are meant to be disjoint and reports a name declared twice. Where two fragments
  are disjoint the two agree (spec/14 §8.3).

  ## Examples

      iex> house = %{theme: :dark, styles: %{series: %{stroke: :series_1, stroke_width: 2}}}
      iex> panel = %{styles: %{series: %{stroke_width: 3}}, labels: [%{anchor: :title, text: ["Uptime"]}]}
      iex> design = Visualize.Chart.stack(house, panel)
      iex> design.styles.series
      %{stroke_width: 3}
      iex> {design.theme, length(design.labels)}
      {:dark, 1}
      iex> Visualize.Chart.compose(house, panel)
      {:error, [{[:styles, :series], :conflict}]}

  """
  @spec stack(layer(), layer()) :: map()
  def stack(lower, higher), do: Stack.cascade(layer(lower), layer(higher))

  defp fragment(%__MODULE__{} = chart), do: to_map(chart)
  defp fragment(map) when is_map(map), do: map

  defp layer({_name, l}), do: fragment(l)
  defp layer(l), do: fragment(l)

  @doc """
  Where every value of a stack came from (spec/14 §17.1).

  Takes the *layers* — the same list `stack/1` takes, each a fragment, a chart or a
  `{name, layer}` pair — and returns one `t:provenance/0` per leaf path of `stack/1` of
  those layers, ordered by path: the value, the layer that set it, and the layers it
  overrode, lowest first. A layer without a name is reported by its zero-based position.

  A leaf is a value the cascade does not descend into: the walk descends through every
  node, every name-keyed declaration and every element of a collection, and stops at a
  scalar, a name, a text, an extent or a variable. The stack itself carries no tags — a
  tagged fragment would not validate and could not be a layer of another stack — so this
  recomputes the cascade of spec/14 §8.2, which is why the two cannot disagree.

  ## Examples

      iex> house = %{theme: :dark, frames: %{main: %{margin: %{top: 800, bottom: 400}}}}
      iex> panel = %{frames: %{main: %{margin: %{top: 600}}}}
      iex> Visualize.Chart.explain([{:house, house}, {:panel, panel}])
      [
        %{path: [:frames, :main, :margin, :bottom], value: 400, layer: :house, overrode: []},
        %{path: [:frames, :main, :margin, :top], value: 600, layer: :panel, overrode: [:house]},
        %{path: [:theme], value: :dark, layer: :house, overrode: []}
      ]

  """
  @spec explain([layer()]) :: [provenance()]
  def explain(layers) when is_list(layers) do
    layers |> Enum.with_index() |> Enum.map(&tag/1) |> Stack.explain()
  end

  @doc """
  Where each part of one element's style came from (spec/14 §17.3, D-172).

  `applied` is a `%Visualize.Chart.Applied{}`; `at:` the path of the node whose style is
  explained — `[:marks, i]`, `[:marks, i, :label]`, `[:labels, i]`,
  `[:frames, f, :axes, i]` or `[:frames, f, :legend]`; `datum:` the element's datum, which
  a `{:field, f}` entry reads; `state:` a view state laid at its layer (§3.7). The answer is
  `%{at, kind, state, parts, generators}`, `parts` each part's `value`, whether the kind
  draws it (`drawn`), and its `chain` of contributions, lowest first: each
  `%{layer, style, via, field, value, set, generators}`. A generator (§3.13) is called as
  the frame calls it, and `generators` lists each it called — `%{name, args, at, result,
  layer}`, `result` `{:fault, reason}` for one that applied nothing.

      iex> design = %{version: 3, sources: %{s: %{fields: [:x, :y, :k]}},
      ...>   styles: %{base: %{extends: :bad, stroke: %{width: 3}}},
      ...>   frames: %{main: %{kind: :cartesian, scales: %{x: %{kind: :linear}, y: %{kind: :linear}}}},
      ...>   marks: [%{type: :line, data: :s, channels: %{x: :x, y: :y}, style: [:base, %{opacity: 0.5}]}]}
      iex> {:ok, applied} = Visualize.Chart.apply(design, sources: %{s: [%{x: 0, y: 1, k: "a"}]})
      iex> %{parts: %{stroke: stroke, fill: fill}} = Visualize.Chart.explain(applied, at: [:marks, 0])
      iex> Enum.map(stroke.chain, &{&1.layer, &1.style, &1.via})
      [{:theme, nil, []}, {:style, :base, [:bad]}]
      iex> stroke.value.width
      3
      iex> fill.drawn
      false
  """
  @spec explain(Applied.t(), keyword()) :: map()
  def explain(%Applied{} = applied, opts) do
    at = Keyword.fetch!(opts, :at)
    state = Keyword.get(opts, :state)
    {stack, kind, frame, series, own} = explained(applied, at)
    stack = if state, do: Visualize.Chart.Style.with_state(stack, state), else: stack
    declared = Map.keys(applied.chart.styles || %{})

    {parts, generators} =
      Visualize.Chart.Style.Explain.parts(
        frame.styles,
        declared,
        stack,
        kind,
        Keyword.get(opts, :datum),
        series,
        containers(applied, frame, own),
        frame
      )

    %{at: at, kind: kind, state: state, parts: parts, generators: generators}
  end

  # The stack, the kind, the frame, the mark's own paint and the node's own defaults of the
  # node at a path.
  defp explained(applied, [:marks, i]) do
    mark = Enum.at(applied.chart.marks, i)
    frame = mark_frame(applied, mark)
    position = Enum.find_index(frame.marks, &(&1 == mark)) || 0
    {Map.get(mark, :style), mark.type, frame, {:series, position + 1}, Map.get(mark, :defaults)}
  end

  defp explained(applied, [:marks, i, :label]) do
    mark = Enum.at(applied.chart.marks, i)
    label = Map.get(mark, :label) || %{}
    stack = Map.get(label, :style, Schema.default(:mark_label, :style))
    {stack, :text, mark_frame(applied, mark), nil, Map.get(mark, :defaults)}
  end

  defp explained(applied, [:labels, i]) do
    label = Enum.at(applied.chart.labels, i)
    default = if label.anchor == :title, do: :title, else: Schema.default(:label, :style)
    frame = Map.get(applied.frames, Map.get(label, :frame)) || applied.frame
    {Map.get(label, :style, default), :text, frame, nil, Map.get(label, :defaults)}
  end

  defp explained(applied, [:frames, name, :axes, i]) do
    axis = applied.chart.frames |> Map.fetch!(name) |> Map.get(:axes, []) |> Enum.at(i)
    stack = Map.get(axis, :style, Schema.default(:axis, :style))
    {stack, :axis, applied.frames[name], nil, Map.get(axis, :defaults)}
  end

  defp explained(applied, [:frames, name, :legend]) do
    legend = applied.chart.frames |> Map.fetch!(name) |> Map.get(:legend) || %{}
    stack = Map.get(legend, :style, Schema.default(:legend, :style))
    {stack, :legend, applied.frames[name], nil, nil}
  end

  # The element's containers, farthest first (spec/14 §3.8): the theme's root — every part,
  # with the theme's own entries per kind — the design's, the frame's and its own.
  defp containers(applied, frame, own) do
    theme = frame.theme
    kinds = Visualize.Chart.Style.Defaults.kinds()
    root = theme.defaults |> Map.take(kinds) |> Map.merge(Visualize.Theme.defaults(theme))
    frame_node = Map.get(applied.chart.frames || %{}, frame.name) || %{}

    [
      {:theme, root},
      {:design, applied.chart.defaults},
      {{:frame, frame.name}, Map.get(frame_node, :defaults)},
      {:site, own}
    ]
  end

  defp mark_frame(applied, mark),
    do: Map.get(applied.frames, Map.get(mark, :frame)) || applied.frame

  defp tag({{name, layer}, _index}), do: {name, layer(layer)}
  defp tag({layer, index}), do: {index, layer(layer)}

  @doc """
  The variables a design still demands (spec/14 §17.2).

  Takes a fragment, a chart or the layers of a stack — the list `stack/1` takes, stacked
  first — and returns one `t:free_var/0` per variable still in the result, ordered by
  name: its `default` from the stacked `vars` node, `required` where no layer declares
  one, and one `uses` entry per path it stands at with the schema's expectation there
  (§1.4) and the layer that set the leaf it stands in. A fragment is a one-layer stack,
  so its uses are reported as layer `0`.

  The walk is `apply/2`'s own, so this lists exactly the variables application will
  demand: a variable resolution does not reach — inside an extent, inside a value another
  variable is bound to — is not listed, because it is not resolved either.

  ## Examples

      iex> house = %{vars: %{accent: %{default: :series_1}}, styles: %{s: %{stroke: Visualize.Chart.var(:accent)}}}
      iex> panel = %{labels: [%{anchor: :title, text: ["Uptime in ", Visualize.Chart.var(:unit)]}]}
      iex> Visualize.Chart.free_vars([{:house, house}, {:panel, panel}])
      [
        %{
          name: :accent,
          default: :series_1,
          required: false,
          uses: [%{path: [:styles, :s, :stroke], expects: :color, layer: :house}]
        },
        %{
          name: :unit,
          default: nil,
          required: true,
          uses: [%{path: [:labels, 0, :text], expects: :text, layer: :panel}]
        }
      ]

  """
  @spec free_vars(t() | map() | [layer()]) :: [free_var()]
  def free_vars(layers) when is_list(layers) do
    layers |> Enum.with_index() |> Enum.map(&tag/1) |> Stack.free_vars()
  end

  def free_vars(design) when is_map(design), do: free_vars([design])

  @doc """
  The design compiled for rendering per tick (spec/14 §12): the split into static and
  dynamic regions computed from the design, a render target per mark chosen from the
  bound data, and a `Visualize.Chart.Compiled` per frame that draws only what moves.

  The result is **one compiled chart per frame**, by name (§12.1, #385) — a design of one
  frame is a map of one, so a caller has one shape to read whatever the design holds.
  Each is compiled over its own realized frame and the marks and labels that say it.

  An applied chart is compiled as it is; a chart or a design map is applied first with
  the `sources:`, `vars:`, `theme:`, `size:`, `now:`, `system:`, `generators:` and `assigns:` options of `apply/2`, and its errors are this
  function's. The compiler's own options are `:ceiling`, the point count above which
  `render: :auto` leaves SVG for the canvas (default `1000`, spec/00 §3.2), and `:motion`,
  `:full` (default) or `:reduce`: a reader who asks for less motion gets every transition
  and mark motion as a step to its target (spec/14 §21.6, D-142).

  ## Examples

      iex> design = %{
      ...>   version: 2,
      ...>   sources: %{primary: %{fields: [:t, :v]}},
      ...>   frames: %{main: %{kind: :cartesian, scales: %{x: %{kind: :linear, domain: [0, 10]}, y: %{kind: :linear, domain: [0, 10]}}}},
      ...>   marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v}}]
      ...> }
      iex> {:ok, %{main: compiled}} = Visualize.Chart.compile(design, sources: %{primary: %{t: [1, 2], v: [3, 9]}}, ceiling: 1)
      iex> Visualize.Chart.Compiled.dynamic_regions(compiled)
      [{{:mark, 0}, :data}]
      iex> Visualize.Chart.Compiled.targets(compiled)
      [{:binary, 2}]

  """
  @spec compile(Applied.t() | t() | map(), keyword()) ::
          {:ok, %{atom() => Compiled.t()}} | {:error, [Validator.error(), ...]}
  def compile(design, opts \\ [])

  def compile(%Applied{frames: frames} = applied, opts) do
    {:ok, Map.new(frames, fn {name, _frame} -> {name, Compiled.new(applied, name, opts)} end)}
  end

  def compile(design, opts) do
    with {:ok, applied} <-
           __MODULE__.apply(
             design,
             Keyword.take(opts, [
               :sources,
               :vars,
               :theme,
               :size,
               :now,
               :system,
               :schemas,
               :describe,
               :generators,
               :assigns
             ])
           ) do
      compile(applied, opts)
    end
  end

  @doc "As `generate/2` with `[]` options."
  @spec generate(Applied.t()) :: Element.t()
  def generate(%Applied{} = applied), do: generate(applied, [])

  @doc """
  The applied chart as a `Visualize.IR.Element` (spec/14 §4.7): the frame's group over
  the bound sources — `resolve:` and `paths:` as `Visualize.Chart.Frame.generate/2` takes
  them — or, with `root: true`, that group inside the accessible root of
  `Visualize.IR.Element.root/3` at the frame's size (#131).

  ## Options

    * `:root` - wrap the group in a root `<svg>` (default `false`)
    * `:title` - the root's accessible name; default the design's `meta.name`, else the
      chart's kind (`Visualize.Chart.Summary`, spec/14 §21.2), so every chart is named
    * `:description` - the root's own description; default the design's
      `meta.description`, an absent or empty one saying nothing
    * `:summary` - the generated text alternative written after the description
      (spec/14 §21.1): `true` (default) for `Visualize.Chart.Summary.text/1`, a string
      for the caller's own, `false` for none
    * `:responsive` - the root's, as `Visualize.IR.Element.root/3` takes it
    * `:color_scheme` - `false` to leave out the root's automatic dark mode: in `:css`
      output, under the implicit default theme, the root carries a `<style>` that switches
      to the theme's dark counterpart when the viewer prefers it (spec/08 §7.3, #668)
  """
  @spec generate(Applied.t(), keyword()) :: Element.t()
  def generate(
        %Applied{chart: chart, frame: frame, frames: frames, sources: sources} = applied,
        opts
      ) do
    group = frames_group(realized(frames, frame), sources, opts)

    if Keyword.get(opts, :root, false) do
      meta = chart.meta || %{}
      summary = summary(applied, Keyword.get(opts, :summary, true))

      description =
        Keyword.get_lazy(opts, :description, fn -> meta_text(Map.get(meta, :description)) end)

      title = Keyword.get_lazy(opts, :title, fn -> title(meta, summary, applied) end)
      description = described(description, summary)

      Element.root(frame.size.width, frame.size.height,
        title: title,
        description: description,
        responsive: Keyword.get(opts, :responsive, false),
        children:
          scheme(applied, Element.label_ids(nil, title, description).root, opts) ++ [group]
      )
    else
      group
    end
  end

  # The root's automatic dark mode (spec/08 §7.3, spec/14 §4.7, #668): in `:css` output, the
  # rule that switches to the theme's counterpart, scoped to the root, while the theme is
  # the implicit default — the design's `:default` and no theme of the host's own.
  defp scheme(%Applied{chart: chart, frame: frame}, id, opts) do
    auto? =
      Keyword.get(opts, :resolve, :css) == :css and Keyword.get(opts, :color_scheme, true) and
        chart.theme == :default and frame.theme == Visualize.Theme.default() and id != nil

    case auto? && Visualize.Theme.color_scheme(frame.theme, "#" <> id) do
      css when is_binary(css) -> [Element.stylesheet(css)]
      _none -> []
    end
  end

  # The generated text alternative a root describes itself with (spec/14 §21.1).
  defp summary(applied, true), do: Summary.new(applied)
  defp summary(_applied, text) when is_binary(text), do: text
  defp summary(_applied, false), do: nil

  # The root's name: the design's, else the chart's kind (spec/14 §21.2).
  defp title(meta, summary, applied) do
    case meta_text(Map.get(meta, :name)) do
      nil -> (match?(%Summary{}, summary) && summary.name) || Summary.new(applied).name
      name -> name
    end
  end

  # The design's description, then the summary, as one text.
  defp described(description, nil), do: description

  defp described(description, %Summary{} = summary),
    do: described(description, Summary.text(summary))

  defp described(nil, text), do: text
  defp described(description, text), do: description <> sentence_end(description) <> text

  defp sentence_end(text), do: if(String.ends_with?(text, [".", "!", "?"]), do: " ", else: ". ")

  # An `%Applied{}` assembled by hand — one frame realized through `Visualize.Chart.Frame.new/2`
  # and no `frames` — draws that frame alone, so a caller that has one frame need not name it.
  defp realized(frames, frame) when frames == %{} or is_nil(frames), do: %{frame.name => frame}
  defp realized(frames, _frame), do: frames

  # Every frame drawn at its own pixel box, in `z` order with ties broken by name
  # (spec/14 §4.7, #383): one group per frame, the design's own group when there is only
  # one so a single-frame design renders exactly what it always did.
  defp frames_group(frames, sources, opts) do
    draw = Keyword.take(opts, [:resolve, :paths]) ++ [sources: sources]

    case Map.values(frames) do
      [only] ->
        Frame.generate(only, draw)

      many ->
        many
        |> Enum.sort_by(&{&1.z, &1.name})
        |> Enum.map(&frame_group(&1, draw))
        |> Element.group()
    end
  end

  # One group per frame, at the frame's own pixel box: `Visualize.Chart.Frame.generate/2`
  # already returns a `class="frame"` group translated by the margins, so its children are
  # taken and the two translations composed — a frame is one group, not two nested ones
  # that share a class.
  defp frame_group(%Frame{} = frame, draw) do
    [x, y, _w, _h] = frame.box
    {width, height} = {frame.size.width, frame.size.height}
    %Element{children: children} = Frame.generate(frame, draw)
    margin = frame.margin

    Element.group(children,
      style: %{class: "frame frame-#{frame.name}"},
      attrs:
        frame
        |> Frame.sync_attrs()
        |> Map.merge(Frame.brush_attrs(frame))
        |> Map.put("data-node", "frames.#{frame.name}"),
      transform: Transform.translate(x * width + margin.left, y * height + margin.top)
    )
  end

  # A meta text as the root's string, `nil` when absent or empty; an applied chart has no
  # hole left in it, so a variable here is the unresolved-variable fault.
  defp meta_text(nil), do: nil

  defp meta_text(text) do
    case Text.parse!(text) do
      [] ->
        nil

      parts ->
        Enum.map_join(parts, "", fn
          string when is_binary(string) -> string
          %Var{name: name} -> Visualize.Chart.Style.unresolved!(name)
        end)
    end
  end

  @doc "As `render/2` with `[]` options."
  @spec render(Applied.t()) :: String.t()
  def render(%Applied{} = applied), do: render(applied, [])

  @doc """
  The applied chart drawn: `generate/2` serialized through `Visualize.Render.to_string/2`
  — `backend:` and `resolve:` (default `Visualize.Theme.mode/1` of the backend), and
  `paths:`, `root:`, `title:`, `description:` and `responsive:` as `generate/2` takes them.
  """
  @spec render(Applied.t(), keyword()) :: String.t()
  def render(%Applied{} = applied, opts) do
    {mode, opts} =
      Keyword.pop_lazy(opts, :resolve, fn -> Visualize.Theme.mode(opts[:backend]) end)

    {ours, rest} =
      Keyword.split(opts, [
        :paths,
        :root,
        :title,
        :description,
        :summary,
        :responsive,
        :color_scheme
      ])

    applied
    |> generate([resolve: mode] ++ ours)
    |> Visualize.Render.to_string(rest)
  end
end
