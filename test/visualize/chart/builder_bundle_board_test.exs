defmodule Visualize.Chart.Builder.BundleBoardTest do
  @moduledoc """
  A board in a bundle (spec/15 §11, D-147): exported with its components, their closure
  and the themes it names; imported with every check before any entry is put, every id
  re-keyed by the receiving store and the board's refs rewritten through the same table.
  """
  use ExUnit.Case, async: true

  import Visualize.Chart, only: [var: 1]

  alias Visualize.Board
  alias Visualize.Chart.Builder.{Bundle, Store}
  alias Visualize.Chart.{Composite, Fragment}

  # A store over an Agent: ids issued from a per-kind counter that only goes up.
  defmodule Memory do
    @behaviour Store

    def start do
      {:ok, agent} = Agent.start_link(fn -> %{entries: %{}, counters: %{}} end)
      {__MODULE__, agent}
    end

    @impl true
    def list(agent),
      do: Agent.get(agent, fn s -> for {id, e} <- Enum.sort(s.entries), do: summary(id, e) end)

    defp summary(id, entry), do: %{id: id, name: entry.name, kind: entry.kind}

    @impl true
    def get(id, agent) do
      Agent.get(agent, fn s ->
        with {:ok, entry} <- Map.fetch(s.entries, id), do: {:ok, Map.put(entry, :id, id)}
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

    def put(%{id: id} = entry, agent) do
      stored = %{name: entry.name, kind: Fragment.kind(entry.fragment), fragment: entry.fragment}
      Agent.update(agent, fn s -> %{s | entries: Map.put(s.entries, id, stored)} end)
      {:ok, id}
    end

    @impl true
    def delete(id, agent) do
      Agent.update(agent, fn s -> %{s | entries: Map.delete(s.entries, id)} end)
      :ok
    end

    @impl true
    def import(bundle, agent), do: Store.relocate(bundle, agent, &put/2)

    def ids(agent), do: Agent.get(agent, fn s -> Map.keys(s.entries) end)
  end

  @ocean %{theme: %{name: :ocean, series: ["#1f5f8b", "#3fa7a0"], background: "#f4f8fb"}}

  # A line drawn in the theme a variable names, its mark in a stored style.
  defp line(style) do
    %{
      version: 2,
      theme: var(:look),
      sources: %{primary: %{fields: [:t, :v]}},
      vars: %{look: %{default: :ocean}, title: %{default: "Latency"}},
      frames: %{
        main: %{kind: :cartesian, scales: %{x: %{kind: :linear}, y: %{kind: :linear}}}
      },
      marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v}, style: style}],
      labels: [%{anchor: :title, text: "\#{var(:title)}"}]
    }
  end

  @gauge %{
    version: 2,
    sources: %{reading: %{fields: [:n, :v]}},
    frames: %{main: %{kind: :polar, scales: %{angle: %{kind: :radial}, r: %{kind: :sqrt}}}},
    marks: [%{type: :rose, data: :reading, channels: %{angle: :n, value: :v}}]
  }

  defp entry(name, fragment), do: %{id: nil, name: name, kind: nil, fragment: fragment}

  # A source store holding a style, the ocean theme, an unrelated theme, the line stored
  # as structure (a composite of its sites) and the gauge stored flat.
  defp source do
    {_module, agent} = store = Memory.start()
    {:ok, _} = Store.put(store, entry("Looks::spare", %{theme: %{name: :spare}}))
    {:ok, thick} = Store.put(store, entry("Styles::thick", %{style: %{stroke_width: 3}}))
    {:ok, ocean} = Store.put(store, entry("Looks::ocean", @ocean))
    {uses, _labels} = Composite.decompose(line(thick))
    {:ok, line} = Store.put(store, entry("Charts::line", %{composite: %{uses: uses, vars: %{}}}))
    {:ok, gauge} = Store.put(store, entry("Charts::gauge", @gauge))

    %{store: store, agent: agent, thick: thick, ocean: ocean, line: line, gauge: gauge}
  end

  defp board(%{line: line, gauge: gauge}) do
    Board.from_map!(%{
      cells: %{
        latency: %{x: 0, y: 0, w: 8, h: 4, ref: line, title: "Latency"},
        eu: %{x: 0, y: 4, w: 8, h: 4, ref: line, vars: %{title: "EU"}},
        gauge: %{x: 8, y: 0, w: 4, h: 4, ref: gauge}
      },
      window: %{last: 3600},
      vars: %{title: "US"}
    })
  end

  @pools %{
    latency: %{primary: [%{t: 1, v: 10}, %{t: 2, v: 20}]},
    eu: %{primary: [%{t: 1, v: 300}, %{t: 2, v: 400}]},
    gauge: %{reading: [%{n: 1, v: 0.5}, %{n: 2, v: 0.8}]}
  }

  # Each cell rendered, through the theme its store holds under the name.
  defp rendered(board, store) do
    {:ok, theme} = Store.theme(store, :ocean)
    {:ok, applied, _cache} = Board.realise(board, store_fetch(store), @pools, theme: theme)
    Map.new(applied, fn {cell, done} -> {cell, Visualize.Chart.render(done)} end)
  end

  defp store_fetch(store) do
    fn id ->
      with {:ok, entry} <- Store.get(store, id), do: {:ok, entry.fragment}
    end
  end

  describe "export" do
    test "carries the board, its components, their closure and the theme it names" do
      src = source()
      bundle = Bundle.export_board(src.store, board(src), :metresis)

      assert bundle.provenance.store == :metresis
      assert bundle.provenance.schema == Visualize.Chart.Migration.current()
      assert bundle.board == Board.to_map(board(src))

      ids = Enum.map(bundle.entries, & &1.id)
      assert Enum.sort(ids) == Enum.sort([src.thick, src.line, src.gauge, src.ocean])
      # Dependencies first: the style before the composite that uses it.
      assert Enum.find_index(ids, &(&1 == src.thick)) < Enum.find_index(ids, &(&1 == src.line))
    end

    test "never carries a binding" do
      src = source()
      bundle = Bundle.export_board(src.store, board(src), :metresis)
      refute Map.has_key?(Map.from_struct(bundle), :binding)
      refute Map.has_key?(bundle.board, :binding)
    end

    test "a built-in theme, or one the store does not hold, is not carried" do
      src = source()
      on = %{board(src) | vars: %{look: :dark}}
      refute src.ocean in Enum.map(Bundle.export_board(src.store, on, :m).entries, & &1.id)

      elsewhere = %{board(src) | vars: %{look: :harbour}}
      refute src.ocean in Enum.map(Bundle.export_board(src.store, elsewhere, :m).entries, & &1.id)
    end

    test "a board variable names the theme its components draw in" do
      src = source()
      {:ok, spare} = Store.theme_entry(src.store, :spare)
      on = %{board(src) | vars: %{look: :spare}}
      ids = Enum.map(Bundle.export_board(src.store, on, :m).entries, & &1.id)

      assert spare.id in ids
      refute src.ocean in ids
    end
  end

  describe "import" do
    test "into an empty store realises the same board" do
      src = source()
      board = board(src)
      bundle = Bundle.export_board(src.store, board, :metresis)

      to = Memory.start()
      assert {:ok, %{board: imported, ids: ids, outside: []}} = Bundle.import_board(to, bundle)

      assert imported.cells.latency.ref == Map.fetch!(ids, src.line)
      assert imported.cells.gauge.ref == Map.fetch!(ids, src.gauge)
      assert %{imported | cells: nil} == %{board | cells: nil}
      assert rendered(imported, to) == rendered(board, src.store)
    end

    test "into a non-empty store re-keys every id with no collision" do
      src = source()
      bundle = Bundle.export_board(src.store, board(src), :metresis)

      {_m, agent} = to = Memory.start()
      {:ok, _} = Store.put(to, entry("Styles::mine", %{style: %{stroke_width: 9}}))
      {:ok, _} = Store.put(to, entry("Charts::mine", @gauge))
      {:ok, _} = Store.put(to, entry("Charts::other", @gauge))
      held = Memory.ids(agent)

      {:ok, %{board: imported, ids: ids}} = Bundle.import_board(to, bundle)

      new = Map.values(ids)
      assert length(Enum.uniq(new)) == length(new)
      assert MapSet.disjoint?(MapSet.new(new), MapSet.new(held))
      assert Enum.sort(Memory.ids(agent)) == Enum.sort(held ++ new)

      # The style the line uses is the one that arrived with it, not the store's own.
      {:ok, line} = Store.get(to, imported.cells.latency.ref)
      assert Map.fetch!(ids, src.thick) in Fragment.refs(line.fragment)
      assert rendered(imported, to) == rendered(board(src), src.store)
    end

    test "a component the bundle does not carry is reported at its cell" do
      src = source()
      bundle = Bundle.export_board(src.store, board(src), :metresis)
      bundle = %{bundle | entries: Enum.reject(bundle.entries, &(&1.id == src.gauge))}

      {_m, agent} = to = Memory.start()

      assert Bundle.import_board(to, bundle) ==
               {:error, [{[:cells, :gauge, :ref], {:not_carried, src.gauge}}]}

      assert Memory.ids(agent) == []

      assert Board.format_error({[:cells, :gauge, :ref], {:not_carried, src.gauge}}) ==
               "cells.gauge.ref: refers to {:composite, 2}, which the bundle does not carry"
    end

    test "a cell whose component the source store did not hold exports and is reported" do
      src = source()
      board = put_in(board(src).cells.gauge.ref, {:composite, 99})
      bundle = Bundle.export_board(src.store, board, :metresis)

      assert Bundle.import_board(Memory.start(), bundle) ==
               {:error, [{[:cells, :gauge, :ref], {:not_carried, {:composite, 99}}}]}
    end

    test "a newer bundle is refused before anything is read or put" do
      src = source()
      bundle = Bundle.export_board(src.store, board(src), :metresis)
      {_m, agent} = to = Memory.start()

      newer = put_in(bundle.provenance.schema, 4)

      assert Bundle.import_board(to, %{newer | board: :unreadable}) ==
               {:error, [{[:provenance, :schema], {:newer_schema, 4, 3}}]}

      assert Bundle.import_board(to, %{bundle | board: %{bundle.board | version: 4}}) ==
               {:error, [{[:version], {:newer_schema, 4, 3}}]}

      assert Memory.ids(agent) == []
    end

    test "limits apply to the board, the entries and the components" do
      src = source()
      bundle = Bundle.export_board(src.store, board(src), :metresis)
      {_m, agent} = to = Memory.start()

      assert {:error, errors} = Bundle.import_board(to, bundle, limits: [items: 2])
      assert {[:cells], {:limit, :items, 2, 3}} in errors

      # A hand-edited bundle carrying more entries than the board's own maps hold items
      # (its root holds ten keys, `stale_after` and `links` among them, so ten is the
      # tightest limit the board itself passes).
      spare =
        for n <- 100..106,
            do: %{id: {:style, n}, name: "s", kind: :style, fragment: %{style: %{}}}

      wide = %{bundle | entries: bundle.entries ++ spare}
      assert {:error, errors} = Bundle.import_board(to, wide, limits: [items: 10])
      assert {[:entries], {:limit, :items, 10, 11}} in errors

      assert {:error, errors} = Bundle.import_board(to, bundle, limits: [depth: 4])
      key = Store.encode_id(src.line)
      assert Enum.any?(errors, &match?({[:entries, ^key | _], {:limit, :depth, 4, _}}, &1))

      assert Memory.ids(agent) == []
    end

    test "a theme name the store already gives a different theme is refused" do
      src = source()
      bundle = Bundle.export_board(src.store, board(src), :metresis)

      {_m, agent} = to = Memory.start()
      {:ok, _} = Store.put(to, entry("Looks::ocean", %{theme: %{name: :ocean, axis: "#000000"}}))

      assert Bundle.import_board(to, bundle) ==
               {:error, [{[:entries, Store.encode_id(src.ocean)], {:theme_taken, "ocean"}}]}

      assert length(Memory.ids(agent)) == 1

      # The same theme under the same name draws the board as it was designed.
      same = Memory.start()
      {:ok, _} = Store.put(same, entry("Looks::ocean", @ocean))
      assert {:ok, _} = Bundle.import_board(same, bundle)
    end

    test "a bundle with no board, or a store that refuses, is the fault" do
      src = source()
      bundle = Bundle.export_board(src.store, board(src), :metresis)

      assert Bundle.import_board(Memory.start(), %{bundle | board: nil}) ==
               {:error, [{[:board], :required}]}

      assert Bundle.import_board(Visualize.BuilderFixture.Refusing, bundle) ==
               {:error, [{[], {:store, :read_only}}]}
    end
  end

  test "a bundle export/3 makes carries no board, and imports as it did" do
    src = source()
    bundle = Bundle.export(src.store, src.line, :metresis)
    assert bundle.board == nil
    assert {:ok, %{outside: []}} = Store.import(Memory.start(), bundle)
  end
end
