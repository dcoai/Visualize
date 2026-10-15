defmodule Visualize.Chart.FactsTest do
  @moduledoc """
  A design's contract with its feed's schema (spec/14 §7.4, #552, D-136): a slot
  `requires` attributes, a design reads facts, `apply/2` checks one against the other and
  resolves the other, and a schema change recompiles a compiled chart (§12.1).
  """
  use ExUnit.Case, async: true

  import Visualize.Chart, only: [fact: 3]

  alias Visualize.Chart
  alias Visualize.Chart.{Compiled, Fact, Frame, Text, Validator}
  alias Visualize.Data.{Delivery, Schema}
  alias Visualize.Data.Schema.Cache

  doctest Fact

  # `t` counts readings, 1, 2, 3, on a linear `x`: a `:number`, the feed's window field —
  # not `:time`, which is instants (D-154).
  @latency %{
    t: %{type: :number, window: true},
    latency: %{type: :number, unit: "s", quantity: :duration, label: "Request time"},
    state: %{
      type: :category,
      order: ["ok", "warn", "fail"],
      status: %{"ok" => :good, "warn" => :warning, "fail" => :bad}
    }
  }

  @rows [
    %{t: 1, latency: 0.2, state: "warn"},
    %{t: 2, latency: 0.4, state: "ok"},
    %{t: 3, latency: 0.3, state: "fail"}
  ]

  defp design(extra \\ %{}) do
    Map.merge(
      %{
        version: 2,
        sources: %{
          primary: %{
            fields: [:t, :latency, :state],
            types: %{latency: :number, state: :category},
            requires: %{latency: [:unit, :label]}
          }
        },
        frames: %{
          main: %{
            kind: :cartesian,
            scales: %{
              x: %{kind: :linear},
              y: %{kind: :linear},
              color: %{kind: :ordinal, domain: fact(:primary, :state, :order)}
            },
            axes: [
              %{scale: :x, side: :bottom},
              %{scale: :y, side: :left, unit: fact(:primary, :latency, :unit)}
            ]
          }
        },
        marks: [
          %{
            type: :circle,
            data: :primary,
            channels: %{x: :t, y: :latency, series: :state}
          }
        ],
        labels: [
          %{
            anchor: {:axis, :y},
            text: "\#{fact(:primary, :latency, :label)} (\#{fact(:primary, :latency, :unit)})"
          }
        ]
      },
      extra
    )
  end

  defp schema(fields \\ @latency), do: Schema.new!(fields)

  defp delivery(schema, rows \\ @rows), do: Delivery.new(rows, schema: Schema.version(schema))

  defp counting(answer) do
    test = self()

    fn feed ->
      send(test, {:described, feed})
      answer
    end
  end

  defp apply_with(design, schema, opts \\ []) do
    Chart.apply(
      design,
      [sources: %{primary: delivery(schema)}, schemas: Cache.new([{:primary, schema}])] ++ opts
    )
  end

  describe "facts resolve from the bound schema" do
    test "an axis title from the field's label and unit, a tick unit and an ordinal domain" do
      {:ok, applied} = apply_with(design(), schema())

      assert [%{text: "Request time (s)"}] = applied.chart.labels
      assert Enum.at(applied.chart.frames.main.axes, 1).unit == "s"
      assert Frame.scale(applied.frame, :color).domain == ["ok", "warn", "fail"]
      assert Chart.render(applied) =~ "Request time (s)"
    end

    test "the applied chart carries the schema, the version and the cache" do
      s = schema()
      {:ok, applied} = apply_with(design(), s)

      assert applied.schemas == %{primary: s}
      assert applied.versions == %{primary: s.version}
      assert Cache.fetch(applied.cache, :primary, s.version) == {:ok, s}
    end

    test "the feed is the pool name the slot bound to, its own or its default" do
      s = schema()
      d = put_in(design(), [:sources, :primary, :default], :latency_feed)

      {:ok, applied} =
        Chart.apply(d,
          sources: %{latency_feed: delivery(s)},
          schemas: Cache.new([{:latency_feed, s}])
        )

      assert [%{text: "Request time (s)"}] = applied.chart.labels

      assert {:error, [{[:sources, :primary], {:unknown_schema, :latency_feed, _}}]} =
               Chart.apply(d,
                 sources: %{latency_feed: delivery(s)},
                 schemas: Cache.new([{:primary, s}])
               )
    end

    test "a fact holds a value the validator then types where it stood" do
      d =
        put_in(
          design(),
          [:frames, :main, :scales, :color, :domain],
          fact(:primary, :latency, :unit)
        )

      assert {:error, [{path, {:type, :extent}}]} = apply_with(d, schema())
      assert path == [:frames, :main, :scales, :color, :domain]
    end
  end

  describe "the cache" do
    test "a cached version costs nothing: describe is never called" do
      s = schema()
      {:ok, _} = apply_with(design(), s, describe: counting({:error, :not_asked}))
      refute_received {:described, _}
    end

    test "an unknown version is asked of the feed once, even for two slots" do
      s = schema()

      d =
        design()
        |> put_in([:sources, :secondary], %{
          fields: [:latency],
          default: :primary,
          requires: %{latency: [:unit]}
        })

      {:ok, applied} =
        Chart.apply(d, sources: %{primary: delivery(s)}, describe: counting({:ok, s}))

      assert_received {:described, :primary}
      refute_received {:described, _}
      assert applied.schemas == %{primary: s, secondary: s}
      assert Cache.fetch(applied.cache, :primary, s.version) == {:ok, s}
    end

    test "a slot that states no contract and that no scale reads does not resolve its version" do
      d = %{
        version: 2,
        sources: %{primary: %{fields: [:t, :latency]}, spare: %{fields: [:t]}},
        frames: %{main: %{kind: :cartesian, scales: %{x: %{kind: :linear}, y: %{kind: :linear}}}},
        marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :latency}}]
      }

      {:ok, applied} =
        Chart.apply(d,
          sources: %{primary: @rows, spare: Delivery.new(@rows, schema: "abc")},
          describe: counting({:error, :not_asked})
        )

      refute_received {:described, _}
      assert applied.schemas == %{}
      assert applied.versions == %{spare: "abc"}
    end

    # The type check (D-153) reads a schema nothing requires, and asks for it once: an
    # answer it cannot have is no fault.
    test "a slot that states no contract resolves its version for the type check alone" do
      d = %{
        version: 2,
        sources: %{primary: %{fields: [:t, :latency]}},
        frames: %{main: %{kind: :cartesian, scales: %{x: %{kind: :linear}, y: %{kind: :linear}}}},
        marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :latency}}]
      }

      {:ok, applied} =
        Chart.apply(d,
          sources: %{primary: Delivery.new(@rows, schema: "abc")},
          describe: counting({:error, :not_asked})
        )

      assert_received {:described, :primary}
      refute_received {:described, _}
      assert applied.schemas == %{}
      assert applied.versions == %{primary: "abc"}

      s = schema()

      {:ok, applied} =
        Chart.apply(d, sources: %{primary: delivery(s)}, describe: counting({:ok, s}))

      assert applied.schemas == %{primary: s}
    end
  end

  describe "the contract fails loudly, naming slot, field and attribute" do
    test "a required attribute the schema lacks" do
      s = schema(Map.update!(@latency, :latency, &Map.delete(&1, :unit)))

      d = Map.put(design(), :labels, [])
      d = put_in(d, [:frames, :main, :axes], [])

      assert apply_with(d, s) ==
               {:error,
                [
                  {[:sources, :primary, :requires, :latency],
                   {:missing_attribute, :primary, :latency, :unit}}
                ]}

      line =
        Validator.format(
          {[:sources, :primary, :requires, :latency],
           {:missing_attribute, :primary, :latency, :unit}}
        )

      assert line =~ "sources.primary.requires.latency"
      assert line =~ ":primary"
      assert line =~ ":latency"
      assert line =~ ":unit"
    end

    test "requiring identity is requiring it declared: false is not enough (D-167)" do
      d = put_in(design(), [:sources, :primary, :requires], %{state: [:identity]})
      declared = schema(put_in(@latency, [:state, :identity], true))

      assert {:ok, _applied} = apply_with(d, declared)

      for undeclared <- [@latency, put_in(@latency, [:state, :identity], false)] do
        assert apply_with(d, schema(undeclared)) ==
                 {:error,
                  [
                    {[:sources, :primary, :requires, :state],
                     {:missing_attribute, :primary, :state, :identity}}
                  ]}
      end
    end

    test "a fact of an attribute the schema lacks is reported where it stands" do
      s = schema(Map.update!(@latency, :state, &Map.delete(&1, :order)))
      d = design() |> put_in([:sources, :primary, :requires], %{})

      assert apply_with(d, s) ==
               {:error,
                [
                  {[:frames, :main, :scales, :color, :domain],
                   {:missing_attribute, :primary, :state, :order}}
                ]}
    end

    test "a field the schema does not describe gives none of its attributes" do
      s = schema(Map.delete(@latency, :latency))
      {:error, errors} = apply_with(design(), s)

      assert {[:labels, 0, :text], {:missing_attribute, :primary, :latency, :label}} in errors

      assert {[:sources, :primary, :requires, :latency],
              {:missing_attribute, :primary, :latency, :unit}} in errors
    end

    test "a declared type the schema contradicts" do
      s =
        schema(
          put_in(@latency, [:state, :type], :text)
          |> Map.update!(:state, &Map.drop(&1, [:order, :status]))
        )

      d = design() |> put_in([:frames, :main, :scales, :color, :domain], :auto)

      assert apply_with(d, s) ==
               {:error,
                [{[:sources, :primary, :types, :state], {:schema_type, :state, :category, :text}}]}
    end

    test "a slot that needs a schema and is given rows, or a delivery naming none" do
      for source <- [@rows, Delivery.new(@rows)] do
        assert Chart.apply(design(), sources: %{primary: source}) ==
                 {:error, [{[:sources, :primary], {:no_schema, :primary}}]}
      end
    end

    test "an unknown version, a failed describe, a describe of another version" do
      s = schema()
      other = schema(put_in(@latency, [:latency, :label], "Latency"))
      pool = %{primary: delivery(s)}

      assert Chart.apply(design(), sources: pool) ==
               {:error, [{[:sources, :primary], {:unknown_schema, :primary, s.version}}]}

      assert Chart.apply(design(), sources: pool, describe: fn _ -> {:error, :timeout} end) ==
               {:error, [{[:sources, :primary], {:describe, :primary, :timeout}}]}

      assert Chart.apply(design(), sources: pool, describe: fn _ -> {:ok, other} end) ==
               {:error,
                [{[:sources, :primary], {:schema_version, :primary, s.version, other.version}}]}
    end

    test "every contract fault has a line" do
      for reason <- [
            {:missing_attribute, :primary, :latency, :unit},
            {:schema_type, :state, :category, :text},
            {:no_schema, :primary},
            {:unknown_schema, :primary, "abc"},
            {:describe, :primary, :timeout},
            {:schema_version, :primary, "abc", "def"},
            {:undeclared_field, :primary, :x},
            {:type, :fact}
          ] do
        line = Validator.format({[:sources, :primary], reason})
        assert line =~ "sources.primary: "
        refute line =~ "%{"
      end
    end
  end

  describe "the design states its contract" do
    test "contract/1 is requires with every fact read, attributes in order" do
      assert Chart.contract(design()) ==
               %{primary: %{latency: [:unit, :label], state: [:order]}}

      assert Chart.contract(%{version: 2, frames: %{main: %{kind: :cartesian}}}) == %{}
      assert Chart.contract(%{sources: Chart.var(:sources)}) == %{}
    end

    test "requires names the slot's own fields and known attributes" do
      d = put_in(design(), [:sources, :primary, :requires], %{latency: [:color], other: [:unit]})
      {:error, errors} = Chart.from_map(d)

      assert {[:sources, :primary, :requires, :other], {:undeclared, :field, :other}} in errors

      assert {[:sources, :primary, :requires, :latency, 0], {:enum, Schema.attributes()}} in errors
    end

    test "a fact names a declared slot, one of its fields and an attribute" do
      bad = [
        {fact(:nope, :latency, :unit), {:undeclared, :source, :nope}},
        {fact(:primary, :nope, :unit), {:undeclared_field, :primary, :nope}},
        {fact(:primary, :latency, :color), {:enum, Schema.attributes()}}
      ]

      for {f, reason} <- bad do
        d = put_in(design(), [:frames, :main, :axes, Access.at(1), :unit], f)
        assert {:error, [{[:frames, :main, :axes, 1, :unit], ^reason}]} = Chart.from_map(d)
      end
    end

    test "a text cannot hold a list or a map: order and status are not words" do
      d = put_in(design(), [:labels, Access.at(0), :text], "\#{fact(:primary, :state, :order)}")
      assert {:error, [{[:labels, 0, :text], {:invalid_for, :text}}]} = Chart.from_map(d)
    end
  end

  describe "the text hole" do
    test "parses and unparses" do
      assert Text.parse("u: \#{fact(:primary, :latency, :unit)}") ==
               {:ok, ["u: ", %Fact{source: :primary, field: :latency, key: :unit}]}

      assert Text.unparse(["u: ", fact(:primary, :latency, :unit)]) ==
               "u: \#{fact(:primary, :latency, :unit)}"

      assert {:error, {:hole, _}} = Text.parse("\#{fact(:primary, :latency)}")
      assert {:error, {:hole, _}} = Text.parse("\#{fact(primary, latency, unit)}")
    end

    test "a variable resolved at application keeps the design's facts in its text" do
      d =
        design()
        |> Map.put(:vars, %{host: %{default: "web"}})
        |> put_in(
          [:labels, Access.at(0), :text],
          "\#{var(:host)}: \#{fact(:primary, :latency, :label)}"
        )

      {:ok, applied} = apply_with(d, schema())
      assert [%{text: "web: Request time"}] = applied.chart.labels
    end
  end

  describe "JSON" do
    test "a fact and requires round-trip" do
      {:ok, chart} = Chart.from_map(design())
      {:ok, json} = Chart.to_json(chart)
      assert json =~ ~s("$fact")
      assert Chart.from_json(json) == {:ok, chart}
    end
  end

  describe "a schema change recompiles (spec/14 §12.1)" do
    setup do
      v1 = schema()
      v2 = schema(put_in(@latency, [:latency, :label], "Latency"))
      cache = Cache.new([{:primary, v1}, {:primary, v2}])

      {:ok, %{main: compiled}} =
        Chart.compile(design(), sources: %{primary: delivery(v1)}, schemas: cache)

      %{v1: v1, v2: v2, cache: cache, compiled: compiled}
    end

    test "a delivery of the compiled version is current", %{v1: v1, compiled: compiled} do
      refute Compiled.stale?(compiled, %{primary: delivery(v1)})
      refute Compiled.stale?(compiled, %{primary: @rows})
      assert {_payload, _} = Compiled.tick(compiled, %{primary: delivery(v1)}, at: 0)
    end

    test "another version is stale, and a tick refuses it", %{v2: v2, compiled: compiled} do
      sources = %{primary: delivery(v2)}
      assert Compiled.stale?(compiled, sources)

      for draw <- [
            fn -> Compiled.tick(compiled, sources, at: 0) end,
            fn -> Compiled.step(compiled, sources, at: 0) end,
            fn -> Compiled.render(compiled, sources) end,
            fn -> Compiled.svg(compiled, sources) end
          ] do
        error = assert_raise ArgumentError, draw
        assert error.message =~ ":primary"
        assert error.message =~ "recompile"
      end
    end

    test "recompiling draws the new facts, carrying the state",
         %{v1: v1, v2: v2, cache: cache, compiled: compiled} do
      assert Compiled.static(compiled) =~ "Request time (s)"

      {:ok, %{main: fresh}} =
        Chart.compile(design(), sources: %{primary: delivery(v2)}, schemas: cache)

      fresh = Compiled.carry(compiled, fresh)
      assert Compiled.static(fresh) =~ "Latency (s)"
      refute Compiled.static(fresh) =~ "Request time"
      refute Compiled.stale?(fresh, %{primary: delivery(v2)})
      assert Compiled.stale?(fresh, %{primary: delivery(v1)})
    end
  end
end
