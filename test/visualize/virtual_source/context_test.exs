defmodule Visualize.VirtualSource.ContextTest do
  # A function of two arguments is given its context (spec/08 §10.5.6, spec/15 §14.2,
  # D-228): its inputs' schemas in wire form and their deliveries' facts, and its scope's
  # variables, which `Engine.vars/3` shows the engine and which mark only such sources.
  # Every pulse is driven by the `now` the test passes: nothing waits on a clock.
  use ExUnit.Case, async: true

  @moduletag :capture_log

  alias Visualize.Data.{Delivery, Schema}
  alias Visualize.VirtualSource
  alias Visualize.VirtualSource.Engine

  # Host functions that hand their context back to the test, which is the engine's owner
  # and so the bounded call's first caller.
  defmodule Sources do
    use Visualize.VirtualSources

    defsource seen(inputs, context) do
      [owner | _] = Process.get(:"$callers")
      send(owner, {:context, inputs, context})
      [%{n: 1}]
    end

    defsource rows_only(inputs) do
      [owner | _] = Process.get(:"$callers")
      send(owner, {:rows_only, inputs})
      [%{n: 1}]
    end

    defsource(secret(_inputs, context), do: [%{n: String.to_integer(context["vars"]["secret"])}])
  end

  @names ~w(hosts host cpu n state t bin_domain)a
  setup_all do
    {:ok, names: @names}
  end

  @hosts Schema.new!(%{
           t: %{type: :number, window: true},
           host: %{type: :category, identity: true},
           state: %{
             type: :category,
             values: [%{value: :ok, name: "OK", color: "#2e7d32"}, :down],
             status: %{ok: :good}
           },
           cpu: %{type: :number, bounds: [0, 100], continuity: 60}
         })

  @rows [%{t: 1, host: "a", state: :ok, cpu: 10}, %{t: 2, host: "b", state: :down, cpu: 20}]

  defp host(id, function, extra \\ []) do
    VirtualSource.new!(
      [id: id, from: [hosts: nil], schema: %{n: %{type: :number}}, function: function] ++ extra
    )
  end

  defp stored(id, elixir, extra \\ []) do
    VirtualSource.new!(
      [id: id, from: [hosts: nil], schema: %{n: %{type: :number}}, elixir: elixir] ++ extra
    )
  end

  defp engine(sources, opts \\ []) do
    {:ok, engine} =
      Engine.new(
        sources,
        [feeds: [:hosts], functions: Visualize.VirtualSources.registry([Sources])] ++ opts
      )

    engine
  end

  # The feed's answer at 0, with every fact a delivery carries.
  defp push(engine) do
    delivery = Delivery.new(@rows, window: [0, 10], resolution: 5, capped: true)
    Engine.push(engine, %{hosts: delivery}, %{hosts: @hosts}, 0)
  end

  describe "what a function is called with" do
    test "a function of one argument is called with its inputs alone, as before" do
      engine = engine(%{["a"] => host(:a, :rows_only)}) |> push() |> Engine.run(0)
      assert_received {:rows_only, %{"hosts" => @rows}}
      assert Engine.outputs(engine)[["a"]].rows == [%{"n" => 1}]
    end

    test "a host function of two arguments receives exactly the documented context" do
      engine(%{["a"] => host(:a, :seen)}, vars: %{[] => %{bin_domain: [0, 100]}})
      |> push()
      |> Engine.run(0)

      assert_received {:context, %{"hosts" => @rows}, context}

      assert context == %{
               "inputs" => %{
                 "hosts" => %{
                   "schema" => %{
                     "t" => %{"type" => :number, "window" => true},
                     "host" => %{"type" => :category, "identity" => true},
                     "state" => %{
                       "type" => :category,
                       "values" => [
                         %{"value" => :ok, "name" => "OK", "color" => "#2e7d32"},
                         :down
                       ],
                       "status" => %{ok: :good}
                     },
                     "cpu" => %{"type" => :number, "bounds" => [0, 100], "continuity" => 60}
                   },
                   "window" => [0, 10],
                   "resolution" => 5,
                   "capped" => true
                 }
               },
               "vars" => %{"bin_domain" => [0, 100]}
             }
    end

    test "a stored function reads its context's values as it reads its rows'" do
      # `"category"` is no word, so the schema's `:category` is its string; `:ok` is one, so
      # the entry's value is the atom a row's `:ok` is.
      elixir = ~S"""
      fn %{hosts: rows}, c ->
        hosts = c["inputs"]["hosts"]
        state = hosts["schema"]["state"]
        [entry | _] = state["values"]

        checks = [
          state["type"] == "category",
          entry["value"] == :ok and entry["name"] == "OK",
          Enum.at(state["values"], 1) == :down,
          hosts["schema"]["cpu"]["continuity"] == 60,
          hosts["window"] == [0, 10] and hosts["resolution"] == 5 and hosts["capped"],
          c["vars"]["bin_domain"] == [0, 100],
          c.vars.bin_domain == [0, 100],
          Enum.count(rows) == 2
        ]

        [%{n: Enum.count(checks, & &1)}]
      end
      """

      engine =
        engine(%{["a"] => stored(:a, elixir)}, vars: %{[] => %{"bin_domain" => [0, 100]}})
        |> push()
        |> Engine.run(0)

      assert Engine.faults(engine) == %{}
      assert Engine.outputs(engine)[["a"]].rows == [%{"n" => 8}]
    end

    test "a virtual source's output is a delivery with no facts, under its output's schema" do
      a = stored(:a, "fn %{hosts: rows} -> [%{n: Enum.count(rows)}] end")

      b =
        VirtualSource.new!(
          id: :b,
          from: [a: nil],
          schema: %{n: %{type: :number}},
          function: :seen
        )

      engine(%{["a"] => a, ["b"] => b}) |> push() |> Engine.run(0)

      assert_received {:context, %{"a" => [%{"n" => 2}]}, context}

      assert context == %{
               "inputs" => %{
                 "a" => %{
                   "schema" => %{"n" => %{"type" => :number}},
                   "window" => nil,
                   "resolution" => nil,
                   "capped" => false
                 }
               },
               "vars" => %{}
             }
    end

    test "per identity, every entity's call is given the same context" do
      source =
        VirtualSource.new!(
          id: :per,
          from: [hosts: nil],
          per: :identity,
          schema: %{host: %{type: :category, identity: true}, n: %{type: :number}},
          elixir: ~S|fn rows, c -> %{n: Enum.count(rows) + c["vars"]["bump"]} end|
        )

      engine =
        engine(%{["per"] => source}, vars: %{[] => %{"bump" => 10}}) |> push() |> Engine.run(0)

      assert Engine.outputs(engine)[["per"]].rows == [
               %{"host" => "a", "n" => 11},
               %{"host" => "b", "n" => 11}
             ]
    end
  end

  describe "Engine.vars/3: a variable marks the sources that take a context" do
    setup do
      count = "fn %{hosts: rows} -> [%{n: Enum.count(rows)}] end"
      with_x = ~S|fn %{hosts: rows}, c -> [%{n: Enum.count(rows) + c["vars"]["x"]}] end|

      sources = %{
        # The board's: one of two arguments, one of one.
        ["board_ctx"] => stored(:board_ctx, with_x),
        ["board_rows"] => stored(:board_rows, count),
        # A cell that sees the board's `x`, and one that overrides it.
        ["c1", "ctx"] => stored(:ctx, with_x),
        ["c2", "ctx"] => stored(:ctx, with_x)
      }

      engine =
        sources
        |> engine(vars: %{[] => %{"x" => 1}, ["c2"] => %{"x" => 5}}, debounce: 100)
        |> push()
        |> Engine.run(100)

      %{engine: engine}
    end

    test "the cascade at each source's scope: the board's, the cell's over it", %{
      engine: engine
    } do
      outputs = Engine.outputs(engine)
      assert outputs[["board_ctx"]].rows == [%{"n" => 3}]
      assert outputs[["c1", "ctx"]].rows == [%{"n" => 3}]
      assert outputs[["c2", "ctx"]].rows == [%{"n" => 7}]
    end

    test "a board variable marks the board's and every cell's that does not override it", %{
      engine: engine
    } do
      engine = Engine.vars(engine, %{[] => %{"x" => 2}}, 200)
      assert Engine.due(engine) == 300

      engine = Engine.run(engine, 300)

      assert Engine.runs(engine) == %{
               ["board_ctx"] => 2,
               ["board_rows"] => 1,
               ["c1", "ctx"] => 2,
               ["c2", "ctx"] => 1
             }

      assert Engine.outputs(engine)[["c1", "ctx"]].rows == [%{"n" => 4}]
      assert Engine.outputs(engine)[["c2", "ctx"]].rows == [%{"n" => 7}]
    end

    test "a cell variable marks only its own cell's", %{engine: engine} do
      engine = engine |> Engine.vars(%{["c2"] => %{"x" => 6}}, 200) |> Engine.run(300)

      assert Engine.runs(engine) == %{
               ["board_ctx"] => 1,
               ["board_rows"] => 1,
               ["c1", "ctx"] => 1,
               ["c2", "ctx"] => 2
             }

      assert Engine.outputs(engine)[["c2", "ctx"]].rows == [%{"n" => 8}]
    end

    test "unchanged variables mark nothing; a source of one argument never", %{engine: engine} do
      engine = Engine.vars(engine, %{[] => %{"x" => 1}, ["c2"] => %{x: 5}}, 200)
      assert Engine.due(engine) == nil

      # A new board variable changes every scope's cascade: each context-taking source runs.
      engine = engine |> Engine.vars(%{[] => %{"x" => 1, "y" => 0}}, 200) |> Engine.run(300)

      assert Engine.runs(engine) == %{
               ["board_ctx"] => 2,
               ["board_rows"] => 1,
               ["c1", "ctx"] => 2,
               ["c2", "ctx"] => 2
             }
    end
  end

  describe "in context: a literal read of a variable the scope does not declare" do
    test "faults once the scope's variables are known, and runs once it declares it" do
      source = stored(:a, ~S'fn _inputs, c -> [%{n: c["vars"]["limit"] || 0}] end')

      # Unknown variables: nothing to check against.
      engine = engine(%{["a"] => source}) |> push() |> Engine.run(0)
      assert Engine.outputs(engine)[["a"]].rows == [%{"n" => 0}]

      engine = engine |> Engine.vars(%{[] => %{"x" => 1}}, 0) |> Engine.run(0)

      assert Engine.faults(engine) == %{
               ["a"] => %{
                 kind: :restricted,
                 detail: [{[:elixir], {:check, 1, {:unknown_var, "limit"}}}]
               }
             }

      # Declared: checked again, and it runs.
      engine = engine |> Engine.vars(%{[] => %{"limit" => 9}}, 0) |> Engine.run(0)
      assert Engine.faults(engine) == %{}
      assert Engine.outputs(engine)[["a"]].rows == [%{"n" => 9}]
    end

    test "a dynamic read is not checked" do
      elixir = ~S"""
      fn _inputs, c -> [%{n: c["vars"][Enum.at(Map.keys(c["vars"]), 0)]}] end
      """

      engine =
        engine(%{["a"] => stored(:a, elixir)}, vars: %{[] => %{"x" => 4}})
        |> push()
        |> Engine.run(0)

      assert Engine.faults(engine) == %{}
      assert Engine.outputs(engine)[["a"]].rows == [%{"n" => 4}]
    end
  end

  describe "faults (spec/15 §14.3)" do
    test "a fault's detail carries no value of the context" do
      sources = %{
        ["raised"] => host(:raised, :secret),
        ["nonconforming"] =>
          stored(:nonconforming, ~S|fn _i, c -> [%{n: c["vars"]["secret"]}] end|)
      }

      engine =
        engine(sources, vars: %{[] => %{"secret" => "s3cr3t"}}) |> push() |> Engine.run(0)

      assert Engine.faults(engine) == %{
               ["raised"] => %{kind: :raised, detail: ArgumentError},
               ["nonconforming"] => %{kind: :nonconforming, detail: {0, "n", {:type, :number}}}
             }

      refute inspect(Engine.faults(engine)) =~ "s3cr3t"
    end

    test "a call of two arguments is bounded by its reductions" do
      runaway =
        "fn _i, c -> Enum.reduce(1..100_000_000_000_000, 0, fn x, acc -> rem(acc + x, c[\"vars\"][\"m\"]) end) end"

      engine =
        engine(%{["a"] => stored(:a, runaway)},
          vars: %{[] => %{"m" => 7}},
          max_reductions: 1_000_000
        )
        |> push()
        |> Engine.run(0)

      assert Engine.faults(engine) == %{["a"] => %{kind: :reductions, detail: 1_000_000}}
    end
  end
end
