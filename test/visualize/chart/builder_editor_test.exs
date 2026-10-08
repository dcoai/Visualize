defmodule Visualize.Chart.Builder.EditorTest do
  @moduledoc """
  The fragment editor generated from the schema (spec/14 §18.5-§18.7, spec/10 §15, D-86).

  Nothing here asserts a hand-written list: the properties are that every key of every node
  kind has a control, that every schema default reads back as itself, and that the nodes of
  a fragment are the ones the schema's own walk reaches.
  """
  use ExUnit.Case, async: true

  doctest Visualize.Chart.Builder.Editor
  doctest Visualize.Chart.Builder.Fills
  doctest Visualize.Chart.Builder.Sources
  doctest Visualize.Chart.Builder.Page
  doctest Visualize.Chart.Builder.Stack
  doctest Visualize.Chart.Builder.Styles
  doctest Visualize.Chart.Builder.Palette
  doctest Visualize.Chart.Builder.Library
  doctest Visualize.Chart.Builder.Glyphs
  doctest Visualize.Chart.Builder.StyleStack

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Visualize.BuilderFixture
  alias Visualize.Chart
  alias Visualize.Chart.Builder.Editor
  alias Visualize.Chart.Schema

  @widgets [:checkbox, :number, :text, :textarea, :colour]
  @shaped [:select, :items]

  for name <- ~w(editor_design editor_mark editor_style_errors)a do
    test "#{name} renders as recorded" do
      c = Keyword.fetch!(BuilderFixture.cases(), unquote(name))
      assert BuilderFixture.golden(unquote(name)) == BuilderFixture.render_case(c)
    end
  end

  describe "nodes/1 (spec/14 §18.5)" do
    test "the root is first and carries the empty path" do
      [root | _rest] = Editor.nodes(BuilderFixture.layer(:house))
      assert root == %{path: [], kind: :design, label: "design"}
    end

    test "the walk descends nodes, named declarations and list elements, and stops at values" do
      labels = Enum.map(Editor.nodes(Chart.stack(BuilderFixture.layers())), & &1.label)

      assert labels == [
               "design",
               "sources.primary",
               "vars.unit",
               "styles.series",
               "frames.main",
               "frames.main.margin",
               "frames.main.scales.x",
               "frames.main.scales.y",
               "frames.main.axes[0]",
               "frames.main.axes[1]",
               "marks[0]",
               "marks[0].channels",
               "labels[0]"
             ]
    end

    test "every node's kind is a kind of the schema and its label spells its path" do
      for entry <- Editor.nodes(Chart.stack(BuilderFixture.layers())) do
        assert entry.kind in Schema.kinds()
        assert entry.label == label(entry.path)
      end
    end

    test "a key the fragment does not carry has no node" do
      labels = Enum.map(Editor.nodes(%{version: 2}), & &1.label)
      assert labels == ["design"]
    end

    test "an inline theme is a node and a named one is a value" do
      inline = Enum.map(Editor.nodes(%{theme: %{name: :house}}), & &1.label)
      named = Enum.map(Editor.nodes(%{theme: :dark}), & &1.label)
      assert inline == ["design", "theme"]
      assert named == ["design"]
    end
  end

  describe "a drawn enum is chosen by its picture (spec/14 §18.6)" do
    alias Visualize.Chart.Builder.Glyphs

    test "every value of every drawn key has a picture, and an undrawn key has none" do
      drawn = [
        stroke_linejoin: [:miter, :round, :bevel],
        stroke_linecap: [:butt, :round, :square],
        curve: Schema.curve_types(),
        symbol: Schema.symbol_types(),
        side: [:top, :right, :bottom, :left],
        anchor: [:top, :bottom, :left, :right, :start, :middle, :end],
        position: [
          :top_left,
          :top_right,
          :bottom_left,
          :bottom_right,
          :top,
          :bottom,
          :left,
          :right
        ],
        text_anchor: [:start, :middle, :end],
        orientation: [:vertical, :horizontal],
        link: [:curve, :elbow, :line],
        kind: [:cartesian, :polar, :geo, :facet]
      ]

      for {key, values} <- drawn, value <- values do
        assert Glyphs.drawn?(key)
        svg = Glyphs.glyph(key, value)
        assert is_binary(svg) and svg =~ "<svg", "#{key} #{value} has no picture"
      end

      refute Glyphs.drawn?(:op)
      assert Glyphs.glyph(:op, :sum) == nil
      # A scale's kind is not a frame's: the values decide, and a scale kind has none.
      assert Glyphs.glyph(:kind, :linear) == nil
    end

    test "the form draws a radio per value, the chosen one checked, the word as the name" do
      html =
        render_component(&Editor.panel/1, %{
          kind: :style,
          node: %{stroke_linejoin: :round, curve: :step},
          path: [:styles, :series],
          facet: :style
        })

      assert html =~
               ~s(<span class="vis-builder-glyphs" role="radiogroup" aria-label="stroke_linejoin">)

      assert html =~ ~s(<label class="vis-builder-glyph vis-builder-glyph-on" title="round">)

      assert html =~
               ~s(<input type="radio" name="stroke_linejoin" value="round" checked aria-label="round">)

      assert html =~
               ~s(<input type="radio" name="stroke_linejoin" value="miter" aria-label="miter">)

      assert html =~ ~s(stroke-linejoin="bevel")
      refute html =~ ~s(<select name="stroke_linejoin">)

      # A curve is drawn by the library's own line generator.
      assert html =~
               ~s(<input type="radio" name="curve" value="monotone_x" aria-label="monotone_x">)

      assert length(Regex.scan(~r/name="curve" value=/, html)) == length(Schema.curve_types())

      # And it submits the word the select would.
      assert Editor.change(:style, %{"_target" => ["curve"], "curve" => "natural"}) ==
               {:curve, {:ok, :natural}}
    end

    test "a scale's kind stays a select: its values have no picture" do
      html =
        render_component(&Editor.panel/1, %{
          kind: :scale,
          node: %{kind: :linear},
          path: [:frames, :main, :scales, :x]
        })

      assert html =~ ~s(<select name="kind">)
      refute html =~ "vis-builder-glyphs"
    end
  end

  describe "a ranged number is a slider beside its box (spec/14 §14.2, §18.6)" do
    test "every range in the schema is a sensible span" do
      for kind <- Schema.kinds(), %{range: range} = spec <- Schema.describe(kind), range != nil do
        assert {min, max, step} = range
        assert min < max, "#{kind}.#{spec.key} has min >= max"
        assert step > 0
        assert spec.type in [:number, :integer, :size], "#{kind}.#{spec.key} is not numeric"
      end
    end

    test "the slider stands at the value, and its write is the box's write" do
      html =
        render_component(&Editor.panel/1, %{
          kind: :style,
          node: %{opacity: 0.4, stroke_width: :label_size},
          path: [:styles, :series],
          facet: :style
        })

      # The slider lies over its box, in one span, the box first (§18.6).
      assert html =~
               ~r|<span class="vis-builder-ranged">\s*<input type="text" name="opacity" value="0.4">\s*<input type="range" name="opacity.range" class="vis-builder-range vis-builder-scrubber" style="--vis-builder-scrub: 40.0%" min="0" max="1" step="0.05" value="0.4"|

      # A slot word has no place on a slider: it stands at the floor; the box shows the word.
      assert html =~
               ~s(name="stroke_width.range" class="vis-builder-range vis-builder-scrubber" style="--vis-builder-scrub: 0.0%" min="0" max="20" step="0.5" value="0")

      # The stylesheet lays it over the box: full height, mostly transparent, a dot that
      # alone takes the pointer.
      css = Visualize.Chart.Builder.Styles.css()

      assert css =~
               ~r/\.vis-builder-scrubber \{[^}]*position: absolute;[^}]*opacity: 0\.3;[^}]*pointer-events: none;/s

      assert css =~
               ~r/\.vis-builder-scrubber::-webkit-slider-thumb \{[^}]*border-radius: 50%;[^}]*pointer-events: auto;/s

      assert html =~ ~s(<input type="text" name="stroke_width" value="label_size">)

      assert Editor.change(:style, %{"_target" => ["opacity.range"], "opacity.range" => "0.75"}) ==
               {:opacity, {:ok, 0.75}}

      # A key with no range has no slider.
      refute html =~ ~s(name="stroke.range")
    end

    test "a dash pattern is drawn beside its box" do
      html =
        render_component(&Editor.panel/1, %{
          kind: :style,
          node: %{stroke_dasharray: [4, 2]},
          path: [:styles, :series],
          facet: :style
        })

      assert html =~ ~s(class="vis-builder-dash")
      assert html =~ ~s(stroke-dasharray="4 2")
    end
  end

  describe "widget/1 (spec/14 §18.6)" do
    test "every key of every node kind has a control" do
      for kind <- Schema.kinds(), spec <- Schema.describe(kind) do
        widget = Editor.widget(spec.type)

        assert widget in @widgets or (is_tuple(widget) and elem(widget, 0) in @shaped),
               "#{kind}.#{spec.key} (#{inspect(spec.type)}) has no widget: #{inspect(widget)}"
      end
    end

    test "a one_of takes the widget of its first alternative" do
      assert Editor.widget({:one_of, [:name, {:node, :theme}]}) == :text
      assert Editor.widget({:one_of, [:integer, {:list, :term}]}) == :number
      assert Editor.widget({:one_of, [:anchor, :name]}) == :textarea
    end

    # A channel and an extent are text, not textareas (#371): a name, a number, `auto` or
    # `min, max` are typed as a person writes them; the literal forms still read.
    test "a channel and an extent are text" do
      assert Editor.widget(:channel) == :text
      assert Editor.widget(:extent) == :text

      assert Editor.parse(:channel, "value") == {:ok, :value}
      assert Editor.parse(:channel, ":value") == {:ok, :value}
      assert Editor.parse(:channel, "0") == {:ok, 0}
      assert Editor.parse(:channel, "2.5") == {:ok, 2.5}
      assert Editor.parse(:channel, "{:field, :v}") == {:ok, {:field, :v}}
      assert Editor.parse(:channel, "{:scale, :min}") == {:ok, {:scale, :min}}
      assert Editor.parse(:channel, "not a name") == :error

      assert Editor.parse(:extent, "auto") == {:ok, :auto}
      assert Editor.parse(:extent, "0, 100") == {:ok, [0, 100]}
      assert Editor.parse(:extent, "auto, 100") == {:ok, [:auto, 100]}
      assert Editor.parse(:extent, "-1.5,2") == {:ok, [-1.5, 2]}

      assert Editor.parse(:extent, "2024-01-01T00:00:00Z, 2024-12-31T00:00:00Z") ==
               {:ok, [~U[2024-01-01 00:00:00Z], ~U[2024-12-31 00:00:00Z]]}

      assert Editor.parse(:extent, "[0, 100]") == {:ok, [0, 100]}
      assert Editor.parse(:extent, ~s(["a", "b", "c"])) == {:ok, ["a", "b", "c"]}
      assert Editor.parse(:extent, "1, 2, 3") == :error
      assert Editor.parse(:extent, "low, high") == :error
    end
  end

  describe "parse/2 (spec/14 §18.6)" do
    test "every schema default reads back as itself from what the control shows" do
      # An empty text's default is the empty string, which a blank control is — a removal
      # and the default are one state (§7.1), so it is not read back as a value.
      for kind <- Schema.kinds(),
          spec <- Schema.describe(kind),
          not spec.required,
          spec.default != nil,
          spec.default != "" do
        shown =
          case Editor.widget(spec.type) do
            :textarea -> inspect(spec.default)
            # A list of items has no one control to read back from: its default is its rows.
            {:items, _} -> inspect(spec.default)
            _other -> to_string(spec.default)
          end

        assert Editor.parse(spec.type, shown) == {:ok, spec.default},
               "#{kind}.#{spec.key}: #{shown} did not read back as #{inspect(spec.default)}"
      end
    end

    test "a blank string removes the key rather than setting it" do
      assert Editor.parse(:string, "") == :error
      assert Editor.parse(:integer, "  ") == :error
      assert Editor.parse({:node, :size}, "") == :error
    end

    test "the scalar controls read what they can produce" do
      assert Editor.parse(:boolean, "on") == {:ok, true}
      assert Editor.parse(:boolean, "false") == {:ok, false}
      assert Editor.parse(:boolean, "yes") == :error
      assert Editor.parse(:integer, "6") == {:ok, 6}
      assert Editor.parse(:integer, "6.5") == :error
      assert Editor.parse(:number, "6.5") == {:ok, 6.5}
      assert Editor.parse({:enum, [:top, :bottom]}, "bottom") == {:ok, :bottom}
      assert Editor.parse({:enum, [:top, :bottom]}, "sideways") == :error
      assert Editor.parse(:string, "%H:%M") == {:ok, "%H:%M"}
      assert Editor.parse(:field, "t") == {:ok, :t}
      assert Editor.parse(:field, ":t") == {:ok, :t}
      assert Editor.parse({:ref, :scale}, "x") == {:ok, :x}
    end

    test "a colour, a size and a font read loosely: an atom, a number, or the string" do
      assert Editor.parse(:colour, "#3b6fa8") == {:ok, "#3b6fa8"}
      assert Editor.parse(:colour, ":series_1") == {:ok, :series_1}
      assert Editor.parse(:size, "2") == {:ok, 2}
      assert Editor.parse(:size, "1.5") == {:ok, 1.5}
      assert Editor.parse(:font, "sans-serif") == {:ok, "sans-serif"}
    end

    test "a composite value is read as a literal, and inspect/1 is its inverse" do
      values = [
        {:extent, [0, 100]},
        {:extent, :auto},
        {:extent, [-1, 1]},
        {:anchor, {:axis, :y}},
        {:channel, {:field, :sha}},
        {:channel, {:scale, :min}},
        {:term, %{a: 1, b: [true, false, nil]}},
        {{:node, :size}, %{width: 400, height: 200}},
        {{:list, :field}, [:t, :v]},
        {:term, ~U[2024-01-01 00:00:00Z]}
      ]

      for {type, value} <- values do
        assert Editor.parse(type, inspect(value)) == {:ok, value}
      end
    end

    test "anything outside a design's vocabulary is an error, and nothing is evaluated" do
      for source <- [
            "System.halt()",
            "1 + 1",
            "File.read!(\"/etc/passwd\")",
            "%URI{}",
            "fn -> 1 end",
            "self()",
            "%Visualize.Chart.Var{bogus: 1}",
            "["
          ] do
        assert Editor.parse(:term, source) == :error, "#{source} was accepted"
      end
    end
  end

  describe "panel/1 (spec/14 §18.7)" do
    test "the tabs are the facets of the node kind, in the order of §1.3" do
      html = render_component(&Editor.panel/1, %{kind: :mark, node: BuilderFixture.mark()})

      facets =
        ~r/phx-value-facet="(\w+)"/
        |> Regex.scan(html)
        |> Enum.map(fn [_, facet] -> facet end)

      assert facets == ~w(binding channel geometry style content)

      assert html =~
               ~s(class="vis-builder-tab vis-builder-tab-open" phx-click="facet" ) <>
                 ~s(phx-value-facet="binding")
    end

    test "a facet the node kind does not carry falls back to its first" do
      open = render_component(&Editor.panel/1, %{kind: :margin, node: %{}, facet: :style})
      assert open =~ ~s(phx-value-facet="geometry")
      assert open =~ ~s(class="vis-builder-tab vis-builder-tab-open")
      refute open =~ ~s(phx-value-facet="style")
    end

    test "the keys of the open tab are in the schema's order, with the value and the default" do
      html =
        render_component(&Editor.panel/1, %{
          kind: :axis,
          node: %{scale: :x, side: :bottom},
          facet: :geometry
        })

      # The key span carries an optional origin child now (spec/14 §18.19), so the key is
      # its leading text rather than the whole of it.
      keys =
        ~r/<span class="vis-builder-key">\s*(\w+)/
        |> Regex.scan(html)
        |> Enum.map(fn [_, key] -> key end)

      assert keys == ~w(scale side ticks grid offset radius at)
      assert html =~ ~s(<input type="text" name="scale" value="x">)
      # A side is a drawn enum (§18.6): the chosen one is the checked glyph.
      assert html =~
               ~s(<input type="radio" name="side" value="bottom" checked aria-label="bottom">)

      assert html =~ ~s(<input type="checkbox" name="grid" value="true">)
    end

    test "a style's keys are five blocks under their headings, the ungrouped on their own" do
      html = render_component(&Editor.panel/1, %{kind: :style, node: %{}, facet: :style})

      blocks =
        ~r/<legend class="vis-builder-block-name">(\w+)<\/legend>/
        |> Regex.scan(html)
        |> Enum.map(fn [_, group] -> group end)

      assert blocks == ~w(fill stroke font position effects)
      assert blocks == Enum.map(Schema.groups(:style), &to_string/1)

      # Each block holds its run of keys in table order; extends stands before the first
      # block and class after the last.
      keys =
        ~r/<span class="vis-builder-key">\s*(\w+)/
        |> Regex.scan(html)
        |> Enum.map(fn [_, key] -> key end)

      # The fill block opens with the fill style, in a row of its own (§18.6).
      assert html =~
               ~r|<legend class="vis-builder-block-name">fill</legend>\s*<div class="vis-builder-field vis-builder-field-fill-style">\s*<span class="vis-builder-key">style</span>|

      fill_row =
        html
        |> String.split(~s(phx-value-field="fill"))
        |> Enum.at(1)
        |> String.split("</label>")
        |> hd()

      refute fill_row =~ ~s(name="fill_style")

      assert keys ==
               ~w(extends style opacity colour stroke_style stroke_width stroke stroke_opacity
                  stroke_dasharray stroke_linejoin stroke_linecap font_family font_size
                  font_weight line_height text_anchor vertical_align margin_x margin_y
                  text_angle opacity blend effect effect_radius class curve curve_opts symbol
                  symbol_size)

      {extends, _} = :binary.match(html, ~s(phx-value-field="extends"))
      {first, _} = :binary.match(html, ~s(<fieldset class="vis-builder-block))
      assert extends < first

      stroke =
        html
        |> String.split(~s(<legend class="vis-builder-block-name">stroke</legend>))
        |> Enum.at(1)
        |> String.split("</fieldset>")
        |> hd()

      assert stroke =~ ~s(phx-value-field="stroke_linecap")
      refute stroke =~ ~s(phx-value-field="font_family")

      # A kind whose keys carry no group has no block.
      refute render_component(&Editor.panel/1, %{kind: :axis, node: %{}}) =~
               ~s(<fieldset class="vis-builder-block)
    end

    test "line height shows the points between lines it means" do
      html =
        render_component(&Editor.panel/1, %{
          kind: :style,
          node: %{font_size: 20, line_height: 1.5},
          facet: :style
        })

      assert html =~ ~s(name="line_height.range")
      assert html =~ "10.0 pt between lines"

      # Without a font size the theme's stands in, and without a line height the default.
      html =
        render_component(&Editor.panel/1, %{
          kind: :style,
          node: %{},
          facet: :style,
          theme: Visualize.Theme.default()
        })

      assert html =~
               "#{Float.round(Visualize.Theme.default().font_size * 0.2, 1)} pt between lines"
    end

    test "a key's errors are under its control and nowhere else" do
      html =
        BuilderFixture.render_case(Keyword.fetch!(BuilderFixture.cases(), :editor_style_errors))

      assert html =~
               ~s(<li class="vis-builder-error">styles.series.stroke: slot :series_1 is not a slot of the theme</li>)

      refute html =~ "marks[0].style"
      assert length(Regex.scan(~r/vis-builder-key-errors/, html)) == 2
    end
  end

  describe "the form's id (spec/10 §15.3, #444)" do
    # LiveView recovers a form after a crash or reconnect only by its id, and warns of a
    # `phx-change` form without one.
    test "is derived from the node's path, as a valid HTML id" do
      html =
        render_component(&Editor.panel/1, %{
          kind: :mark,
          node: BuilderFixture.mark(),
          path: [:marks, 0]
        })

      assert form_ids(html) == ["vis-builder-editor-marks-0-form"]
    end

    test "is derived from the node's label when the form carries one" do
      html =
        render_component(&Editor.form_body/1, %{
          kind: :axis,
          node: %{},
          path: [:frames, :main, :axes, 1],
          label: "frames.main.axes[1]"
        })

      assert form_ids(html) == ["vis-builder-editor-frames-main-axes-1-form"]
    end

    test "is derived from the kind at the root path" do
      html = render_component(&Editor.panel/1, %{kind: :mark, node: BuilderFixture.mark()})
      assert form_ids(html) == ["vis-builder-editor-mark-form"]
    end

    test "two node forms on one page differ" do
      ids =
        for path <- [[:marks, 0], [:marks, 1], [:styles, :series]] do
          html = render_component(&Editor.panel/1, %{kind: :mark, node: %{}, path: path})
          [id] = form_ids(html)
          id
        end

      assert length(Enum.uniq(ids)) == 3
    end

    test "an explicit id wins over the derived one" do
      panel =
        render_component(&Editor.panel/1, %{
          id: "host-editor",
          kind: :mark,
          node: %{},
          path: [:marks, 0]
        })

      body =
        render_component(&Editor.form_body/1, %{
          id: "host-body",
          kind: :mark,
          node: %{},
          label: "marks[0]"
        })

      assert form_ids(panel) == ["host-editor-form"]
      assert form_ids(body) == ["host-body-form"]
    end

    test "the events are unchanged" do
      html = render_component(&Editor.panel/1, %{kind: :mark, node: %{}, path: [:marks, 0]})
      assert html =~ ~s(class="vis-builder-form" phx-change="edit")
    end
  end

  defp form_ids(html) do
    ~r/<form id="([^"]*)" class="vis-builder-form"/
    |> Regex.scan(html)
    |> Enum.map(fn [_, id] -> id end)
  end

  defp label(path) do
    Enum.reduce(path, "", fn
      index, acc when is_integer(index) -> "#{acc}[#{index}]"
      key, "" -> "#{key}"
      key, acc -> "#{acc}.#{key}"
    end)
    |> case do
      "" -> "design"
      spelled -> spelled
    end
  end
end
