defmodule Visualize.ChartTest do
  @moduledoc """
  The map and JSON round trips of spec/14 §14.1 and §11 over generated designs, and the
  struct's defaults against the schema.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Visualize.Chart
  alias Visualize.Chart.{Migration, Schema, Validator, Var}
  alias Visualize.ChartGen

  @design_keys [:version, :meta, :sources, :vars, :theme, :styles, :frame, :marks, :labels]

  describe "from_map/1 and to_map/1" do
    property "every generated design validates and round-trips exactly" do
      check all(design <- ChartGen.design(), max_runs: 200) do
        assert Validator.validate(design) == :ok
        assert {:ok, chart} = Chart.from_map(design)
        assert Chart.from_map(Chart.to_map(chart)) == {:ok, chart}
        assert Chart.to_map(chart) == design
      end
    end

    test "absent design-level keys take the schema's defaults" do
      {:ok, chart} = Chart.from_map(%{version: 1, frame: %{kind: :cartesian}})
      assert chart.marks == []
      assert chart.theme == :default

      for key <- @design_keys -- [:version, :frame] do
        assert Map.fetch!(chart, key) == Schema.default(:design, key)
      end

      assert chart.version == Migration.current()
      assert Chart.to_map(chart) |> Map.keys() |> Enum.sort() == Enum.sort(@design_keys)
    end

    test "nested nodes are stored as written, without defaults filled in" do
      frame = %{kind: :cartesian, scales: %{x: %{kind: :linear}}}
      {:ok, chart} = Chart.from_map(%{version: 1, frame: frame})
      assert chart.frame == frame
    end

    test "an invalid design is every error by path" do
      assert Chart.from_map(%{version: 1, frame: %{kind: :cartesian}, marks: [%{}]}) ==
               {:error, [{[:marks, 0, :data], :required}, {[:marks, 0, :type], :required}]}
    end

    test "from_map!/1 raises with the formatted errors" do
      assert_raise ArgumentError, ~r/frame: is required/, fn ->
        Chart.from_map!(%{version: 1})
      end
    end
  end

  describe "from_json/1 and to_json/1" do
    property "every generated design round-trips through JSON" do
      check all(design <- ChartGen.design(), max_runs: 200) do
        chart = Chart.from_map!(design)
        assert {:ok, json} = Chart.to_json(chart)
        assert Chart.from_json(json) == {:ok, chart}
      end
    end

    test "tagged terms take the forms of spec/14 §11.2" do
      chart =
        Chart.from_map!(%{
          version: 1,
          sources: %{p: %{fields: [:t, :v, :sha]}},
          vars: %{unit: %{default: :pct}},
          styles: %{
            s: %{stroke: {:series, 3}, fill: {:field, :sha}, opacity: 0.5},
            t: %{fill: :none}
          },
          frame: %{
            kind: :cartesian,
            scales: %{
              x: %{kind: :time, domain: [~U[2026-09-08 00:00:00Z], :auto]},
              y: %{kind: :linear, unknown: nil}
            }
          },
          marks: [%{type: :line, data: :p, channels: %{x: :t, y: :v}, style: :s}],
          labels: [%{anchor: {:axis, :y}, text: ["unit: ", Chart.var(:unit)]}]
        })

      {:ok, json} = Chart.to_json(chart)
      decoded = Jason.decode!(json)

      assert decoded["vars"] == %{"unit" => %{"default" => %{"$atom" => "pct"}}}
      assert decoded["styles"]["s"]["stroke"] == %{"$series" => 3}
      assert decoded["styles"]["s"]["fill"] == %{"$field" => "sha"}
      assert decoded["styles"]["s"]["opacity"] == 0.5
      assert decoded["styles"]["t"]["fill"] == "none"

      assert decoded["frame"]["scales"]["x"]["domain"] ==
               [%{"$time" => "2026-09-08T00:00:00Z"}, "auto"]

      assert decoded["frame"]["scales"]["y"]["unknown"] == nil

      assert decoded["labels"] == [
               %{"anchor" => %{"$axis" => "y"}, "text" => ["unit: ", %{"$var" => "unit"}]}
             ]

      assert Chart.from_json(json) == {:ok, chart}
    end

    test "a document that does not parse is a JSON error at the root" do
      assert {:error, [{[], {:json, message}}]} = Chart.from_json("{")
      assert is_binary(message)
    end

    test "a document that parses but does not validate reports by path" do
      assert Chart.from_json(~s({"version": 1, "frame": {"kind": "cartesian"}, "marks": 3})) ==
               {:error, [{[:marks], {:type, {:list, {:node, :mark}}}}]}
    end
  end

  test "var/1 is the name-only term" do
    assert Chart.var(:unit) == %Var{name: :unit}
  end
end
