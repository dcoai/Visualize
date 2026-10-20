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

  doctest Var

  @design_keys [
    :version,
    :meta,
    :sources,
    :vars,
    :theme,
    :styles,
    :defs,
    :layout,
    :interaction,
    :frames,
    :marks,
    :labels
  ]

  describe "from_map/1 and to_map/1" do
    property "every generated design validates and round-trips exactly" do
      check all(design <- ChartGen.design(), max_runs: 200) do
        assert Validator.validate(design) == :ok
        assert {:ok, chart} = Chart.from_map(design)
        assert Chart.from_map(Chart.to_map(chart)) == {:ok, chart}
        # A text is written as its string whichever form the generator chose (§7.1).
        assert Chart.to_map(chart) == Visualize.Chart.Migration.canonical(design)
      end
    end

    test "absent design-level keys take the schema's defaults" do
      {:ok, chart} = Chart.from_map(%{version: 2, frames: %{main: %{kind: :cartesian}}})
      assert chart.marks == []
      assert chart.theme == :default

      for key <- @design_keys -- [:version, :frames] do
        assert Map.fetch!(chart, key) == Schema.default(:design, key)
      end

      assert chart.version == Migration.current()
      assert Chart.to_map(chart) |> Map.keys() |> Enum.sort() == Enum.sort(@design_keys)
    end

    test "nested nodes are stored as written, without defaults filled in" do
      frame = %{kind: :cartesian, scales: %{x: %{kind: :linear}}}
      {:ok, chart} = Chart.from_map(%{version: 2, frames: %{main: frame}})
      # Names are strings in the map form (spec/14 §1.4, D-195).
      assert chart.frames["main"] == %{kind: :cartesian, scales: %{"x" => %{kind: :linear}}}
    end

    test "an invalid design is every error by path" do
      assert Chart.from_map(%{version: 2, frames: %{main: %{kind: :cartesian}}, marks: [%{}]}) ==
               {:error, [{[:marks, 0, :data], :required}, {[:marks, 0, :type], :required}]}
    end

    test "from_map!/1 raises with the formatted errors" do
      assert_raise ArgumentError, ~r/frames: is required/, fn ->
        Chart.from_map!(%{version: 2})
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
          version: 2,
          sources: %{p: %{fields: [:t, :v, :sha]}},
          vars: %{unit: %{default: :pct}},
          styles: %{
            s: %{stroke: {:series, 3}, fill: {:field, :sha}, opacity: 0.5},
            t: %{fill: :none}
          },
          frames: %{
            main: %{
              kind: :cartesian,
              scales: %{
                x: %{kind: :time, domain: [~U[2026-09-08 00:00:00Z], :auto]},
                y: %{kind: :linear, unknown: nil}
              }
            }
          },
          marks: [%{type: :line, data: :p, channels: %{x: :t, y: :v}, style: :s}],
          labels: [%{anchor: {:axis, :y}, text: ["unit: ", Chart.var(:unit)]}]
        })

      {:ok, json} = Chart.to_json(chart)
      decoded = Jason.decode!(json)

      assert decoded["vars"] == %{"unit" => %{"default" => %{"$atom" => "pct"}}}

      assert decoded["styles"]["s"]["stroke"] == %{
               "type" => "solid",
               "color" => %{"$series" => 3}
             }

      assert decoded["styles"]["s"]["fill"] == %{
               "type" => "solid",
               "color" => %{"$field" => "sha"}
             }

      assert decoded["styles"]["s"]["opacity"] == 0.5
      assert decoded["styles"]["t"]["fill"] == %{"type" => "none"}

      assert decoded["frames"]["main"]["scales"]["x"]["domain"] ==
               [%{"$time" => "2026-09-08T00:00:00Z"}, "auto"]

      assert decoded["frames"]["main"]["scales"]["y"]["unknown"] == nil

      # A text is its string, the hole spelled as it is written (§7.1): no tagged term.
      assert decoded["labels"] == [
               %{"anchor" => %{"$axis" => "y"}, "text" => ~S|unit: #{var(:unit)}|}
             ]

      assert Chart.from_json(json) == {:ok, chart}
    end

    # A key that is a string or an enumeration (an axis's `format`) reads a member's name as
    # the member, whichever alternative the schema lists first (spec/14 §11.1, D-144).
    test "a string naming an enumeration alternative's member reads back as that atom" do
      axis = fn format -> %{scale: :x, side: :bottom, format: format} end

      chart =
        Chart.from_map!(%{
          version: 2,
          frames: %{
            main: %{
              kind: :cartesian,
              scales: %{x: %{kind: :linear}},
              axes: [axis.(:duration), axis.(".1~s")]
            }
          }
        })

      {:ok, json} = Chart.to_json(chart)

      assert [%{"format" => "duration"}, %{"format" => ".1~s"}] =
               Jason.decode!(json)["frames"]["main"]["axes"]

      assert {:ok, ^chart} = Chart.from_json(json)
    end

    test "a document that does not parse is a JSON error at the root" do
      assert {:error, [{[], {:json, message}}]} = Chart.from_json("{")
      assert is_binary(message)
    end

    test "a document that parses but does not validate reports by path" do
      assert Chart.from_json(
               ~s({"version": 2, "frames": {"main": {"kind": "cartesian"}}, "marks": 3})
             ) ==
               {:error, [{[:marks], {:type, {:list, {:node, :mark}}}}]}
    end
  end

  describe "generate/2 and render/2 with root: (spec/14 §4.7, #131)" do
    defp applied(meta, opts \\ []) do
      design = %{
        version: 2,
        meta: meta,
        sources: %{s: %{fields: [:x, :y]}},
        frames: %{main: %{kind: :cartesian}},
        marks: [%{type: :line, data: :s, channels: %{x: :x, y: :y}}]
      }

      {:ok, applied} =
        Chart.apply(
          design,
          [sources: %{s: [%{x: 1, y: 2}, %{x: 2, y: 3}]}, size: {300, 200}] ++ opts
        )

      applied
    end

    test "the root is one <svg> whose only child group is byte for byte the bare render" do
      applied = applied(%{name: "Rain", description: ["Rain in ", "mm"]})
      bare = Chart.render(applied)
      svg = Chart.render(applied, root: true)

      assert svg =~ ~r/^<svg /
      assert String.ends_with?(svg, bare <> "</svg>")
      assert svg =~ ~s(role="img") and svg =~ ~s(viewBox="0 0 300 200")
      assert svg =~ ~s(<title id="vis-) and svg =~ ">Rain</title>"
      # The design's description, then the generated summary (spec/14 §21.2, D-142).
      # The frame declares no scale, so its marks draw pixels and no value (§21.1).
      assert svg =~ ">Rain in mm. Line chart, 2 points.</desc>"
      assert svg =~ ~r/aria-describedby="(vis-[a-z0-9]+)-desc" aria-labelledby="\1-title"/
      assert length(String.split(svg, "<svg ")) == 2

      root = Chart.generate(applied, root: true)
      # Title, description, the automatic dark mode (#668), the group.
      assert root.type == :root and length(root.children) == 4
      assert Chart.generate(applied) == List.last(root.children)
    end

    test "under the implicit default theme the root follows the viewer's color scheme (#668)" do
      applied = applied(%{name: "Rain"})
      svg = Chart.render(applied, root: true)
      [_, id] = Regex.run(~r/<svg [^>]*id="(vis-[a-z0-9]+)"/, svg)
      dark = Visualize.Theme.color_scheme(Visualize.Theme.default(), "#" <> id)
      assert svg =~ "<style>" <> dark <> "</style>"
      assert dark =~ "@media (prefers-color-scheme: dark)" and dark =~ "--vis-axis: #a0a4ab;"

      # Off when asked, in :literal output, and under a theme the host or design chose.
      refute Chart.render(applied, root: true, color_scheme: false) =~ "<style>"
      refute Chart.render(applied, root: true, resolve: :literal) =~ "<style>"

      chosen = applied(%{name: "Rain"}, theme: Visualize.Theme.new(name: :house))
      refute Chart.render(chosen, root: true) =~ "<style>"
    end

    test "an empty meta is named by the kind and described by the summary; the options override them" do
      svg = Chart.render(applied(%{}), root: true)
      assert svg =~ ">Line chart</title>"

      assert svg =~
               ">Line chart, 2 points.</desc>"

      assert svg =~ ~s(role="img")

      svg = Chart.render(applied(%{name: "Rain"}), root: true, title: "Snow", description: "cm")
      assert svg =~ ">Snow</title>" and svg =~ ">cm. Line chart, 2 points.</desc>"

      svg = Chart.render(applied(%{name: "Rain"}), root: true, description: "cm", summary: false)
      assert svg =~ ">cm</desc>"

      svg = Chart.render(applied(%{}), root: true, summary: "Two readings.")
      assert svg =~ ">Line chart</title>" and svg =~ ">Two readings.</desc>"
      assert Chart.render(applied(%{}), root: true, responsive: true) =~ "width:100%;height:auto"
    end

    test "without root: nothing changes, and the group renders on a canvas as before" do
      applied = applied(%{name: "Rain"})
      assert Chart.render(applied) == Chart.render(applied, root: false)
      refute Chart.render(applied) =~ "<svg"
      assert is_binary(Chart.render(applied, backend: :canvas, format: :binary_base64))
    end
  end

  test "var/1 is the name-only term, its name the string" do
    assert Chart.var(:unit) == %Var{name: "unit"}
    assert Chart.var("unit") == %Var{name: "unit"}
  end
end
