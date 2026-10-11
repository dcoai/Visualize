defmodule Visualize.Data.Schema.Cache do
  @moduledoc """
  Schemas by `{feed, version}`, as a value (spec/08 §10.3, D-136).

  A delivery names the version of its feed's schema (`Visualize.Data.Delivery`); a
  version already held costs a lookup, and one not seen before is asked of the feed
  once. The cache is not a process and not a table: whatever owns the feeds — a board's
  process, or the caller of `Visualize.Chart.apply/2` — holds it in its own state, passes
  it in and keeps the grown cache it gets back. A feed is any term that names one.

  ## Examples

      iex> alias Visualize.Data.Schema
      iex> schema = Schema.new!(%{v: %{type: :number, unit: "ms"}})
      iex> cache = Schema.Cache.new([{:latency, schema}])
      iex> {:ok, ^schema, ^cache} = Schema.Cache.resolve(cache, :latency, Schema.version(schema), nil)
      iex> Schema.Cache.resolve(cache, :latency, "0000", nil)
      {:error, {:unknown_schema, :latency, "0000"}, cache}

  """

  alias Visualize.Data.Schema

  defstruct entries: %{}

  @type feed :: term()
  @type t :: %__MODULE__{entries: %{{feed(), String.t()} => Schema.t()}}

  @typedoc "The pull side of a feed: its present schema, or why it has none."
  @type describe :: (feed() -> {:ok, Schema.t()} | {:error, term()}) | nil

  @typedoc "Why `resolve/4` has no schema for a version (spec/08 §10.3)."
  @type reason ::
          {:unknown_schema, feed(), String.t()}
          | {:describe, feed(), term()}
          | {:schema_version, feed(), String.t(), String.t()}

  @doc "The empty cache."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "A cache holding each `{feed, schema}` pair under the schema's own version."
  @spec new([{feed(), Schema.t()}]) :: t()
  def new(pairs) when is_list(pairs) do
    Enum.reduce(pairs, new(), fn {feed, schema}, cache -> put(cache, feed, schema) end)
  end

  @doc "The cache with a feed's schema added under its version."
  @spec put(t(), feed(), Schema.t()) :: t()
  def put(%__MODULE__{entries: entries} = cache, feed, %Schema{version: version} = schema),
    do: %{cache | entries: Map.put(entries, {feed, version}, schema)}

  @doc "A feed's schema at a version, or `:error` when the cache does not hold it."
  @spec fetch(t(), feed(), String.t()) :: {:ok, Schema.t()} | :error
  def fetch(%__MODULE__{entries: entries}, feed, version),
    do: Map.fetch(entries, {feed, version})

  @doc """
  A feed's schema at a version (spec/08 §10.3): the cached one without calling anything,
  else `describe`'s answer, asked once and cached.

  `describe` answering a schema of another version is `{:schema_version, feed, version,
  got}`, with the answer cached under its own version; `{:error, reason}` from it is
  `{:describe, feed, reason}`; no `describe` for a version the cache lacks is
  `{:unknown_schema, feed, version}`. The cache comes back in every case.
  """
  @spec resolve(t(), feed(), String.t(), describe()) ::
          {:ok, Schema.t(), t()} | {:error, reason(), t()}
  def resolve(%__MODULE__{} = cache, feed, version, describe) when is_binary(version) do
    case fetch(cache, feed, version) do
      {:ok, schema} -> {:ok, schema, cache}
      :error -> ask(cache, feed, version, describe)
    end
  end

  defp ask(cache, feed, version, nil), do: {:error, {:unknown_schema, feed, version}, cache}

  defp ask(cache, feed, version, describe) when is_function(describe, 1) do
    case describe.(feed) do
      {:ok, %Schema{version: ^version} = schema} ->
        {:ok, schema, put(cache, feed, schema)}

      {:ok, %Schema{version: got} = schema} ->
        {:error, {:schema_version, feed, version, got}, put(cache, feed, schema)}

      {:error, reason} ->
        {:error, {:describe, feed, reason}, cache}
    end
  end
end
