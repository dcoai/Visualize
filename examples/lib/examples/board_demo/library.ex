defmodule Examples.BoardDemo.Library do
  @moduledoc """
  A host's library of designs, a `Visualize.Chart.Builder.Store` over an `Agent` (spec/14
  §19.7): what `/board`'s *A board in a bundle* carries the demo board between (#781, work
  item #822). One library is the authoring host's, holding the demo's components under the
  ids the demo's own store gives them; the other is a second host's, which already holds
  designs of its own, so the ids an import issues are new ones.

  Each is started linked to the page that shows it and goes when the page does. Ids are
  issued from a per-kind counter that only goes up, as a store's `import/2` needs.
  """
  @behaviour Visualize.Chart.Builder.Store

  alias Visualize.Chart.Builder.Store
  alias Visualize.Chart.Fragment

  @doc """
  A library holding `entries` — `{id, name, fragment}` — under their own ids, linked to
  the caller: `{__MODULE__, agent}`, the store a `Bundle` function takes.
  """
  @spec start([{Store.id(), String.t(), map()}]) :: {module(), pid()}
  def start(entries) do
    {:ok, agent} = Agent.start_link(fn -> %{entries: %{}, counters: %{}} end)
    for {id, name, fragment} <- entries, do: {:ok, ^id} = put(entry(id, name, fragment), agent)
    {__MODULE__, agent}
  end

  @doc "The authoring host's library: the demo board's components, named `Board:demo:<n>`."
  @spec authoring() :: {module(), pid()}
  def authoring do
    start(
      for {{_kind, n} = id, design} <- Examples.BoardDemo.store(),
          do: {id, "Board:demo:#{n}", design}
    )
  end

  @doc """
  A second host's library, already holding two designs of its own (the gallery's *Line
  Chart* and *Bar Chart*) under the ids its counter issued them.
  """
  @spec receiving() :: {module(), pid()}
  def receiving do
    {line, _rows} = Examples.Charts.LineChart.design([])
    {bar, _rows} = Examples.Charts.BarChart.design([])
    start([{{:composite, 1}, "Ours:line", line}, {{:composite, 2}, "Ours:bar", bar}])
  end

  @doc "Every entry's id and name, in id order."
  @spec entries({module(), pid()}) :: [{Store.id(), String.t()}]
  def entries({__MODULE__, agent}),
    do: for(%{id: id, name: name} <- list(agent), do: {id, name})

  @doc "The library as a board's store reads one: id to fragment."
  @spec fragments({module(), pid()}) :: %{Store.id() => map()}
  def fragments({__MODULE__, agent}),
    do: Agent.get(agent, fn s -> Map.new(s.entries, fn {id, e} -> {id, e.fragment} end) end)

  defp entry(id, name, fragment), do: %{id: id, name: name, fragment: fragment}

  @impl true
  def list(agent),
    do:
      Agent.get(agent, fn s ->
        for {id, e} <- Enum.sort(s.entries), do: %{id: id, name: e.name, kind: e.kind}
      end)

  @impl true
  def get(id, agent) do
    Agent.get(agent, fn s ->
      with {:ok, e} <- Map.fetch(s.entries, id), do: {:ok, Map.put(e, :id, id)}
    end)
  end

  @impl true
  def put(%{id: nil} = entry, agent) do
    # A flat design is held under a composite id, as an imported document is (spec/15 §1.3).
    kind = Fragment.kind(entry.fragment) || :composite

    id =
      Agent.get_and_update(agent, fn s ->
        n = Map.get(s.counters, kind, 0) + 1
        {{kind, n}, %{s | counters: Map.put(s.counters, kind, n)}}
      end)

    put(%{entry | id: id}, agent)
  end

  def put(%{id: {kind, n} = id} = entry, agent) do
    stored = %{name: entry.name, kind: Fragment.kind(entry.fragment), fragment: entry.fragment}

    Agent.update(agent, fn s ->
      %{
        s
        | entries: Map.put(s.entries, id, stored),
          counters: Map.update(s.counters, kind, n, &max(&1, n))
      }
    end)

    {:ok, id}
  end

  @impl true
  def delete(id, agent), do: Agent.update(agent, &%{&1 | entries: Map.delete(&1.entries, id)})

  @impl true
  def import(bundle, agent), do: Store.relocate(bundle, agent, &put/2)
end
