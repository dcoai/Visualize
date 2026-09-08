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
  `compose/2` merges fragments by the schema's merge rules (§8).

  ## Examples

      iex> {:ok, chart} =
      ...>   Visualize.Chart.from_map(%{
      ...>     version: 1,
      ...>     sources: %{primary: %{fields: [:t, :v]}},
      ...>     frame: %{kind: :cartesian, scales: %{x: %{kind: :time}, y: %{kind: :linear}}},
      ...>     marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v}}]
      ...>   })
      iex> chart.marks
      [%{type: :line, data: :primary, channels: %{x: :t, y: :v}}]
      iex> Visualize.Chart.from_map(%{version: 1, frame: %{kind: :cartesian}, marks: [%{}]})
      {:error, [{[:marks, 0, :data], :required}, {[:marks, 0, :type], :required}]}

  """

  # Jason is optional (spec/14 §11.1, D-50): the calls stay direct and a missing Jason is
  # reported as a value by the two JSON functions, never as a compile warning.
  @compile {:no_warn_undefined, Jason}

  # `apply/2` is a function of this module (spec/14 §7.3), never the kernel's.
  import Kernel, except: [apply: 2]

  alias Visualize.Chart.{Applied, Codec, Compose, Frame, Migration, Template, Validator, Var}

  @design_keys [:version, :meta, :sources, :vars, :theme, :styles, :frame, :marks, :labels]

  defstruct version: 1,
            meta: %{},
            sources: %{},
            vars: %{},
            theme: :default,
            styles: %{},
            frame: nil,
            marks: [],
            labels: []

  @type t :: %__MODULE__{
          version: pos_integer(),
          meta: map(),
          sources: %{atom() => map()},
          vars: %{atom() => map()},
          theme: atom() | map(),
          styles: %{atom() => map()},
          frame: map() | nil,
          marks: [map()],
          labels: [map()]
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

  Raises `ArgumentError` as `Visualize.Chart.Frame.new/2` does, for a value a scale
  cannot take or a theme name it cannot resolve.

  ## Examples

      iex> design = %{
      ...>   version: 1,
      ...>   sources: %{primary: %{fields: [:t, :v], default: :uptime}},
      ...>   vars: %{unit: %{default: "%"}},
      ...>   frame: %{kind: :cartesian, scales: %{x: %{kind: :linear}, y: %{kind: :linear}}},
      ...>   marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v}}],
      ...>   labels: [%{anchor: {:axis, :y}, text: ["unit: ", Visualize.Chart.var(:unit)]}]
      ...> }
      iex> {:ok, applied} = Visualize.Chart.apply(design, sources: %{uptime: %{t: [1, 2], v: [3, 9]}})
      iex> applied.chart.labels
      [%{anchor: {:axis, :y}, text: ["unit: ", "%"]}]
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
      frame = Frame.new(chart, [sources: sources] ++ Keyword.take(opts, [:theme]))
      {:ok, %Applied{chart: chart, sources: sources, frame: frame}}
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
      iex> chart = %{version: 1, frame: %{kind: :cartesian}, labels: [%{anchor: :title, text: ["Uptime"]}]}
      iex> {:ok, design} = Visualize.Chart.compose(house, chart)
      iex> Enum.map(design.labels, & &1.anchor)
      [:caption, :title]
      iex> Visualize.Chart.compose(house, %{styles: %{series: %{stroke_width: 3}}})
      {:error, [{[:styles, :series], :conflict}]}

  """
  @spec compose(t() | map(), t() | map()) :: {:ok, map()} | {:error, [Validator.error(), ...]}
  def compose(a, b), do: Compose.merge(fragment(a), fragment(b))

  defp fragment(%__MODULE__{} = chart), do: to_map(chart)
  defp fragment(map) when is_map(map), do: map

  @doc "As `render/2` with `[]` options."
  @spec render(Applied.t()) :: String.t()
  def render(%Applied{} = applied), do: render(applied, [])

  @doc """
  The applied chart drawn: `Visualize.Chart.Frame.render/2` of its frame over its bound
  sources, `backend:` and `resolve:` as that function takes them.
  """
  @spec render(Applied.t(), keyword()) :: String.t()
  def render(%Applied{frame: frame, sources: sources}, opts) do
    Frame.render(frame, Keyword.put(opts, :sources, sources))
  end
end
