defmodule Visualize.Chart.Theme do
  @moduledoc """
  A theme as a document: stored, shipped and read back as a value (spec/14 §9.3, D-139).

  A theme document is the inline `:theme` node of a design (§2.5) — every field of
  `Visualize.Theme`, its `ramps`, `roles` and style palette `styles` whole — stamped with
  the schema version. It
  has no schema of its own: the theme node is a node of the design schema, so it is
  versioned by `Visualize.Chart.Migration.current/0` and read under the one policy every
  document of this library keeps (§9.1, D-137).

    * the map form is `%{version: v, theme: node}` (`to_map/1`); the builder's store keeps
      the fragment `%{theme: node}` (`fragment/1`), a library entry of kind `:theme`, which
      reads as the same document at the current version
    * the JSON form is the stamped fragment document `{"$version": v, "theme": {…}}`
      (`to_json/1`), as `Visualize.Chart.Fragment.to_json/1` writes it

  Reading one back runs, in order: the version gate, the `depth` and `items` limits
  (`limits:`, §9.2), the migration of §9, per-kind validity — which reports a ramp, role or
  palette entry that breaks its contract (spec/08 §7.5, §7.7) — and then builds the theme.
  Every fault
  is `{path, reason}` in the validator's shape, so `Visualize.Chart.Validator.format/1`
  words all of them.

  ## Examples

      iex> theme = Visualize.Theme.new(name: :house, axis: "#555555")
      iex> Visualize.Chart.Theme.from_map(Visualize.Chart.Theme.to_map(theme))
      {:ok, theme}

      iex> Visualize.Chart.Theme.from_map(%{theme: :dark})
      {:ok, Visualize.Theme.dark()}

      iex> Visualize.Chart.Theme.from_map(%{version: 4, theme: %{}})
      {:error, [{[:version], {:newer_schema, 4, 3}}]}

  """

  import Kernel, except: [node: 1]

  alias Visualize.Chart.{Fragment, Limits, Migration, Validator, Var}
  alias Visualize.Theme

  @fields [
    :name,
    :series,
    :axis,
    :grid,
    :text,
    :background,
    :surface,
    :ramps,
    :roles,
    :styles,
    :font_family,
    :font_size,
    :label_size,
    :title_size
  ]

  @doc """
  The theme as the `:theme` node of spec/14 §2.5: every field, `ramps`, `roles` and `styles`
  whole.
  """
  @spec node(Theme.t()) :: map()
  def node(%Theme{} = theme), do: Map.take(theme, @fields)

  @doc "`%{theme: node}`: what the builder's store keeps, a fragment of kind `:theme` (§19.8)."
  @spec fragment(Theme.t()) :: %{theme: map()}
  def fragment(%Theme{} = theme), do: %{theme: node(theme)}

  @doc "The theme's map document, `%{version: current, theme: node}` (spec/14 §9.3)."
  @spec to_map(Theme.t()) :: %{version: pos_integer(), theme: map()}
  def to_map(%Theme{} = theme), do: %{version: Migration.current(), theme: node(theme)}

  @doc """
  The theme a map document or a theme fragment holds, or every fault found (spec/14 §9.3).

  The version gate first — a newer document is refused before anything of it is read —
  then the `depth` and `items` limits over the document as given, the migration, per-kind
  validity with the contracts, and the theme: a node that is a name is the built-in theme
  of that name, any other name is `{[:theme], {:unknown_theme, name}}`, and a variable
  anywhere is `{path, {:unresolved, :var, name}}`, since nothing applies a theme document.

  ## Options

    * `:limits` - the sanity limits of §9.2, as `Visualize.Chart.Limits.new/1` takes them
  """
  @spec from_map(term(), keyword()) :: {:ok, Theme.t()} | {:error, [Validator.error(), ...]}
  def from_map(document, opts \\ [])

  def from_map(%{theme: _} = document, opts) when not is_struct(document) do
    version = Map.get(document, :version, Migration.current())
    limits = opts |> Keyword.get(:limits, []) |> Limits.new()

    with :ok <- readable(version),
         :ok <- within(document, limits),
         {:ok, migrated} <- Migration.migrate(Map.put(document, :version, version)),
         fragment = Map.delete(migrated, :version),
         :ok <- only_theme(fragment),
         :ok <- Validator.validate(fragment, :theme),
         :ok <- no_variables(fragment.theme, [:theme]) do
      build(fragment.theme)
    end
  end

  def from_map(_other, _opts), do: {:error, [{[], {:type, {:node, :theme}}}]}

  @doc """
  The theme's JSON document: `{:ok, json}`, stamped `"$version"` as every fragment document
  is (spec/14 §9.3, §19.7), or `{:error, {:missing_dependency, :jason}}` without Jason.
  """
  @spec to_json(Theme.t()) :: {:ok, String.t()} | {:error, {:missing_dependency, :jason}}
  def to_json(%Theme{} = theme), do: Fragment.to_json(fragment(theme))

  @doc """
  The theme a JSON document holds, read as `from_map/2` reads a map; the version gate and
  the limits run on the parsed document before a key of it is decoded, so no atom is made
  from a document this library cannot read. A JSON fault and a missing Jason are errors in
  the same `{path, reason}` shape.

      iex> {:ok, json} = Visualize.Chart.Theme.to_json(Visualize.Theme.dark())
      iex> Visualize.Chart.Theme.from_json(json)
      {:ok, Visualize.Theme.dark()}
  """
  @spec from_json(String.t(), keyword()) ::
          {:ok, Theme.t()} | {:error, [Validator.error(), ...]}
  def from_json(json, opts \\ []) when is_binary(json) do
    case Fragment.read_json(json, opts) do
      {:ok, fragment, version} -> from_map(Map.put(fragment, :version, version), opts)
      {:error, {:newer_schema, _, _} = reason} -> {:error, [{[:version], reason}]}
      {:error, {:limits, errors}} -> {:error, errors}
      {:error, reason} -> {:error, [{[], reason}]}
    end
  end

  # -- reading ------------------------------------------------------------------------

  defp readable(version) do
    case Migration.readable(version) do
      :ok -> :ok
      {:error, reason} -> {:error, [{[:version], reason}]}
    end
  end

  defp within(document, limits) do
    case Limits.structure(document, limits) do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  defp only_theme(fragment) do
    case fragment |> Map.keys() |> Enum.reject(&(&1 == :theme)) |> Enum.sort() do
      [] -> :ok
      others -> {:error, Enum.map(others, &{[&1], :unknown_key})}
    end
  end

  defp no_variables(%Var{name: name}, path), do: {:error, [{path, {:unresolved, :var, name}}]}

  defp no_variables(map, path) when is_map(map) and not is_struct(map) do
    map |> Enum.sort() |> faults(fn {key, value} -> no_variables(value, path ++ [key]) end)
  end

  defp no_variables(list, path) when is_list(list) do
    list
    |> Enum.with_index()
    |> faults(fn {value, i} -> no_variables(value, path ++ [i]) end)
  end

  defp no_variables(_leaf, _path), do: :ok

  # The faults of every element, in order, so a document with two variables names both.
  defp faults(enumerable, fun) do
    enumerable
    |> Enum.flat_map(fn element ->
      case fun.(element) do
        :ok -> []
        {:error, errors} -> errors
      end
    end)
    |> case do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  defp build(name) when is_atom(name) do
    case Theme.builtin(name) do
      nil -> {:error, [{[:theme], {:unknown_theme, name}}]}
      theme -> {:ok, theme}
    end
  end

  # Validity held, so the contracts hold and `new/1` builds; a document names only what it
  # changes and the rest is the default theme's (§2.5).
  defp build(node) when is_map(node), do: {:ok, Theme.new(node)}
end
