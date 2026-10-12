defmodule Visualize.Data.SchemaTest do
  @moduledoc """
  `Visualize.Data.Schema`, its cache and `Visualize.Data.Delivery` (spec/08 §10, #551,
  D-136): a feed's fields described by meaning, never colour; a version every node agrees
  on; a cache that asks a feed once; a delivery that is a source.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Visualize.Chart
  alias Visualize.Chart.Compiled
  alias Visualize.Data.{Delivery, Schema, Table}
  alias Visualize.Data.Schema.Cache

  doctest Schema
  doctest Cache
  doctest Delivery

  @full %{
    t: %{type: :time, label: "Time"},
    latency: %{
      type: :number,
      unit: "s",
      quantity: :duration,
      label: "Request time",
      polarity: :lower_is_better,
      target: 0.25,
      continuity: 60
    },
    route: %{type: :text, label: "Route"},
    state: %{
      type: :category,
      order: ["ok", "warn", "fail"],
      status: %{"ok" => :good, "warn" => :warning, "fail" => :bad}
    }
  }

  defp faults(fields) do
    {:error, errors} = Schema.new(fields)
    errors
  end

  describe "new/1: a description by meaning" do
    test "every key with a value it takes" do
      assert {:ok, %Schema{fields: @full}} = Schema.new(@full)
    end

    test "the twelve keys are the vocabulary" do
      assert Schema.attributes() ==
               [
                 :type,
                 :unit,
                 :quantity,
                 :label,
                 :order,
                 :status,
                 :polarity,
                 :target,
                 :continuity,
                 :window,
                 :metric_kind,
                 :bounds
               ]

      assert Map.keys(@full.latency) -- Schema.attributes() == []
    end

    test "a numeric field says its metric kind and its bounds (D-155)" do
      for kind <- [:gauge, :counter, :rate] do
        assert {:ok, _} = Schema.new(%{v: %{type: :number, quantity: :count, metric_kind: kind}})
      end

      for bounds <- [[0, nil], [nil, 100], [-5, 5], [0.0, 1.0], [nil, nil]] do
        assert {:ok, _} = Schema.new(%{v: %{type: :number, bounds: bounds}}), inspect(bounds)
      end

      assert faults(%{v: %{type: :number, metric_kind: :sum}}) ==
               [{[:v, :metric_kind], {:enum, [:gauge, :counter, :rate]}}]

      for bounds <- [[5, 0], [1, 1], [0], {0, 1}, ["0", 1], [0, 1, 2]] do
        assert faults(%{v: %{type: :number, bounds: bounds}}) == [
                 {[:v, :bounds], {:type, :bounds}}
               ],
               inspect(bounds)
      end

      assert faults(%{v: %{type: :category, metric_kind: :gauge, bounds: [0, 1]}}) == [
               {[:v, :bounds], {:invalid_for, :category}},
               {[:v, :metric_kind], {:invalid_for, :category}}
             ]

      assert Schema.format_error({[:v, :bounds], {:type, :bounds}}) =~ "[min, max]"
    end

    test "type is required and one of the four column types" do
      assert faults(%{v: %{unit: "s"}}) == [{[:v, :type], :required}]

      assert faults(%{v: %{type: :float}}) ==
               [{[:v, :type], {:enum, Chart.Schema.column_types()}}]
    end

    test "a colour key is refused, whatever its value, and says why" do
      for key <- [:color, :colour, :colors, :colours, :palette, :fill, :stroke] do
        assert faults(%{s: %{key => %{"ok" => :good}, :type => :category}}) ==
                 [{[:s, key], {:colour_key, key}}]
      end

      line = Schema.format_error({[:s, :colors], {:colour_key, :colors}})
      assert line =~ "s.colors"
      assert line =~ "never"
      assert line =~ "status"
      assert line =~ "theme"
    end

    test "a colour cannot hide in a status either: a role is an atom" do
      assert faults(%{s: %{type: :category, status: %{"fail" => {:palette, 5}}}}) ==
               [{[:s, :status], {:type, :status}}]

      assert faults(%{s: %{type: :category, status: %{"fail" => "#c00"}}}) ==
               [{[:s, :status], {:type, :status}}]
    end

    test "an unknown key is reported with the keys there are" do
      assert faults(%{v: %{type: :number, scale: 2}}) == [{[:v, :scale], :unknown_key}]
      assert Schema.format_error({[:v, :scale], :unknown_key}) =~ ":continuity"
    end

    test "a key the field's type does not take" do
      assert faults(%{v: %{type: :category, unit: "s", target: 1}}) ==
               [
                 {[:v, :target], {:invalid_for, :category}},
                 {[:v, :unit], {:invalid_for, :category}}
               ]

      assert faults(%{v: %{type: :number, order: [1, 2]}}) ==
               [{[:v, :order], {:invalid_for, :number}}]

      assert faults(%{v: %{type: :time, status: %{}, quantity: :duration}}) ==
               [
                 {[:v, :quantity], {:invalid_for, :time}},
                 {[:v, :status], {:invalid_for, :time}}
               ]
    end

    test "window names a clock: a boolean on a :time or :number field, one field at most (D-154)" do
      assert {:ok, _} = Schema.new(%{t: %{type: :number, window: true}, v: %{type: :number}})
      assert {:ok, _} = Schema.new(%{t: %{type: :time, window: true}})
      assert {:ok, _} = Schema.new(%{t: %{type: :time, window: false}})

      assert faults(%{s: %{type: :category, window: true}, x: %{type: :text, window: true}}) ==
               [
                 {[:s, :window], {:invalid_for, :category}},
                 {[:x, :window], {:invalid_for, :text}}
               ]

      assert faults(%{t: %{type: :number, window: :yes}}) == [{[:t, :window], {:type, :boolean}}]

      assert faults(%{a: %{type: :time, window: true}, b: %{type: :number, window: true}}) ==
               [{[:b, :window], {:duplicate_window, :a}}]

      assert Schema.format_error({[:b, :window], {:duplicate_window, :a}}) =~ "one field"
      assert Schema.format_error({[:t, :window], {:type, :boolean}}) =~ "true or false"
    end

    test "values of the wrong shape" do
      assert faults(%{v: %{type: :number, unit: ""}}) == [{[:v, :unit], {:type, :unit}}]
      assert faults(%{v: %{type: :number, unit: :s}}) == [{[:v, :unit], {:type, :unit}}]

      assert faults(%{v: %{type: :number, quantity: "duration"}}) == [
               {[:v, :quantity], {:type, :name}}
             ]

      assert faults(%{v: %{type: :number, quantity: nil}}) == [{[:v, :quantity], {:type, :name}}]
      assert faults(%{v: %{type: :number, label: :x}}) == [{[:v, :label], {:type, :string}}]
      assert faults(%{v: %{type: :number, target: "1"}}) == [{[:v, :target], {:type, :number}}]

      assert faults(%{v: %{type: :number, continuity: 0}}) == [
               {[:v, :continuity], {:type, :positive}}
             ]

      assert faults(%{v: %{type: :number, polarity: :up}}) ==
               [{[:v, :polarity], {:enum, [:higher_is_better, :lower_is_better, :neutral]}}]
    end

    test "any quantity atom and any role atom are carried until #536 and #533 fix their lists" do
      assert {:ok, _} = Schema.new(%{v: %{type: :number, quantity: :sheep_per_hour}})
      assert {:ok, _} = Schema.new(%{s: %{type: :category, status: %{"x" => :mauve}}})
    end

    test "an order is non-empty, of states, each once" do
      assert faults(%{s: %{type: :category, order: []}}) == [{[:s, :order], {:type, :order}}]
      assert faults(%{s: %{type: :category, order: [%{}]}}) == [{[:s, :order], {:type, :order}}]

      assert faults(%{s: %{type: :category, order: ["a", "b", "a", "b"]}}) ==
               [{[:s, :order, 2], :duplicate}, {[:s, :order, 3], :duplicate}]
    end

    test "a status names only states the order lists" do
      assert faults(%{
               s: %{type: :category, order: ["ok"], status: %{"ok" => :good, "down" => :bad}}
             }) == [{[:s, :status, "down"], :not_in_order}]

      assert {:ok, _} = Schema.new(%{s: %{type: :category, status: %{"down" => :bad}}})
    end

    test "field names: atoms or strings, each column once" do
      assert {:ok, _} = Schema.new(%{"v" => %{type: :number}, t: %{type: :time}})
      assert faults(%{1 => %{type: :number}}) == [{[1], {:type, :name}}]
      assert faults(%{"" => %{type: :number}}) == [{[""], {:type, :name}}]
      assert faults(%{nil => %{type: :number}}) == [{[nil], {:type, :name}}]

      assert faults(%{:v => %{type: :number}, "v" => %{type: :number}}) ==
               [{["v"], {:duplicate_field, :v}}]
    end

    test "a schema is a map of description maps" do
      assert Schema.new(v: %{type: :number}) == {:error, [{[], {:type, :schema}}]}
      assert faults(%{v: [type: :number]}) == [{[:v], {:type, :description}}]
    end

    test "every fault is reported, by path" do
      errors = faults(%{a: %{}, b: %{type: :number, fill: "#000"}})
      assert errors == [{[:a, :type], :required}, {[:b, :fill], {:colour_key, :fill}}]
    end

    test "new!/1 raises with every fault formatted" do
      error = assert_raise ArgumentError, fn -> Schema.new!(%{a: %{}, b: %{type: :x}}) end
      assert error.message =~ "a.type: is required"
      assert error.message =~ "b.type: must be one of :time"
    end

    test "every fault formats as a line" do
      for {path, reason} <- [
            {[], {:type, :schema}},
            {[1], {:type, :name}},
            {[:v], {:type, :description}},
            {[:v, :unit], {:type, :unit}},
            {[:v, :label], {:type, :string}},
            {[:v, :target], {:type, :number}},
            {[:v, :continuity], {:type, :positive}},
            {[:v, :order], {:type, :order}},
            {[:v, :status], {:type, :status}},
            {["v"], {:duplicate_field, :v}},
            {[:v, :order, 2], :duplicate},
            {[:v, :status, "down"], :not_in_order}
          ] do
        assert is_binary(Schema.format_error({path, reason}))
      end

      assert Schema.format_error({[:v, :order, 2], :duplicate}) == "v.order[2]: is listed twice"
    end
  end

  describe "fetch/2 and fetch/3" do
    test "by either spelling, never creating an atom" do
      schema = Schema.new!(%{"latency" => %{type: :number, unit: "ms"}, t: %{type: :time}})
      assert Schema.fetch(schema, :latency) == {:ok, %{type: :number, unit: "ms"}}
      assert Schema.fetch(schema, "t") == {:ok, %{type: :time}}
      assert Schema.fetch(schema, "never_an_atom_#{System.unique_integer([:positive])}") == :error
      assert Schema.fetch(schema, :latency, :unit) == {:ok, "ms"}
      assert Schema.fetch(schema, :latency, :label) == :error
      assert Schema.fetch(schema, :other, :unit) == :error
    end
  end

  describe "version/1: a content hash (spec/08 §10.2)" do
    test "is pinned: a change of encoding is a deliberate, visible change" do
      # visualize.schema/1\n m1: s1:v m1: a4:type a6:number — by hand, `sha256sum` agrees.
      assert Schema.version(Schema.new!(%{v: %{type: :number}})) ==
               "39b0c8eff6adfa6c6c9ada7fb3ee3a308675a1a5869afcd1ef1aca19378d0a81"

      assert Schema.version(Schema.new!(@full)) ==
               "b2c21496f503413d6d7aa558bcc08f67b5457078a494ab33d887fee31edbcb3f"
    end

    test "is the SHA-256 of the documented encoding" do
      bytes = "visualize.schema/1\nm1:s1:vm1:a4:typea6:number"

      assert Schema.version(Schema.new!(%{v: %{type: :number}})) ==
               Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
    end

    test "is the same whichever way a field name is spelled" do
      assert Schema.new!(%{v: %{type: :number}}).version ==
               Schema.new!(%{"v" => %{type: :number}}).version
    end

    property "is independent of the order the maps were built in" do
      entries = Enum.flat_map(@full, fn {name, d} -> Enum.map(d, &{name, &1}) end)

      check all(shuffled <- shuffled(entries)) do
        rebuilt =
          Enum.reduce(shuffled, %{}, fn {name, {k, v}}, acc ->
            v = if is_map(v), do: v |> Enum.shuffle() |> Map.new(), else: v
            Map.update(acc, name, %{k => v}, &Map.put(&1, k, v))
          end)

        assert Schema.new!(rebuilt).version == Schema.new!(@full).version
      end
    end

    test "changes with any change of content" do
      base = Schema.new!(@full).version

      variants = [
        put_in(@full, [:latency, :label], "Latency"),
        put_in(@full, [:latency, :unit], "ms"),
        put_in(@full, [:latency, :target], 0.3),
        put_in(@full, [:latency, :continuity], 60.0),
        put_in(@full, [:state, :order], ["ok", "fail", "warn"]),
        put_in(@full, [:state, :status, "warn"], :bad),
        Map.delete(@full, :route),
        put_in(@full, [:route, :type], :category),
        Map.put(@full, :route2, %{type: :text})
      ]

      versions = Enum.map(variants, &Schema.new!(&1).version)
      refute base in versions
      assert length(Enum.uniq(versions)) == length(variants)
    end

    test "a string state and the atom state are different values" do
      a = Schema.new!(%{s: %{type: :category, order: ["ok"]}})
      b = Schema.new!(%{s: %{type: :category, order: [:ok]}})
      refute a.version == b.version
    end

    defp shuffled(list), do: StreamData.map(StreamData.integer(), fn _ -> Enum.shuffle(list) end)
  end

  describe "Cache (spec/08 §10.3)" do
    setup do
      v1 = Schema.new!(%{v: %{type: :number, unit: "s"}})
      v2 = Schema.new!(%{v: %{type: :number, unit: "ms"}})
      %{v1: v1, v2: v2}
    end

    defp counting(answer) do
      test = self()

      fn feed ->
        send(test, {:described, feed})
        answer
      end
    end

    test "a cached version costs nothing: describe is not called", %{v1: v1} do
      cache = Cache.new([{:latency, v1}])

      assert {:ok, ^v1, ^cache} =
               Cache.resolve(cache, :latency, v1.version, counting({:error, :not_asked}))

      refute_received {:described, _}
    end

    test "an unknown version calls describe once, then is cached", %{v1: v1} do
      describe = counting({:ok, v1})
      {:ok, ^v1, cache} = Cache.resolve(Cache.new(), :latency, v1.version, describe)
      assert_received {:described, :latency}

      {:ok, ^v1, ^cache} = Cache.resolve(cache, :latency, v1.version, describe)
      refute_received {:described, _}
      assert Cache.fetch(cache, :latency, v1.version) == {:ok, v1}
    end

    test "the same version of another feed is another entry", %{v1: v1} do
      cache = Cache.new([{:latency, v1}])
      assert Cache.fetch(cache, :other, v1.version) == :error
    end

    test "describe answering another version is reported and its answer cached",
         %{v1: v1, v2: v2} do
      assert {:error, {:schema_version, :latency, v1_version, v2_version}, cache} =
               Cache.resolve(Cache.new(), :latency, v1.version, counting({:ok, v2}))

      assert {v1_version, v2_version} == {v1.version, v2.version}
      assert Cache.fetch(cache, :latency, v2.version) == {:ok, v2}
    end

    test "describe failing, and no describe at all", %{v1: v1} do
      cache = Cache.new()

      assert Cache.resolve(cache, :latency, v1.version, fn _ -> {:error, :down} end) ==
               {:error, {:describe, :latency, :down}, cache}

      assert Cache.resolve(cache, :latency, v1.version, nil) ==
               {:error, {:unknown_schema, :latency, v1.version}, cache}
    end

    test "put/3 keys a schema by its own version", %{v1: v1, v2: v2} do
      cache = Cache.new() |> Cache.put(:f, v1) |> Cache.put(:f, v2)
      assert Cache.fetch(cache, :f, v1.version) == {:ok, v1}
      assert Cache.fetch(cache, :f, v2.version) == {:ok, v2}
    end
  end

  describe "Delivery (spec/08 §10.4)" do
    @rows [%{t: 1, v: 10}, %{t: 2, v: 20}]

    test "Table.rows/1 reads a delivery over every inner shape" do
      assert Table.rows(Delivery.new(@rows)) === @rows
      assert Table.rows(Delivery.new(%{t: [1, 2], v: [10, 20]})) == @rows
      assert Table.rows(Delivery.new(t: [1, 2], v: [10, 20])) == @rows
      assert Table.rows(Delivery.new(Nx.tensor([1, 2]))) == [1, 2]

      assert Table.rows(Delivery.new(Explorer.DataFrame.new(t: [1], v: [2]))) == [
               %{"t" => 1, "v" => 2}
             ]

      assert Table.rows(Delivery.new([])) == []
    end

    test "new/2 takes the facts of an answer and checks them" do
      d =
        Delivery.new(@rows,
          window: [0, 10],
          resolution: :minute,
          capped: true,
          reduced_by: :feed,
          schema: "ab"
        )

      assert %Delivery{window: [0, 10], resolution: :minute, capped: true, reduced_by: :feed} = d
      assert d.schema == "ab"

      for bad <- [
            [window: [1]],
            [capped: :yes],
            [reduced_by: :host],
            [schema: :ab],
            [colour: "red"]
          ] do
        assert_raise ArgumentError, fn -> Delivery.new(@rows, bad) end
      end

      assert_raise ArgumentError, fn -> Delivery.new(Delivery.new(@rows)) end
    end

    test "source/1 is the carried source, any other as it is" do
      assert Delivery.source(Delivery.new(@rows)) === @rows
      assert Delivery.source(%{t: [1]}) == %{t: [1]}
    end

    @design %{
      version: 2,
      sources: %{primary: %{fields: [:t, :v]}},
      frames: %{
        main: %{
          kind: :cartesian,
          scales: %{x: %{kind: :linear}, y: %{kind: :linear}}
        }
      },
      marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v}}]
    }

    test "apply/2 binds a delivery as the source it carries" do
      delivery = Delivery.new(%{t: [1, 2], v: [3, 9]}, schema: "ab")
      {:ok, applied} = Chart.apply(@design, sources: %{primary: delivery})
      {:ok, plain} = Chart.apply(@design, sources: %{primary: %{t: [1, 2], v: [3, 9]}})

      assert applied.sources == %{primary: %{t: [1, 2], v: [3, 9]}}
      assert Chart.render(applied) == Chart.render(plain)

      assert Chart.apply(@design, sources: %{primary: Delivery.new(%{t: [1, 2]})}) ==
               {:error, [{[:sources, :primary], {:missing_field, :v}}]}
    end

    test "a compiled chart takes a delivery per slot, as it takes any source" do
      rows = [%{t: 1, v: 3}, %{t: 2, v: 9}]
      {:ok, %{main: compiled}} = Chart.compile(@design, sources: %{primary: Delivery.new(rows)})

      plain = %{primary: rows}
      delivered = %{primary: Delivery.new(rows, window: [1, 2])}

      assert Compiled.svg(compiled, delivered) == Compiled.svg(compiled, plain)
      assert Compiled.render(compiled, delivered) == Compiled.render(compiled, plain)

      assert elem(Compiled.tick(compiled, delivered, at: 0), 0) ==
               elem(Compiled.tick(compiled, plain, at: 0), 0)

      assert elem(Compiled.step(compiled, delivered, at: 0), 0) ==
               elem(Compiled.step(compiled, plain, at: 0), 0)
    end
  end
end
