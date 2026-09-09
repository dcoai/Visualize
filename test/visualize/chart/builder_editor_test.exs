defmodule Visualize.Chart.Builder.EditorTest do
  @moduledoc """
  The fragment editor generated from the schema (spec/14 §18.5-§18.7, spec/10 §15, D-86).

  Nothing here asserts a hand-written list: the properties are that every key of every node
  kind has a control, that every schema default reads back as itself, and that the nodes of
  a fragment are the ones the schema's own walk reaches.
  """
  use ExUnit.Case, async: true

  doctest Visualize.Chart.Builder.Editor

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Visualize.BuilderFixture
  alias Visualize.Chart
  alias Visualize.Chart.Builder.Editor
  alias Visualize.Chart.{Schema, Var}

  @widgets [:checkbox, :number, :text, :textarea]

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
               "frame",
               "frame.size",
               "frame.margin",
               "frame.scales.x",
               "frame.scales.y",
               "frame.axes[0]",
               "frame.axes[1]",
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
      labels = Enum.map(Editor.nodes(%{version: 1}), & &1.label)
      assert labels == ["design"]
    end

    test "an inline theme is a node and a named one is a value" do
      inline = Enum.map(Editor.nodes(%{theme: %{name: :house}}), & &1.label)
      named = Enum.map(Editor.nodes(%{theme: :dark}), & &1.label)
      assert inline == ["design", "theme"]
      assert named == ["design"]
    end
  end

  describe "widget/1 (spec/14 §18.6)" do
    test "every key of every node kind has a control" do
      for kind <- Schema.kinds(), spec <- Schema.describe(kind) do
        widget = Editor.widget(spec.type)

        assert widget in @widgets or match?({:select, [_ | _]}, widget),
               "#{kind}.#{spec.key} (#{inspect(spec.type)}) has no widget: #{inspect(widget)}"
      end
    end

    test "a one_of takes the widget of its first alternative" do
      assert Editor.widget({:one_of, [:name, {:node, :theme}]}) == :text
      assert Editor.widget({:one_of, [:integer, {:list, :term}]}) == :number
      assert Editor.widget({:one_of, [:extent, :name]}) == :textarea
    end
  end

  describe "parse/2 (spec/14 §18.6)" do
    test "every schema default reads back as itself from what the control shows" do
      for kind <- Schema.kinds(),
          spec <- Schema.describe(kind),
          not spec.required,
          spec.default != nil do
        shown =
          case Editor.widget(spec.type) do
            :textarea -> inspect(spec.default)
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
        {:text, ["Uptime — ", %Var{name: :unit}]},
        {:anchor, {:axis, :y}},
        {:channel, {:field, :sha}},
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
      open = render_component(&Editor.panel/1, %{kind: :size, node: %{}, facet: :style})
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

      keys =
        ~r/<span class="vis-builder-key">(\w+)<\/span>/
        |> Regex.scan(html)
        |> Enum.map(fn [_, key] -> key end)

      assert keys == ~w(scale side ticks grid offset)
      assert html =~ ~s(<input type="text" name="scale" value="x">)
      assert html =~ ~s(<option value="bottom" selected>bottom</option>)
      assert html =~ ~s(<input type="checkbox" name="grid" value="true">)
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
