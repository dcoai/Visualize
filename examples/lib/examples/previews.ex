defmodule Examples.Previews do
  @moduledoc """
  The gallery's previews, cached (#397): a design at rest is a pure function of its
  module, so its rendered document is kept in an ETS table keyed by the module, the size
  and the module's md5 — a recompile in dev misses and renders again — and every later
  mount of the gallery is instant.

  The table is public and owned by the application (`table/0` creates it when it is
  absent, so a test process may use it too); `render/2` is what a preview task runs,
  reading the cache first and filling it after.
  """

  @table __MODULE__

  @typedoc "A preview's size, `{width, height}` in user units."
  @type size :: {pos_integer(), pos_integer()}

  @doc "The cache table, created when absent: named, public, read-concurrent."
  @spec table() :: :ets.table()
  def table do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:named_table, :public, read_concurrency: true])
      table -> table
    end
  end

  @doc "The cached document of a module at a size, or `:miss`."
  @spec get(module(), size()) :: {:ok, String.t()} | :miss
  def get(module, size) do
    case :ets.lookup(table(), key(module, size)) do
      [{_key, svg}] -> {:ok, svg}
      [] -> :miss
    end
  end

  @doc "The module's document at a size, from the cache or rendered and cached."
  @spec render(module(), size()) :: String.t()
  def render(module, {width, height} = size) do
    case get(module, size) do
      {:ok, svg} ->
        svg

      :miss ->
        svg = Examples.Charts.Design.render(module, width: width, height: height)
        :ets.insert(table(), {key(module, size), svg})
        svg
    end
  end

  @doc "Forgets every cached preview."
  @spec clear() :: :ok
  def clear do
    :ets.delete_all_objects(table())
    :ok
  end

  # The module's md5 is in the key, so a recompiled module renders afresh (dev reload).
  defp key(module, size), do: {module, size, module.module_info(:md5)}
end
