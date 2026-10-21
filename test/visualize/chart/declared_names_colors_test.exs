defmodule Visualize.Chart.DeclaredNamesColorsTest do
  @moduledoc """
  #863, D-225: a feed's declared value names and colors (spec/08 §10.1, D-224) reach a
  design. The facts `:names` and `:colors` read them (spec/14 §7.4); the `:ordinal` `color`
  scale whose `:auto` range is over a `:values` fact takes the declared colors, the palette
  slot of its position for the rest, and an explicit range wins (§4.3); a legend labels its
  entries by name on both of its paths (§4.5); a tooltip shows the name beside the raw
  value, which everything that keys on a value still reads (§5.7, spec/10 §12.2).
  """
  use ExUnit.Case, async: true

  import Visualize.Chart, only: [fact: 3]

  alias Visualize.Backend.Canvas
  alias Visualize.Backend.CanvasBinary.Decoder
  alias Visualize.Board.Binding
  alias Visualize.Chart
  alias Visualize.Chart.{Fact, Frame}
  alias Visualize.Data.{Delivery, Schema}
  alias Visualize.Data.Schema.Cache
  alias Visualize.Theme

  @ok "#2e7d32"
  @degraded "#ef6c00"

  # A catalog's states: two with a name and a color, one bare, which the palette draws.
  @fields %{
    service: %{type: :category},
    since: %{type: :number},
    until: %{type: :number},
    state: %{
      type: :category,
      values: [
        %{value: "ok", name: "OK", color: @ok},
        %{value: "degraded", name: "Degraded", color: @degraded},
        "unknown"
      ]
    }
  }

  @rows [
    %{service: "api", since: 0, until: 1, state: "ok"},
    %{service: "api", since: 1, until: 2, state: "degraded"},
    %{service: "db", since: 0, until: 2, state: "unknown"}
  ]

  defp schema(fields \\ @fields), do: Schema.new!(fields)

  # A state timeline: a band per stretch at its service's row, filled by its state through
  # the color scale over the feed's declared states.
  defp timeline(color \\ %{}, extra \\ %{}) do
    Map.merge(
      %{
        version: 3,
        sources: %{status: %{fields: [:service, :since, :until, :state]}},
        styles: %{stretch: %{fill: {:field, :state}}},
        frames: %{
          main: %{
            kind: :cartesian,
            margin: %{top: 10, right: 10, bottom: 40, left: 40},
            scales: %{
              x: %{kind: :linear, domain: [0, 2]},
              y: %{kind: :band, domain: ["api", "db"]},
              color: Map.merge(%{kind: :ordinal, domain: fact(:status, :state, :values)}, color)
            },
            legend: %{scale: :color, position: :bottom, inside: false}
          }
        },
        marks: [
          %{
            type: :band,
            data: :status,
            channels: %{x0: :since, x1: :until, y: :service},
            style: :stretch,
            options: %{height: 14}
          }
        ]
      },
      extra
    )
  end

  defp applied(design, s \\ schema(), rows \\ @rows) do
    {:ok, applied} =
      Chart.apply(design,
        sources: %{status: Delivery.new(rows, schema: Schema.version(s))},
        schemas: Cache.new([{:status, s}])
      )

    applied
  end

  defp palette(i), do: Theme.resolve(Theme.default(), {:series, i}, :literal)

  # The fill of each element of the band mark's group, in order.
  defp svg_fills(applied) do
    svg = Chart.render(applied, resolve: :literal)

    ~r/<g [^>]*class="mark mark-band"[^>]*>(.*?)<\/g>/s
    |> Regex.run(svg, capture: :all_but_first)
    |> hd()
    |> then(&Regex.scan(~r/<(?:rect|path) [^>]*?fill="([^"]*)"/, &1, capture: :all_but_first))
    |> List.flatten()
  end

  # The fills the canvas command stream sets, in order, none repeated.
  defp canvas_fills(applied) do
    applied
    |> Chart.generate(resolve: :literal)
    |> Canvas.render_element(format: :commands)
    |> Enum.flat_map(fn
      {:set_fillStyle, [color]} -> [color]
      _command -> []
    end)
    |> Enum.dedup()
  end

  # The fills the binary stream's style records carry, as hex.
  defp binary_fills(applied) do
    applied
    |> Chart.render(backend: :canvas, format: :binary)
    |> Decoder.decode()
    |> Enum.flat_map(fn
      {:style, %{fill: {r, g, b, _a}}} -> [hex(r, g, b)]
      _record -> []
    end)
  end

  defp hex(r, g, b), do: "#" <> Enum.map_join([r, g, b], &pad/1)
  defp pad(n), do: n |> Integer.to_string(16) |> String.pad_leading(2, "0") |> String.downcase()

  # Each legend entry as `{data-series, label}`.
  defp legend(applied) do
    svg = Chart.render(applied, resolve: :literal)

    Regex.scan(
      ~r/<g [^>]*class="legend-item"[^>]*data-series="([^"]*)"[^>]*>.*?<text[^>]*>([^<]*)<\/text>/s,
      svg,
      capture: :all_but_first
    )
    |> Enum.map(&List.to_tuple/1)
  end

  describe "the facts :names and :colors (spec/14 §7.4)" do
    test "give the value maps; :values stays bare" do
      s = schema()
      assert Fact.fetch(s, :state, :names) == {:ok, %{"ok" => "OK", "degraded" => "Degraded"}}
      assert Fact.fetch(s, :state, :colors) == {:ok, %{"ok" => @ok, "degraded" => @degraded}}
      assert Fact.fetch(s, :state, :values) == {:ok, ["ok", "degraded", "unknown"]}

      a = applied(timeline(%{range: fact(:status, :state, :colors)}))

      assert a.chart.frames["main"].scales["color"].range == %{
               "ok" => @ok,
               "degraded" => @degraded
             }
    end

    test "are the fact keys, after the attributes, and order a contract" do
      assert Fact.keys() == Schema.attributes() ++ [:names, :colors]

      d = put_in(timeline(), [:sources, :status, :requires], %{state: [:colors, :names, :type]})
      assert Chart.contract(d) == %{"status" => %{"state" => [:type, :values, :names, :colors]}}
    end

    test "fault where the field's values carry none, at the fact and at requires" do
      bare = schema(put_in(@fields, [:state, :values], ["ok", "degraded"]))

      d =
        timeline(%{range: fact(:status, :state, :colors)})
        |> put_in([:sources, :status, :requires], %{state: [:names]})

      assert {:error, errors} =
               Chart.apply(d,
                 sources: %{status: Delivery.new(@rows, schema: Schema.version(bare))},
                 schemas: Cache.new([{:status, bare}])
               )

      assert {[:frames, "main", :scales, "color", :range],
              {:missing_attribute, "status", "state", :colors}} in errors

      assert {[:sources, "status", :requires, "state"],
              {:missing_attribute, "status", "state", :names}} in errors

      assert Fact.fetch(bare, :state, :names) == :error
      assert Fact.fetch(bare, :service, :colors) == :error
      assert Fact.fetch(bare, :nope, :names) == :error
    end

    test "a board's binding check reads them as application does" do
      need = %{fields: [:state], types: %{}, requires: %{"state" => [:colors]}, reads: []}
      bare = schema(put_in(@fields, [:state, :values], ["ok"]))
      binding = %Binding{slots: %{{"cell", "status"} => :feed}}

      assert :ok = Binding.check(binding, %{{"cell", "status"} => need}, %{feed: schema()})

      assert {:error, [{_path, {:missing_attribute, "status", "state", :colors}}]} =
               Binding.check(binding, %{{"cell", "status"} => need}, %{feed: bare})
    end

    test "are maps, never words, in a text" do
      for key <- [:names, :colors] do
        hole = "\#{fact(:status, :state, :#{key})}"
        d = Map.put(timeline(), :labels, [%{anchor: {:frame, :top_right}, text: hole}])
        assert {:error, [{[:labels, 0, :text], {:invalid_for, :text}}]} = Chart.from_map(d)
      end
    end

    test "round-trip through JSON" do
      {:ok, chart} = Chart.from_map(timeline(%{range: fact(:status, :state, :colors)}))
      {:ok, json} = Chart.to_json(chart)
      assert json =~ ~s(["status","state","colors"])
      assert Chart.from_json(json) == {:ok, chart}
    end
  end

  describe "declared colors on the color scale (spec/14 §4.3)" do
    test "a state timeline draws the declared colors, and the palette slot of its position for the rest" do
      a = applied(timeline())

      assert a.chart.frames["main"].scales["color"].range == [@ok, @degraded, {:series, 3}]
      assert svg_fills(a) == [@ok, @degraded, palette(3)]
    end

    test "every backend draws what the range says" do
      a = applied(timeline())
      fills = [@ok, @degraded, palette(3)]

      # The legend's swatches draw them again, after the marks.
      assert a |> canvas_fills() |> Enum.filter(&(&1 in fills)) |> Enum.uniq() == fills
      assert a |> binary_fills() |> Enum.filter(&(&1 in fills)) |> Enum.uniq() == fills
    end

    test "a value's palette slot is its position's, whether or not its neighbors declare one" do
      undeclared = schema(put_in(@fields, [:state, :values], ["ok", "degraded", "unknown"]))
      before = applied(timeline(), undeclared)

      # No declared color: the range is not written, and the theme draws every state.
      assert Map.get(before.chart.frames["main"].scales["color"], :range, :auto) == :auto
      assert svg_fills(before) == [palette(1), palette(2), palette(3)]

      # "unknown" draws the color it drew before its neighbors declared theirs.
      assert List.last(svg_fills(applied(timeline()))) == palette(3)
    end

    test "an explicit range overrides the declared colors" do
      a = applied(timeline(%{range: ["#111111", "#222222", "#333333"]}))
      assert svg_fills(a) == ["#111111", "#222222", "#333333"]

      roles = applied(timeline(%{range: {:ramp, :status}}))
      refute Enum.any?(svg_fills(roles), &(&1 in [@ok, @degraded]))
    end

    test "the :colors fact as the range pins: a value without a color draws unknown" do
      a = applied(timeline(%{range: fact(:status, :state, :colors)}))
      axis = Theme.resolve(Theme.default(), :axis, :literal)

      assert svg_fills(a) == [@ok, @degraded, axis]
    end

    test "a domain that is no :values fact, or a scale of another name, is left to the theme" do
      listed = applied(timeline(%{domain: ["ok", "degraded", "unknown"]}))
      assert svg_fills(listed) == [palette(1), palette(2), palette(3)]

      d =
        timeline()
        |> update_in([:frames, :main, :scales], fn scales ->
          scales |> Map.delete(:color) |> Map.put(:state, scales.color)
        end)
        |> put_in([:frames, :main, :legend, :scale], :state)
        |> update_in([:marks, Access.at(0)], &Map.put(&1, :scales, %{color: :state}))

      renamed = applied(d)
      refute Map.has_key?(renamed.chart.frames["main"].scales["state"], :range)
    end
  end

  describe "a legend labels each entry by its declared name (spec/14 §4.5)" do
    test "over the scale: the names, with data-series the raw value" do
      assert legend(applied(timeline())) == [
               {"ok", "OK"},
               {"degraded", "Degraded"},
               {"unknown", "unknown"}
             ]
    end

    test "over an inferred domain too: the name is the field's" do
      d = put_in(timeline(), [:frames, :main, :scales, :color, :domain], :auto)

      assert legend(applied(d)) == [
               {"ok", "OK"},
               {"degraded", "Degraded"},
               {"unknown", "unknown"}
             ]
    end

    test "of declared values: the names of the field the marks map by" do
      d =
        timeline(%{}, %{
          styles: %{ok: %{fill: @ok}, degraded: %{fill: @degraded}, unknown: %{fill: "#999999"}}
        })
        |> put_in([:marks, Access.at(0), :style], [{:field, :state}])
        |> put_in([:frames, :main, :legend], %{
          scale: :color,
          values: fact(:status, :state, :values),
          position: :bottom,
          inside: false
        })

      assert legend(applied(d)) == [
               {"ok", "OK"},
               {"degraded", "Degraded"},
               {"unknown", "unknown"}
             ]
    end

    test "with prefix, unit and max_label as any label" do
      d =
        put_in(timeline(), [:frames, :main, :legend], %{
          scale: :color,
          position: :right,
          inside: true,
          prefix: "[",
          unit: "]",
          max_label: 6
        })

      assert legend(applied(d)) == [
               {"ok", "[OK]"},
               {"degraded", "[Degr…"},
               {"unknown", "[unkn…"}
             ]
    end

    test "a frame realized with no schemas labels values as before" do
      {:ok, chart} =
        Chart.from_map(put_in(timeline(), [:frames, :main, :scales, :color, :domain], :auto))

      frame = Frame.new(chart, sources: %{status: @rows})
      svg = Visualize.Chart.Frame.render(frame, sources: %{status: @rows})
      refute svg =~ ">OK<"
      assert svg =~ ">ok<"
    end
  end

  describe "a tooltip shows the declared name beside the value (spec/14 §5.7)" do
    defp tipped(tooltip) do
      timeline()
      |> put_in([:marks, Access.at(0), :tooltip], tooltip)
      |> applied()
      |> Chart.render(resolve: :literal)
    end

    test "data-named-<field> carries the name; data-datum-<field> keeps the value" do
      svg = tipped(%{fields: [:service, :state], event: :pick})

      assert svg =~ ~s(data-datum-state="degraded")
      assert svg =~ ~s(data-named-state="Degraded")
      assert svg =~ ~s(data-datum-state="unknown")
      refute svg =~ ~s(data-named-state="unknown")
      refute svg =~ "data-named-service"

      # What keys on a value reads the value: the row, the series.
      assert svg =~ ~r/data-datum-state="ok"[^>]*data-named-state="OK"[^>]*data-row="0"/
      refute svg =~ ~s(data-series="OK")
    end

    test "a field whose feed declares no names writes no name" do
      undeclared = schema(put_in(@fields, [:state, :values], ["ok", "degraded", "unknown"]))

      svg =
        timeline()
        |> put_in([:marks, Access.at(0), :tooltip], %{fields: [:state]})
        |> applied(undeclared)
        |> Chart.render(resolve: :literal)

      assert svg =~ ~s(data-datum-state="ok")
      refute svg =~ "data-named-"
    end

    test "a mark with a tooltip has its slot's schema resolved, nothing else reading it" do
      d = %{
        version: 3,
        sources: %{status: %{fields: [:since, :state]}},
        frames: %{
          main: %{kind: :cartesian, scales: %{x: %{kind: :linear}, y: %{kind: :linear}}}
        },
        marks: [
          %{
            type: :circle,
            data: :status,
            channels: %{x: :since, y: 0},
            tooltip: %{fields: [:state]}
          }
        ]
      }

      a = applied(d)
      assert Map.has_key?(a.schemas, "status")
      assert Chart.render(a) =~ ~s(data-named-state="Degraded")

      # Where the version does not resolve there is no fault, and no name.
      {:ok, rows_only} = Chart.apply(d, sources: %{status: @rows})
      refute Chart.render(rows_only) =~ "data-named-"
    end
  end
end
