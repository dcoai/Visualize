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

  alias Visualize.Chart.{Codec, Migration, Validator, Var}

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
end
