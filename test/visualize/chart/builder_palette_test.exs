defmodule Visualize.Chart.BuilderPaletteTest do
  @moduledoc """
  The builder's palette shows the theme's palette (spec/14 §18.14, #685, D-178; the redo of
  #639): listed in its five groups beneath the design's styles, each entry in its parts
  previewed in the theme's looks, a design's entry of a palette name marked as overriding
  it, an entry made the design's own by an explicit override written as a style site in
  the design, a style reference offering the palette's names, and the context panel
  resolving names against the design's own theme.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Phoenix.LiveView.Socket
  alias Visualize.BuilderFixture
  alias Visualize.Chart.Builder
  alias Visualize.Chart.Builder.{Palette, Stack, StyleStack}
  alias Visualize.Chart.Use
  alias Visualize.Theme

  defp socket(layers \\ BuilderFixture.layers()) do
    host = %{id: "b", layers: layers, sources: BuilderFixture.sources()}
    {:ok, socket} = Builder.mount(%Socket{})
    {:ok, socket} = Builder.update(host, socket)
    socket
  end

  # The fixture with the house layer's design swapped for `fun` of it.
  defp house(fun) do
    [{:house, house} | rest] = BuilderFixture.layers()
    [{:house, fun.(house)} | rest]
  end

  defp panel(design, extra \\ %{}),
    do: render_component(&Palette.panel/1, Map.merge(%{id: "p", design: design}, extra))

  # The `<li>` of a theme row, by its name.
  defp row(html, name) do
    html |> String.split("<li ") |> Enum.find(&(&1 =~ ~s(phx-value-name="#{name}")))
  end

  describe "listing" do
    test "the theme's palette is listed beneath the design's styles, in its five groups" do
      html = panel(%{styles: %{series: %{stroke: :series_1}}})

      [declared, theme] = String.split(html, "The theme's palette", parts: 2)
      assert declared =~ ~s(<span class="vis-builder-palette-name">series</span>)

      titles =
        Regex.scan(~r/<h4 class="vis-builder-palette-group-title">([^<]+)</, theme,
          capture: :all_but_first
        )

      assert List.flatten(titles) == ["style series", "roles", "states", "furniture", "modifiers"]

      for name <- Theme.style_names(Theme.default()) do
        assert theme =~ ~s(phx-value-name="#{name}"), "#{name} is not listed"
      end
    end

    test "groups/2 is the design's names, then the palette's, each name once" do
      theme = Theme.default()
      groups = Palette.groups(%{styles: %{series: %{}, warning: %{}}}, theme)

      assert List.keyfind(groups, "design", 0) == {"design", [:series, :warning]}
      assert {"roles", roles} = List.keyfind(groups, "roles", 0)
      refute :warning in roles

      flat = Enum.flat_map(groups, &elem(&1, 1))
      assert flat == Enum.uniq(flat)
      assert Enum.sort(flat) == Enum.sort([:series | Theme.style_names(theme)])
    end

    test "a theme with three style series lists three" do
      series =
        for k <- 1..3,
            into: %{},
            do: {:"style_#{k}", Theme.style(Theme.default(), :"style_#{k}")}

      theme = Theme.build(%{Theme.default() | styles: %{}}, styles: series)
      groups = Palette.groups(%{}, theme)

      assert List.keyfind(groups, "style series", 0) ==
               {"style series", [:style_1, :style_2, :style_3]}
    end
  end

  describe "previews" do
    test "an entry is a sample shape, a stroke and a label in the theme's literal colours" do
      theme = Theme.default()
      html = panel(%{})
      warning = row(html, "warning")
      colour = Theme.resolve(theme, :warning, :literal)

      assert warning =~
               ~s(<rect x="2" y="4" width="20" height="14" rx="2" fill="#{colour}" stroke="#{colour}")

      assert warning =~ ~s(<line x1="26" y1="11" x2="46" y2="11" stroke="#{colour}")
      assert warning =~ ~s(stroke-dasharray="#{Theme.style(theme, :warning).stroke.dash}")
      assert warning =~ ~s(<text x="50" y="16" fill="#{colour}")
      refute warning =~ "var(--vis-"
    end

    test "a state entry is laid over a neutral sample" do
      theme = Theme.default()
      neutral = Theme.resolve(theme, :neutral, :literal)

      preview = Palette.preview(theme, :selected, Theme.style(theme, :selected))
      assert {"fill", neutral} in preview.shape
      assert {"stroke", neutral} in preview.shape
      assert {"stroke-width", "2"} in preview.shape

      muted = Palette.preview(theme, :muted, Theme.style(theme, :muted))
      assert {"opacity", "0.25"} in muted.shape
      assert {"fill", neutral} in muted.shape

      # A style that is not a state is drawn as it is: no neutral fill under the grid.
      assert {"fill", "none"} in Palette.preview(theme, :grid, Theme.style(theme, :grid)).shape
    end

    test "a modifier is laid over the neutral sample, showing the one thing it changes" do
      theme = Theme.default()
      neutral = Theme.resolve(theme, :neutral, :literal)

      thick = Palette.preview(theme, :thick, Theme.style(theme, :thick))
      assert {"stroke", neutral} in thick.line
      assert {"stroke-width", "3"} in thick.line

      italic = Palette.preview(theme, :italic, Theme.style(theme, :italic))
      assert {"font-style", "italic"} in italic.label
    end

    test "a text entry draws its label in its own font" do
      theme = Theme.default()
      title = Palette.preview(theme, :title, Theme.style(theme, :title))
      assert {"font-weight", "bold"} in title.label
      assert Enum.any?(title.label, &match?({"font-size", _}, &1))
    end

    test "a value the preview cannot draw is left out" do
      preview =
        Palette.preview(Theme.default(), :style_1, %{
          stroke: %{type: :paint, name: :fade, width: 2}
        })

      refute Enum.any?(preview.shape, &match?({"stroke", _}, &1))
      assert {"stroke-width", "2"} in preview.shape
    end

    test "the palette is the design's theme: dark draws on dark, with dark's colours" do
      dark = Theme.dark()
      html = panel(%{theme: :dark}, %{theme: dark})

      assert html =~
               ~s(<rect width="76" height="22" fill="#{Theme.resolve(dark, :background, :literal)}")

      s = socket(house(&Map.put(&1, :theme, :dark)))
      assert Builder.Editing.editing(s.assigns).palette_theme == dark
    end

    test "an inline theme's own palette entries are what is listed" do
      thick = %{stroke: %{type: :solid, color: {:color, :warning}, width: 4}}
      s = socket(house(&Map.put(&1, :theme, %{styles: %{warning: thick}})))
      theme = Builder.Editing.editing(s.assigns).palette_theme
      assert Theme.style(theme, :warning) == thick
    end

    test "the context panel resolves a palette name against the design's own theme" do
      thick = %{stroke: %{type: :solid, color: {:color, :warning}, width: 4}}
      s = socket(house(&Map.put(&1, :theme, %{styles: %{warning: thick}})))
      {:noreply, s} = Builder.handle_event("select_layer", %{"index" => "2"}, s)
      {:noreply, s} = Builder.handle_event("select_node", %{"node" => "marks[0]"}, s)
      {:noreply, s} = Builder.handle_event("add_style_entry", %{"name" => "warning"}, s)
      {:noreply, s} = Builder.handle_event("select_style_entry", %{"index" => "1"}, s)

      theme = Builder.Editing.editing(s.assigns).palette_theme
      resolved = StyleStack.resolved(%{styles: %{}}, [:warning], theme)
      assert resolved.stroke.width == 4
      # The default theme's warning is not 4 wide: the panel did not read it.
      refute StyleStack.resolved(%{styles: %{}}, [:warning], Theme.default()).stroke[:width] == 4

      html = BuilderFixture.render(s)

      [_, panel] =
        String.split(html, ~s(class="vis-builder-editor vis-builder-style-panel"), parts: 2)

      assert panel =~ ~s(<input type="text" name="stroke.width" value="4">)
    end
  end

  describe "shadowing" do
    test "a design entry of a palette name is marked as overriding the theme's" do
      html = panel(%{styles: %{warning: %{stroke: %{width: 5}}}})
      [declared, _theme] = String.split(html, "The theme's palette", parts: 2)
      assert declared =~ "shadows the theme's"
      [_declared, theme] = String.split(html, "The theme's palette", parts: 2)
      warning = row(theme, "warning")

      assert warning =~ "vis-builder-palette-entry-shadowed"
      assert warning =~ "overridden by the design"
      # Selecting it opens the design's entry, which is the one that draws.
      assert warning =~ ~s(phx-click="select_style")
      refute row(theme, "bad") =~ "shadowed"
    end
  end

  describe "overriding" do
    test "choosing a theme entry marks it and offers an override, writing nothing" do
      s = socket()
      {:noreply, chosen} = Builder.handle_event("choose_palette_style", %{"name" => "warning"}, s)

      assert chosen.assigns.palette_chosen == :warning
      assert BuilderFixture.layers(chosen) == BuilderFixture.layers(s)

      html = BuilderFixture.render(chosen)
      assert html =~ ~s(phx-click="override_style" phx-value-name="warning")
      assert row(html, "warning") =~ "vis-builder-palette-entry-open"
    end

    test "overriding writes the theme's entry as styles.<name> in the design, never in a layer" do
      s = socket()
      before = BuilderFixture.layers(s)
      {:noreply, s} = Builder.handle_event("select_layer", %{"index" => "2"}, s)
      {:noreply, s} = Builder.handle_event("choose_palette_style", %{"name" => "warning"}, s)
      {:noreply, s} = Builder.handle_event("override_style", %{"name" => "warning"}, s)

      # A style site keyed by the name, holding the theme's entry; no layer changed.
      assert Enum.take(BuilderFixture.layers(s), length(before)) == before
      site = Stack.get(s.assigns.uses, s.assigns.selected)
      assert %Use{ref: nil, key: :warning} = site
      assert site.local == %{style: Theme.style(Theme.default(), :warning)}
      assert BuilderFixture.design(s).styles.warning == Theme.style(Theme.default(), :warning)
      assert s.assigns.node_label == "styles.warning"
      assert s.assigns.palette_chosen == nil
      assert s.assigns.notice == nil

      # The design's entry now shadows the theme's.
      html = BuilderFixture.render(s)
      [_declared, theme] = String.split(html, "The theme's palette", parts: 2)
      assert row(theme, "warning") =~ "vis-builder-palette-entry-shadowed"
    end

    test "a state is overridden as the theme gives it, and a name the design declares is opened" do
      s = socket()
      {:noreply, s} = Builder.handle_event("override_style", %{"name" => "selected"}, s)
      assert BuilderFixture.design(s).styles.selected == %{stroke: %{width: 2}}

      count = length(s.assigns.uses)
      {:noreply, again} = Builder.handle_event("override_style", %{"name" => "selected"}, s)
      assert length(again.assigns.uses) == count
      assert again.assigns.node_label == "styles.selected"
    end

    test "a name not of the palette writes nothing" do
      s = socket()
      {:noreply, after_miss} = Builder.handle_event("override_style", %{"name" => "nope"}, s)
      assert after_miss.assigns.uses == s.assigns.uses

      {:noreply, after_choose} =
        Builder.handle_event("choose_palette_style", %{"name" => "nope"}, s)

      assert after_choose.assigns.palette_chosen == nil
    end
  end

  describe "a style reference offers the palette" do
    test "a mark's style select offers the palette's names, grouped" do
      html =
        render_component(Builder, %{
          id: "b",
          layers: BuilderFixture.layers(),
          sources: BuilderFixture.sources(),
          styles: false,
          selected: {:use, 3},
          node_label: "marks[0]",
          facet: :style
        })

      [_, select] = String.split(html, ~s(<select name="style">), parts: 2)
      [select, _] = String.split(select, "</select>", parts: 2)

      assert select =~ ~s(<optgroup label="design">)
      assert select =~ ~s(<option value="series" selected>series</option>)
      assert select =~ ~s(<optgroup label="roles">)
      assert select =~ ~s(<option value="warning">warning</option>)
      assert select =~ ~s(<optgroup label="states">)
      assert select =~ ~s(<option value="selected">selected</option>)
    end

    test "the stack's add offers the design's names and the palette's" do
      html =
        render_component(&StyleStack.panel/1, %{
          id: "st",
          value: :series,
          design: %{styles: %{series: %{}}}
        })

      assert html =~ ~s(<optgroup label="design">)
      assert html =~ ~s(<option value="warning">warning</option>)
      assert html =~ ~s(<option value="caption">caption</option>)

      assert [{"design", [:series]} | _] =
               StyleStack.choices(%{styles: %{series: %{}}}, Theme.default())

      assert {"states", states} = List.keyfind(StyleStack.choices(%{}, Theme.dark()), "states", 0)
      assert :hover in states
    end
  end
end
