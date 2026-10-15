defmodule Visualize.Chart.StylePartsTest do
  @moduledoc """
  A style in compound parts (spec/14 §3.1, §3.5, §9, D-172): each part's shorthands
  normalize to the stored shape, the flat keys of version 2 are read as the parts they mean
  and projected back to themselves, parts merge key by key with a change of `type`
  replacing the part, and a version 2 design — in a map, in JSON, or built in host code at
  version 3 — is read in parts.
  """
  use ExUnit.Case, async: true

  import Visualize.Chart, only: [var: 1]

  alias Visualize.Chart
  alias Visualize.Chart.{Migration, Style, Validator}

  # One value per flat key of version 2, each what the key took.
  @flat %{
    fill: "#abcdef",
    fill_opacity: 0.4,
    stroke: :axis,
    stroke_opacity: 0.8,
    stroke_width: 2,
    stroke_dasharray: [4, 2],
    stroke_linejoin: :round,
    stroke_linecap: :butt,
    stroke_style: :outside,
    font_family: "Inter",
    font_size: :label_size,
    font_weight: :bold,
    font_style: :italic,
    line_height: 1.4,
    text_anchor: :middle,
    vertical_align: :top,
    margin_x: 4,
    margin_y: 2,
    text_angle: 45,
    opacity: 0.9,
    blend: :multiply,
    effect: :shadow,
    effect_radius: 5,
    class: "critical",
    curve: :cardinal,
    curve_opts: %{tension: 0.5, alpha: 0.25},
    symbol: :star,
    symbol_size: 40
  }

  describe "normalize/1: the stored shape" do
    test "every flat key of version 2 moves into its part" do
      assert Style.normalize(@flat) == %{
               fill: %{type: :solid, color: "#abcdef", opacity: 0.4},
               stroke: %{
                 type: :solid,
                 color: :axis,
                 opacity: 0.8,
                 width: 2,
                 dash: [4, 2],
                 join: :round,
                 cap: :butt,
                 placement: :outside
               },
               font: %{
                 family: "Inter",
                 size: :label_size,
                 weight: :bold,
                 style: :italic,
                 line_height: 1.4
               },
               text: %{anchor: :middle, baseline: :top, offset: [4, 2], angle: 45},
               opacity: 0.9,
               blend: :multiply,
               effect: %{type: :shadow, radius: 5},
               class: "critical",
               curve: %{type: :cardinal, tension: 0.5, alpha: 0.25},
               marker: %{shape: :star, size: 40}
             }
    end

    test "the projection of the parts is the flat node again" do
      assert Style.project(Style.normalize(@flat)) == @flat

      # A placement of `:single`, the flat key's default, is the stroke's `:center`.
      assert Style.normalize(%{stroke_style: :single}) == %{stroke: %{placement: :center}}
      assert Style.project(%{stroke: %{placement: :center}}) == %{stroke_style: :single}

      # One half of the offset is the other half zero, which the placements read as absent.
      assert Style.project(Style.normalize(%{margin_x: 6})) == %{margin_x: 6, margin_y: 0}
    end

    test "each part's shorthands expand, and a node in the stored shape is unchanged" do
      assert Style.normalize(%{fill: :none}) == %{fill: %{type: :none}}
      assert Style.normalize(%{fill: {:paint, :fade}}) == %{fill: %{type: :paint, name: :fade}}

      assert Style.normalize(%{fill: {:field, :c}}) == %{
               fill: %{type: :solid, color: {:field, :c}}
             }

      assert Style.normalize(%{stroke: var(:c)}) == %{stroke: %{type: :solid, color: var(:c)}}

      assert Style.normalize(%{stroke: %{color: :bad, width: 2}}) ==
               %{stroke: %{type: :solid, color: :bad, width: 2}}

      assert Style.normalize(%{curve: :step}) == %{curve: %{type: :step}}
      assert Style.normalize(%{effect: :none}) == %{effect: %{type: :none}}

      assert Style.normalize(%{fill: %{type: :radial, color: [:a, :b, :c], center: [0.2, 0.3]}}) ==
               %{
                 fill: %{
                   type: :radial,
                   stops: [%{at: 0, color: :a}, %{at: 0.5, color: :b}, %{at: 1, color: :c}],
                   center: [0.2, 0.3]
                 }
               }

      stored = Style.normalize(@flat)
      assert Style.normalize(stored) == stored
    end

    test "a value in a part's place that is neither is left where it stands" do
      assert Style.normalize(%{fill: {:bad}}) == %{fill: {:bad}}
      assert Style.normalize(%{curve: 12}) == %{curve: 12}
    end
  end

  describe "merge/2: the merge rule" do
    test "a part merges key by key" do
      warning = %{stroke: %{type: :solid, color: :warning, dash: "6 3"}, fill: :warning}

      assert Style.merge(warning, %{stroke: %{width: 3}}) == %{
               stroke: %{type: :solid, color: :warning, dash: "6 3", width: 3},
               fill: %{type: :solid, color: :warning}
             }
    end

    test "a change of type replaces the part, but for what no type decides" do
      solid = %{
        fill: %{type: :solid, color: :red, opacity: 0.5},
        stroke: %{type: :solid, color: :red, width: 3, dash: [2, 2]}
      }

      linear = %{type: :linear, stops: [%{at: 0, color: :a}, %{at: 1, color: :b}]}

      assert Style.merge(solid, %{fill: linear, stroke: linear}) == %{
               fill: Map.put(linear, :opacity, 0.5),
               stroke: linear |> Map.put(:width, 3) |> Map.put(:dash, [2, 2])
             }

      assert Style.merge(%{curve: %{type: :cardinal, tension: 0.5}}, %{curve: :step}) ==
               %{curve: %{type: :step}}

      assert Style.merge(%{effect: %{type: :shadow, radius: 6}}, %{effect: :blur}) ==
               %{effect: %{type: :blur}}
    end

    test "no paint is a type too: a partial part keeps it, a colour replaces it" do
      outline = %{fill: :none}

      assert Style.merge(outline, %{fill: %{opacity: 0.5}}) == %{
               fill: %{type: :none, opacity: 0.5}
             }

      assert Style.merge(outline, %{fill: :red}) == %{fill: %{type: :solid, color: :red}}
    end

    test "extends and a stack lay parts by the rule" do
      styles =
        Style.all(%{
          base: %{stroke: %{color: "#f00", dash: [4, 2]}, font: %{size: 12}},
          heavy: %{extends: :base, stroke: %{width: 3}}
        })

      assert Style.node(styles, :heavy) ==
               %{stroke: "#f00", stroke_dasharray: [4, 2], stroke_width: 3, font_size: 12}

      assert Style.node(styles, [:base, %{stroke: %{width: 5}, font: %{weight: :bold}}]) ==
               %{
                 stroke: "#f00",
                 stroke_dasharray: [4, 2],
                 stroke_width: 5,
                 font_size: 12,
                 font_weight: :bold
               }

      # A flat inline node stacks over parts as the parts it means.
      assert Style.node(styles, [:base, %{stroke_width: 5}]).stroke_dasharray == [4, 2]
    end

    test "the fragment cascade merges a part key by key, a shorthand under a part included" do
      # Two style fragments cascade key by key as two styles would (§8.2, §19.2).
      stacked =
        Chart.stack([
          %{style: %{stroke: :red, fill: %{type: :solid, color: :red, opacity: 0.5}}},
          %{style: %{stroke: %{width: 3}, fill: %{type: :linear, stops: []}}}
        ])

      assert stacked.style == %{
               stroke: %{type: :solid, color: :red, width: 3},
               fill: %{type: :linear, stops: [], opacity: 0.5}
             }
    end
  end

  describe "version 3" do
    test "a version 2 design migrates its styles and its paints into the shape version 3 holds" do
      v2 = %{
        version: 2,
        frames: %{main: %{kind: :cartesian}},
        defs: %{
          fade: %{
            kind: :radial,
            # spelling: allow — version 2's stop word.
            stops: [%{offset: 0, colour: :series_1}, %{offset: 1, colour: "#fff"}],
            # spelling: allow — version 2's paint word.
            centre: [0.4, 0.4]
          }
        },
        styles: %{s: %{stroke: :series_1, stroke_width: 2, fill: {:paint, :fade}}},
        theme: %{styles: %{muted: %{opacity: 0.3, stroke_dasharray: "2 2"}}},
        marks: [%{type: :line, style: [:s, %{symbol: :star}]}]
      }

      assert {:ok, v3} = Migration.migrate(v2)
      assert v3.version == 3

      assert v3.defs.fade == %{
               type: :radial,
               stops: [%{at: 0, color: {:color, :series_1}}, %{at: 1, color: "#fff"}],
               center: [0.4, 0.4]
             }

      assert v3.styles.s == %{
               stroke: %{type: :solid, color: {:color, :series_1}, width: 2},
               fill: %{type: :paint, name: :fade}
             }

      assert v3.theme.styles.muted == %{opacity: 0.3, stroke: %{dash: "2 2"}}
      # The line drew its fill as the area under it: an `:area` before it now (#659).
      assert [%{type: :area, style: %{fill: %{type: :paint, name: :fade}}}, line] = v3.marks
      assert line.style == [:s, %{marker: %{shape: :star}}]
    end

    test "a design built at version 3 in the flat keys is read in parts too" do
      design = %{
        version: 3,
        frames: %{main: %{kind: :cartesian}},
        styles: %{s: %{stroke: :series_1, stroke_width: 2}}
      }

      assert Validator.validate(design) == :ok
      chart = Chart.from_map!(design)
      assert chart.styles.s == %{stroke: %{type: :solid, color: {:color, :series_1}, width: 2}}

      # A fault in a flat key is reported at the part it means.
      assert {:error, [{[:styles, :s, :stroke, :width], {:type, :size}}]} =
               Validator.validate(put_in(design, [:styles, :s, :stroke_width], "thick"))
    end

    test "a version 2 document in JSON decodes its flat keys typed and migrates them" do
      json = ~s({
        "version": 2,
        "frames": {"main": {"kind": "cartesian"}},
        "defs": {"fade": {"kind": "linear", "stops": [
          {"offset": 0, "color": "series_1"}, {"offset": 1, "color": "#fff"}]}},
        "styles": {
          "s": {"stroke": {"$series": 2}, "stroke_width": 2, "font_weight": "bold",
                "curve": "step", "fill": {"$paint": "fade"}, "text_anchor": "end"}
        }
      })

      assert {:ok, chart} = Chart.from_json(json)

      assert chart.styles.s == %{
               stroke: %{type: :solid, color: {:series, 2}, width: 2},
               font: %{weight: :bold},
               curve: %{type: :step},
               fill: %{type: :paint, name: :fade},
               text: %{anchor: :end}
             }

      assert chart.defs.fade.stops == [
               %{at: 0, color: {:color, :series_1}},
               %{at: 1, color: "#fff"}
             ]

      {:ok, back} = Chart.to_json(chart)
      assert Chart.from_json(back) == {:ok, chart}
    end

    test "a paint under defs is a gradient or a hatch" do
      design = %{version: 3, frames: %{main: %{kind: :cartesian}}}

      assert {:error, [{[:defs, :p, :type], {:enum, [:linear, :radial, :hatch]}}]} =
               Validator.validate(
                 Map.put(design, :defs, %{p: %{type: :solid, color: "#f00", stops: []}})
               )

      assert {:error, errors} = Validator.validate(Map.put(design, :defs, %{p: %{angle: 90}}))
      assert {[:defs, :p, :type], :required} in errors
      assert {[:defs, :p, :stops], :required} in errors

      gradient = %{type: :linear, color: [:series_1, "#fff"]}
      assert Validator.validate(Map.put(design, :defs, %{p: gradient})) == :ok
    end
  end
end
