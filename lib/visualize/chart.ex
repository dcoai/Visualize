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
  realises the frame into a `Visualize.Chart.Applied` that `render/2` draws (spec/14 §7.3);
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
    Fragment,
    Frame,
    Migration,
    Schema,
    Stack,
    Template,
    Text,
    Use,
    Validator,
    Var
  }

  alias Visualize.IR.{Element, Transform}

  @design_keys [
    :version,
    :meta,
    :sources,
    :vars,
    :theme,
    :styles,
    :defs,
    :frames,
    :marks,
    :labels
  ]

  defstruct version: 2,
            meta: %{},
            sources: %{},
            vars: %{},
            theme: :default,
            styles: %{},
            defs: %{},
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

  @doc """
  The chart of a design map, or every fault in it.

  The map is migrated to the current version (spec/14 §9) and validated (§10) first;
  design-level keys absent from the map take the defaults of spec/14 §2.1.
  """
  @spec from_map(term()) :: {:ok, t()} | {:error, [Validator.error(), ...]}
  def from_map(map) do
    with {:ok, map} <- Migration.migrate(map),
         :ok <- Validator.validate(map) do
      {:ok, struct(__MODULE__, Map.take(map, @design_keys))}
    end
  end

  @doc "As `from_map/1`, raising `ArgumentError` with the formatted errors."
  @spec from_map!(term()) :: t()
  def from_map!(map) do
    case from_map(map) do
      {:ok, chart} ->
        chart

      {:error, errors} ->
        raise ArgumentError,
              "invalid design:\n" <> Enum.map_join(errors, "\n", &("  " <> Validator.format(&1)))
    end
  end

  @doc "The design map of a chart: every design-level key, nested nodes as stored."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = chart), do: Map.from_struct(chart)

  @doc """
  The chart of a JSON document (spec/14 §11).

  A document that does not parse is `{:error, [{[], {:json, message}}]}`; without
  `Jason` the result is `{:error, {:missing_dependency, :jason}}`.
  """
  @spec from_json(String.t()) ::
          {:ok, t()} | {:error, [Validator.error(), ...] | {:missing_dependency, :jason}}
  def from_json(json) when is_binary(json) do
    if Code.ensure_loaded?(Jason) do
      case Jason.decode(json) do
        {:ok, term} -> from_map(Codec.decode(term))
        {:error, error} -> {:error, [{[], {:json, Exception.message(error)}}]}
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
  frame realised.

  The design is a chart or a design map, which goes through `from_map/1` first. Three
  steps follow, each reporting every fault it finds by path and stopping before the
  next: every variable is replaced by the value `vars:` gives it, else by its declared
  default (`{:unresolved, :var, name}` where it stood; `{:undeclared, :var, name}` at
  `[:vars, name]` for a value no declaration carries); every slot binds to the pool's
  entry under its own name, else its default (`{:unbound, :source, name}` at
  `[:sources, name]`), and every field it declares must be a key of some row of the
  bound source (`{:missing_field, field}` there); then the result is validated and
  `Visualize.Chart.Frame.new/2` realises its frame, inferring every `:auto` domain.

  ## Options

    * `:sources` - the pool: a map from name to anything `Visualize.Data.Table.rows/1`
      reads (default `%{}`)
    * `:vars` - a map from variable name to value (default `%{}`)
    * `:theme` - a `%Visualize.Theme{}`, as `Visualize.Chart.Frame.new/2` takes it
    * `:size` - the host's container as `{width, height}` (default `{600, 400}`, spec/14
      §4.2); a design records no size
    * `:now` - the instant a `:window` step measures its durations back from (spec/14
      §5.4.1); without it each such step takes the newest reading of its own column

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

    with {:ok, chart} <- Template.resolve(chart, vars),
         {:ok, sources} <- Template.bind(chart, pool),
         :ok <- Validator.validate(to_map(chart)) do
      shared = [sources: sources] ++ Keyword.take(opts, [:theme, :now, :size])

      frames =
        Map.new(chart.frames, fn {name, _} ->
          {name, Frame.new(chart, [frame: name] ++ shared)}
        end)

      frame = frames |> Map.values() |> Enum.min_by(& &1.name)
      {:ok, %Applied{chart: chart, sources: sources, frame: frame, frames: frames}}
    end
  end

  def apply(map, opts) when is_map(map) do
    with {:ok, chart} <- from_map(map), do: __MODULE__.apply(chart, opts)
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
          uses: [%{path: [:styles, :s, :stroke], expects: :colour, layer: :house}]
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
  Each is compiled over its own realised frame and the marks and labels that say it.

  An applied chart is compiled as it is; a chart or a design map is applied first with
  the `sources:`, `vars:` and `theme:` options of `apply/2`, and its errors are this
  function's. The one option of the compiler's own is `:ceiling`, the point count above
  which `render: :auto` leaves SVG for the canvas (default `1000`, spec/00 §3.2).

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
           __MODULE__.apply(design, Keyword.take(opts, [:sources, :vars, :theme, :size, :now])) do
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
    * `:title` and `:description` - the root's; default the design's `meta.name` and
      `meta.description`, an absent or empty one leaving its element out
    * `:responsive` - the root's, as `Visualize.IR.Element.root/3` takes it
  """
  @spec generate(Applied.t(), keyword()) :: Element.t()
  def generate(%Applied{chart: chart, frame: frame, frames: frames, sources: sources}, opts) do
    group = frames_group(realised(frames, frame), sources, opts)

    if Keyword.get(opts, :root, false) do
      meta = chart.meta || %{}

      Element.root(frame.size.width, frame.size.height,
        title: Keyword.get_lazy(opts, :title, fn -> meta_text(Map.get(meta, :name)) end),
        description:
          Keyword.get_lazy(opts, :description, fn -> meta_text(Map.get(meta, :description)) end),
        responsive: Keyword.get(opts, :responsive, false),
        children: [group]
      )
    else
      group
    end
  end

  # An `%Applied{}` assembled by hand — one frame realised through `Visualize.Chart.Frame.new/2`
  # and no `frames` — draws that frame alone, so a caller that has one frame need not name it.
  defp realised(frames, frame) when frames == %{} or is_nil(frames), do: %{frame.name => frame}
  defp realised(frames, _frame), do: frames

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
      attrs: %{"data-node" => "frames.#{frame.name}"},
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
  The applied chart drawn: `generate/2` serialised through `Visualize.Render.to_string/2`
  — `backend:` and `resolve:` (default `Visualize.Theme.mode/1` of the backend), and
  `paths:`, `root:`, `title:`, `description:` and `responsive:` as `generate/2` takes them.
  """
  @spec render(Applied.t(), keyword()) :: String.t()
  def render(%Applied{} = applied, opts) do
    {mode, opts} =
      Keyword.pop_lazy(opts, :resolve, fn -> Visualize.Theme.mode(opts[:backend]) end)

    {ours, rest} = Keyword.split(opts, [:paths, :root, :title, :description, :responsive])

    applied
    |> generate([resolve: mode] ++ ours)
    |> Visualize.Render.to_string(rest)
  end
end
