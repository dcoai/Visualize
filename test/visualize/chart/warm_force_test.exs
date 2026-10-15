defmodule Visualize.Chart.WarmForceTest do
  # A compiled chart's force layout is warm (spec/14 §5.4.3, §12.5, #527, D-132): each
  # tick moves the graph from where it was, the marks of one graph share one run, and
  # `apply/2` stays cold.
  use ExUnit.Case, async: true

  import Visualize.Chart.Build

  alias Visualize.Chart
  alias Visualize.Chart.{Compiled, Frame, Mark, Schema, Validator}
  alias Visualize.IR.Element
  alias Visualize.Layout.Force

  # The bound a node may move between consecutive ticks, in pixels at 600 × 400 — the
  # gallery's size. Cold, the same ticks move a node by up to 327 px.
  @bound 15

  @ids ~w(A B C D E F G H I J K L)
  @nodes Enum.map(@ids, &%{id: &1})
  @links [
    {"A", "B"},
    {"A", "C"},
    {"B", "C"},
    {"D", "E"},
    {"D", "F"},
    {"E", "F"},
    {"G", "H"},
    {"G", "I"},
    {"H", "I"},
    {"J", "K"},
    {"J", "L"},
    {"K", "L"},
    {"A", "D"},
    {"B", "G"},
    {"C", "J"},
    {"E", "H"},
    {"F", "K"},
    {"I", "L"}
  ]
  @sources %{
    nodes: @nodes,
    links: Enum.map(@links, fn {s, t} -> %{source: s, target: t} end)
  }

  # The gallery's graph: the links drawn as paths and the nodes as circles, each mark
  # over the same `:force` step but its `output`.
  defp design(distance, opts \\ []) do
    {fields, opts} = Keyword.pop(opts, :fields, [:id])
    layout = [nodes: :nodes, strength: -400, distance: distance] ++ opts

    {:ok, design} =
      Chart.compose([
        chart(),
        source(:nodes, fields),
        source(:links, [:source, :target]),
        cartesian(margin: %{top: 0, right: 0, bottom: 0, left: 0}),
        path(force(from(:links), [:source, :target], layout ++ [output: :links]), %{path: :path}),
        circle(force(from(:links), [:source, :target], layout), %{x: :x, y: :y},
          options: %{radius: 10}
        )
      ])

    design
  end

  # The breathing distance of the gallery's tick.
  defp breathing(tick), do: 100 + 12 * :math.sin(tick * 0.1)

  defp compile(design, sources \\ @sources) do
    {:ok, %{main: compiled}} = Chart.compile(design, sources: sources, size: {600, 400})
    compiled
  end

  defp realized(design) do
    {:ok, %Chart{} = chart} = Chart.from_map(design)
    Frame.new(chart, sources: @sources, size: {600, 400})
  end

  # The node positions a frame's group draws, and the links' endpoints.
  defp drawn(group) do
    elements = flatten(group)

    nodes =
      for %Element{type: :circle, attrs: %{cx: x, cy: y}} <- elements, do: {x, y}

    links =
      for %Element{type: :path, path: %{commands: [{:M, x0, y0}, {:L, x1, y1}]}} <- elements,
          do: {{x0, y0}, {x1, y1}}

    {nodes, links}
  end

  defp flatten(%Element{children: children} = element),
    do: [element | Enum.flat_map(children || [], &flatten/1)]

  # The warm state of the compiled chart's one graph, `id => {x, y}`.
  defp positions(%Compiled{forces: forces}) do
    [{_key, nodes}] = Map.to_list(forces)
    Map.new(nodes, fn {id, m} -> {id, {m.x, m.y}} end)
  end

  # The greatest move of a node both layouts hold.
  defp moved(a, b) do
    Enum.max(
      for {id, {x, y}} <- a,
          Map.has_key?(b, id),
          {x2, y2} = b[id],
          do: distance(x2 - x, y2 - y)
    )
  end

  defp distance(dx, dy), do: :math.sqrt(dx * dx + dy * dy)

  # The gallery's run:the marks differ every tick, so each tick is compiled again and
  # carries the last one's state (spec/14 §12.5, #424, #434).
  defp run(ticks) do
    {layouts, _last} =
      Enum.map_reduce(ticks, nil, fn tick, previous ->
        fresh = compile(design(breathing(tick)))
        compiled = if previous, do: Compiled.carry(previous, fresh), else: fresh
        {group, compiled} = Compiled.step(compiled, @sources, at: tick * 50)
        {{positions(compiled), drawn(group)}, compiled}
      end)

    layouts
  end

  test "ticks move the graph from where it was: every node within the bound, the graph still moving" do
    layouts = run(0..60)
    steps = layouts |> Enum.map(&elem(&1, 0)) |> Enum.chunk_every(2, 1, :discard)
    moves = Enum.map(steps, fn [a, b] -> moved(a, b) end)

    assert Enum.max(moves) < @bound
    # It moves: the breathing distance swells and settles the graph on every tick.
    assert Enum.min(moves) > 0.01
    {first, _} = hd(layouts)
    {last, _} = List.last(layouts)
    assert moved(first, last) > 20

    # Cold — `apply/2` per tick, as every frame was drawn before — the same ticks jump.
    cold =
      for tick <- 0..10 do
        {:ok, applied} = Chart.apply(design(breathing(tick)), sources: @sources, size: {600, 400})
        mark = Enum.find(applied.frame.marks, &(&1.type == :circle))
        Map.new(Mark.rows(applied.frame, mark, applied.sources), &{&1.id, {&1.x, &1.y}})
      end

    assert cold
           |> Enum.chunk_every(2, 1, :discard)
           |> Enum.map(fn [a, b] -> moved(a, b) end)
           |> Enum.max() > 100
  end

  test "the links' endpoints are the nodes' positions at every tick" do
    for {positions, {nodes, links}} <- run(0..20) do
      assert length(nodes) == length(@ids) and length(links) == length(@links)
      assert MapSet.new(nodes) == MapSet.new(Map.values(positions))

      for {{s, t}, {from, to}} <- Enum.zip(@links, links) do
        assert from == positions[s] and to == positions[t]
      end
    end
  end

  test "apply is cold: the same input lays out the same graph, whatever a compiled chart has drawn" do
    applied = fn ->
      {:ok, applied} = Chart.apply(design(100), sources: @sources, size: {600, 400})
      mark = Enum.find(applied.frame.marks, &(&1.type == :circle))
      Mark.rows(applied.frame, mark, applied.sources)
    end

    before = applied.()
    _warm = run(0..5)
    assert applied.() == before

    # The cold run is `Force.run/1` at its defaults over the spiral.
    cold =
      Force.run(
        nodes: @nodes,
        links: Enum.map(@links, fn {s, t} -> %{source: s, target: t} end),
        forces: [
          {:center, x: 300.0, y: 200.0},
          {:many_body, strength: -400},
          {:link, distance: 100}
        ]
      )

    assert Enum.map(before, &Map.take(&1, [:id, :x, :y])) ==
             Enum.map(cold.nodes, &Map.take(&1, [:id, :x, :y]))

    # A compiled chart starts from that cold layout.
    assert positions(compile(design(100))) == Map.new(before, &{&1.id, {&1.x, &1.y}})
  end

  test "a node added between ticks leaves the others in place, and a node removed is forgotten" do
    # The graph has run for three seconds of the gallery's ticks, past the first swell from
    # the cold layout, as a graph a reader adds to has.
    compiled = compile(design(100))

    compiled =
      Enum.reduce(1..60, compiled, fn tick, c -> elem(Compiled.step(c, @sources, at: tick), 1) end)

    before = positions(compiled)

    grown = %{
      nodes: @nodes ++ [%{id: "M"}],
      links: @sources.links ++ [%{source: "M", target: "A"}]
    }

    {_group, grown_chart} = Compiled.step(compiled, grown, at: 61)
    after_growth = positions(grown_chart)

    assert Map.has_key?(after_growth, "M")
    assert moved(before, after_growth) < @bound
    # The new node starts near its neighbor, not across the plot.
    {ax, ay} = after_growth["A"]
    {mx, my} = after_growth["M"]
    assert distance(mx - ax, my - ay) < 150

    {_group, shrunk} = Compiled.step(grown_chart, @sources, at: 62)
    refute Map.has_key?(positions(shrunk), "M")
    assert map_size(positions(shrunk)) == length(@ids)
    assert moved(after_growth, positions(shrunk)) < @bound
  end

  test "carry keeps the layout of the graph the fresh chart still draws, and nothing of another" do
    {_group, warm} = Compiled.step(compile(design(100)), @sources, at: 0)
    {_group, warm} = Compiled.step(warm, @sources, at: 1)

    fresh = compile(design(112))
    assert Compiled.carry(warm, fresh).forces == warm.forces
    refute fresh.forces == warm.forces

    # Another graph: the same nodes over other links' columns.
    {:ok, other} =
      Chart.compose([
        chart(),
        source(:nodes, [:id]),
        source(:edges, [:from, :to]),
        cartesian(margin: %{top: 0, right: 0, bottom: 0, left: 0}),
        circle(force(from(:edges), [:from, :to], nodes: :nodes), %{x: :x, y: :y})
      ])

    edges = Enum.map(@links, fn {s, t} -> %{from: s, to: t} end)
    other = compile(other, %{nodes: @nodes, edges: edges})
    assert Compiled.carry(warm, other).forces == other.forces
  end

  test "a realized frame lays out each graph once, and the two marks read that one layout" do
    frame = realized(design(100))
    assert map_size(frame.forces) == 1

    # A third mark over a different step is a second run.
    {:ok, three} =
      Chart.compose([
        chart(),
        source(:nodes, [:id]),
        source(:links, [:source, :target]),
        cartesian(margin: %{top: 0, right: 0, bottom: 0, left: 0}),
        path(force(from(:links), [:source, :target], nodes: :nodes, output: :links), %{
          path: :path
        }),
        circle(force(from(:links), [:source, :target], nodes: :nodes), %{x: :x, y: :y}),
        circle(force(from(:links), [:source, :target], nodes: :nodes, distance: 50), %{
          x: :x,
          y: :y
        })
      ])

    assert map_size(realized(three).forces) == 2
  end

  test "a node source's x and y seed the cold layout, as d3 honors a given position" do
    seeded = Enum.with_index(@nodes, fn node, i -> Map.merge(node, %{x: 50 * i, y: 20 * i}) end)
    sources = %{@sources | nodes: seeded}

    {:ok, applied} =
      Chart.apply(design(100, fields: [:id, :x, :y]), sources: sources, size: {600, 400})

    mark = Enum.find(applied.frame.marks, &(&1.type == :circle))
    rows = Mark.rows(applied.frame, mark, applied.sources)

    expected =
      Force.run(
        nodes: seeded,
        links: Enum.map(@links, fn {s, t} -> %{source: s, target: t} end),
        forces: [
          {:center, x: 300.0, y: 200.0},
          {:many_body, strength: -400},
          {:link, distance: 100}
        ]
      )

    assert Enum.map(rows, &{&1.id, &1.x, &1.y}) == Enum.map(expected.nodes, &{&1.id, &1.x, &1.y})
  end

  test "alpha and ticks are the step's keys, with their defaults and ranges" do
    assert %{default: 0.3, range: {0, 1, 0.05}, type: :number} = Schema.key(:transform, :alpha)
    assert %{default: 3, range: {1, 300, 1}, type: :integer} = Schema.key(:transform, :ticks)
    assert :alpha in Schema.transform_keys(:force).optional
    assert :ticks in Schema.transform_keys(:force).optional

    assert :ok = Validator.validate(design(100, alpha: 0.1, ticks: 10))
    assert {:error, errors} = Validator.validate(design(100, ticks: 2.5))
    assert Enum.any?(errors, &match?({_path, {:type, :integer}}, &1))

    # A livelier graph moves further per tick.
    calm = compile(design(100, alpha: 0.05, ticks: 1))
    lively = compile(design(100, alpha: 0.3, ticks: 20))
    {_g, calm2} = Compiled.step(calm, @sources, at: 0)
    {_g, lively2} = Compiled.step(lively, @sources, at: 0)
    assert moved(positions(calm), positions(calm2)) < moved(positions(lively), positions(lively2))
  end
