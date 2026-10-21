defmodule Visualize.Chart.FragmentJsonTest do
  @moduledoc """
  The public JSON codec for fragments (spec/14 §19.7, #465): a host that keeps its library
  in a database writes what `Store.put/2` hands it and reads back the same fragment —
  every kind, and a composite with every part of its use sites filled — without a design's
  validation in the way, since a fragment may be partial.
  """
  use ExUnit.Case, async: true

  import Visualize.Chart, only: [var: 1]

  alias Visualize.Chart.{Composite, Fragment, Migration, Use}

  defp round_trip(fragment) do
    assert {:ok, json} = Fragment.to_json(fragment)
    assert is_binary(json)
    assert {:ok, back} = Fragment.from_json(json)
    back
  end

  test "a fragment of each singular kind round-trips" do
    for fragment <- [
          %{style: %{stroke: "#111", stroke_width: 2, curve: :step_after, fill: var(:color)}},
          %{theme: :dark},
          %{frames: %{main: %{kind: :cartesian, margin: %{top: 24, left: 40}}}},
          %{frames: %{main: %{scales: %{y: %{kind: :linear, domain: [0, :auto], nice: true}}}}},
          %{marks: [%{type: :line, data: :series, channels: %{x: :t, y: :v}, style: :series}]},
          %{sources: %{series: %{fields: [:t, :v]}}},
          %{vars: %{color: %{default: :series_1}}}
        ] do
      assert round_trip(fragment) == Migration.names(fragment), inspect(fragment)
      assert Fragment.kind(round_trip(fragment)) == Fragment.kind(fragment)
    end
  end

  test "a composite keeps every part of every use site: ref, mask, vars, local, key, origin" do
    composite = %{
      composite: %{
        uses: [
          Use.new({:theme, 3}),
          %Use{
            id: {:use, 2},
            ref: {:style, 11},
            mask: [:stroke, [:frames, :main, :margin]],
            vars: %{color: var(:color_1)},
            local: %{opacity: 0.8, curve: :monotone_x},
            key: :series
          },
          %Use{id: {:use, 3}, ref: nil, local: %{stroke_width: 3}, origin: {:style, 4}},
          %Use{id: {:use, 4}, ref: {:composite, 2}, mask: :all, key: :gauge}
        ],
        vars: %{color_1: %{default: :series_1}}
      }
    }

    assert round_trip(composite) == Migration.names(composite)
    assert Composite.composite?(round_trip(composite))
  end

  test "a document decomposed into sites round-trips, and still flattens back to itself" do
    document = %{
      version: Visualize.Chart.Migration.current(),
      theme: :dark,
      styles: %{series: %{stroke_width: 2}},
      frames: %{
        main: %{
          kind: :cartesian,
          scales: %{x: %{kind: :time}, y: %{kind: :linear}},
          axes: [%{scale: :x, side: :bottom}]
        }
      },
      marks: [%{type: :line, data: :rows, channels: %{x: :t, y: :v}, style: :series}],
      sources: %{rows: %{fields: [:t, :v]}}
    }

    {uses, _labels} = Composite.decompose(document)
    composite = %{composite: %{uses: uses, vars: %{}}}

    back = round_trip(composite)
    assert back == Migration.names(composite)

    assert {:ok, flat, %{missing: [], keyless: []}} =
             Composite.flatten(back, fn _id -> :error end)

    assert Map.drop(flat, [:version]) == Map.drop(Migration.names(document), [:version])
  end

  test "an id whose kind no fragment has is left as it was read — no atom from a document" do
    json = ~s({"composite": {"uses": [], "ref": {"$id": ["no_such_kind_465", 1]}}})
    assert {:ok, %{composite: %{ref: ref}}} = Fragment.from_json(json)
    assert ref == %{"$id" => ["no_such_kind_465", 1]}
    assert_raise ArgumentError, fn -> String.to_existing_atom("no_such_kind_465") end
  end

  test "text that is not JSON is an error, not a crash" do
    assert {:error, _reason} = Fragment.from_json("{not json")
  end

  describe "a singular entry's body is the node of its kind (spec/14 §11.2, §19.2, #823)" do
    import Visualize.Color, only: [color: 1]

    @entries [
      %{style: %{fill: %{color: color(:red)}, stroke: %{width: {1.5, :pt}}}},
      %{
        style: %{
          fill: %{color: {:lighten, color(:steelblue), 0.2}},
          stroke: %{color: {:blend, [color(:red), color(:blue)]}, dash: [{2, :mm}, {1, :mm}]},
          curve: :step_after
        }
      },
      %{style: %{fill: %{color: {:paint, "sky"}}, stroke: %{color: {:ramp, :sequential, 0.4}}}},
      %{scale: %{kind: :linear, domain: [0, 1], nice: true}},
      %{axis: %{scale: "x", side: :bottom}},
      %{source: %{fields: ["t", "v"]}},
      %{mark: %{type: :line, data: "s", channels: %{x: "t", y: "v"}, style: "series"}},
      %{label: %{text: "peak"}},
      %{var: %{default: :series_1}},
      %{
        gradient: %{
          type: :linear,
          stops: [%{at: 0, color: color(:red)}, %{at: 1, color: {:darken, color(:blue), 0.1}}]
        }
      }
    ]

    test "every singular kind round-trips with its typed values" do
      for entry <- @entries do
        assert round_trip(entry) == Migration.names(entry), inspect(entry)
      end
    end

    test "a typed color and a unit are tagged, an enumerated atom is its string" do
      entry = %{style: %{fill: %{color: color(:red)}, stroke: %{width: {1.5, :pt}}}}
      assert {:ok, json} = Fragment.to_json(entry)
      assert json =~ ~s("$color":"red")
      assert json =~ ~s("$unit":[1.5,"pt"])
      assert Fragment.from_json(json) == {:ok, entry}

      assert {:ok, json} = Fragment.to_json(%{scale: %{kind: :linear, domain: [0, 1]}})
      assert Jason.decode!(json)["scale"]["kind"] == "linear"
    end

    test "the singular and the plural forms write the same body" do
      for {key, plural} <- [style: :styles, source: :sources, var: :vars] do
        [body | _] = for %{^key => body} <- @entries, do: body
        {:ok, singular} = Fragment.to_json(%{key => body})
        {:ok, design} = Fragment.to_json(%{plural => %{"one" => body}})

        assert Jason.decode!(singular)[to_string(key)] ==
                 Jason.decode!(design)[to_string(plural)]["one"]
      end
    end

    test "a body that is no object is a term, as before" do
      for entry <- [%{style: [{:style, 11}, %{fill: {:style, 3}}]}, %{style: {:style, 3}}] do
        assert round_trip(entry) == entry
      end
    end

    test "an entry written before #823, every atom a $atom, still reads" do
      legacy = [
        {~s({"$version":3,"scale":{"domain":[0,1],"kind":{"$atom":"linear"}}}),
         %{scale: %{kind: :linear, domain: [0, 1]}}},
        {~s({"$version":3,"style":{"curve":{"$atom":"step_after"},"fill":{"color":{"$atom":"red"}},"stroke":{"width":2}}}),
         %{style: %{curve: :step_after, fill: %{color: :red}, stroke: %{width: 2}}}},
        {~s({"$version":3,"axis":{"scale":"x","side":{"$atom":"bottom"}}}),
         %{axis: %{scale: "x", side: :bottom}}}
      ]

      for {json, fragment} <- legacy do
        assert Fragment.from_json(json) == {:ok, fragment}, json
      end
    end
  end

  describe "a stack's fixed key order (spec/14 §11.2, #492)" do
    @streams %{
      version: 2,
      sources: %{s: %{fields: [:t, :a, :b]}},
      frames: %{main: %{kind: :cartesian, scales: %{x: %{kind: :linear}, y: %{kind: :linear}}}},
      marks: [
        %{
          type: :area,
          data: %{
            source: :s,
            transforms: [%{op: :stack, fields: [:a, :b], order: {:keys, [:b, :a]}}]
          },
          channels: %{x: :t, y: :y1, y0: :y0, series: :key}
        }
      ]
    }

    test "a design whose stack order is fixed round-trips through JSON" do
      {:ok, chart} = Visualize.Chart.from_map(@streams)
      assert {:ok, json} = Visualize.Chart.to_json(chart)
      assert json =~ ~s("$keys":["b","a"])
      assert {:ok, back} = Visualize.Chart.from_json(json)
      assert back == chart
      assert hd(hd(back.marks).data.transforms).order == {:keys, ["b", "a"]}
    end

    test "a named order still reads back as its atom" do
      fragment = %{marks: [%{data: %{transforms: [%{op: :stack, order: :inside_out}]}}]}
      assert {:ok, json} = Fragment.to_json(fragment)
      assert Fragment.from_json(json) == {:ok, Migration.names(fragment)}
    end
  end

  describe "an adopted scale (spec/14 §11, #480)" do
    @shared %{
      version: 2,
      sources: %{a: %{fields: [:t, :v]}, b: %{fields: [:t, :v]}},
      frames: %{
        main: %{kind: :cartesian, scales: %{x: %{kind: :linear}, y: %{kind: :linear}}},
        right: %{
          kind: :cartesian,
          scales: %{x: {:frame, :main, :x}, y: %{kind: :linear}},
          axes: [%{scale: :y, side: :right}]
        }
      },
      marks: [
        %{type: :line, data: :a, frame: :main, channels: %{x: :t, y: :v}},
        %{type: :line, data: :b, frame: :right, channels: %{x: :t, y: :v}}
      ]
    }

    test "a design whose frames share a scale round-trips through JSON and still shares it" do
      {:ok, chart} = Visualize.Chart.from_map(@shared)
      assert {:ok, json} = Visualize.Chart.to_json(chart)
      assert json =~ ~s("$adopted":["main","x"])
      assert {:ok, back} = Visualize.Chart.from_json(json)
      assert back.frames["right"].scales["x"] == {:frame, "main", "x"}

      sources = %{a: [%{t: 1, v: 1}, %{t: 2, v: 2}], b: [%{t: 5, v: 9}]}
      {:ok, applied} = Visualize.Chart.apply(back, sources: sources)
      assert Visualize.Chart.Frame.scale(applied.frames["right"], :x).domain == [1, 5]
    end

    test "a fragment carrying an adoption round-trips too" do
      fragment = %{frames: %{right: %{scales: %{x: {:frame, :main, :x}}}}}
      assert {:ok, json} = Fragment.to_json(fragment)
      assert Fragment.from_json(json) == {:ok, Migration.names(fragment)}
    end
  end
end
