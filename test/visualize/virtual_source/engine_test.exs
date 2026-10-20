defmodule Visualize.VirtualSource.EngineTest do
  # The engine (spec/15 §14, D-194): defined, pulsed in rank order, faults kept local.
  # Every pulse is driven by the `now` the test passes: nothing waits on a clock.
  use ExUnit.Case, async: true

  @moduletag :capture_log

  alias Visualize.Data.{Delivery, Schema}
  alias Visualize.VirtualSource
  alias Visualize.VirtualSource.Engine

  doctest Visualize.VirtualSource.Engine

  @names ~w(hosts host cpu n a b c d sum total state health trend load x)a
  setup_all do
    {:ok, names: @names}
  end

  @hosts Schema.new!(%{
           t: %{type: :number, window: true},
           host: %{type: :category, identity: true},
           cpu: %{type: :number}
         })

  defp source(id, from, elixir, schema \\ %{n: %{type: :number}}, extra \\ []) do
    VirtualSource.new!([id: id, from: from, schema: schema, elixir: elixir] ++ extra)
  end

  defp rows(n), do: for(i <- 1..n, do: %{t: i, host: "h#{rem(i, 2)}", cpu: i * 10})

  defp push(engine, rows, now \\ 0),
    do: Engine.push(engine, %{hosts: Delivery.new(rows)}, %{hosts: @hosts}, now)

  defp count, do: "fn %{hosts: rows} -> [%{n: Enum.count(rows)}] end"

  describe "new/2: defining (spec/15 §14.1)" do
    test "every input resolves, and a host function is registered" do
      a = source(:a, [nowhere: nil], count())

      f =
        VirtualSource.new!(
          id: :f,
          from: [hosts: nil],
          schema: %{n: %{type: :number}},
          function: :f
        )

      assert {:error, errors} = Engine.new(%{["a"] => a, ["f"] => f}, feeds: [:hosts])

      assert errors == [
               {["a"], [:from, 0], {:unknown_input, "nowhere"}},
               {["f"], [:function], {:undeclared, :function, "f"}}
             ]
    end

    test "a cycle is refused, named, a source reading itself included" do
      a = source(:a, [b: nil], "fn %{b: r} -> r end")
      b = source(:b, [a: nil], "fn %{a: r} -> r end")
      c = source(:c, [c: nil], "fn %{c: r} -> r end")
      d = source(:d, [a: nil], "fn %{a: r} -> r end")

      assert {:error, errors} = Engine.new(%{["a"] => a, ["b"] => b, ["c"] => c, ["d"] => d})

      assert errors == [
               {["a"], [:from], {:cycle, [["a"], ["b"]]}},
               {["c"], [:from], {:cycle, [["c"]]}}
             ]
    end

    test "inputs resolve from the source's own scope, inside out, then to a feed" do
      outer = source(:sum, [hosts: nil], count())
      inner = source(:sum, [hosts: nil], "fn %{hosts: r} -> [%{n: 0 * Enum.count(r)}] end")
      reader = source(:total, [sum: nil], "fn %{sum: [%{n: n}]} -> [%{n: n}] end")

      sources = %{[:sum] => outer, [:cell, :sum] => inner, [:cell, :total] => reader}
      {:ok, engine} = Engine.new(sources, feeds: [:hosts])

      assert Engine.resolve(engine, [:cell], :sum) == {:source, ["cell", "sum"]}
      assert Engine.resolve(engine, [:other], :sum) == {:source, ["sum"]}
      assert Engine.resolve(engine, [:cell], :hosts) == {:feed, :hosts}
      assert Engine.resolve(engine, [:cell], :nothing) == :error

      engine = engine |> push(rows(3)) |> Engine.run(0)
      assert Engine.outputs(engine)[["cell", "total"]].rows == [%{"n" => 0}]
    end
  end

  describe "pulses (spec/15 §14.2)" do
    setup do
      # A diamond: a and b read the feed, c reads both, d reads c.
      a = source(:a, [hosts: nil], count())

      b =
        source(:b, [hosts: nil], "fn %{hosts: r} -> [%{n: Enum.sum(Enum.map(r, & &1.cpu))}] end")

      c = source(:c, [a: nil, b: nil], "fn %{a: [%{n: x}], b: [%{n: y}]} -> [%{n: x + y}] end")
      d = source(:d, [c: nil], "fn %{c: [%{n: n}]} -> [%{n: n * 2}] end")

      {:ok, engine} =
        Engine.new(%{["a"] => a, ["b"] => b, ["c"] => c, ["d"] => d},
          feeds: [:hosts],
          debounce: 100
        )

      {:ok, engine: engine}
    end

    test "rank order, each source at most once per pulse, no glitch", %{engine: engine} do
      engine = push(engine, rows(2), 0)
      assert Engine.due(engine) == 100

      # Not yet due: nothing runs.
      assert Engine.run(engine, 99) == engine

      engine = Engine.run(engine, 100)
      assert Engine.due(engine) == nil
      assert Engine.runs(engine) == %{["a"] => 1, ["b"] => 1, ["c"] => 1, ["d"] => 1}
      assert Engine.outputs(engine)[["c"]].rows == [%{"n" => 2 + 30}]
      assert Engine.outputs(engine)[["d"]].rows == [%{"n" => 64}]
      assert Engine.status(engine) |> Map.values() |> Enum.uniq() == [:live]
    end

    test "changes within the debounce are one pulse; an unchanged feed marks nothing", %{
      engine: engine
    } do
      engine = engine |> push(rows(2), 0) |> push(rows(3), 40) |> push(rows(4), 90)
      assert Engine.due(engine) == 100
      engine = Engine.run(engine, 100)
      assert Engine.runs(engine)[["c"]] == 1
      assert Engine.outputs(engine)[["a"]].rows == [%{"n" => 4}]

      same = push(engine, rows(4), 200)
      assert Engine.due(same) == nil
    end

    test "an answer that does not change marks no reader", %{engine: engine} do
      engine = engine |> push(rows(2), 0) |> Engine.run(100)
      # Same count and sum, other rows: a and b run, their answers are unchanged.
      swapped = [%{t: 1, host: "h1", cpu: 20}, %{t: 2, host: "h0", cpu: 10}]
      engine = engine |> push(swapped, 200) |> Engine.run(300)
      assert Engine.runs(engine) == %{["a"] => 2, ["b"] => 2, ["c"] => 1, ["d"] => 1}
    end

    test "a source waits while an input has no delivery" do
      a = source(:a, [hosts: nil], count())
      {:ok, engine} = Engine.new(%{["a"] => a}, feeds: [:hosts])
      engine = Engine.push(engine, %{}, %{}, 0) |> Engine.run(0)
      assert Engine.status(engine) == %{["a"] => :loading}
      assert Engine.runs(engine) == %{["a"] => 0}
    end
  end

  describe "names a stored function reads (spec/08 §10.5.6, D-195)" do
    test "a row's fields and category values are read as the function's own literals are" do
      checks = Schema.new!(%{day: %{type: :number}, state: %{type: :category}})

      # `:ok` is a word Elixir's functions take, so the row's `:ok` and the literal are one
      # atom; `:warning` is no word, so both are its string; `day` is a word, so the
      # function's `%{day: d}` matches the row's field, and `row.state` reads it by spelling.
      elixir = """
      fn %{checks: rows} ->
        [%{n: Enum.count(rows, fn %{day: d} = row -> d > 1 and row.state in [:ok, :warning] end)}]
      end
      """

      source = source(:a, [checks: nil], elixir)
      {:ok, engine} = Engine.new(%{["a"] => source}, feeds: [:checks], debounce: 0)

      rows = [
        %{day: 1, state: :ok},
        %{day: 2, state: :ok},
        %{day: 3, state: :warning},
        %{day: 4, state: :error}
      ]

      engine =
        engine
        |> Engine.push(%{checks: Delivery.new(rows)}, %{checks: checks}, 0)
        |> Engine.run(0)

      assert Engine.outputs(engine)[["a"]].rows == [%{"n" => 2}]
    end
  end

  describe "faults (spec/15 §14.3)" do
    defp chain(elixir) do
      a = source(:a, [hosts: nil], elixir)
      d = source(:d, [a: nil], "fn %{a: [%{n: n}]} -> [%{n: n + 1}] end")

      {:ok, engine} =
        Engine.new(%{["a"] => a, ["d"] => d}, feeds: [:hosts], timeout: 50, max_heap: 200_000)

      engine
    end

    test "a fault keeps the last good output and the pulse stops there" do
      a = "fn %{hosts: rows} -> [%{n: 10 / (Enum.count(rows) - 3)}] end"
      engine = chain(a) |> push(rows(2)) |> Engine.run(0)
      assert Engine.outputs(engine)[["a"]].rows == [%{"n" => -10.0}]
      assert Engine.outputs(engine)[["d"]].rows == [%{"n" => -9.0}]

      engine = engine |> push(rows(3)) |> Engine.run(0)
      assert Engine.faults(engine) == %{["a"] => %{kind: :raised, detail: ArithmeticError}}
      assert Engine.status(engine)[["a"]] == {:down, {:virtual_source, "a", :raised}}
      assert Engine.outputs(engine)[["a"]].rows == [%{"n" => -10.0}]
      assert Engine.runs(engine) == %{["a"] => 2, ["d"] => 1}

      # A good answer clears it.
      engine = engine |> push(rows(4)) |> Engine.run(0)
      assert Engine.faults(engine) == %{}
      assert Engine.outputs(engine)[["d"]].rows == [%{"n" => 11.0}]
    end

    test "the five kinds" do
      kinds = %{
        timeout:
          "fn _ -> Enum.reduce(1..100_000_000_000_000, 0, fn x, acc -> rem(acc + x, 7) end) end",
        memory: "fn _ -> Enum.to_list(1..100_000_000_000) end",
        raised: "fn _ -> Map.fetch!(%{}, :n) end",
        nonconforming: "fn _ -> [%{n: :none}] end",
        restricted: "fn %{hosts: rows} -> [%{n: Enum.count(rows, & &1.load)}] end"
      }

      for {kind, elixir} <- kinds do
        engine = chain(elixir) |> push(rows(2)) |> Engine.run(0)
        assert %{kind: ^kind} = Engine.faults(engine)[["a"]], "#{kind}"
        assert Engine.status(engine)[["d"]] == :loading
      end

      engine = chain(kinds.nonconforming) |> push(rows(2)) |> Engine.run(0)
      assert Engine.faults(engine)[["a"]].detail == {0, "n", {:type, :number}}

      engine = chain(kinds.restricted) |> push(rows(2)) |> Engine.run(0)

      assert [{[:elixir], {:check, 1, {:unknown_field, "load"}}}] =
               Engine.faults(engine)[["a"]].detail
    end
  end

  describe "per identity (spec/15 §14.4)" do
    defp health(elixir, window \\ nil) do
      health =
        source(
          :health,
          [hosts: window],
          elixir,
          %{
            host: %{type: :category, identity: true},
            state: %{type: :category, values: [:ok, :error]},
            n: %{type: :number}
          },
          per: :identity
        )

      {:ok, engine} = Engine.new(%{[:health] => health}, feeds: [:hosts])
      engine
    end

    test "once per entity, joined back by identity, in order of first appearance" do
      engine =
        health(
          "fn rows -> %{n: Enum.count(rows), state: if(Enum.count(rows) > 2, do: :error, else: :ok)} end"
        )
        |> push(rows(5))
        |> Engine.run(0)

      assert Engine.outputs(engine)[["health"]].rows == [
               %{"host" => "h1", "n" => 3, "state" => :error},
               %{"host" => "h0", "n" => 2, "state" => :ok}
             ]
    end

    test "a window of the last n rows is each entity's newest n" do
      engine =
        health("fn rows -> %{n: Enum.sum(Enum.map(rows, & &1.cpu))} end", %{last: 2})
        |> push(rows(5))
        |> Engine.run(0)

      # h1: cpu 10, 30, 50 → the newest two, 30 + 50; h0: 20 + 40. In the window h0 comes first.
      assert Engine.outputs(engine)[["health"]].rows == [
               %{"host" => "h0", "n" => 60},
               %{"host" => "h1", "n" => 80}
             ]
    end

    test "a row naming another entity does not conform" do
      engine = health(~S|fn _ -> %{host: "other"} end|) |> push(rows(2)) |> Engine.run(0)

      assert Engine.faults(engine)[["health"]] == %{
               kind: :nonconforming,
               detail: {0, "host", :identity}
             }
    end

    test "a box window is finished as the monitor finishes one" do
      engine =
        health("fn rows -> %{n: Enum.count(rows)} end", %{ranges: %{t: [2, 3]}})
        |> push(rows(5))
        |> Engine.run(0)

      assert Engine.outputs(engine)[["health"]].rows == [
               %{"host" => "h0", "n" => 1},
               %{"host" => "h1", "n" => 1}
             ]
    end
  end
end