end

defmodule Visualize.Chart.WarmForceRunsTest do
  # The shared run executes once per tick (spec/14 §5.4.3, D-132), counted by the BEAM's
  # own call counter on `Visualize.Layout.Force.run/1` — a global counter, so this module
  # runs alone.
  use ExUnit.Case, async: false

  import Visualize.Chart.Build

  alias Visualize.Chart
  alias Visualize.Chart.Compiled

  @mfa {Visualize.Layout.Force, :run, 1}

  setup do
    :erlang.trace_pattern(@mfa, true, [:call_count])
    on_exit(fn -> :erlang.trace_pattern(@mfa, false, [:call_count]) end)
  end

  defp runs(fun) do
    :erlang.trace_pattern(@mfa, :restart, [:call_count])
    result = fun.()
    {:call_count, n} = :erlang.trace_info(@mfa, :call_count)
    {n, result}
  end

  test "compiling a graph of two marks lays it out once, and each tick runs it once" do
    layout = [nodes: :nodes, strength: -400, distance: 100]

    {:ok, design} =
      Chart.compose([
        chart(),
        source(:nodes, [:id]),
        source(:links, [:source, :target]),
        cartesian(margin: %{top: 0, right: 0, bottom: 0, left: 0}),
        path(force(from(:links), [:source, :target], layout ++ [output: :links]), %{path: :path}),
        circle(force(from(:links), [:source, :target], layout), %{x: :x, y: :y})
      ])

    nodes = Enum.map(~w(a b c d), &%{id: &1})

    links = [
      %{source: "a", target: "b"},
      %{source: "b", target: "c"},
      %{source: "c", target: "d"}
    ]

    sources = %{nodes: nodes, links: links}

    {1, {:ok, %{main: compiled}}} = runs(fn -> Chart.compile(design, sources: sources) end)

    Enum.reduce(1..5, compiled, fn tick, compiled ->
      {n, {_group, compiled}} = runs(fn -> Compiled.step(compiled, sources, at: tick) end)
      assert n == 1
      {m, {_payload, compiled}} = runs(fn -> Compiled.tick(compiled, sources, at: tick) end)
      assert m == 1
      compiled
    end)
  end
end
