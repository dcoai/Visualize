defmodule Visualize.Chart.DefaultsTest do
  @moduledoc """
  Inherited defaults (spec/14 §3.7, §3.8, #651, #670, D-174): a design, a frame, a layer and
  a group declare defaults in a style's parts and per mark kind; an element inherits them
  container by container, nearest last, under its style, over a theme root that is every
  part — the base never written, a theme's own laid.
  """
  use ExUnit.Case, async: true

  alias Visualize.{Chart, Theme}
  alias Visualize.Chart.{Composite, Migration, Use, Validator}
  alias Visualize.Chart.Style.Defaults
  alias Visualize.IR.Element

  @rows [%{x: 0, y: 1, k: "a"}, %{x: 1, y: 2, k: "b"}]

  defp design(extra) do
    Map.merge(
      %{
        version: 3,
        sources: %{s: %{fields: [:x, :y, :k]}},
        frames: %{
          main: %{
            kind: :cartesian,
            scales: %{x: %{kind: :linear}, y: %{kind: :linear}},
            axes: [%{scale: :x, side: :bottom}]
          }
        },
        marks: [
          %{type: :line, data: :s, channels: %{x: :x, y: :y}},
          %{type: :rect, data: :s, channels: %{x0: :x, x1: :x, y0: 0, y1: :y}}
        ]
      },
      extra
    )
  end

  defp applied(design, opts \\ []) do
    {:ok, applied} = Chart.apply(design, Keyword.merge([sources: %{s: @rows}], opts))
    applied
  end

  defp all(%Element{children: children} = element),
    do: [element | Enum.flat_map(children, &all/1)]

  defp drawn(design, opts \\ []) do
    design |> applied(opts) |> Chart.generate(resolve: :literal) |> all()
  end

  defp of_type(elements, type), do: Enum.filter(elements, &(&1.type == type))

  defp classed(elements, class),
    do: Enum.filter(elements, &String.contains?(to_string(Map.get(&1.style, :class, "")), class))

  # The style the first element of a type inside the group of a mark class draws with: its
  # own over every group's on the way down to it.
  defp mark_style(elements, mark_class, type) do
    [group | _] = classed(elements, mark_class)
    group |> way_to(type) |> Enum.reduce(%{}, &Map.merge(&2, &1.style))
  end

  defp way_to(%Element{type: type} = element, type), do: [element]

  defp way_to(%Element{children: children} = element, type) do
    Enum.find_value(children, fn child ->
      case way_to(child, type) do
        nil -> nil
        way -> [element | way]
      end
    end)
  end

  describe "containers and kinds" do
    test "a design's stroke default reaches every mark, its kind entry wins for that kind" do
      elements =
        drawn(
          design(%{defaults: %{stroke: %{width: 2, cap: :round}, line: %{stroke: %{width: 1.5}}}})
        )

      line = mark_style(elements, "mark-line", :path)
      rect = mark_style(elements, "mark-rect", :rect)

      assert line.stroke_width == 1.5 and line.stroke_linecap == :round
      assert rect.stroke_width == 2 and rect.stroke_linecap == :round
      # A partial stroke leaves the paint to the layer under it: the series color.
      assert line.stroke == Theme.resolve(Theme.default(), {:series, 1}, :literal)
    end

    test "a nearer container's part defaults beat a farther one's kind entry" do
      design =
        design(%{defaults: %{line: %{stroke: %{width: 1.5}}}})
        |> put_in([:frames, :main, :defaults], %{stroke: %{width: 4}})

      assert mark_style(drawn(design), "mark-line", :path).stroke_width == 4
    end

    test "a mark's own defaults are the nearest container, and its style beats them all" do
      design =
        design(%{defaults: %{stroke: %{width: 2}}})
        |> update_in([:marks], fn [line, rect] ->
          [
            Map.put(line, :defaults, %{stroke: %{width: 3, dash: [2, 2]}}),
            Map.put(rect, :style, %{stroke: %{width: 5}})
          ]
        end)

      elements = drawn(design)
      line = mark_style(elements, "mark-line", :path)
      assert line.stroke_width == 3 and line.stroke_dasharray == "2 2"
      assert mark_style(elements, "mark-rect", :rect).stroke_width == 5
    end

    test "a default paint is the color of every mark that names none; :none turns it off" do
      elements =
        drawn(design(%{defaults: %{stroke: "#123456", rect: %{stroke: :none, fill: "#abcdef"}}}))

      assert mark_style(elements, "mark-line", :path).stroke == "#123456"
      rect = mark_style(elements, "mark-rect", :rect)
      assert rect.stroke == :none and rect.fill == "#abcdef"
    end

    test "a part the kind does not draw is ignored: a default fill fills no line" do
      elements = drawn(design(%{defaults: %{fill: "#abcdef"}}))
      assert mark_style(elements, "mark-line", :path).fill == :none
      assert mark_style(elements, "mark-rect", :rect).fill == "#abcdef"
    end

    test "labels, the axis and the legend inherit the part defaults" do
      design =
        design(%{
          defaults: %{font: %{weight: :bold}, stroke: %{width: 3}, opacity: 0.9},
          labels: [%{anchor: :title, text: "T"}]
        })
        |> update_in([:marks], fn [line, rect] ->
          [Map.put(line, :label, %{text: "\#{field(:k)}", anchor: :top}), rect]
        end)
        |> put_in([:frames, :main, :scales, :color], %{kind: :ordinal, domain: ["a", "b"]})
        |> put_in([:frames, :main, :legend], %{scale: :color})

      elements = drawn(design)
      title = Enum.find(elements, &(&1.type == :text and &1.content == "T"))
      assert title.style.font_weight == :bold

      assert [%{style: %{font_weight: :bold}} | _] =
               elements |> of_type(:text) |> Enum.filter(&(&1.style[:class] == "mark-label"))

      [legend] = classed(elements, "legend") |> Enum.filter(&(&1.style.class == "legend"))
      assert legend.style.opacity == 0.9

      axis = elements |> classed("axis") |> hd() |> all() |> of_type(:path) |> hd()
      assert axis.style.stroke_width == 3
    end
  end

  describe "the theme's root" do
    test "every part is defined, and the base is what an absent key draws" do
      root = Theme.defaults(Theme.default())
      assert Map.keys(root) |> Enum.sort() == Map.keys(Defaults.base()) |> Enum.sort()
      assert root.stroke.width == 1 and root.marker == %{shape: :circle, size: 64}
    end

    test "the base is never written: no defaults draws what it drew" do
      plain = design(%{})
      empty = design(%{defaults: %{}})
      assert drawn(plain) == drawn(empty)

      assert mark_style(drawn(plain), "mark-line", :path)
             |> Map.has_key?(:stroke_width)
             |> Kernel.not()
    end

    test "a theme's own defaults are laid under the design's" do
      theme = Theme.new(defaults: %{stroke: %{width: 1.5}, rect: %{stroke: %{width: 0.5}}})
      elements = drawn(design(%{}), theme: theme)
      assert mark_style(elements, "mark-line", :path).stroke_width == 1.5
      assert mark_style(elements, "mark-rect", :rect).stroke_width == 0.5

      elements = drawn(design(%{defaults: %{stroke: %{width: 2}}}), theme: theme)
      assert mark_style(elements, "mark-line", :path).stroke_width == 2
      # The theme's kind entry is a farther container's: the design's parts beat it.
      assert mark_style(elements, "mark-rect", :rect).stroke_width == 2
    end
  end

  describe "layers and groups" do
    defp site(n, local), do: %Use{id: {:use, n}, ref: nil, local: local}

    test "flatten writes a composite's defaults onto what it places, a nested group nearer" do
      group = %{
        composite: %{
          uses: [site(3, %{mark: %{type: :line, data: :s, channels: %{x: :x, y: :y}}})],
          vars: %{},
          defaults: %{stroke: %{width: 4}}
        }
      }

      layer = %{
        composite: %{
          uses: [
            site(1, %{mark: %{type: :rect, data: :s, channels: %{x0: :x, x1: :x, y0: 0, y1: :y}}}),
            site(2, group)
          ],
          vars: %{},
          defaults: %{stroke: %{width: 2, cap: :round}}
        }
      }

      root = %{
        composite: %{
          uses: [
            site(4, %{source: %{fields: [:x, :y, :k]}}) |> Map.put(:key, :s),
            site(5, %{
              frames: %{
                main: %{kind: :cartesian, scales: %{x: %{kind: :linear}, y: %{kind: :linear}}}
              }
            }),
            site(6, layer)
          ],
          vars: %{}
        }
      }

      {:ok, flat, %{missing: [], keyless: []}} = Composite.flatten(root, fn _ -> :error end)
      [rect, line] = flat.marks
      assert rect.defaults == %{stroke: %{width: 2, cap: :round}}
      assert line.defaults == %{stroke: %{width: 4, cap: :round}}
      refute Map.has_key?(flat.frames.main, :defaults)

      elements = drawn(flat)
      assert mark_style(elements, "mark-line", :path).stroke_width == 4
      assert mark_style(elements, "mark-rect", :rect).stroke_width == 2
    end

    test "a composite without defaults flattens as before, and its defaults are validated" do
      plain = %{composite: %{uses: [site(1, %{mark: %{type: :line}})], vars: %{}}}
      {:ok, flat, _} = Composite.flatten(plain, fn _ -> :error end)
      refute Map.has_key?(hd(flat.marks), :defaults)

      bad = put_in(plain, [:composite, :defaults], %{stroke: %{width: "wide"}, bar: %{}})
      assert {:error, errors} = Validator.validate(bad, :composite)
      assert {[:composite, :defaults, :bar], :unknown_key} in errors
      assert Enum.any?(errors, &match?({[:composite, :defaults, :stroke, :width], _}, &1))
    end
  end

  describe "the schema, the codec and the migration" do
    test "a design with defaults validates and round-trips through its map and JSON" do
      design =
        design(%{
          defaults: %{stroke: %{width: 2}, font: %{family: "Inter"}, line: %{curve: :step}}
        })
        |> put_in([:frames, :main, :defaults], %{fill: %{opacity: 0.5}})

      chart = Chart.from_map!(design)
      assert chart.defaults.line == %{curve: %{type: :step}}
      assert Chart.from_map(Chart.to_map(chart)) == {:ok, chart}
      {:ok, json} = Chart.to_json(chart)
      assert Chart.from_json(json) == {:ok, chart}
    end

    test "a design without defaults has no key for them" do
      refute Map.has_key?(Chart.to_map(Chart.from_map!(design(%{}))), :defaults)
    end

    test "shorthands and bare color names are read in the parts" do
      canonical =
        Migration.canonical(%{version: 3, defaults: %{stroke: :red, line: %{fill: :blue}}})

      assert canonical.defaults == %{
               stroke: %{type: :solid, color: {:color, :red}},
               line: %{fill: %{type: :solid, color: {:color, :blue}}}
             }
    end

    test "a key that is neither a part nor a mark type is refused; text is the part" do
      {:error, errors} =
        Validator.validate(design(%{defaults: %{bar: %{}, text: %{anchor: :middle}, class: "x"}}))

      assert {[:defaults, :bar], :unknown_key} in errors
      assert {[:defaults, :class], :unknown_key} in errors
      refute Enum.any?(errors, &match?({[:defaults, :text | _], _}, &1))

      {:error, errors} = Validator.validate(design(%{defaults: %{text: %{font: %{size: 3}}}}))
      assert {[:defaults, :text, :font], :unknown_key} in errors
    end

    test "a gradient written in defaults is drawn from the frame's defs" do
      gradient = %{type: :linear, color: ["#ffffff", "#000000"]}
      svg = design(%{defaults: %{rect: %{fill: gradient}}}) |> applied() |> Chart.render()
      assert svg =~ ~s(<g class="mark mark-rect" fill="url(#vis-paint-)
      assert svg =~ "<linearGradient"
    end
  end

  describe "explain/2" do
    test "the theme's root, then each container's parts and kind entry, then the stack" do
      design =
        design(%{defaults: %{stroke: %{width: 2}, line: %{stroke: %{dash: [2, 2]}}}})
        |> put_in([:frames, :main, :defaults], %{stroke: %{cap: :round}})
        |> update_in([:marks], fn [line, rect] -> [Map.put(line, :style, :bad), rect] end)

      %{parts: %{stroke: stroke}} = Chart.explain(applied(design), at: [:marks, 0])

      assert Enum.map(stroke.chain, &{&1.layer, &1.container}) == [
               {:theme, :theme},
               {:defaults, :design},
               {:kind, :design},
               {:defaults, {:frame, :main}},
               {:palette, nil}
             ]

      assert stroke.value.cap == :round
    end
  end
end
