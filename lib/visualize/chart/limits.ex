defmodule Visualize.Chart.Limits do
  @moduledoc """
  Sanity limits on a document read from elsewhere (spec/14 §9.2, D-137).

  Every reader — `Visualize.Chart.from_map/2`, `from_json/2` and
  `Visualize.Chart.Fragment.from_json/2` — applies these, the defaults when no `limits:` is
  given. They bound what reading and rendering a document can be made to cost; they are
  sanity limits, not a render budget.

  | Limit | Default | Bounds |
  |---|---|---|
  | `depth` | `64` | how deeply maps and lists nest, a use site's `local` and `vars` included |
  | `items` | `100_000` | the entries one list or map holds — a design holds no rows of its own, so this bounds every list a row could be held inline in |
  | `ticks` | `1_000` | an axis's tick count |
  | `iterations` | `10_000` | a `:force` step's `ticks` |
  | `counts` | `1_000_000` | bins, samples, `n`, `width`, and a grid's `size` |

  **The defaults are the system's sanity values, and the host holds the number.** A host
  loading untrusted input knows its inputs and tightens the limits at its layer:
  `Visualize.Chart.from_json(json, limits: [items: 5_000, depth: 24])`; a limit it does not
  name keeps its default.

  A fault is `{path, {:limit, name, max, given}}`, the validator's shape (spec/14 §10.1),
  so `Visualize.Chart.Validator.format/1` words it:

      iex> Visualize.Chart.Limits.check(%{version: 2, frames: %{main: %{axes: [%{scale: :x, ticks: 5000}]}}})
      {:error, [{[:frames, :main, :axes, 0, :ticks], {:limit, :ticks, 1000, 5000}}]}

      iex> Visualize.Chart.Validator.format({[:frames, :main, :axes, 0, :ticks], {:limit, :ticks, 1000, 5000}})
      "frames.main.axes[0].ticks: asks for 5000 ticks; the limit ticks is 1000"
  """

  alias Visualize.Chart.{Schema, Use, Validator}

  @defaults %{depth: 64, items: 100_000, ticks: 1_000, iterations: 10_000, counts: 1_000_000}

  @typedoc "A limit's name."
  @type name :: :depth | :items | :ticks | :iterations | :counts

  @typedoc "The limits a reader applies, one positive integer per name."
  @type t :: %{name() => pos_integer()}

  @doc "The system's sanity values (spec/14 §9.2)."
  @spec defaults() :: t()
  def defaults, do: @defaults

  @doc """
  The limits a reader applies: `given` merged over `defaults/0`.

  Raises `ArgumentError` for a name that is not a limit or a value that is not a positive
  integer.

      iex> Visualize.Chart.Limits.new(items: 10).items
      10
  """
  @spec new(keyword() | map() | t()) :: t()
  def new(given) when is_list(given) or is_map(given) do
    Enum.reduce(given, @defaults, fn
      {name, max}, acc when is_map_key(@defaults, name) and is_integer(max) and max > 0 ->
        Map.put(acc, name, max)

      {name, max}, _acc when is_map_key(@defaults, name) ->
        raise ArgumentError, "limit #{name} must be a positive integer, got: #{inspect(max)}"

      {name, _max}, _acc ->
        raise ArgumentError,
              "not a limit: #{inspect(name)}; the limits are #{inspect(Map.keys(@defaults))}"
    end)
  end

  @doc """
  `:ok`, or every `depth`, `items`, `ticks`, `iterations` and `counts` fault of a design
  map at the current version, `structure/2`'s first; `limits` as `new/1` takes them.
  """
  @spec check(term(), keyword() | map()) :: :ok | {:error, [Validator.error(), ...]}
  def check(design, limits \\ []) do
    limits = new(limits)

    case structure(design, limits) ++ counts(design, limits) do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  # -- structure: depth and items, over any term ----------------------------------------

  @doc """
  Every `depth` and `items` fault of any term — a design, a fragment, a parsed JSON
  document with string keys — ordered by path.

  The document itself is depth 1. A struct is a leaf, but a `%Visualize.Chart.Use{}`,
  whose `local` and `vars` hold fragments. Past the depth limit a branch is reported once,
  at the first map or list beyond it, and not walked further.
  """
  @spec structure(term(), t()) :: [Validator.error()]
  def structure(term, limits) do
    term |> walk([], 1, limits) |> Enum.sort_by(&elem(&1, 0))
  end

  defp walk(%Use{} = use, path, depth, limits) do
    walk(%{local: use.local, vars: use.vars}, path, depth, limits)
  end

  defp walk(%_{}, _path, _depth, _limits), do: []

  defp walk(term, path, depth, %{depth: max})
       when (is_map(term) or is_list(term)) and depth > max,
       do: [{path, {:limit, :depth, max, depth}}]

  defp walk(term, path, depth, limits) when is_map(term) do
    here = items(map_size(term), path, limits)
    here ++ Enum.flat_map(term, fn {k, v} -> walk(v, path ++ [k], depth + 1, limits) end)
  end

  defp walk(term, path, depth, limits) when is_list(term) do
    here = items(length(term), path, limits)

    here ++
      (term
       |> Enum.with_index()
       |> Enum.flat_map(fn {v, i} -> walk(v, path ++ [i], depth + 1, limits) end))
  end

  defp walk(_leaf, _path, _depth, _limits), do: []

  defp items(n, path, %{items: max}) when n > max, do: [{path, {:limit, :items, max, n}}]
  defp items(_n, _path, _limits), do: []

  # -- counts: ticks, iterations and counts, by the schema ------------------------------

  @doc """
  Every `ticks`, `iterations` and `counts` fault of a design map at the current version,
  found by walking it with the schema, ordered by path. A variable is not a literal of the
  document and is not checked.
  """
  @spec counts(term(), t()) :: [Validator.error()]
  def counts(design, limits) when is_map(design) and not is_struct(design) do
    :design |> node(design, [], limits) |> Enum.sort_by(&elem(&1, 0))
  end

  def counts(_other, _limits), do: []

  defp node(kind, map, path, limits) do
    Enum.flat_map(map, fn {k, v} ->
      case Schema.key(kind, k) do
        nil ->
          []

        spec ->
          limit(kind, map, k, v, path ++ [k], limits) ++ value(spec.type, v, path ++ [k], limits)
      end
    end)
  end

  defp value({:node, kind}, v, path, limits) when is_map(v) and not is_struct(v),
    do: node(kind, v, path, limits)

  defp value({:list, t}, v, path, limits) when is_list(v) do
    v |> Enum.with_index() |> Enum.flat_map(fn {e, i} -> value(t, e, path ++ [i], limits) end)
  end

  defp value({:map, t}, v, path, limits) when is_map(v) and not is_struct(v),
    do: Enum.flat_map(v, fn {k, e} -> value(t, e, path ++ [k], limits) end)

  defp value({:one_of, types}, v, path, limits) do
    case Schema.select(types, v) do
      nil -> []
      type -> value(type, v, path, limits)
    end
  end

  defp value(_type, _v, _path, _limits), do: []

  # The keys a limit reads (spec/14 §9.2): what is checked where, and against which.
  defp limit(:axis, _node, :ticks, n, path, limits) when is_integer(n),
    do: over(:ticks, n, path, limits)

  defp limit(:ticks, _node, :count, n, path, limits) when is_integer(n),
    do: over(:ticks, n, path, limits)

  defp limit(:transform, %{op: :force}, :ticks, n, path, limits) when is_integer(n),
    do: over(:iterations, n, path, limits)

  defp limit(:transform, _node, key, n, path, limits)
       when key in [:thresholds, :samples, :n, :width] and is_integer(n),
       do: over(:counts, n, path, limits)

  # A grid's dimensions: a `:contour` step's columns and rows, a `:density` step's pixels.
  defp limit(:transform, %{op: op}, :size, dims, path, limits)
       when op in [:contour, :density] and is_list(dims) do
    dims
    |> Enum.with_index()
    |> Enum.flat_map(fn {n, i} ->
      if is_number(n), do: over(:counts, n, path ++ [i], limits), else: []
    end)
  end

  defp limit(_kind, _node, _key, _v, _path, _limits), do: []

  defp over(name, n, path, limits) do
    max = Map.fetch!(limits, name)
    if n > max, do: [{path, {:limit, name, max, n}}], else: []
  end
end
