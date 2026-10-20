defmodule Visualize.Chart.Builder.StackExplainTest.Looks do
  @moduledoc false
  # A host's generators, for the stack editor's + generator (spec/14 §3.13, §18.18).
  use Visualize.Generators

  defgenerator tone(name, _ctx) do
    name
  end
end

defmodule Visualize.Chart.Builder.StackExplainTest do
  @moduledoc """
  Every stack entry made in the builder, and an element's look explained in the inspector
  (spec/14 §18.9, §18.18, D-178 as amended by #686).
  """
  use ExUnit.Case, async: true

  alias Visualize.BuilderFixture
  alias Visualize.Chart.Builder
  alias Visualize.Chart.Builder.StackExplainTest.Looks
  alias Visualize.Chart.Builder.StyleStack

  doctest Visualize.Chart.Builder.StyleStack, only: [entries: 2, columns: 3]

  setup do
    s = BuilderFixture.socket(BuilderFixture.layers())
    s = Phoenix.Component.assign(s, :generators, [Looks])
    {:noreply, s} = Builder.handle_event("select_layer", %{"index" => "2"}, s)
    {:noreply, s} = Builder.handle_event("select_node", %{"node" => "marks[0]"}, s)
    %{socket: s}
  end

  defp event(s, name, params), do: elem(Builder.handle_event(name, params, s), 1)

  describe "every entry a stack may hold (§18.18)" do
    test "a field entry from the site's data columns, a generator entry, the local node", %{
      socket: s
    } do
      html = BuilderFixture.render(s)
      assert html =~ ~s(<button type="submit" class="vis-builder-style-append">+ field</button>)
      assert html =~ ~s(<option value="t">t</option>)
      assert html =~ ~s(<option value="tone/1">tone/1</option>)

      s = event(s, "add_style_entry", %{"field" => "v"})
      s = event(s, "add_style_entry", %{"generator" => "tone/1", "args" => "[:warning]"})
      s = event(s, "edit_style", %{"_target" => ["opacity"], "opacity" => "0.5"})

      assert BuilderFixture.style_at(s) ==
               ["series", {:field, "v"}, {:generate, "tone", [:warning]}, %{opacity: 0.5}]

      # Each row says what it is.
      html = BuilderFixture.render(s)

      for kind <- ~w(name field generator local) do
        assert html =~ "vis-builder-style-entry-#{kind}"
      end

      assert html =~ "generate tone(:warning)"

      # The design holds the stack, and it applies.
      design = BuilderFixture.design(s)

      assert hd(design.marks).style ==
               ["series", {:field, "v"}, {:generate, "tone", [:warning]}, %{opacity: 0.5}]

      assert {:ok, _applied} =
               Visualize.Chart.apply(design,
                 sources: BuilderFixture.sources(),
                 generators: [Looks]
               )
    end

    test "a generator is checked for its arguments, and an unknown one refused", %{socket: s} do
      wrong = event(s, "add_style_entry", %{"generator" => "tone/1", "args" => "[]"})
      assert wrong.assigns.notice == "tone/1 takes that many arguments"
      assert BuilderFixture.style_at(wrong) == BuilderFixture.style_at(s)

      unknown = event(s, "add_style_entry", %{"generator" => "nope/0", "args" => ""})
      assert unknown.assigns.notice == "nope/0 is not a generator here"

      bad = event(s, "add_style_entry", %{"generator" => "tone/1", "args" => "System.halt()"})
      assert bad.assigns.notice == "a generator's arguments are a list"
    end

    test "entries move by key, and the local entry stays last", %{socket: s} do
      s = event(s, "add_style_entry", %{"name" => "warning"})
      s = event(s, "add_style_entry", %{"field" => "t"})
      assert BuilderFixture.style_at(s) == ["series", "warning", {:field, "t"}]

      s = event(s, "style_entry_key", %{"key" => "ArrowUp", "index" => "2"})
      assert BuilderFixture.style_at(s) == ["series", {:field, "t"}, "warning"]

      s = event(s, "style_entry_key", %{"key" => "ArrowDown", "index" => "0"})
      assert BuilderFixture.style_at(s) == [{:field, "t"}, "series", "warning"]

      s = event(s, "edit_style", %{"_target" => ["opacity"], "opacity" => "0.5"})
      refused = event(s, "style_entry_key", %{"key" => "ArrowDown", "index" => "2"})
      assert refused.assigns.notice =~ "the local style stays last"
      assert BuilderFixture.style_at(refused) == BuilderFixture.style_at(s)
    end

    test "the choices and the offers are the site's" do
      assert {:tone, 1} in StyleStack.generators([Looks])

      assert StyleStack.columns(
               %{sources: %{primary: %{fields: ["t", "v"]}}},
               %{data: :primary},
               %{}
             ) == ["t", "v"]
    end
  end

  describe "an element's look explained (§18.9)" do
    test "each part's chain, from the theme root to the local edit", %{socket: s} do
      s = event(s, "add_style_entry", %{"generator" => "tone/1", "args" => "[:warning]"})
      s = event(s, "edit_style", %{"_target" => ["stroke.width"], "stroke.width" => "5"})
      html = BuilderFixture.render(s)

      assert html =~ "why marks[0] looks as it does"
      [_, look] = String.split(html, ~s(class="vis-builder-look"), parts: 2)
      [_, stroke] = String.split(look, ~r/<h4 class="vis-builder-look-name">\s*stroke/, parts: 2)
      [stroke, _] = String.split(stroke, "</ol>", parts: 2)

      # The chain, lowest first: the theme's root, the mark's series color, the named style,
      # the generator's result, the local edit.
      layers =
        Regex.scan(~r/<span class="vis-builder-look-layer">(\w+)<\/span>/, stroke,
          capture: :all_but_first
        )

      layers = List.flatten(layers)
      assert hd(layers) == "theme"
      assert "style" in layers
      assert "generator" in layers
      assert List.last(layers) == "local"
      assert stroke =~ "generate tone(:warning) → &quot;warning&quot;"
      assert stroke =~ "series"

      # A line draws no fill: the part is marked.
      assert look =~ ~r|fill<span class="vis-builder-look-note"> · not drawn</span>|
    end

    test "a node that draws nothing explains nothing" do
      s = BuilderFixture.socket(BuilderFixture.layers())
      {:noreply, s} = Builder.handle_event("select_node", %{"node" => "styles.series"}, s)
      refute BuilderFixture.render(s) =~ "vis-builder-look"
    end
  end
end
