defmodule Visualize.BoardTest do
  @moduledoc """
  The board as a value (spec/15, D-141): its map and JSON forms under the version policy
  and limits of spec/14 §9.1–9.2, its validation alone and given a store, its required
  sources namespaced per cell, its layout and reflow, its variables' cascade and
  `realize/4`.
  """
  use ExUnit.Case, async: true

  import Visualize.Chart, only: [var: 1]

  alias Visualize.Board
  alias Visualize.Board.Binding
  alias Visualize.Chart.Composite
  alias Visualize.Data.{Delivery, Schema}

  doctest Visualize.Board

  # A line of a feed's latency: a slot that requires a unit, a title read from a
  # variable, and an axis title read as a fact.
  @line %{
    version: 2,
    sources: %{
      primary: %{
        fields: [:t, :v],
        types: %{t: :number, v: :number},
        requires: %{v: [:unit]}
      }
    },
    vars: %{title: %{default: "Latency"}, service: %{default: "api"}},
    frames: %{
      main: %{kind: :cartesian, scales: %{x: %{kind: :linear}, y: %{kind: :linear}}}
    },
    marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v}}],
    labels: [
      %{anchor: :title, text: "\#{var(:title)} for \#{var(:service)}"},
      %{anchor: {:axis, :y}, text: "\#{fact(:primary, :v, :label)}"}
    ]
  }

  # A polar gauge: no group can sync it (spec/14 §2.9).
  @gauge %{
    version: 2,
    sources: %{reading: %{fields: [:n, :v]}},
    frames: %{
      main: %{kind: :polar, scales: %{angle: %{kind: :radial}, r: %{kind: :sqrt}}}
    },
    marks: [%{type: :rose, data: :reading, channels: %{angle: :n, value: :v}}]
  }

  # The line stored as structure — a composite of its sites — and the gauge stored flat,
  # as an imported design is: a component may be either (spec/15 §1.3).
  defp store do
    {uses, _labels} = Composite.decompose(@line)

    %{
      {:composite, 1} => %{composite: %{uses: uses, vars: %{}}},
      {:composite, 2} => @gauge,
      {:composite, 3} => %{
        composite: %{uses: [%Visualize.Chart.Use{id: {:use, 1}, ref: {:composite, 3}}], vars: %{}}
      },
      {:composite, 4} => %{
        composite: %{
          uses: [%Visualize.Chart.Use{id: {:use, 1}, ref: nil, local: %{theme: :dark}}],
          vars: %{}
        }
      }
    }
  end

  defp board(extra \\ %{}) do
    Map.merge(
      %{
        meta: %{name: "API", description: "The API at a glance"},
        cells: %{
          latency: %{x: 0, y: 0, w: 8, h: 4, ref: {:composite, 1}, title: "Latency"},
          eu: %{x: 0, y: 4, w: 8, h: 4, ref: {:composite, 1}, vars: %{service: "api-eu"}},
          gauge: %{x: 8, y: 0, w: 4, h: 4, ref: {:composite, 2}, sync: false}
        },
        window: %{last: 3600},
        zone: "Etc/UTC",
        vars: %{service: "api-us", region: "us"},
        sync: "api",
        layout: %{breakpoint: 640}
      },
      extra
    )
  end

  defp schema,
    do:
      Schema.new!(%{t: %{type: :number}, v: %{type: :number, unit: "ms", label: "Request time"}})

  describe "the map form" do
    test "reads a board, fills the defaults, and is the inverse of to_map/1" do
      {:ok, board} = Board.from_map(board())

      assert board.version == Visualize.Chart.Migration.current()
      assert board.sync == "api"
      assert Board.from_map(Board.to_map(board)) == {:ok, board}

      {:ok, empty} = Board.from_map(%{})
      assert empty == %Board{}
      assert Board.layout(empty) == %{breakpoint: 768, row_height: 80, gap: 8}
    end

    test "a newer board is refused by name before anything else is read" do
      bad = board(%{version: 4, cells: :not_a_map, oops: 1})
      assert Board.from_map(bad) == {:error, [{[:version], {:newer_schema, 4, 3}}]}
    end

    test "boards begin at schema version 2" do
      assert Board.from_map(%{version: 1}) == {:error, [{[:version], {:unsupported_version, 1}}]}
      assert Board.from_map(%{version: "2"}) == {:error, [{[:version], {:type, :integer}}]}
    end

    test "the structural limits apply before validation, and a host may tighten them" do
      cells =
        Map.new(1..6, fn i ->
          {:"c#{i}", %{x: 0, y: i * 2, w: 1, h: 1, ref: {:composite, 1}}}
        end)

      assert {:ok, _} = Board.from_map(%{cells: cells})

      assert Board.from_map(%{cells: cells}, limits: [items: 5]) ==
               {:error, [{[:cells], {:limit, :items, 5, 6}}]}

      assert {:error, [{[:cells, :c1], {:limit, :depth, 2, 3}} | _]} =
               Board.from_map(%{cells: cells}, limits: [depth: 2])
    end

    test "from_map!/2 raises with the faults worded" do
      assert_raise ArgumentError, ~r/cells\.a: runs past the board's 12 columns/, fn ->
        Board.from_map!(%{cells: %{a: %{x: 10, y: 0, w: 4, h: 1, ref: {:composite, 1}}}})
      end
    end
  end

  describe "the JSON form" do
    test "round-trips a board, stamped $version, with ids, times and atoms tagged" do
      {:ok, board} =
        Board.from_map(
          board(%{
            window: %{from: ~U[2026-10-11 10:00:00Z], to: ~U[2026-10-11 12:00:00Z]},
            vars: %{service: "api-us", level: :warning, limits: [1, 2.5]}
          })
        )

      {:ok, json} = Board.to_json(board)
      decoded = Jason.decode!(json)

      assert decoded["$version"] == Visualize.Chart.Migration.current()
      refute Map.has_key?(decoded, "version")
      assert decoded["cells"]["latency"]["ref"] == %{"$id" => ["composite", 1]}
      assert decoded["window"]["from"] == %{"$time" => "2026-10-11T10:00:00Z"}
      assert decoded["vars"]["level"] == %{"$atom" => "warning"}

      assert Board.from_json(json) == {:ok, board}
    end

    test "a newer stamp is refused before a key is decoded" do
      json = ~s({"$version": 4, "cells": {"never_made_atom_board_x1": {"x": 0}}})

      assert Board.from_json(json) == {:error, [{["$version"], {:newer_schema, 4, 3}}]}
      assert_raise ArgumentError, fn -> String.to_existing_atom("never_made_atom_board_x1") end
    end

    test "the limits apply to the parsed document, by its own key strings" do
      json = ~s({"$version": 2, "vars": {"a": 1, "b": 2, "c": 3}})

      assert Board.from_json(json, limits: [items: 2]) ==
               {:error, [{["vars"], {:limit, :items, 2, 3}}]}
    end

    test "an unstamped document reads as the current version" do
      assert {:ok, %Board{version: 3}} = Board.from_json(~s({"cells": {}}))
    end

    test "an unknown key stays a string and is reported at its own spelling" do
      assert Board.from_json(~s({"$version": 2, "never_made_atom_board_x2": 1})) ==
               {:error, [{["never_made_atom_board_x2"], :unknown_key}]}

      assert_raise ArgumentError, fn -> String.to_existing_atom("never_made_atom_board_x2") end
    end

    test "text that is not a JSON object is a :json fault" do
      assert {:error, [{[], {:json, _}}]} = Board.from_json("{")
      assert {:error, [{[], {:json, "a board is an object, got [1]"}}]} = Board.from_json("[1]")
    end
  end

  describe "validation alone" do
    test "cells off the grid, overlapping, and of the wrong shape" do
      cells = %{
        a: %{x: 0, y: 0, w: 6, h: 2, ref: {:composite, 1}},
        b: %{x: 4, y: 1, w: 6, h: 2, ref: {:composite, 1}},
        c: %{x: 5, y: 0, w: 2, h: 4, ref: {:composite, 1}},
        d: %{x: 9, y: 9, w: 4, h: 1, ref: {:composite, 1}},
        e: %{x: -1, y: 0, w: 0, ref: {:composite, 0}, sync: "yes", color: "red"}
      }

      assert Board.validate(%{cells: cells}) ==
               {:error,
                [
                  {[:cells, :b], {:overlap, :a}},
                  {[:cells, :c], {:overlap, :a}},
                  {[:cells, :c], {:overlap, :b}},
                  {[:cells, :d], {:off_grid, 12}},
                  {[:cells, :e, :color], :unknown_key},
                  {[:cells, :e, :h], :required},
                  {[:cells, :e, :ref], {:type, {:id, :composite}}},
                  {[:cells, :e, :sync], {:type, :boolean}},
                  {[:cells, :e, :w], {:type, :pos_integer}},
                  {[:cells, :e, :x], {:type, :non_neg_integer}}
                ]}
    end

    test "cells that touch do not overlap" do
      assert :ok =
               Board.validate(%{
                 cells: %{
                   a: %{x: 0, y: 0, w: 6, h: 2, ref: {:composite, 1}},
                   b: %{x: 6, y: 0, w: 6, h: 2, ref: {:composite, 1}},
                   c: %{x: 0, y: 2, w: 12, h: 1, ref: {:composite, 1}}
                 }
               })
    end

    test "a component reference of another kind is refused by its tag" do
      assert Board.validate(%{cells: %{a: %{x: 0, y: 0, w: 1, h: 1, ref: {:style, 3}}}}) ==
               {:error, [{[:cells, :a, :ref], {:ref_kind, :composite, :style}}]}
    end

    test "the window: one of the two forms, in UTC, from before to" do
      faults = fn window -> Board.validate(%{window: window}) end

      assert faults.(nil) == :ok
      assert faults.(%{last: 90.5}) == :ok
      assert faults.(%{last: 0}) == {:error, [{[:window, :last], {:type, :positive}}]}

      assert faults.(%{last: 60, from: ~U[2026-10-11 10:00:00Z]}) ==
               {:error, [{[:window], {:window, :both}}]}

      assert faults.(%{from: ~U[2026-10-11 10:00:00Z]}) == {:error, [{[:window, :to], :required}]}

      assert faults.(%{from: ~U[2026-10-11 12:00:00Z], to: ~U[2026-10-11 10:00:00Z]}) ==
               {:error, [{[:window], {:window, :inverted}}]}

      assert faults.(%{from: ~N[2026-10-11 10:00:00], to: ~U[2026-10-11 12:00:00Z]}) ==
               {:error, [{[:window, :from], {:type, :utc_datetime}}]}

      assert faults.(%{}) == {:error, [{[:window], {:type, :window}}]}
    end

    test "the zone, the variables, the group, the meta and the layout" do
      assert {:error, [{[:zone], {:zone, "Mars/Olympus", _}}]} =
               Board.validate(%{zone: "Mars/Olympus"})

      assert Board.validate(%{
               vars: %{:a => var(:b), "s" => 1},
               sync: "",
               meta: %{name: :api, owner: "me"},
               layout: %{gap: -1, row_height: 0, columns: 24}
             }) ==
               {:error,
                [
                  {[:layout, :columns], :unknown_key},
                  {[:layout, :gap], {:type, :non_neg_integer}},
                  {[:layout, :row_height], {:type, :pos_integer}},
                  {[:meta, :name], {:type, :string}},
                  {[:meta, :owner], :unknown_key},
                  {[:sync], {:type, :string}},
                  {[:vars, :a], {:var_binding, :a}},
                  {[:vars, "s"], {:type, :name}}
                ]}
    end

    test "the grid is not generalized: columns is not a key" do
      assert Board.validate(%{columns: 24}) == {:error, [{[:columns], :unknown_key}]}
      assert Board.columns() == 12
    end

    test "a board's faults read as a person reads them" do
      assert Board.format_error({[:cells, :d], {:off_grid, 12}}) ==
               "cells.d: runs past the board's 12 columns"

      assert Board.format_error({[:window], {:window, :inverted}}) ==
               "window: has a from that is not before its to"

      assert Board.format_error({[:cells, :a, :ref], {:dangling, {:composite, 9}}}) ==
               "cells.a.ref: refers to {:composite, 9}, which the store does not hold"
    end
  end

  describe "validation given a store" do
    test "a valid board, its components resolved from structure and from a flat design" do
      assert Board.validate(Board.from_map!(board()), store()) == :ok
      assert Board.validate(board(), &Map.fetch(store(), &1)) == :ok
    end

    test "dangling refs, cycles, components that are not designs, undeclared vars, unsyncable cells" do
      cells = %{
        dangling: %{x: 0, y: 0, w: 2, h: 1, ref: {:composite, 99}},
        loop: %{x: 2, y: 0, w: 2, h: 1, ref: {:composite, 3}},
        partial: %{x: 4, y: 0, w: 2, h: 1, ref: {:composite, 4}},
        stranger: %{x: 6, y: 0, w: 2, h: 1, ref: {:composite, 1}, vars: %{color: "red"}},
        dial: %{x: 8, y: 0, w: 2, h: 1, ref: {:composite, 2}}
      }

      assert {:error, errors} = Board.validate(%{cells: cells, sync: "api"}, store())

      assert {[:cells, :dangling, :ref], {:dangling, {:composite, 99}}} in errors

      assert {[:cells, :loop, :ref], {:cycle, [{:composite, 3}, {:composite, 3}]}} in errors

      assert {[:cells, :partial, :ref, :frames], :required} in errors
      assert {[:cells, :stranger, :vars, :color], {:undeclared, :var, :color}} in errors
      assert {[:cells, :dial, :sync], {:sync, :frame_kind, :polar}} in errors
    end

    test "a store's v1 design migrates where the board reads it" do
      v1 = @gauge |> Map.delete(:frames) |> Map.merge(%{version: 1, frame: @gauge.frames.main})
      board = %{cells: %{dial: %{x: 0, y: 0, w: 4, h: 4, ref: {:composite, 7}}}}

      assert Board.validate(board, %{{:composite, 7} => v1}) == :ok

      assert {:ok, %{{:dial, :reading} => %{fields: [:n, :v]}}} =
               Board.required_sources(Board.from_map!(board), %{{:composite, 7} => v1})
    end

    test "components are read under the board reader's limits" do
      assert {:error, errors} = Board.validate(board(), store(), limits: [items: 2])
      assert {[:cells, :latency, :ref, :marks, 0], {:limit, :items, 2, 3}} in errors
    end

    test "a board variable no component declares is not a fault" do
      assert Board.validate(board(%{vars: %{nobody: 1}}), store()) == :ok
    end
  end

  describe "required sources" do
    test "the aggregate of the cells' slots, namespaced per cell, with each contract and reads" do
      {:ok, required} = Board.required_sources(Board.from_map!(board()), store())

      line = %{
        fields: [:t, :v],
        types: %{t: :number, v: :number},
        requires: %{v: [:unit, :label]},
        reads: [
          {[:marks, 0, :channels, :x], :t, :number},
          {[:marks, 0, :channels, :y], :v, :number}
        ]
      }

      gauge = %{
        fields: [:n, :v],
        types: %{},
        requires: %{},
        reads: [
          {[:marks, 0, :channels, :angle], :n, :number},
          {[:marks, 0, :channels, :value], :v, :number}
        ]
      }

      assert required == %{
               {:latency, :primary} => line,
               {:eu, :primary} => line,
               {:gauge, :reading} => gauge
             }
    end

    test "one design in two cells is bound to different data" do
      board = Board.from_map!(board())
      {:ok, required} = Board.required_sources(board, store())

      binding =
        Binding.new(%{
          {:latency, :primary} => :us,
          {:eu, :primary} => :eu,
          {:gauge, :reading} => :cpu
        })

      assert Binding.check(binding, required, %{us: schema(), eu: schema()}) == :ok

      us = Delivery.new([%{t: 1, v: 10}, %{t: 2, v: 20}], schema: Schema.version(schema()))
      eu = Delivery.new([%{t: 1, v: 300}, %{t: 2, v: 400}], schema: Schema.version(schema()))
      pools = Binding.pools(binding, %{us: us, eu: eu, cpu: [%{n: 1, v: 0.5}]})

      {:ok, applied, _cache} =
        Board.realize(board, store(), pools, schemas: Schema.Cache.new([{:primary, schema()}]))

      assert Visualize.Chart.Frame.scale(applied.latency.frame, :y).domain == [10, 20]
      assert Visualize.Chart.Frame.scale(applied.eu.frame, :y).domain == [300, 400]
    end

    test "a component that cannot be read is the fault" do
      board = Board.from_map!(%{cells: %{a: %{x: 0, y: 0, w: 1, h: 1, ref: {:composite, 99}}}})

      assert Board.required_sources(board, store()) ==
               {:error, [{[:cells, :a, :ref], {:dangling, {:composite, 99}}}]}
    end
  end

  describe "layout" do
    test "at or above the breakpoint every cell is where it was placed, in reading order" do
      board = Board.from_map!(board())

      assert Board.arrange(board, 640) == [
               latency: %{x: 0, y: 0, w: 8, h: 4},
               gauge: %{x: 8, y: 0, w: 4, h: 4},
               eu: %{x: 0, y: 4, w: 8, h: 4}
             ]
    end

    test "below it the cells stack full width in reading order, keeping their heights" do
      board =
        Board.from_map!(
          board(%{
            cells: Map.put(board().cells, :tall, %{x: 8, y: 4, w: 4, h: 6, ref: {:composite, 2}})
          })
        )

      assert Board.arrange(board, 639) == [
               latency: %{x: 0, y: 0, w: 12, h: 4},
               gauge: %{x: 0, y: 4, w: 12, h: 4},
               eu: %{x: 0, y: 8, w: 12, h: 4},
               tall: %{x: 0, y: 12, w: 12, h: 6}
             ]
    end

    test "boxes are a CSS grid's arithmetic, after reflow" do
      board = Board.from_map!(board(%{layout: %{breakpoint: 640, gap: 10, row_height: 50}}))
      # (1210 - 11 × 10) / 12 = 91.666… per column.
      boxes = Board.boxes(board, 1210)
      {x, y, w, h} = boxes.gauge

      assert_in_delta x, 8 * (1100 / 12 + 10), 1.0e-9
      assert y == 0
      assert_in_delta w, 4 * (1100 / 12) + 30, 1.0e-9
      assert h == 4 * 50 + 30
      assert boxes.eu == {0.0, 4 * 60, 8 * (1100 / 12) + 70, 230}

      narrow = Board.boxes(board, 400)
      assert narrow.eu == {0.0, 8 * 60, 400.0, 230}
    end
  end

  describe "shared state" do
    test "the window resolves at the board's now, in UTC" do
      now = DateTime.new!(~D[2026-10-11], ~T[14:00:00], "Etc/UTC")

      assert Board.window(Board.from_map!(%{window: %{last: 90.5}}), now) ==
               {DateTime.add(now, -90_500_000, :microsecond), now}

      fixed = %{from: ~U[2026-10-11 10:00:00Z], to: ~U[2026-10-11 12:00:00Z]}
      assert Board.window(Board.from_map!(%{window: fixed}), now) == {fixed.from, fixed.to}
      assert Board.window(Board.from_map!(%{}), now) == nil
    end

    test "variables cascade: the cell's over the board's over the component's default" do
      board = Board.from_map!(board())

      pools = %{
        latency: %{primary: [%{t: 1, v: 1}]},
        eu: %{primary: [%{t: 1, v: 1}]},
        gauge: %{reading: [%{n: 1, v: 1}]}
      }

      design = Map.update!(@line, :sources, fn s -> put_in(s, [:primary, :requires], %{}) end)
      design = Map.update!(design, :labels, &Enum.take(&1, 1))
      store = Map.put(store(), {:composite, 1}, design)

      {:ok, applied, _cache} = Board.realize(board, store, pools)

      assert [%{text: "Latency for api-us"}] = applied.latency.chart.labels
      assert [%{text: "Latency for api-eu"}] = applied.eu.chart.labels

      {:ok, applied, _cache} = Board.realize(%{board | vars: %{}}, store, pools)
      assert [%{text: "Latency for api"}] = applied.latency.chart.labels
    end
  end

  describe "realize" do
    test "each cell applied at its box's size, the board's group written where it syncs" do
      board = Board.from_map!(board())

      pools = %{
        latency: %{primary: [%{t: 1, v: 1}]},
        eu: %{primary: [%{t: 1, v: 1}]},
        gauge: %{reading: [%{n: 1, v: 1}]}
      }

      design =
        @line
        |> put_in([:sources, :primary, :requires], %{})
        |> Map.update!(:labels, &Enum.take(&1, 1))

      store = Map.put(store(), {:composite, 1}, design)

      {:ok, applied, _cache} = Board.realize(board, store, pools, width: 1288)

      assert applied.latency.chart.interaction.sync == "api"
      refute Map.get(applied.gauge.chart.interaction, :sync)
      assert applied.latency.frame.sync == "api"
    end

    test "faults are reported under their cells; an unbound slot where the binding check puts it" do
      board = Board.from_map!(board())
      pools = %{latency: %{primary: [%{t: 1, v: 1}]}}

      assert {:error, errors} = Board.realize(board, store(), pools)
      assert {[:cells, :eu, :sources, :primary], {:unbound, :source, :primary}} in errors
      assert {[:cells, :gauge, :sources, :reading], {:unbound, :source, :reading}} in errors
      assert {[:cells, :latency, :sources, :primary], {:no_schema, :primary}} in errors
    end

    test "the board's own faults come before any cell is applied" do
      board = Board.from_map!(%{cells: %{a: %{x: 0, y: 0, w: 1, h: 1, ref: {:composite, 99}}}})

      assert Board.realize(board, store(), %{}) ==
               {:error, [{[:cells, :a, :ref], {:dangling, {:composite, 99}}}]}
    end

    test "describe is asked with the cell's slot, and the cache is threaded across cells" do
      board = Board.from_map!(board())
      version = Schema.version(schema())
      rows = [%{t: 1, v: 1}]

      pools = %{
        latency: %{primary: Delivery.new(rows, schema: version)},
        eu: %{primary: Delivery.new(rows, schema: version)},
        gauge: %{reading: [%{n: 1, v: 1}]}
      }

      test = self()

      describe = fn key ->
        send(test, {:described, key})
        {:ok, schema()}
      end

      {:ok, applied, cache} = Board.realize(board, store(), pools, describe: describe)

      assert_received {:described, {:eu, :primary}}
      refute_received {:described, {:latency, :primary}}
      assert [%{text: "Request time"}] = Enum.drop(applied.latency.chart.labels, 1)
      assert {:ok, _} = Schema.Cache.fetch(cache, :primary, version)
    end
  end
end
