defmodule Visualize.Chart.Builder.StoreTest do
  @moduledoc """
  The store revised (spec/14 §19.7, D-100, D-103): ids as the DOM carries them, a context
  on every call, and import as a relocation through one table.
  """
  use ExUnit.Case, async: true

  alias Visualize.Chart.Builder.{Bundle, Store}
  alias Visualize.Chart.Fragment

  doctest Visualize.Chart.Fragment
  doctest Visualize.Chart.Builder.Store

  # A store over an Agent: ids issued from a per-kind counter that only goes up, the
  # context recorded with every write so a test can see it arrived.
  defmodule Memory do
    @behaviour Store

    def start, do: Agent.start_link(fn -> %{entries: %{}, counters: %{}, writes: []} end)

    # The context is `{agent, who}`; a bare agent is tolerated so a test can read back.
    defp agent_of({agent, _who}), do: agent
    defp agent_of(agent), do: agent

    @impl true
    def list(context),
      do:
        Agent.get(agent_of(context), fn s -> for {id, e} <- s.entries, do: Map.put(e, :id, id) end)

    @impl true
    def get(id, context) do
      Agent.get(agent_of(context), fn s ->
        case Map.fetch(s.entries, id) do
          {:ok, entry} -> {:ok, Map.put(entry, :id, id)}
          :error -> :error
        end
      end)
    end

    @impl true
    def put(%{id: nil} = entry, {agent, who}) do
      kind = Fragment.kind(entry.fragment)

      id =
        Agent.get_and_update(agent, fn s ->
          n = Map.get(s.counters, kind, 0) + 1
          {{kind, n}, %{s | counters: Map.put(s.counters, kind, n)}}
        end)

      put(%{entry | id: id, kind: kind}, {agent, who})
    end

    def put(%{id: id} = entry, {agent, who}) do
      stored = %{name: entry.name, kind: Fragment.kind(entry.fragment), fragment: entry.fragment}

      Agent.update(agent, fn s ->
        %{s | entries: Map.put(s.entries, id, stored), writes: [{id, who} | s.writes]}
      end)

      {:ok, id}
    end

    def put(entry, agent), do: put(entry, {agent, nil})

    @impl true
    def delete(id, context) do
      Agent.update(agent_of(context), fn s -> %{s | entries: Map.delete(s.entries, id)} end)
      :ok
    end

    @impl true
    def import(bundle, context), do: Store.relocate(bundle, context, &put/2)

    def writes(agent), do: Agent.get(agent, & &1.writes)
  end

  setup do
    {:ok, agent} = Memory.start()
    %{store: {Memory, {agent, :doug}}, agent: agent}
  end

  describe "ids (spec/14 §19.2, D-100)" do
    test "are tagged with the kind and issued from a sequence that only goes up", %{store: store} do
      {:ok, a} = Store.put(store, entry("Styles::a", %{style: %{opacity: 1}}))
      {:ok, b} = Store.put(store, entry("Styles::b", %{style: %{opacity: 0.5}}))
      {:ok, t} = Store.put(store, entry("Theme::dark", %{theme: :dark}))

      assert a == {:style, 1}
      assert b == {:style, 2}
      assert t == {:theme, 1}
    end

    test "a deleted id is never reused, and a reference to it finds nothing", %{store: store} do
      {:ok, a} = Store.put(store, entry("Styles::a", %{style: %{}}))
      :ok = Store.delete(store, a)
      {:ok, next} = Store.put(store, entry("Styles::b", %{style: %{}}))

      assert next == {:style, 2}
      assert Store.get(store, a) == :error
    end

    test "round-trip the DOM's string form, and refuse a kind that is not one" do
      assert Store.encode_id({:style, 11}) == "style:11"
      assert Store.decode_id("style:11") == {:ok, {:style, 11}}
      assert Store.decode_id("theme:32") == {:ok, {:theme, 32}}

      # No atom is created from a client's string.
      assert Store.decode_id("nonsense:11") == :error
      assert Store.decode_id("style:0") == :error
      assert Store.decode_id("style:x") == :error
      assert Store.decode_id("style") == :error
    end
  end

  describe "the context (spec/14 §19.7)" do
    test "reaches every write", %{store: store, agent: agent} do
      {:ok, id} = Store.put(store, entry("Styles::a", %{style: %{}}))
      assert [{^id, :doug}] = Memory.writes(agent)
    end

    test "a bare module is a nil context", %{agent: agent} do
      assert Store.split(Memory) == {Memory, nil}
      assert Store.split({Memory, agent}) == {Memory, agent}
    end
  end

  describe "a bundle (spec/14 §19.7, D-103)" do
    test "export takes the closure, dependencies first, each once", %{store: store} do
      {:ok, base} = Store.put(store, entry("Styles::base", %{style: %{stroke_width: 1}}))
      {:ok, thick} = Store.put(store, entry("Styles::thick", %{style: %{extends: base}}))

      {:ok, comp} =
        Store.put(
          store,
          entry("Composites::c", %{composite: %{uses: [thick, base, thick]}})
        )

      bundle = Bundle.export(store, comp, :here)

      assert bundle.provenance.store == :here
      assert %DateTime{} = bundle.provenance.exported_at
      assert Enum.map(bundle.entries, & &1.id) == [base, thick, comp]
    end

    test "an id the store does not hold is skipped, not an error", %{store: store} do
      {:ok, id} = Store.put(store, entry("Styles::a", %{style: %{fill: {:style, 99}}}))
      bundle = Bundle.export(store, id, :here)
      assert Enum.map(bundle.entries, & &1.id) == [id]
    end

    test "import relocates through one table and rewrites the references", %{store: from} do
      {:ok, base} = Store.put(from, entry("Styles::base", %{style: %{stroke_width: 1}}))
      {:ok, thick} = Store.put(from, entry("Styles::thick", %{style: %{extends: base}}))
      bundle = Bundle.export(from, thick, :from)

      {:ok, agent} = Memory.start()
      to = {Memory, {agent, :importer}}
      # The destination already has a style, so the numbers cannot coincide.
      {:ok, _} = Store.put(to, entry("Styles::existing", %{style: %{}}))

      {:ok, result} = Store.import(to, bundle)

      assert result.outside == []
      assert result.ids == %{base => {:style, 2}, thick => {:style, 3}}

      {:ok, moved} = Store.get(to, {:style, 3})
      assert moved.fragment == %{style: %{extends: {:style, 2}}}
    end

    test "a composite of real use sites exports its closure and imports with its uses rewritten (#470)",
         %{store: from} do
      {:ok, base} = Store.put(from, entry("Styles::base", %{style: %{stroke_width: 1}}))

      {:ok, comp} =
        Store.put(
          from,
          entry("Composites::c", %{
            composite: %{uses: [Visualize.Chart.Use.new(base)], vars: %{}}
          })
        )

      bundle = Bundle.export(from, comp, :from)
      assert Enum.map(bundle.entries, & &1.id) == [base, comp]

      {:ok, agent} = Memory.start()
      to = {Memory, {agent, :importer}}
      {:ok, _} = Store.put(to, entry("Styles::existing", %{style: %{}}))

      {:ok, result} = Store.import(to, bundle)
      assert result.outside == []
      new_base = Map.fetch!(result.ids, base)

      {:ok, moved} = Store.get(to, Map.fetch!(result.ids, comp))
      assert %{composite: %{uses: [%Visualize.Chart.Use{ref: ^new_base}]}} = moved.fragment
    end

    test "a reference outside the bundle is left alone and reported", %{store: from} do
      {:ok, id} = Store.put(from, entry("Styles::a", %{style: %{extends: {:style, 40}}}))
      bundle = Bundle.export(from, id, :from)

      {:ok, agent} = Memory.start()
      {:ok, result} = Store.import({Memory, {agent, nil}}, bundle)

      assert result.outside == [{:style, 40}]
      {:ok, moved} = Store.get({Memory, agent}, {:style, 1})
      assert moved.fragment == %{style: %{extends: {:style, 40}}}
    end

    test "a store that refuses a write refuses the whole import" do
      bundle = %Bundle{
        provenance: %{store: :x, exported_at: DateTime.utc_now()},
        entries: [%{id: {:style, 1}, name: "a", kind: :style, fragment: %{style: %{}}}]
      }

      assert Store.import(Visualize.BuilderFixture.Refusing, bundle) == {:error, :read_only}
    end
  end

  describe "refs and relocate (spec/14 §19.7)" do
    test "an id is found wherever it sits, sorted, and a look-alike tuple is not" do
      fragment = %{
        style: [{:style, 3}, %{fill: {:style, 11}}],
        anchor: {:axis, :y},
        field: {:field, :t},
        data: {:data, [1, 2]},
        nested: %{deep: [{:theme, 2}]}
      }

      assert Fragment.refs(fragment) == [{:style, 3}, {:style, 11}, {:theme, 2}]
    end

    test "a struct is a leaf" do
      fragment = %{v: Visualize.Chart.var(:x), s: {:style, 1}}
      assert Fragment.refs(fragment) == [{:style, 1}]
    end

    test "a use site's ids are found: its ref, its origin, and any in its local and vars (#470)" do
      composite = %{
        composite: %{
          uses: [
            Visualize.Chart.Use.new({:style, 9}),
            %Visualize.Chart.Use{
              id: {:use, 2},
              ref: nil,
              origin: {:style, 4},
              local: %{fill: {:style, 5}},
              vars: %{c: {:theme, 6}}
            }
          ],
          vars: %{}
        }
      }

      assert Fragment.refs(composite) == [{:style, 4}, {:style, 5}, {:style, 9}, {:theme, 6}]
    end

    test "relocate rewrites a use site's ids in place, and the site stays a use (#470)" do
      use = %Visualize.Chart.Use{
        id: {:use, 1},
        ref: {:style, 9},
        origin: {:style, 4},
        local: %{fill: {:style, 5}}
      }

      table = %{{:style, 9} => {:style, 1}, {:style, 4} => {:style, 2}}

      {%{composite: %{uses: [moved]}}, missed} =
        Fragment.relocate(%{composite: %{uses: [use], vars: %{}}}, table)

      assert %Visualize.Chart.Use{ref: {:style, 1}, origin: {:style, 2}} = moved
      assert moved.local == %{fill: {:style, 5}}
      assert missed == [{:style, 5}]
    end
  end

  defp entry(name, fragment), do: %{id: nil, name: name, kind: nil, fragment: fragment}
end
