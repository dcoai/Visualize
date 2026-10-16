if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Typed do
    @moduledoc false
    # The column types of the host's data, typed once per change of it (spec/14 §19.10,
    # §22.8, #714, D-189). `update/2` keeps `typed/2` of the host's `sources` and `catalog`
    # beside them; a pass reads it when it is given the very terms it was typed from, and
    # types them itself otherwise, so nothing reads stale types. The signals, whose rows move
    # with the tick, are typed in the pass.

    alias Visualize.Chart.Builder.{Boards, Scales}
    alias Visualize.Data.{Delivery, Table}
    alias Visualize.Signals

    @doc false
    # The host's data typed: the pool's sampled types (`Scales.pool_types/1`), and each feed
    # a board binds read whole (`Table.column_types/1`, D-153) — a catalog feed's preview
    # rows, the host's source of its name or rows made from its schema, or with no catalog
    # each source of the host's.
    @spec typed(map(), map() | nil) :: map()
    def typed(sources, catalog) do
      %{
        sources: sources,
        catalog: catalog,
        pool: Scales.pool_types(sources),
        feeds: feeds(sources, catalog)
      }
    end

    @doc false
    # The pass's pool types: the host's, then the signals' at the tick.
    @spec pool(map()) :: Scales.pool_types()
    def pool(assigns) do
      host =
        case own(assigns) do
          %{pool: pool} -> pool
          nil -> Scales.pool_types(assigns.sources)
        end

      Map.merge(host, Scales.pool_types(signals(assigns)))
    end

    @doc false
    # The pass's feed types, by feed, for the binding's row check (§22.8): with a catalog,
    # its feeds'; with none, the pool's sources', the signals' among them.
    @spec feeds(map()) :: %{term() => %{atom() => atom()}}
    def feeds(%{catalog: catalog} = assigns) when is_map(catalog), do: own_feeds(assigns)

    def feeds(assigns),
      do: Map.merge(own_feeds(assigns), Map.new(signals(assigns), &whole/1))

    defp own_feeds(assigns) do
      case own(assigns) do
        %{feeds: feeds} -> feeds
        nil -> feeds(assigns.sources, assigns.catalog)
      end
    end

    # What `update/2` typed, when the assigns hold the very data it typed; `nil` otherwise,
    # for the caller to type what it reads.
    defp own(%{sources: sources, catalog: catalog} = assigns) do
      case Map.get(assigns, :typed) do
        %{sources: ^sources, catalog: ^catalog} = typed -> typed
        _other -> nil
      end
    end

    defp signals(assigns),
      do: Signals.pool(Map.get(assigns, :signals, %{}), Map.get(assigns, :tick, 0))

    defp feeds(sources, catalog) when is_map(catalog) do
      # A sample's types do not depend on the instant its rows end at.
      now = ~U[2000-01-01 00:00:00Z]

      Map.new(catalog, fn {feed, schema} ->
        whole({feed, Map.get_lazy(sources, feed, fn -> Boards.sample(schema, now) end)})
      end)
    end

    defp feeds(sources, _none), do: Map.new(sources, &whole/1)

    defp whole({feed, %Delivery{} = delivery}), do: whole({feed, Delivery.source(delivery)})
    defp whole({feed, source}), do: {feed, Table.column_types(source)}
  end
end
