defmodule Visualize.EventTest do
  @moduledoc """
  One shape for every interaction (spec/10 §19, #627, D-170): a click's wire params
  decoded, then resolved against the applied chart that was drawn to the row its element
  was drawn from — typed, with its item by the declared identity, else inference — or
  dropped.
  """
  use ExUnit.Case, async: true

  alias Visualize.Chart
  alias Visualize.Chart.{Compiled, Mark}
  alias Visualize.Data.{Delivery, Schema}
  alias Visualize.Event

  doctest Visualize.Event

  @t0 ~U[2026-10-14 09:00:00Z]

  @fleet Schema.new!(%{
           t: %{type: :time},
           car: %{type: :category, identity: true},
           v: %{type: :number}
         })

  @links Schema.new!(%{
           t: %{type: :time},
           host: %{type: :category, identity: true},
           iface: %{type: :category, identity: true},
           v: %{type: :number}
         })

  defp rows do
    for i <- 0..5, car <- ["a", "b"] do
      %{t: DateTime.add(@t0, i * 60), car: car, host: "mx1", iface: "eth#{i}", v: 10 * i}
    end
  end

  defp design(mark \\ %{}) do
    %{
      version: 2,
      sources: %{cars: %{fields: [:t, :car, :host, :iface, :v]}},
      frames: %{
        main: %{
          kind: :cartesian,
          margin: %{top: 10, right: 0, bottom: 0, left: 30},
          scales: %{x: %{kind: :time}, y: %{kind: :linear}}
        }
      },
      marks: [
        %{type: :line, data: :cars, channels: %{x: :t, y: :v, series: :car}},
        Map.merge(
          %{
            type: :circle,
            id: :dot,
            data: %{source: :cars, transforms: [%{op: :sort, field: :v, order: :descending}]},
            channels: %{x: :t, y: :v},
            tooltip: %{fields: [:car, :v], event: :car_click}
          },
          mark
        )
      ]
    }
  end

  defp apply!(design, schema \\ @fleet) do
    {:ok, applied} =
      Chart.apply(design,
        sources: %{cars: Delivery.new(rows(), schema: Schema.version(schema))},
        describe: fn :cars -> {:ok, schema} end,
        size: {330, 210}
      )

    applied
  end

  defp click(overrides \\ %{}) do
    Map.merge(
      %{
        event: "car_click",
        frame: "main",
        mark: 1,
        row: 0,
        drawn: nil,
        at: %{x: 130, y: 60},
        modifiers: []
      },
      overrides
    )
  end

  describe "decode/1" do
    test "reads the wire's params, and refuses any other shape" do
      assert {:ok, %{event: "e", frame: nil, mark: 0, row: 3, drawn: nil, at: nil, modifiers: []}} =
               Event.decode(%{"event" => "e", "mark" => 0, "row" => 3})

      for bad <- [
            %{"event" => "", "mark" => 0, "row" => 0},
            %{"event" => "e", "mark" => "0", "row" => 0},
            %{"event" => "e", "mark" => 0, "row" => 1.5},
            %{"event" => "e", "mark" => 0, "row" => 0, "frame" => 3},
            %{"event" => "e", "mark" => 0, "row" => 0, "at" => %{"x" => "1", "y" => 2}},
            %{"event" => "e", "mark" => 0, "row" => 0, "modifiers" => "shift"},
            %{"event" => "e", "mark" => 0, "row" => 0, "modifiers" => [1]},
            %{"fields" => %{"v" => "1"}}
          ] do
        assert Event.decode(bad) == :error, inspect(bad)
      end
    end

    test "keeps the modifiers in their order, whatever order they were sent in" do
      params = %{
        "event" => "e",
        "mark" => 0,
        "row" => 0,
        "modifiers" => ["meta", "shift", "ctrl"]
      }

      assert {:ok, %{modifiers: [:shift, :ctrl, :meta]}} = Event.decode(params)
    end
  end

  describe "resolve/3" do
    test "a click is the row its element was drawn from, typed, its item the declared identity" do
      applied = apply!(design())

      # The circles are drawn sorted by v, descending: ordinal 0 is the last minute's.
      t5 = DateTime.add(@t0, 300)

      assert {:ok,
              %Event{
                event: "car_click",
                cell: nil,
                frame: "main",
                item: {"dot", car},
                path: [{"dot", car}],
                row: %{t: ^t5, v: 50, car: car},
                at: %{x: 100, y: 50},
                value: %{},
                modifiers: []
              }} = Event.resolve(click(), applied)

      assert car in ["a", "b"]
    end

    test "every keyed element of the drawing resolves to the row it shows (D-170)" do
      applied = apply!(design())
      svg = Chart.render(applied)

      keyed =
        Regex.scan(
          ~r/<circle [^>]*data-datum-car="([^"]+)" data-datum-v="([^"]+)"[^>]*data-row="(\d+)"/,
          svg
        )

      assert length(keyed) == 12

      for [_, car, v, ordinal] <- keyed do
        {:ok, event} = Event.resolve(click(%{row: String.to_integer(ordinal)}), applied)
        assert {to_string(event.row.car), to_string(event.row.v)} == {car, v}
      end
    end

    test "a composite identity is the item's map; with none declared it is inferred, else nil" do
      assert {:ok, %Event{item: {"dot", %{"host" => "mx1", "iface" => "eth5"}}}} =
               Event.resolve(click(), apply!(design(), @links))

      anonymous = Schema.new!(%{t: %{type: :time}, car: %{type: :category}, v: %{type: :number}})
      assert {:ok, %Event{item: {"dot", _}}} = Event.resolve(click(), apply!(design(), anonymous))

      # A mark with a series names its field's value; a source of no category names nothing,
      # and the row is still given.
      series =
        update_in(
          design(%{channels: %{x: :t, y: :v, series: :car}}),
          [:marks, Access.at(1)],
          &Map.delete(&1, :id)
        )

      {:ok, plain} = Chart.apply(series, sources: %{cars: rows()}, size: {330, 210})
      assert {:ok, %Event{item: {:circle, car}}} = Event.resolve(click(), plain)
      assert car in ["a", "b"]

      {:ok, bare} = Chart.apply(design(), sources: %{cars: rows()}, size: {330, 210})
      assert {:ok, %Event{item: nil, path: [], row: %{v: 50}}} = Event.resolve(click(), bare)
    end

    test "a click on another drawing, an unknown key or an undeclared name is dropped" do
      applied = apply!(design())

      assert {:ok, _} = Event.resolve(click(%{drawn: "7"}), applied, drawn: "7")
      assert Event.resolve(click(%{drawn: "6"}), applied, drawn: "7") == :error
      assert Event.resolve(click(), applied, drawn: "7") == :error
      assert Event.resolve(click(%{frame: "other"}), applied) == :error
      assert Event.resolve(click(%{frame: nil}), applied) == :error
      assert Event.resolve(click(%{mark: 2}), applied) == :error
      assert Event.resolve(click(%{row: 12}), applied) == :error
      assert Event.resolve(click(%{event: "pick"}), applied) == :error
      # The line declares no event, so a click naming it with any name is no click.
      assert Event.resolve(click(%{mark: 0}), applied) == :error
    end

    test "a declared string names the event as an atom does; cell: and the pointer's frame" do
      applied = apply!(design(%{tooltip: %{event: "car_click"}}))

      assert {:ok, %Event{event: "car_click", cell: :fleet, at: nil, modifiers: [:alt]}} =
               Event.resolve(click(%{at: nil, modifiers: [:alt]}), applied, cell: :fleet)
    end

    test "in a design of several frames a click names its frame, its point in that plot" do
      two = %{
        version: 2,
        sources: %{cars: %{fields: [:t, :car, :v]}},
        layout: %{columns: [1, 1]},
        frames: %{
          left: %{
            kind: :cartesian,
            cell: [0, 0],
            margin: %{top: 0, right: 0, bottom: 0, left: 0},
            scales: %{x: %{kind: :time}, y: %{kind: :linear}}
          },
          right: %{
            kind: :cartesian,
            cell: [1, 0],
            margin: %{top: 5, right: 0, bottom: 0, left: 20},
            scales: %{x: %{kind: :time}, y: %{kind: :linear}}
          }
        },
        marks: [
          %{type: :circle, frame: :left, data: :cars, channels: %{x: :t, y: :v}},
          %{
            type: :circle,
            frame: :right,
            data: :cars,
            channels: %{x: :t, y: :v},
            tooltip: %{event: :right_click}
          }
        ]
      }

      {:ok, applied} = Chart.apply(two, sources: %{cars: rows()}, size: {400, 200})
      svg = Chart.render(applied)
      assert svg =~ ~s(data-frame="right" data-mark="0" data-tooltip-event="right_click")

      right = applied.frames["right"]
      [bx, by | _] = right.box
      ox = bx * 400 + 20
      oy = by * 200 + 5

      assert {:ok, %Event{frame: "right", row: %{v: 0}, at: at}} =
               Event.resolve(
                 click(%{
                   event: "right_click",
                   frame: "right",
                   mark: 0,
                   at: %{x: ox + 3, y: oy + 4}
                 }),
                 applied
               )

      assert at == %{x: 3, y: 4}
    end
  end

  describe "Compiled.rows/3" do
    test "is the mark's realized rows as a tick draws them, [] past the frame's marks" do
      applied = apply!(design())
      {:ok, %{"main" => compiled}} = Chart.compile(applied)
      sources = applied.sources

      assert Compiled.rows(compiled, sources, 1) ==
               Mark.rows(
                 applied.frame,
                 Enum.at(applied.frame.marks, 1),
                 Map.new(sources, fn {k, d} -> {k, Delivery.source(d)} end)
               )

      assert hd(Compiled.rows(compiled, sources, 1)).v == 50
      assert Compiled.rows(compiled, sources, 9) == []
    end
  end

  describe "declared/1" do
    test "the names a chart's marks declare, from the chart or its application" do
      applied = apply!(design())
      assert Event.declared(applied) == ["car_click"]
      assert Event.declared(applied.chart) == ["car_click"]
    end
  end
end
