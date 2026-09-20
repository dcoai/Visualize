defmodule Visualize.Chart.BuilderTest do
  @moduledoc """
  The builder's shell, its message and its preview (spec/14 §18, spec/10 §15, D-85).

  Every panel is rendered through `Phoenix.LiveViewTest.render_component/2` over the fixed
  layers of `Visualize.BuilderFixture` and compared byte for byte with
  `test/support/builder/<name>.html`. Regenerate only when the markup changes on purpose:

      MIX_ENV=test mix run -e 'Visualize.BuilderFixture.write!()'
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Phoenix.LiveView.Socket
  alias Visualize.BuilderFixture
  alias Visualize.BuilderFixture.{Library, Refusing}
  alias Visualize.Chart
  alias Visualize.Chart.Builder
  alias Visualize.Chart.Builder.Editor
  alias Visualize.Chart.Builder.Glyphs
  alias Visualize.Chart.Builder.Palette
  alias Visualize.Chart.Builder.Preview
  alias Visualize.Chart.Builder.StyleStack
  alias Visualize.Chart.Builder.Variables
  alias Visualize.Chart.Use

  doctest Visualize.Chart.Builder.Masks
  doctest Visualize.Chart.Builder.Picker
  doctest Visualize.Chart.Builder.Variables
  doctest Visualize.Chart.Builder.Fonts

  for name <- ~w(preview preview_errors builder builder_store)a do
    test "#{name} renders as recorded" do
      c = Keyword.fetch!(BuilderFixture.cases(), unquote(name))
      assert BuilderFixture.golden(unquote(name)) == BuilderFixture.render_case(c)
    end
  end

  describe "the preview (spec/14 §18.4)" do
    test "a design that applies is drawn, with no error list" do
      html = rendered(:preview)
      assert html =~ ~s(<div class="vis-builder-preview">)
      assert html =~ ~s(<g class="mark mark-line")
      refute html =~ "vis-builder-errors"
    end

    test "a design that does not apply is its faults, by path, and draws nothing" do
      html = rendered(:preview_errors)
      assert html =~ ~s(<ul class="vis-builder-errors">)

      assert html =~
               ~s(<li class="vis-builder-error">marks[0].data: source :primary is not declared</li>)

      assert html =~
               ~s(<li class="vis-builder-error">marks[0].style: style :series is not declared</li>)

      refute html =~ "<svg"
      refute html =~ "<path"
    end

    test "the variables the preview applies with reach the chart" do
      html =
        render_component(&Preview.panel/1, %{
          design: Chart.stack(BuilderFixture.layers()),
          sources: BuilderFixture.sources(),
          vars: %{unit: "mg/hr"}
        })

      assert html =~ "Uptime — mg/hr"
      refute html =~ "Uptime — %"
    end

    test "the class assign is appended and the pane keeps its own" do
      html = render_component(&Preview.panel/1, %{design: %{}, sources: %{}, class: "tall"})
      assert html =~ ~s(class="vis-builder-preview tall")
    end
  end

  describe "the shell (spec/14 §18.1, §18.2)" do
    test "the root carries the id, the builder class and the class assign" do
      html =
        render_component(Builder, %{
          id: "b",
          layers: BuilderFixture.layers(),
          sources: BuilderFixture.sources(),
          class: "drawer"
        })

      assert html =~ ~s(<div id="b" class="vis-builder drawer">)
      assert html =~ ~s(class="vis-builder-save")
      # No toolbar (#365): New is in the charts column, the chart's controls above the chart.
      refute html =~ "vis-builder-toolbar"
    end

    # The chart's controls act on the middle column's chart, so they sit at its top
    # (spec/10 §15.3, #364): the name form, Save, Deploy — no label, no layer count (#367).
    # keeps New alone.
    test "the chart bar holds the save controls just above the graph; there is no toolbar" do
      html = rendered(:builder_store)
      refute html =~ "vis-builder-toolbar"

      [_, main] = String.split(html, ~s(<main class="vis-builder-main">), parts: 2)
      [bar, graph] = String.split(main, ~s(class="vis-builder-graph"), parts: 2)
      assert bar =~ ~s(<div class="vis-builder-chart-bar">)

      order =
        Regex.scan(~r/vis-builder-(keep|save|deploy|layer-count|control-label)/, bar)
        |> Enum.map(&List.last/1)

      assert order == ~w(keep save deploy)
      refute html =~ "vis-builder-layer-count"
      assert bar =~ ~s(placeholder="Group:sub-group:name" aria-label="save the chart as">)
      refute graph =~ ~s(vis-builder-chart-bar)
    end

    # The New form fills the charts column, so it sits under the column's title (#365),
    # beside the `+` that is its chart-only shortcut.
    test "the New form sits under the Charts title, before the list of charts" do
      html = rendered(:builder_store)
      [_, sidebar] = String.split(html, ~s(<aside class="vis-builder-sidebar">), parts: 2)
      [title, rest] = String.split(sidebar, "</h2>", parts: 2)
      assert title =~ "Charts"
      assert title =~ ~s(phx-click="add_chart")

      [form, _charts] = String.split(rest, ~s(<ol class="vis-builder-charts">), parts: 2)
      assert form =~ ~s(<form class="vis-builder-new" phx-submit="new_fragment" phx-target="-1">)
      assert form =~ ~s(<button type="submit" class="vis-builder-new-submit">New</button>)

      # Without a store there is nothing to make a fragment in, and no form.
      refute rendered(:builder) =~ "vis-builder-new"
    end

    test "a style opened from the library has no chart: its bar offers Save as alone" do
      store = Visualize.Chart.BuilderTest.Styles
      s = BuilderFixture.socket(BuilderFixture.layers(), store: store)
      {:noreply, opened} = Builder.handle_event("add_layer", %{"name" => "style:1"}, s)
      html = BuilderFixture.render(opened)
      [_, bar] = String.split(html, ~s(<div class="vis-builder-chart-bar">), parts: 2)
      [bar, _] = String.split(bar, ~s(class="vis-builder-graph"), parts: 2)

      assert bar =~ ~s(aria-label="save as">)
      refute bar =~ "vis-builder-control-label"
      assert bar =~ ~s(class="vis-builder-put")
      refute bar =~ ~s(vis-builder-save)
      refute bar =~ ~s(vis-builder-deploy)
    end

    test "every assign but the id may be left out" do
      html = render_component(Builder, %{id: "b"})
      assert html =~ ~s(<div id="b" class="vis-builder">)
      assert html =~ "vis-builder-preview"
      refute html =~ "vis-builder-store"
    end

    test "the library is a region of its own, and only when a store is given" do
      plain = rendered(:builder)
      stored = rendered(:builder_store)

      refute plain =~ "vis-builder-library-pane"
      refute plain =~ "vis-builder-panels-library"

      assert stored =~
               ~s(<div class="vis-builder-panels vis-builder-panels-library" style="--vis-builder-context: 400px">)

      assert stored =~ ~s(class="vis-builder-library-pane")
      assert stored =~ ~s(phx-value-name="Uncategorised" phx-target="-1">▾ Uncategorised</button>)
      assert stored =~ ~s(data-builder-fragment="composite:1")
      assert stored =~ ~s(class="vis-builder-put")
    end

    test "the three regions are rendered, the layers in the sidebar and the nodes as tabs" do
      html = rendered(:builder)

      assert html =~ ~s(<div class="vis-builder-panels" style="--vis-builder-context: 400px">)
      assert html =~ ~s(<aside class="vis-builder-sidebar">)
      assert html =~ ~s(<main class="vis-builder-main">)

      assert html =~
               ~s(<div id="builder-graph" class="vis-builder-graph" tabindex="0" phx-hook="BuilderHook" data-builder-target="-1" data-builder-scope="graph">)

      # The stack is inside the sidebar; the graph alone in the main column; the node strip
      # and the page of sections in the inspector (spec/14 §18.16).
      [_, sidebar] = String.split(html, ~s(<aside class="vis-builder-sidebar">), parts: 2)
      [sidebar, _] = String.split(sidebar, "</aside>", parts: 2)
      assert sidebar =~ ~s(class="vis-builder-layers")

      [_, main] = String.split(html, ~s(<main class="vis-builder-main">), parts: 2)

      [main, context] =
        String.split(main, ~s(class="vis-builder-context" phx-hook="BuilderHook"), parts: 2)

      refute main =~ ~s(class="vis-builder-nodes")
      assert main =~ ~s(class="vis-builder-preview")
      assert context =~ ~s(class="vis-builder-nodes")
      assert context =~ ~s(class="vis-builder-page vis-builder-page-0")
    end

    test "the top row is every root the design has, the frame first, then the schema's order (spec/14 §18.13)" do
      html = rendered(:builder)
      assert html =~ ~s(class="vis-builder-node vis-builder-node-open")

      # The selected layer is `house`, which declares three of them; the strip shows all
      # seven, because a person asks where the marks are, not which fragment holds them.
      # Neither the design's own root nor vars is a root tab (§18.13): a declaration is
      # the variable panel's, and the panel opens from the tab that ends the row (#363).
      assert tabs(html, "vis-builder-node") == ~w(frame sources styles marks labels variables)

      # Each root is an icon with its name on hover and for a reader (#314); the sine wave
      # the signals panel had is the sources root's.
      assert html =~ ~s(class="vis-builder-icon vis-builder-icon-root vis-builder-icon-frame")

      assert html =~
               ~s(class="vis-builder-icon vis-builder-icon-root vis-builder-icon-sources" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12 C6 4 9 4 12 12 C15 20 18 20 21 12"/>)

      assert html =~ ~s(aria-label="frame" data-builder-bind-root="frame")
      refute html =~ ~s(phx-target="-1">frame</button>)
    end

    test "a root the schema does not name is its first letter in a ring (spec/14 §18.13)" do
      assert Glyphs.icon("extras") =~
               ~s(<text x="12" y="16" text-anchor="middle" font-size="11" font-weight="700" fill="currentColor" stroke="none">E</text>)

      assert Glyphs.icon("marks") =~ ~s(<rect x="4" y="12" width="4" height="8")
    end

    test "no root is elsewhere: the page is the chart's, whatever layer is selected (spec/14 §18.15)" do
      html = rendered(:builder)
      refute html =~ "vis-builder-node-elsewhere"
      assert html =~ ~s(class="vis-builder-node" title="marks of the chart")
      assert html =~ ~s(class="vis-builder-node" title="frame of the chart")
    end

    test "every section is tagged with the layer that owns it, and another layer's is muted (spec/14 §18.15)" do
      # `house` is selected; the sources are `shared`'s and the marks `panel`'s.
      html = at_node("sources.primary")

      assert html =~
               ~s(<summary class="vis-builder-section-title" title="sources.primary — in shared")

      assert html =~ ~s(>primary<span class="vis-builder-section-layer">shared</span></summary>)

      assert html =~
               ~s(class="vis-builder-section vis-builder-section-top vis-builder-section-other")

      # The frame is `shared`'s at the top (its scales and axes) and `house` gives its size:
      # the size section carries no tag of its own but its keys say where they come from.
      html = at_node("frame")

      assert html =~
               ~s(<div class="vis-builder-page-head vis-builder-section-other" title="frame — in shared">)

      assert html =~ ~s(<span class="vis-builder-origin">house</span>)

      # Selecting `shared` brings its sections forward.
      html = at_node("sources.primary", selected: 1)
      refute html =~ "vis-builder-section-other"
    end

    test "a root tab is one page of sections: the frame reads kind, name, size, binding, then its parts (spec/14 §18.15)" do
      html = at_node("frame")
      # No chips, no facet tabs: sections.
      refute html =~ ~s(class="vis-builder-chips")
      refute html =~ ~s(phx-click="facet")

      page =
        html
        |> String.split(~s(class="vis-builder-page vis-builder-page-0"))
        |> Enum.at(1)
        |> String.split("</details>\n</div>")
        |> hd()

      titles =
        Regex.scan(~r/<summary class="vis-builder-section-title[^"]*"[^>]*>([^<]+)</, page)
        |> Enum.map(&List.last/1)

      assert titles == ["size", "binding", "scales", "axes", "x", "y", "x bottom", "y left"] or
               Enum.take(titles, 2) == ["size", "binding"]

      # Kind and the design's name come first, bare; size holds width, height and the margins
      # in one section; no textarea repeats a part.
      {kind_at, _} = :binary.match(page, ~s(name="kind"))
      {name_at, _} = :binary.match(page, ~s(name="name"))
      {size_at, _} = :binary.match(page, ~s(>size</summary>))
      assert kind_at < size_at and name_at < size_at

      size =
        page
        |> String.split(~s(>size</summary>))
        |> Enum.at(1)
        |> String.split(~s(>binding</summary>))
        |> hd()

      for key <- ~w(width height top right bottom left),
          do: assert(size =~ ~s(name="#{key}"), key)

      refute page =~ ~s(<textarea name="size")
      refute page =~ ~s(<textarea name="scales")
      # Every form carries its node.
      assert page =~ ~s(data-builder-node="frame")
      assert page =~ ~s(<input type="hidden" name="_node" value="frame.size">)
      assert page =~ ~s(<input type="hidden" name="_node" value="meta">)
    end

    test "meta is not a tab; a member root's page is a section per member, each with its facets as sections" do
      html = at_node("frame")
      refute html =~ ~s(phx-value-root="meta")

      html = at_node("marks[0]", selected: 2)
      assert html =~ ~s(<summary class="vis-builder-section-title" title="marks[0] — in panel")
      assert html =~ ~s(>binding</summary>)
      assert html =~ ~s(>channel</summary>)
      # The mark's channels node is a sub-section inside the channel facet, not a textarea.
      refute html =~ ~s(<textarea name="channels")
      assert html =~ ~s(<input type="hidden" name="_node" value="marks[0].channels">)
    end

    test "a section folds and keeps, and an edit in a sub-section's form writes that node" do
      s = BuilderFixture.socket(BuilderFixture.layers())
      {:noreply, s} = Builder.handle_event("select_root", %{"root" => "frame"}, s)
      {:noreply, s} = Builder.handle_event("toggle_section", %{"section" => "frame:size"}, s)
      assert MapSet.member?(s.assigns.collapsed, "frame:size")

      assert BuilderFixture.render(s) =~
               ~r|<details class="vis-builder-section"[^>]*>\s*<summary[^>]*>size<|

      refute BuilderFixture.render(s) =~
               ~r|<details class="vis-builder-section" open[^>]*>\s*<summary[^>]*>size<|

      {:noreply, s} = Builder.handle_event("toggle_section", %{"section" => "frame:size"}, s)
      refute MapSet.member?(s.assigns.collapsed, "frame:size")

      {:noreply, s} =
        Builder.handle_event(
          "edit",
          %{"_target" => ["width"], "width" => "500", "_node" => "frame.size"},
          s
        )

      assert s.assigns.node_label == "frame.size"
      {_, house} = hd(BuilderFixture.layers(s))
      assert house.frame.size.width == 500

      {:noreply, s} =
        Builder.handle_event(
          "edit",
          %{"_target" => ["name"], "name" => "Uptime!", "_node" => "meta"},
          s
        )

      {_, house} = hd(BuilderFixture.layers(s))
      assert house.meta.name == "Uptime!"
    end
  end

  describe "the stack is seeded and not controlled (spec/14 §18.1, D-95)" do
    setup do
      host = %{id: "b", layers: BuilderFixture.layers(), sources: BuilderFixture.sources()}
      {:ok, socket} = Builder.mount(%Socket{})
      {:ok, socket} = Builder.update(host, socket)
      %{host: host, socket: socket}
    end

    test "a reorder survives the next host render", %{host: host, socket: socket} do
      {:noreply, socket} = Builder.handle_event("reorder", %{"from" => 2, "to" => 0}, socket)
      assert BuilderFixture.names(socket) == [:panel, :house, :shared]

      {:ok, socket} = Builder.update(host, socket)
      assert BuilderFixture.names(socket) == [:panel, :house, :shared]
    end

    test "a move, an added layer and a node edit all survive it", %{host: host, socket: socket} do
      {:noreply, moved} =
        Builder.handle_event("reorder", %{"from" => 0, "to" => 2}, socket)

      {:ok, moved} = Builder.update(host, moved)
      assert BuilderFixture.names(moved) == [:shared, :panel, :house]

      stored = Map.put(host, :store, Library)
      {:ok, socket} = Builder.update(stored, socket)

      {:noreply, added} =
        Builder.handle_event("insert", %{"name" => "composite:1", "at" => 3}, socket)

      {:ok, added} = Builder.update(stored, added)
      assert length(BuilderFixture.layers(added)) == length(host.layers) + 1

      # The house opens on its first real node, `styles.series` (§18.13): an edit lands there.
      {:noreply, edited} =
        Builder.handle_event(
          "edit",
          %{"_target" => ["stroke_width"], "stroke_width" => "7"},
          socket
        )

      {:ok, edited} = Builder.update(host, edited)
      assert {_name, %{styles: %{series: %{stroke_width: 7}}}} = hd(BuilderFixture.layers(edited))
    end

    test "a host that changes its list replaces the stack", %{socket: socket} do
      {:noreply, socket} = Builder.handle_event("reorder", %{"from" => 2, "to" => 0}, socket)
      assert BuilderFixture.names(socket) == [:panel, :house, :shared]

      replaced = %{id: "b", layers: [{:only, %{version: 1}}], sources: %{}}
      {:ok, socket} = Builder.update(replaced, socket)
      assert BuilderFixture.names(socket) == [:only]
    end

    test "an imported document is not overwritten by the host's stack", %{
      host: host,
      socket: socket
    } do
      {:ok, document} =
        BuilderFixture.layers() |> Chart.stack() |> Chart.from_map!() |> Chart.to_json()

      {:noreply, socket} = Builder.handle_event("import", %{"document" => document}, socket)
      assert hd(BuilderFixture.names(socket)) == "theme"
      assert length(BuilderFixture.names(socket)) == 12

      {:ok, socket} = Builder.update(host, socket)
      assert length(BuilderFixture.names(socket)) == 12
    end
  end

  describe "the row actions (spec/14 §18.8)" do
    test "every action carries an accessible name and hides its word" do
      html = BuilderFixture.render_case(Keyword.fetch!(BuilderFixture.cases(), :layers))

      # The row is the control: clicking it selects, dragging it reorders.
      assert html =~ ~s(phx-click="select_layer" phx-keydown="layer_key" phx-value-index="0")

      assert html =~
               ~s(title="house, layer 1 of 3, selected: Enter to edit, arrows to move, Right to show what it declares, drag to reorder")

      # The one button left names itself, and is not a drag source: a control inside a
      # draggable row swallows its own click otherwise (spec/14 §18.8).
      assert html =~ ~s(class="vis-builder-layer-toggle")
      assert html =~ ~s(title="Disable house")
      assert html =~ ~s(aria-label="Disable house")
      assert html =~ ~s(draggable="false")
      assert html =~ ~s(<span class="vis-builder-action-label">Disable</span>)

      # Moving is dragging, and selecting no longer needs an icon of its own.
      refute html =~ "vis-builder-layer-up"
      refute html =~ "vis-builder-layer-down"
      # `vis-builder-layer-selected` contains this as a substring, so match the attribute.
      refute html =~ ~s(class="vis-builder-layer-select")
    end

    test "no action rule is out-specified by the generic control rule" do
      # `.vis-builder button` is (0,1,1). A rule written as a bare `.vis-builder-layer-up` is
      # (0,1,0) and loses to it, which is how the icons were defeated the first time; every
      # action rule must therefore be compound.
      for class <- ~w(layer-toggle action-label) do
        bare = ~r/(^|,)\s*\.vis-builder-#{class}\b[^,{]*\{/m

        refute Regex.match?(bare, Builder.css()),
               "a bare .vis-builder-#{class} rule loses to `.vis-builder button`"
      end

      assert Builder.css() =~ ".vis-builder .vis-builder-layer-toggle"
    end
  end

  describe "the style palette (spec/14 §18.14, D-96)" do
    setup do
      host = %{id: "b", layers: BuilderFixture.layers(), sources: BuilderFixture.sources()}
      {:ok, socket} = Builder.mount(%Socket{})
      {:ok, socket} = Builder.update(host, socket)
      %{host: host, socket: socket}
    end

    test "the palette lists what the stack declares, not what the selected layer does" do
      html = rendered(:builder)
      assert html =~ ~s(<div class="vis-builder-palette">)
      assert html =~ ~s(<span class="vis-builder-palette-name">series</span>)

      # The list is read from the stacked design, so it is exactly Palette.names/1 of it.
      assert Palette.names(Chart.stack(BuilderFixture.layers())) == [:series]
    end

    test "a style is created in the selected layer and the editor opens on it", %{socket: s} do
      {:noreply, s} = Builder.handle_event("add_style", %{"name" => "callout"}, s)

      {_name, layer} = hd(BuilderFixture.layers(s))
      assert %{} = layer.styles.callout
      assert s.assigns.node_label == "styles.callout"
      assert s.assigns.notice == nil
    end

    test "a style may be added to a layer that carries no styles at all", %{socket: s} do
      {:noreply, s} = Builder.handle_event("select_layer", %{"index" => "1"}, s)
      {_name, shared} = Enum.at(BuilderFixture.layers(s), 1)
      refute Map.has_key?(shared, :styles)

      {:noreply, s} = Builder.handle_event("add_style", %{"name" => "callout"}, s)
      {_name, shared} = Enum.at(BuilderFixture.layers(s), 1)
      assert shared.styles.callout == %{}
    end

    test "a blank name is a notice and declares nothing", %{socket: s} do
      {:noreply, after_blank} = Builder.handle_event("add_style", %{"name" => "   "}, s)
      assert after_blank.assigns.notice == "a style needs a name"
      assert BuilderFixture.layers(after_blank) == BuilderFixture.layers(s)
    end

    test "selecting a style opens the layer that declares it", %{socket: s} do
      # `series` is the house layer's, which is 0; move off it first so the move is visible.
      {:noreply, s} = Builder.handle_event("select_layer", %{"index" => "2"}, s)
      assert BuilderFixture.selected(s) == 2

      {:noreply, s} = Builder.handle_event("select_style", %{"name" => "series"}, s)
      assert BuilderFixture.selected(s) == 0
      assert s.assigns.node_label == "styles.series"
    end

    test "a style nothing declares changes nothing", %{socket: s} do
      {:noreply, after_miss} = Builder.handle_event("select_style", %{"name" => "nope"}, s)
      assert BuilderFixture.selected(after_miss) == BuilderFixture.selected(s)
      assert after_miss.assigns.node_label == s.assigns.node_label
    end

    test "a mark's style is a select over the declared names, not a box" do
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

      assert html =~ ~s(<select name="style">)
      assert html =~ ~s(<option value="series" selected>series</option>)
      refute html =~ ~s(<input type="text" name="style")
    end

    test "a reference with no names offered stays a text box" do
      # `Editor.panel/1` is renderable with no palette at all, which is what keeps it usable
      # over any node (spec/14 §18.14).
      html =
        Phoenix.LiveViewTest.render_component(&Editor.panel/1, %{
          kind: :mark,
          node: BuilderFixture.mark(),
          path: [:marks, 0],
          facet: :style
        })

      assert html =~ ~s(<input type="text" name="style")
    end
  end

  describe "dropping a fragment into the stack (spec/14 §18.17)" do
    setup do
      host = %{
        id: "b",
        layers: BuilderFixture.layers(),
        sources: BuilderFixture.sources(),
        store: Library
      }

      {:ok, socket} = Builder.mount(%Socket{})
      {:ok, socket} = Builder.update(host, socket)
      %{host: host, socket: socket}
    end

    test "the stack is the drop target and the library is not" do
      html = rendered(:builder_store)
      assert html =~ ~s(phx-hook="BuilderHook" data-builder-target="-1" data-builder-stack="true")

      [_, library] = String.split(html, ~s(class="vis-builder-library-pane"), parts: 2)
      [library, _] = String.split(library, "</aside>", parts: 2)
      refute library =~ "data-builder-stack"
      assert library =~ ~s(data-builder-fragment="composite:1")
    end

    test "a fragment lands at the position it was dropped at", %{socket: s} do
      {:noreply, at_top} =
        Builder.handle_event("insert", %{"name" => "composite:1", "at" => 0}, s)

      assert BuilderFixture.names(at_top) == ["baseline", :house, :shared, :panel]

      {:noreply, midway} =
        Builder.handle_event("insert", %{"name" => "composite:1", "at" => 2}, s)

      assert BuilderFixture.names(midway) == [:house, :shared, "baseline", :panel]

      {:noreply, at_end} =
        Builder.handle_event("insert", %{"name" => "composite:1", "at" => 3}, s)

      assert BuilderFixture.names(at_end) == [:house, :shared, :panel, "baseline"]
    end

    test "a position outside the stack is clamped, because a client's number is not trusted",
         %{socket: s} do
      {:noreply, under} =
        Builder.handle_event("insert", %{"name" => "composite:1", "at" => -5}, s)

      assert BuilderFixture.names(under) == ["baseline", :house, :shared, :panel]

      {:noreply, over} = Builder.handle_event("insert", %{"name" => "composite:1", "at" => 99}, s)
      assert BuilderFixture.names(over) == [:house, :shared, :panel, "baseline"]
    end

    test "the selection and the disabled set follow the insert", %{socket: s} do
      {:noreply, s} = Builder.handle_event("select_layer", %{"index" => "2"}, s)
      {:noreply, s} = Builder.handle_event("toggle_layer", %{"index" => "1"}, s)
      assert BuilderFixture.selected(s) == 2
      assert BuilderFixture.disabled(s) == MapSet.new([1])

      {:noreply, s} = Builder.handle_event("insert", %{"name" => "composite:1", "at" => 0}, s)
      assert BuilderFixture.names(s) == ["baseline", :house, :shared, :panel]
      assert BuilderFixture.selected(s) == 3
      assert BuilderFixture.disabled(s) == MapSet.new([2])
    end

    test "an insert below the selection leaves it where it is", %{socket: s} do
      {:noreply, s} = Builder.handle_event("select_layer", %{"index" => "0"}, s)
      {:noreply, s} = Builder.handle_event("insert", %{"name" => "composite:1", "at" => 2}, s)
      assert BuilderFixture.selected(s) == 0
    end

    test "a name the store does not hold is a notice and changes no layer", %{socket: s} do
      {:noreply, missed} = Builder.handle_event("insert", %{"name" => "nope", "at" => 0}, s)
      assert missed.assigns.notice == "no fragment is stored under nope"
      assert BuilderFixture.layers(missed) == BuilderFixture.layers(s)
    end

    test "an insert survives the next host render", %{host: host, socket: s} do
      {:noreply, s} = Builder.handle_event("insert", %{"name" => "composite:1", "at" => 1}, s)
      {:ok, s} = Builder.update(host, s)
      assert BuilderFixture.names(s) == [:house, "baseline", :shared, :panel]
    end
  end

  describe "the style stack at a site (spec/14 §18.18, D-98)" do
    setup do
      host = %{id: "b", layers: BuilderFixture.layers(), sources: BuilderFixture.sources()}
      {:ok, socket} = Builder.mount(%Socket{})
      {:ok, socket} = Builder.update(host, socket)

      # The panel layer's mark is the style site: it references `:series`.
      {:noreply, socket} = Builder.handle_event("select_layer", %{"index" => "2"}, socket)
      {:noreply, socket} = Builder.handle_event("select_node", %{"node" => "marks[0]"}, socket)
      %{host: host, socket: socket}
    end

    test "the site's stack is rendered in the context panel" do
      html = at_node("marks[0]", selected: 2)

      assert html =~ ~s(<ol id="b-style-stack")
      assert html =~ ~s(data-builder-scope="style")
      assert html =~ ~s(<span class="vis-builder-style-name">series</span>)
    end

    test "a node with no style key has no stack; the layer's context is there instead" do
      refute at_node("frame.size") =~ "vis-builder-style-stack"
      assert at_node("frame.size") =~ ~s(class="vis-builder-layer-context")
    end

    test "adding appends, and a bare reference stays bare until it is not one", %{socket: s} do
      {:noreply, s} = Builder.handle_event("add_style_entry", %{"name" => "axis"}, s)
      assert BuilderFixture.style_at(s) == [:series, :axis]

      # One entry naming a style is written back as a bare reference, so an edit elsewhere
      # does not rewrite a document's shape.
      {:noreply, s} = Builder.handle_event("remove_style_entry", %{"index" => "1"}, s)
      assert BuilderFixture.style_at(s) == :series
    end

    test "a site carrying nothing keeps what it resolved as when something is added" do
      # An axis carries no `style`, and resolves as `:axis` by the schema's default.
      {:ok, socket} = Builder.mount(%Socket{})

      {:ok, socket} =
        Builder.update(
          %{id: "b", layers: [{:only, %{frame: %{axes: [%{scale: :x, side: :bottom}]}}}]},
          socket
        )

      {:noreply, socket} =
        Builder.handle_event("select_node", %{"node" => "frame.axes[0]"}, socket)

      {:noreply, socket} = Builder.handle_event("add_style_entry", %{"name" => "grid"}, socket)

      {_name, layer} = hd(BuilderFixture.layers(socket))
      assert hd(layer.frame.axes).style == [:axis, :grid]
    end

    test "reordering at scope style moves an entry and leaves the layers alone", %{socket: s} do
      {:noreply, s} = Builder.handle_event("add_style_entry", %{"name" => "axis"}, s)
      assert BuilderFixture.style_at(s) == [:series, :axis]

      before = Enum.map(BuilderFixture.layers(s), &elem(&1, 0))

      {:noreply, s} =
        Builder.handle_event("reorder", %{"scope" => "style", "from" => 1, "to" => 0}, s)

      assert BuilderFixture.style_at(s) == [:axis, :series]
      assert Enum.map(BuilderFixture.layers(s), &elem(&1, 0)) == before
    end

    test "a reorder with no scope is still the layer stack", %{socket: s} do
      {:noreply, s} = Builder.handle_event("reorder", %{"from" => 2, "to" => 0}, s)
      assert BuilderFixture.names(s) == [:panel, :house, :shared]
    end

    test "selecting an entry marks it, and changing the stack clears the mark", %{socket: s} do
      {:noreply, chosen} = Builder.handle_event("select_style_entry", %{"index" => "0"}, s)
      assert chosen.assigns.style_entry == 0

      {:noreply, added} = Builder.handle_event("add_style_entry", %{"name" => "axis"}, chosen)
      assert added.assigns.style_entry == nil
    end

    test "an entry with no name is a notice and changes nothing", %{socket: s} do
      {:noreply, blank} = Builder.handle_event("add_style_entry", %{"name" => "  "}, s)
      assert blank.assigns.notice == "a style entry needs a name"
      assert BuilderFixture.style_at(blank) == BuilderFixture.style_at(s)
    end
  end

  describe "the context panel over a style (spec/14 §18.19, D-98)" do
    setup do
      host = %{id: "b", layers: BuilderFixture.layers(), sources: BuilderFixture.sources()}
      {:ok, socket} = Builder.mount(%Socket{})
      {:ok, socket} = Builder.update(host, socket)
      {:noreply, socket} = Builder.handle_event("select_layer", %{"index" => "2"}, socket)
      {:noreply, socket} = Builder.handle_event("select_node", %{"node" => "marks[0]"}, socket)
      {:noreply, socket} = Builder.handle_event("select_style_entry", %{"index" => "0"}, socket)
      %{socket: socket}
    end

    test "an edit lands in the local style and leaves the named one alone", %{socket: s} do
      {:noreply, s} =
        Builder.handle_event(
          "edit_style",
          %{"_target" => ["stroke_width"], "stroke_width" => "7"},
          s
        )

      assert BuilderFixture.style_at(s) == [:series, %{stroke_width: 7}]

      # The shared style is untouched, which is the whole reason the local one exists.
      {_name, house} = hd(BuilderFixture.layers(s))
      assert house.styles.series.stroke_width == 2
    end

    test "a second edit reuses the local style rather than making another", %{socket: s} do
      {:noreply, s} =
        Builder.handle_event(
          "edit_style",
          %{"_target" => ["stroke_width"], "stroke_width" => "7"},
          s
        )

      {:noreply, s} =
        Builder.handle_event("edit_style", %{"_target" => ["opacity"], "opacity" => "0.5"}, s)

      assert BuilderFixture.style_at(s) == [:series, %{stroke_width: 7, opacity: 0.5}]
    end

    test "blanking the last local key removes the local entry", %{socket: s} do
      {:noreply, s} =
        Builder.handle_event(
          "edit_style",
          %{"_target" => ["stroke_width"], "stroke_width" => "7"},
          s
        )

      assert BuilderFixture.style_at(s) == [:series, %{stroke_width: 7}]

      {:noreply, s} =
        Builder.handle_event(
          "edit_style",
          %{"_target" => ["stroke_width"], "stroke_width" => ""},
          s
        )

      # An empty local is not worth keeping, and one entry naming a style is a bare reference.
      assert BuilderFixture.style_at(s) == :series
    end

    test "a key the style kind does not declare changes nothing", %{socket: s} do
      {:noreply, other} =
        Builder.handle_event("edit_style", %{"_target" => ["nonsense"], "nonsense" => "1"}, s)

      assert BuilderFixture.style_at(other) == BuilderFixture.style_at(s)
    end

    test "the panel is shown only when an entry is selected" do
      chosen = at_node("marks[0]", selected: 2, style_entry: 0)
      assert chosen =~ ~s(class="vis-builder-editor vis-builder-style-panel")
      assert chosen =~ ~s(phx-change="edit_style")

      refute at_node("marks[0]", selected: 2) =~ "vis-builder-style-panel"
    end

    test "every field names the entry its value came from" do
      design = %{styles: %{series: %{stroke: "#111", stroke_width: 2}}}

      assert StyleStack.origins(design, [:series, %{stroke_width: 5}]) ==
               %{stroke: "series", stroke_width: "local"}

      # A key nothing sets is named by nothing.
      refute Map.has_key?(StyleStack.origins(design, [:series]), :opacity)
    end

    test "the resolved style is the cascade, and the panel is a view of it" do
      design = %{styles: %{series: %{stroke: "#111", stroke_width: 2}}}

      assert StyleStack.resolved(design, [:series, %{stroke_width: 5}]) ==
               %{stroke: "#111", stroke_width: 5}
    end
  end

  describe "dropping a style fragment onto a site (spec/14 §18.20, §19.6)" do
    defmodule Styles do
      @moduledoc false
      @behaviour Visualize.Chart.Builder.Store

      @entries %{
        {:style, 1} => %{name: "Styles::thick", fragment: %{style: %{stroke_width: 5}}},
        {:frame, 1} => %{name: "Frame::wide", fragment: %{frame: %{size: %{width: 900}}}}
      }

      @impl true
      def list(_context) do
        for {{kind, _} = id, entry} <- @entries, do: %{id: id, name: entry.name, kind: kind}
      end

      @impl true
      def get({kind, _} = id, _context) do
        case Map.fetch(@entries, id) do
          {:ok, entry} -> {:ok, Map.merge(entry, %{id: id, kind: kind})}
          :error -> :error
        end
      end

      @impl true
      def put(_entry, _context), do: {:ok, {:design, 9}}

      @impl true
      def delete(_id, _context), do: :ok

      @impl true
      def import(bundle, context),
        do: Visualize.Chart.Builder.Store.relocate(bundle, context, &put/2)
    end

    setup do
      host = %{
        id: "b",
        layers: BuilderFixture.layers(),
        sources: BuilderFixture.sources(),
        store: Styles
      }

      {:ok, socket} = Builder.mount(%Socket{})
      {:ok, socket} = Builder.update(host, socket)
      {:noreply, socket} = Builder.handle_event("select_layer", %{"index" => "2"}, socket)
      {:noreply, socket} = Builder.handle_event("select_node", %{"node" => "marks[0]"}, socket)
      %{socket: socket}
    end

    test "one gesture makes one write: the site refers to the entry by id", %{socket: s} do
      {:noreply, s} =
        Builder.handle_event(
          "insert",
          %{"scope" => "style", "name" => "style:1", "at" => 1},
          s
        )

      # Nothing joins the layer stack: the entry stays where it is, declared once.
      assert length(BuilderFixture.layers(s)) == 3
      assert BuilderFixture.style_at(s) == [:series, {:style, 1}]

      # The design the frame draws carries the entry's body where its id sat.
      design = BuilderFixture.design(s)
      assert hd(design.marks).style == [:series, %{stroke_width: 5}]
    end

    test "the drop position is honoured and clamped", %{socket: s} do
      {:noreply, top} =
        Builder.handle_event(
          "insert",
          %{"scope" => "style", "name" => "style:1", "at" => 0},
          s
        )

      assert BuilderFixture.style_at(top) == [{:style, 1}, :series]

      {:noreply, over} =
        Builder.handle_event(
          "insert",
          %{"scope" => "style", "name" => "style:1", "at" => 99},
          s
        )

      assert BuilderFixture.style_at(over) == [:series, {:style, 1}]
    end

    test "an entry of another kind is refused, and nothing is written", %{socket: s} do
      {:noreply, refused} =
        Builder.handle_event(
          "insert",
          %{"scope" => "style", "name" => "frame:1", "at" => 0},
          s
        )

      assert refused.assigns.notice == "Frame::wide is a frame, and a style site takes a style"
      assert BuilderFixture.style_at(refused) == BuilderFixture.style_at(s)
      assert length(BuilderFixture.layers(refused)) == length(BuilderFixture.layers(s))
    end

    test "a name the store does not hold is refused", %{socket: s} do
      {:noreply, refused} =
        Builder.handle_event("insert", %{"scope" => "style", "name" => "nope", "at" => 0}, s)

      assert refused.assigns.notice == "no fragment is stored under nope"
      assert length(BuilderFixture.layers(refused)) == length(BuilderFixture.layers(s))
    end

    test "an insert with no scope is still the layer stack", %{socket: s} do
      {:noreply, s} = Builder.handle_event("insert", %{"name" => "frame:1", "at" => 0}, s)

      assert Enum.map(BuilderFixture.layers(s), &elem(&1, 0)) == [
               "Frame::wide",
               :house,
               :shared,
               :panel
             ]
    end
  end

  defmodule Cyclic do
    @moduledoc false
    @behaviour Visualize.Chart.Builder.Store

    @entries %{
      {:composite, 1} => %{
        name: "Loops::a",
        fragment: %{composite: %{uses: [Visualize.Chart.Use.new({:composite, 2})], vars: %{}}}
      },
      {:composite, 2} => %{
        name: "Loops::b",
        fragment: %{composite: %{uses: [Visualize.Chart.Use.new({:composite, 1})], vars: %{}}}
      }
    }

    @impl true
    def list(_context) do
      for {{kind, _} = id, entry} <- @entries, do: %{id: id, name: entry.name, kind: kind}
    end

    @impl true
    def get({kind, _} = id, _context) do
      case Map.fetch(@entries, id) do
        {:ok, entry} -> {:ok, Map.merge(entry, %{id: id, kind: kind})}
        :error -> :error
      end
    end

    @impl true
    def put(_entry, _context), do: {:ok, {:composite, 9}}

    @impl true
    def delete(_id, _context), do: :ok

    @impl true
    def import(bundle, context),
      do: Visualize.Chart.Builder.Store.relocate(bundle, context, &put/2)
  end

  describe "the composer constrained by kind (spec/14 §19.6, §19.9)" do
    defmodule Recording do
      @moduledoc false
      @behaviour Visualize.Chart.Builder.Store

      # Entries live in the calling process — the test — so what `put` wrote can be read.
      def seed(entries), do: Process.put(:entries, entries)
      defp entries, do: Process.get(:entries, %{})

      @impl true
      def list(_context) do
        for {{kind, _} = id, entry} <- entries(), do: %{id: id, name: entry.name, kind: kind}
      end

      @impl true
      def get({kind, _} = id, _context) do
        case Map.fetch(entries(), id) do
          {:ok, entry} -> {:ok, Map.merge(entry, %{id: id, kind: kind})}
          :error -> :error
        end
      end

      @impl true
      def put(%{kind: kind} = entry, _context) do
        id = entry.id || {kind, 100 + map_size(entries())}
        Process.put(:entries, Map.put(entries(), id, Map.take(entry, [:name, :fragment])))
        {:ok, id}
      end

      @impl true
      def delete(_id, _context), do: :ok

      @impl true
      def import(bundle, context),
        do: Visualize.Chart.Builder.Store.relocate(bundle, context, &put/2)
    end

    setup do
      Recording.seed(%{
        {:style, 1} => %{name: "Styles::thick", fragment: %{style: %{stroke_width: 5}}},
        {:style, 2} => %{name: "Styles::faint", fragment: %{style: %{opacity: 0.4}}},
        {:style, 3} => %{name: "Styles::lie", fragment: %{frame: %{kind: :polar}}},
        {:style, 4} => %{name: "Styles::odd", fragment: %{style: %{nonsense: 1}}},
        {:frame, 1} => %{name: "Frame::wide", fragment: %{frame: %{size: %{width: 900}}}},
        {:composite, 1} => %{
          name: "Charts::pair",
          fragment: %{
            composite: %{
              uses: [Use.new({:frame, 1}), %Use{id: {:use, 2}, ref: nil, local: %{version: 1}}],
              vars: %{unit: %{default: "%"}}
            }
          }
        }
      })

      %{socket: BuilderFixture.socket(BuilderFixture.layers(), store: Recording)}
    end

    test "opening a style makes it the stack: one inline site, its form, no preview", %{socket: s} do
      {:noreply, s} = Builder.handle_event("add_layer", %{"name" => "style:1"}, s)

      assert s.assigns.open == %{id: {:style, 1}, name: "Styles::thick", kind: :style}
      assert BuilderFixture.layers(s) == [{"Styles::thick", %{style: %{stroke_width: 5}}}]

      html = BuilderFixture.render(s)
      assert html =~ ~s(phx-value-root="style")
      # The chart's row names it and says its kind; a style is a chart of one site.
      assert html =~ ~s(<span class="vis-builder-chart-kind">style</span>)
      assert html =~ ~s(class="vis-builder-chart-name" title="a style opened from the library")
      refute html =~ ~s(class="vis-builder-preview")
    end

    test "the workspace holds several charts; + adds one frame layer; closing selects the neighbour (spec/14 §18.8, §19.9)",
         %{socket: s} do
      assert Enum.map(s.assigns.charts, & &1.name) == ["chart 1"]
      assert s.assigns.chart == 1

      {:noreply, two} = Builder.handle_event("add_chart", %{}, s)
      assert Enum.map(two.assigns.charts, & &1.name) == ["chart 1", "chart 2"]
      assert two.assigns.chart == 2
      assert [%{local: %{frame: %{}}, ref: nil}] = two.assigns.uses
      assert BuilderFixture.layers(two) == [{"new frame", %{frame: %{}}}]

      html = BuilderFixture.render(two)

      assert html =~
               ~s(<button type="button" class="vis-builder-add" title="add a chart: one frame layer to start")

      assert length(Regex.scan(~r/class="vis-builder-chart-row"/, html)) == 2
      assert html =~ ~s(<li class="vis-builder-chart vis-builder-chart-selected">)
      # The first chart, not selected, shows its layers as names to select.
      assert html =~ ~s(phx-click="select_chart_layer" phx-value-chart="1" phx-value-index="2")

      # Selecting the other chart brings its stack back, unchanged; the new one is parked.
      {:noreply, back} = Builder.handle_event("select_chart", %{"chart" => "1"}, two)
      assert back.assigns.chart == 1
      assert BuilderFixture.layers(back) == BuilderFixture.layers(s)
      assert Enum.at(back.assigns.charts, 1).uses == two.assigns.uses

      # A layer of the other chart, clicked, selects that chart and the layer.
      {:noreply, jumped} =
        Builder.handle_event("select_chart_layer", %{"chart" => "2", "index" => "0"}, back)

      assert jumped.assigns.chart == 2 and BuilderFixture.selected(jumped) == 0

      # Collapse and expand.
      {:noreply, folded} = Builder.handle_event("toggle_chart", %{"chart" => "1"}, jumped)
      refute Enum.at(folded.assigns.charts, 0).expanded
      refute BuilderFixture.render(folded) =~ ~s(phx-click="select_chart_layer")

      # Deploy is the selected chart's; closing it selects the neighbour; the last stays.
      {:noreply, _} = Builder.handle_event("deploy", %{}, jumped)
      assert_received {:visualize_chart_deployed, "b", %{frame: %{}}}
      {:noreply, closed} = Builder.handle_event("close_chart", %{"chart" => "2"}, jumped)
      assert Enum.map(closed.assigns.charts, & &1.id) == [1] and closed.assigns.chart == 1
      {:noreply, kept} = Builder.handle_event("close_chart", %{"chart" => "1"}, closed)
      assert kept.assigns.notice =~ "the last chart stays"
      assert length(kept.assigns.charts) == 1
    end

    test "an edit writes to the site, and closing brings the stack back", %{socket: s} do
      {:noreply, opened} = Builder.handle_event("add_layer", %{"name" => "style:1"}, s)

      {:noreply, edited} =
        Builder.handle_event("edit", %{"_target" => ["opacity"], "opacity" => "0.5"}, opened)

      assert BuilderFixture.layers(edited) ==
               [{"Styles::thick", %{style: %{stroke_width: 5, opacity: 0.5}}}]

      {:noreply, closed} = Builder.handle_event("close", %{}, edited)
      assert closed.assigns.open == nil
      assert BuilderFixture.layers(closed) == BuilderFixture.layers(s)
      assert BuilderFixture.selected(closed) == BuilderFixture.selected(s)
    end

    test "a drop copies a composite as its sites, each holding what its use contributed; a link references it (spec/14 §18.17)",
         %{socket: s} do
      {:noreply, copied} =
        Builder.handle_event("insert", %{"name" => "composite:1", "at" => 0}, s)

      assert BuilderFixture.names(copied) == [
               "Frame::wide",
               "Charts::pair",
               :house,
               :shared,
               :panel
             ]

      [wide, pair | rest] = copied.assigns.uses
      assert %Use{ref: nil, local: %{frame: %{size: %{width: 900}}}} = wide
      assert %Use{ref: nil, local: %{version: 1}} = pair
      assert length(Enum.uniq(Enum.map([wide, pair | rest], & &1.id))) == 5
      # The composite's own vars join the chart's.
      assert copied.assigns.stack_vars == %{unit: %{default: "%"}}
      assert copied.assigns.notice == nil

      # Editing the copy never reaches the library: the entry is what it was.
      # The copy is put on top, so it owns `frame.size` and the edit lands in it (§18.15).
      {:noreply, top} = Builder.handle_event("insert", %{"name" => "composite:1", "at" => 3}, s)
      assert BuilderFixture.names(top) == [:house, :shared, :panel, "Frame::wide", "Charts::pair"]
      {:noreply, s2} = Builder.handle_event("select_layer", %{"index" => "3"}, top)
      {:noreply, s2} = Builder.handle_event("select_node", %{"node" => "frame.size"}, s2)

      {:noreply, edited} =
        Builder.handle_event("edit", %{"_target" => ["width"], "width" => "500"}, s2)

      assert {:ok, %{fragment: %{frame: %{size: %{width: 900}}}}} =
               Recording.get({:frame, 1}, %{})

      assert %Use{ref: nil, local: %{frame: %{size: %{width: 500}}}} =
               Enum.at(edited.assigns.uses, 3)

      # A link is the reference site as before, one use for the whole composite.
      {:noreply, linked} =
        Builder.handle_event("insert", %{"name" => "composite:1", "at" => 0, "as" => "link"}, s)

      assert BuilderFixture.names(linked) == ["Charts::pair", :house, :shared, :panel]
      assert %Use{ref: {:composite, 1}} = hd(linked.assigns.uses)
      assert linked.assigns.stack_vars == %{}
    end

    test "a drop on the graph lands above the selected layer: insert without a position", %{
      socket: s
    } do
      {:noreply, s} = Builder.handle_event("select_layer", %{"index" => "1"}, s)

      {:noreply, dropped} =
        Builder.handle_event("insert", %{"name" => "frame:1", "as" => "copy"}, s)

      assert BuilderFixture.names(dropped) == [:house, :shared, "Frame::wide", :panel]

      assert %Use{ref: nil, local: %{frame: %{size: %{width: 900}}}} =
               Enum.at(dropped.assigns.uses, 2)
    end

    test "the hook sends a link for an Alt-drop and accepts a library drag on the graph (spec/10 §16.3)" do
      js = Visualize.Hooks.Builder.js_hook()
      assert js =~ "return e.altKey ? 'link' : 'copy';"
      assert js =~ "this.push('insert', { name: stored, at: at, as: this.dropAs(e) });"

      assert js =~
               "if (name !== null) this.push('place', { name: name, as: this.dropAs(e), x: point.x, y: point.y });"

      assert js =~ "if (this.from !== null) return !graph;"
    end

    test "a linked layer wears a lock, its forms are read-only, and it opens to be edited (spec/14 §18.8, §18.15)",
         %{socket: s} do
      {:noreply, s} =
        Builder.handle_event("insert", %{"name" => "frame:1", "at" => 3, "as" => "link"}, s)

      assert BuilderFixture.names(s) == [:house, :shared, :panel, "Frame::wide"]
      html = BuilderFixture.render(s)

      # The row: locked class, the lock button that opens it, the title saying so.
      assert html =~ ~s(class="vis-builder-layer vis-builder-layer-locked" data-builder-layer="3")

      assert html =~
               ~s(class="vis-builder-layer-lock" title="Open Frame::wide — from the library, edited by opening it")

      assert html =~ ~s(phx-click="open_layer" phx-value-index="3")

      assert html =~
               "Frame::wide, layer 4 of 4: Enter to edit, arrows to move, Right to show what it declares, drag to reorder, from the library: o to open"

      assert length(Regex.scan(~r/vis-builder-layer-lock"/, html)) == 1

      # Its mask is the site's, not the entry's: the › Mask item under its row lists the
      # entry's keys and a tick masks one in the chart, the entry untouched (§18.8, #316).
      {:noreply, m} = Builder.handle_event("toggle_layer_detail", %{"index" => "3"}, s)
      {:noreply, m} = Builder.handle_event("toggle_layer_mask", %{"index" => "3"}, m)
      masked_html = BuilderFixture.render(m)
      assert masked_html =~ ~s(<input type="hidden" name="_index" value="3">)
      assert masked_html =~ ~s(name="frame.size" value="true">)

      {:noreply, m} =
        Builder.handle_event(
          "mask",
          %{"_target" => ["frame.size"], "_index" => "3", "frame.size" => "true"},
          m
        )

      assert Enum.at(m.assigns.uses, 3).mask == [[:frame, :size]]
      assert BuilderFixture.render(m) =~ ~s(name="frame.size" value="true" checked>)

      # Its page: `frame.size` is Frame::wide's word (width 900, on top), so the form is
      # disabled under the note, and an edit is refused with the notice.
      {:noreply, s} = Builder.handle_event("select_layer", %{"index" => "3"}, s)
      {:noreply, s} = Builder.handle_event("select_node", %{"node" => "frame.size"}, s)
      html = BuilderFixture.render(s)
      assert html =~ ~s(class="vis-builder-form-body vis-builder-form-locked" disabled)
      assert html =~ "from the library — open it to edit"
      assert html =~ "vis-builder-page-locked"

      {:noreply, refused} =
        Builder.handle_event("edit", %{"_target" => ["width"], "width" => "500"}, s)

      assert refused.assigns.uses == s.assigns.uses
      assert refused.assigns.notice == "Frame::wide is from the library — open it to edit"

      # The site's own parts stay the site's: it disables and enables.
      {:noreply, off} = Builder.handle_event("toggle_layer", %{"index" => "3"}, s)
      assert BuilderFixture.disabled(off) == MapSet.new([3])

      # The lock, and `o`, open the entry at the chart level.
      {:noreply, opened} = Builder.handle_event("open_layer", %{"index" => "3"}, s)
      assert opened.assigns.open == %{id: {:frame, 1}, name: "Frame::wide", kind: :frame}

      {:noreply, by_key} = Builder.handle_event("layer_key", %{"key" => "o", "index" => "3"}, s)
      assert by_key.assigns.open.id == {:frame, 1}

      # An inline layer has nothing to open, and no lock.
      {:noreply, same} = Builder.handle_event("open_layer", %{"index" => "0"}, s)
      assert same.assigns.open == s.assigns.open
      refute BuilderFixture.render(s) =~ ~s(phx-click="open_layer" phx-value-index="0")
    end

    test "a section another, locked layer owns is read-only from any selection", %{socket: s} do
      {:noreply, s} =
        Builder.handle_event("insert", %{"name" => "frame:1", "at" => 3, "as" => "link"}, s)

      # `house` selected; the size is Frame::wide's, so its form is locked while the
      # sources section, which is `shared`'s, is not.
      {:noreply, s} = Builder.handle_event("select_layer", %{"index" => "0"}, s)
      {:noreply, s} = Builder.handle_event("select_node", %{"node" => "frame.size"}, s)
      assert BuilderFixture.render(s) =~ "vis-builder-form-locked"

      {:noreply, s} = Builder.handle_event("select_node", %{"node" => "sources.primary"}, s)
      refute BuilderFixture.render(s) =~ "vis-builder-form-locked"
    end

    test "a component dropped on the graph is placed where it landed (spec/14 §18.16)", %{
      socket: s
    } do
      # The fixture chart is 400×200 with margins 20/20/30/40 and scales x and y. An axis
      # in the bottom band: an x axis at the bottom, no scale to bring — and the same
      # identity as shared's, so it goes above shared, whose axis it replaces, and the
      # design still has two axes, the new site's the one that draws.
      {:noreply, s1} =
        Builder.handle_event("place", %{"component" => "axis", "x" => 200, "y" => 190}, s)

      assert BuilderFixture.names(s1) == [:house, :shared, "new axis", :panel]

      assert %Use{ref: nil, local: %{axis: %{scale: :x, side: :bottom}}} =
               Enum.at(s1.assigns.uses, 2)

      assert BuilderFixture.selected(s1) == 2
      assert s1.assigns.node_label =~ ~r/^frame\.axes\[\d\]$/
      assert length(BuilderFixture.design(s1).frame.axes) == 2

      # In the right band: a y axis on the right; `y` is declared, so no scale site.
      {:noreply, s2} =
        Builder.handle_event("place", %{"component" => "axis", "x" => 395, "y" => 100}, s)

      assert %Use{local: %{axis: %{scale: :y, side: :right}}} = Enum.at(s2.assigns.uses, 1)
      assert length(BuilderFixture.design(s2).frame.axes) == 3

      # A title in the top band; a label in the plot at the nearest corner.
      {:noreply, s3} =
        Builder.handle_event("place", %{"component" => "title", "x" => 200, "y" => 5}, s)

      assert %Use{local: %{label: %{anchor: :title, text: ["Title"]}}} =
               Enum.at(s3.assigns.uses, 1)

      assert s3.assigns.node_label =~ ~r/^labels\[\d\]$/

      {:noreply, s4} =
        Builder.handle_event("place", %{"component" => "label", "x" => 370, "y" => 160}, s)

      assert %Use{local: %{label: %{anchor: {:frame, :bottom_right}}}} =
               Enum.at(s4.assigns.uses, 1)

      # A mark of a type; a word that is no component.
      {:noreply, s5} =
        Builder.handle_event("place", %{"component" => "mark:circle", "x" => 200, "y" => 100}, s)

      assert %Use{local: %{mark: %{type: :circle}}} = Enum.at(s5.assigns.uses, 1)
      assert s5.assigns.node_label =~ ~r/^marks\[\d\]$/

      {:noreply, s6} =
        Builder.handle_event("place", %{"component" => "banana", "x" => 1, "y" => 1}, s)

      assert s6.assigns.notice == "banana is not a component"
      assert s6.assigns.uses == s.assigns.uses
    end

    test "an axis brings the scale it needs, beneath it", %{socket: _s} do
      only_x = [{:base, %{frame: %{kind: :cartesian, scales: %{x: %{kind: :linear}}}}}]
      s = BuilderFixture.socket(only_x)

      {:noreply, s} =
        Builder.handle_event("place", %{"component" => "axis", "region" => "left"}, s)

      assert BuilderFixture.names(s) == ["base", "new scale", "new axis"]

      assert %Use{key: :y, local: %{scale: %{kind: :linear, domain: :auto}}} =
               Enum.at(s.assigns.uses, 1)

      assert %Use{local: %{axis: %{scale: :y, side: :left}}} = Enum.at(s.assigns.uses, 2)
      assert BuilderFixture.design(s).frame.scales.y == %{kind: :linear, domain: :auto}
    end

    test "a legend takes the ordinal scale and is written through the ownership rule; none is a notice",
         %{socket: s} do
      {:noreply, refused} =
        Builder.handle_event("place", %{"component" => "legend", "x" => 200, "y" => 100}, s)

      assert refused.assigns.notice == "a legend needs a colour scale"
      assert refused.assigns.uses == s.assigns.uses

      with_colour =
        BuilderFixture.layers() ++
          [{:colours, %{frame: %{scales: %{c: %{kind: :ordinal, domain: ["a", "b"]}}}}}]

      s = BuilderFixture.socket(with_colour, selected: 0)

      {:noreply, placed} =
        Builder.handle_event("place", %{"component" => "legend", "x" => 370, "y" => 30}, s)

      # No layer owns `frame.legend`, so it goes to the frame's owner — the highest layer
      # with a value under `frame`, `colours` (§18.15) — not to the selected `house`.
      assert %Use{local: %{frame: %{legend: %{scale: :c, position: :top_right}}}} =
               List.last(placed.assigns.uses)

      assert placed.assigns.node_label == "frame.legend"
      assert BuilderFixture.design(placed).frame.legend == %{scale: :c, position: :top_right}
    end

    test "the + menu and the palette's keys place a component in its home region", %{socket: s} do
      # An x axis at the bottom replaces shared's, so it is placed above shared.
      {:noreply, added} = Builder.handle_event("add_site", %{"kind" => "axis"}, s)
      assert %Use{local: %{axis: %{scale: :x, side: :bottom}}} = Enum.at(added.assigns.uses, 2)
      assert added.assigns.node_label =~ ~r/^frame\.axes\[\d\]$/

      {:noreply, added} = Builder.handle_event("add_site", %{"kind" => "label"}, s)
      assert %Use{local: %{label: %{anchor: {:axis, :x}}}} = Enum.at(added.assigns.uses, 1)

      {:noreply, added} = Builder.handle_event("add_site", %{"kind" => "mark"}, s)
      assert %Use{local: %{mark: %{type: :line}}} = Enum.at(added.assigns.uses, 1)

      # Any other kind is the empty site it was.
      {:noreply, added} = Builder.handle_event("add_site", %{"kind" => "style"}, s)
      assert %Use{local: %{style: %{}}} = Enum.at(added.assigns.uses, 1)

      {:noreply, keyed} =
        Builder.handle_event("component_key", %{"key" => "Insert", "component" => "title"}, s)

      assert %Use{local: %{label: %{anchor: :title}}} = Enum.at(keyed.assigns.uses, 1)
    end

    test "a library entry dropped on the graph is its copy, snapped where the region names a place",
         %{socket: s} do
      Recording.seed(%{
        {:axis, 1} => %{name: "Axes::y", fragment: %{axis: %{scale: :y, side: :left, ticks: 3}}}
      })

      {:noreply, s1} =
        Builder.handle_event("place", %{"name" => "axis:1", "x" => 395, "y" => 100}, s)

      assert %Use{ref: nil, local: %{axis: %{scale: :y, side: :right, ticks: 3}}} =
               Enum.at(s1.assigns.uses, 1)

      {:noreply, s2} =
        Builder.handle_event("place", %{"name" => "axis:1", "x" => 200, "y" => 100}, s)

      assert %Use{ref: nil, local: %{axis: %{side: :left}}} = Enum.at(s2.assigns.uses, 1)

      {:noreply, s3} =
        Builder.handle_event(
          "place",
          %{"name" => "axis:1", "as" => "link", "x" => 395, "y" => 100},
          s
        )

      assert %Use{ref: {:axis, 1}} = Enum.at(s3.assigns.uses, 1)
    end

    test "the Components section and the hook's drop (spec/10 §16.3)", %{socket: s} do
      html = BuilderFixture.render(s)
      assert html =~ ~s(phx-value-name="Components" phx-target="-1">▾ Components</button>)
      assert html =~ ~s(data-builder-component="axis")
      assert html =~ ~s(data-builder-component="mark:line" phx-keydown="component_key")

      js = Visualize.Hooks.Builder.js_hook()
      assert js =~ "e.dataTransfer.setData('application/x-visualize-component', word);"
      assert js =~ "return graph && types.includes('application/x-visualize-component');"
      assert js =~ "const sx = rect.width > 0 ? width / rect.width : 1;"
      assert js =~ "this.push('place', { component: word, x: point.x, y: point.y });"
    end

    test "a placed mark guesses its channels over the chart's first source, marked until edited (spec/14 §18.16)",
         %{socket: s} do
      # The fixture's one source is `primary` with fields [:t, :v]; a line guesses x: t, y: v.
      {:noreply, s1} =
        Builder.handle_event("place", %{"component" => "mark:line", "x" => 200, "y" => 100}, s)

      [_, placed | _] = s1.assigns.uses

      assert %Use{local: %{mark: %{type: :line, data: :primary, channels: %{x: :t, y: :v}}}} =
               placed

      label = s1.assigns.node_label
      assert label =~ ~r/^marks\[\d\]$/
      assert s1.assigns.guessed == MapSet.new(["#{label}.channels.x", "#{label}.channels.y"])

      # It draws at once, and the channel fields say they were guessed.
      html = BuilderFixture.render(s1)
      assert length(Regex.scan(~r/class="mark mark-line"/, html)) == 2

      assert html =~
               ~s(class="vis-builder-field vis-builder-field-guess" title="guessed from the source&#39;s fields — check it")

      assert length(Regex.scan(~r/vis-builder-field-guess"/, html)) == 2

      # Editing `x` clears its mark alone; changing `data` clears the mark's guesses.
      {:noreply, s2} = Builder.handle_event("select_node", %{"node" => label <> ".channels"}, s1)
      {:noreply, s2} = Builder.handle_event("edit", %{"_target" => ["x"], "x" => "v"}, s2)
      assert s2.assigns.guessed == MapSet.new(["#{label}.channels.y"])
      assert length(Regex.scan(~r/vis-builder-field-guess"/, BuilderFixture.render(s2))) == 1

      {:noreply, s3} = Builder.handle_event("select_node", %{"node" => label}, s1)

      {:noreply, s3} =
        Builder.handle_event("edit", %{"_target" => ["data"], "data" => "primary"}, s3)

      assert s3.assigns.guessed == MapSet.new()

      # A rect over two fields binds x0 and x1 and leaves y0, y1 for the needs marks.
      {:noreply, s4} =
        Builder.handle_event("place", %{"component" => "mark:rect", "x" => 200, "y" => 100}, s)

      assert %Use{local: %{mark: %{type: :rect, data: :primary, channels: %{x0: :t, x1: :v}}}} =
               Enum.at(s4.assigns.uses, 1)

      # `+ mark` guesses the same; a chart with no source places the type alone.
      {:noreply, s5} = Builder.handle_event("add_site", %{"kind" => "mark"}, s)
      assert %Use{local: %{mark: %{type: :line, data: :primary}}} = Enum.at(s5.assigns.uses, 1)

      bare = BuilderFixture.socket([{:base, %{frame: %{kind: :cartesian}}}])
      {:noreply, s6} = Builder.handle_event("add_site", %{"kind" => "mark"}, bare)
      assert %Use{local: %{mark: %{type: :line}}} = Enum.at(s6.assigns.uses, 1)
      assert s6.assigns.guessed == MapSet.new()
    end

    test "a placed node is moved on the graph to another region, in the layer that owns it (spec/14 §18.16)",
         %{socket: s} do
      # The fixture's axes are shared's: x at the bottom, y at the left. Moving the x axis
      # to the top band writes its side to shared and keeps its scale.
      {:noreply, s1} =
        Builder.handle_event("move", %{"node" => "frame.axes[0]", "x" => 200, "y" => 5}, s)

      assert %Use{local: %{frame: %{axes: [%{scale: :x, side: :top}, _]}}} =
               Enum.at(s1.assigns.uses, 1)

      assert s1.assigns.node_label == "frame.axes[0]"
      assert BuilderFixture.design(s1).frame.axes |> Enum.map(& &1.side) == [:top, :left]

      # The same region again is nothing; a mark does not move; a region by name works.
      {:noreply, same} =
        Builder.handle_event("move", %{"node" => "frame.axes[0]", "x" => 200, "y" => 190}, s)

      assert same.assigns.uses == s.assigns.uses

      {:noreply, mark} =
        Builder.handle_event("move", %{"node" => "marks[0]", "x" => 200, "y" => 5}, s)

      assert mark.assigns.uses == s.assigns.uses and mark.assigns.notice == nil

      {:noreply, s2} =
        Builder.handle_event("move", %{"node" => "frame.axes[1]", "region" => "right"}, s)

      assert %Use{local: %{frame: %{axes: [_, %{scale: :y, side: :right}]}}} =
               Enum.at(s2.assigns.uses, 1)

      # A title to the bottom band becomes a caption; into the plot, the nearest corner.
      {:noreply, s3} =
        Builder.handle_event("move", %{"node" => "labels[0]", "x" => 200, "y" => 190}, s)

      assert %Use{local: %{labels: [%{anchor: :caption}]}} = Enum.at(s3.assigns.uses, 2)

      {:noreply, s4} =
        Builder.handle_event("move", %{"node" => "labels[0]", "x" => 370, "y" => 160}, s)

      assert %Use{local: %{labels: [%{anchor: {:frame, :bottom_right}}]}} =
               Enum.at(s4.assigns.uses, 2)

      # The render carries the frame for the hook's overlay.
      assert BuilderFixture.render(s) =~ ~s(data-builder-frame="400 200 20 20 30 40")
    end

    test "a legend moves between the margins and the plot's positions; a locked owner refuses" do
      with_legend =
        BuilderFixture.layers() ++
          [
            {:colours,
             %{
               frame: %{
                 scales: %{c: %{kind: :ordinal, domain: ["a"]}},
                 legend: %{scale: :c, position: :top_right}
               }
             }}
          ]

      Recording.seed(%{
        {:axis, 1} => %{name: "Axes::y", fragment: %{axis: %{scale: :y, side: :left, ticks: 3}}}
      })

      s = BuilderFixture.socket(with_legend, store: Recording)

      {:noreply, s1} =
        Builder.handle_event("move", %{"node" => "frame.legend", "x" => 20, "y" => 100}, s)

      assert %Use{local: %{frame: %{legend: %{position: :left}}}} = List.last(s1.assigns.uses)

      {:noreply, s2} =
        Builder.handle_event("move", %{"node" => "frame.legend", "x" => 50, "y" => 160}, s)

      assert %Use{local: %{frame: %{legend: %{position: :bottom_left}}}} =
               List.last(s2.assigns.uses)

      # A linked layer's axis is the library's word: the move is refused with the notice.
      {:noreply, s3} =
        Builder.handle_event("insert", %{"name" => "axis:1", "at" => 9, "as" => "link"}, s)

      {:noreply, refused} =
        Builder.handle_event("move", %{"node" => "frame.axes[1]", "region" => "top"}, s3)

      assert refused.assigns.uses == s3.assigns.uses
      assert refused.assigns.notice == "Axes::y is from the library — open it to edit"
    end

    test "the hook moves a movable drawn node, draws the region while it drags, and has the keyboard twin (spec/10 §16.3)" do
      js = Visualize.Hooks.Builder.js_hook()

      assert js =~
               "return label.startsWith('frame.axes[') || label === 'frame.legend' || label.startsWith('labels[');"

      # A drawn node is moved with the pointer, never an HTML5 drag (spec/10 §16.3, #277).
      refute js =~ "application/x-visualize-node"
      assert js =~ "if (this.scope === 'graph') return this.startMove(e);"
      assert js =~ "if (label === null || !this.movable(label)) return;"

      assert js =~
               "if (!moved && Math.abs(ev.clientX - start.x) + Math.abs(ev.clientY - start.y) < 4) return;"

      assert js =~ "this.el.classList.add('vis-builder-moving');"
      assert js =~ "if (!moved) return;"

      assert js =~
               "if (this.scope === 'graph') this.markRegion(this.regionAt(this.chartPoint(e)));"

      assert js =~ "this.el.classList.toggle('vis-builder-region-' + name, region === name);"
      assert js =~ "this.push('move', { node: label, x: point.x, y: point.y });"
      assert js =~ "this.push('move', { node: label, region: region });"

      assert js =~
               "const regions = { ArrowUp: 'top', ArrowDown: 'bottom', ArrowLeft: 'left', ArrowRight: 'right', Enter: 'plot' };"

      css = Builder.css()

      for region <- ~w(top bottom left right plot),
          do: assert(css =~ ".vis-builder .vis-builder-region-#{region}::after")
    end

    test "an axis moved between orientations takes the scale its new side reads, bringing it when missing (spec/14 §18.16, #279)",
         %{socket: s} do
      # The fixture's x axis to the right: it reads `y`, as the left axis does — not `x`,
      # whose range is the plot's width and would run off the side.
      {:noreply, s1} =
        Builder.handle_event("move", %{"node" => "frame.axes[0]", "region" => "right"}, s)

      assert %Use{
               local: %{frame: %{axes: [%{scale: :y, side: :right}, %{scale: :y, side: :left}]}}
             } =
               Enum.at(s1.assigns.uses, 1)

      html = BuilderFixture.render(s1)
      # Drawn the plot's height on the right: the domain path of an axis on the right spans y.
      assert html =~
               ~s|<g class="axis axis-right" data-node="frame.axes[0]" transform="translate(340,0)">|

      assert html =~ ~s|<path d="M6,150H0V0H6"|

      # Back to the bottom, it reads `x` again.
      {:noreply, s2} =
        Builder.handle_event("move", %{"node" => "frame.axes[0]", "region" => "bottom"}, s1)

      assert %Use{local: %{frame: %{axes: [%{scale: :x, side: :bottom}, _]}}} =
               Enum.at(s2.assigns.uses, 1)

      # A chart with no vertical scale: the move brings `y` beneath the axis's owner.
      only_x =
        [
          {:base,
           %{
             frame: %{
               kind: :cartesian,
               scales: %{x: %{kind: :linear}},
               axes: [%{scale: :x, side: :bottom}]
             }
           }}
        ]

      s3 = BuilderFixture.socket(only_x)

      {:noreply, s4} =
        Builder.handle_event("move", %{"node" => "frame.axes[0]", "region" => "left"}, s3)

      assert BuilderFixture.names(s4) == ["new scale", "base"]
      assert %Use{key: :y, local: %{scale: %{kind: :linear, domain: :auto}}} = hd(s4.assigns.uses)

      assert %Use{local: %{frame: %{axes: [%{scale: :y, side: :left}]}}} =
               List.last(s4.assigns.uses)

      assert BuilderFixture.design(s4).frame.scales.y == %{kind: :linear, domain: :auto}
    end

    test "a layer row opens on the kinds it declares, and a kind opens its page in the inspector (spec/14 §18.8, #285)",
         %{socket: s} do
      html = BuilderFixture.render(s)
      # The expander, closed; no six-dot handle on the row.
      assert html =~
               ~s(class="vis-builder-layer-expand" title="show what shared declares" aria-label="show what shared declares" aria-expanded="false" phx-click="toggle_layer_detail" phx-value-index="1")

      refute html =~ "vis-builder-layer-detail"
      refute Builder.css() =~ ".vis-builder-layer::before"

      # Open `shared`: sources, scales, axes — the kinds alone, and nothing it does not declare.
      {:noreply, s1} = Builder.handle_event("toggle_layer_detail", %{"index" => "1"}, s)
      html = BuilderFixture.render(s1)
      assert html =~ ~s(aria-expanded="true" phx-click="toggle_layer_detail" phx-value-index="1")

      kinds =
        Regex.scan(~r/phx-value-index="1" phx-value-kind="([a-z]+)"/, html)
        |> Enum.map(&Enum.at(&1, 1))

      assert kinds == ~w(sources scales axes)
      refute html =~ "x · bottom"

      {:noreply, s2} = Builder.handle_event("toggle_layer_detail", %{"index" => "0"}, s)

      assert Regex.scan(
               ~r/phx-value-index="0" phx-value-kind="([a-z]+)"/,
               BuilderFixture.render(s2)
             )
             |> Enum.map(&Enum.at(&1, 1)) == ~w(theme styles frame)

      {:noreply, s3} = Builder.handle_event("toggle_layer_detail", %{"index" => "2"}, s)

      assert Regex.scan(
               ~r/phx-value-index="2" phx-value-kind="([a-z]+)"/,
               BuilderFixture.render(s3)
             )
             |> Enum.map(&Enum.at(&1, 1)) == ~w(vars marks labels)

      # A kind opens its page in the inspector with the layer selected.
      {:noreply, o} =
        Builder.handle_event("open_declared", %{"index" => "0", "kind" => "styles"}, s)

      assert BuilderFixture.selected(o) == 0 and o.assigns.node_label == "styles.series" and
               o.assigns.context == :inspect

      {:noreply, o} =
        Builder.handle_event("open_declared", %{"index" => "1", "kind" => "axes"}, s)

      assert BuilderFixture.selected(o) == 1 and o.assigns.node_label == "frame"

      {:noreply, o} =
        Builder.handle_event("open_declared", %{"index" => "2", "kind" => "marks"}, s)

      assert BuilderFixture.selected(o) == 2 and o.assigns.node_label == "marks[0]"

      {:noreply, o} =
        Builder.handle_event("open_declared", %{"index" => "2", "kind" => "vars"}, s)

      assert BuilderFixture.selected(o) == 2 and o.assigns.context == :variables

      # The keys: Right opens, Left closes; the button closes again.
      {:noreply, keyed} =
        Builder.handle_event("layer_key", %{"key" => "ArrowRight", "index" => "1"}, s)

      assert BuilderFixture.render(keyed) =~
               ~s(aria-expanded="true" phx-click="toggle_layer_detail" phx-value-index="1")

      {:noreply, keyed} =
        Builder.handle_event("layer_key", %{"key" => "ArrowLeft", "index" => "1"}, keyed)

      refute BuilderFixture.render(keyed) =~ "vis-builder-layer-detail"
      {:noreply, closed} = Builder.handle_event("toggle_layer_detail", %{"index" => "1"}, s1)
      refute BuilderFixture.render(closed) =~ "vis-builder-layer-detail"

      # An empty site declares nothing yet.
      {:noreply, empty} = Builder.handle_event("add_site", %{"kind" => "style"}, s)
      {:noreply, empty} = Builder.handle_event("toggle_layer_detail", %{"index" => "1"}, empty)
      assert BuilderFixture.render(empty) =~ "declares nothing yet"
    end

    test "a layer referencing a composite lists the kinds the composite declares (spec/14 §18.8, #283)",
         %{socket: s} do
      # `Charts::pair` is a composite of a reference to `Frame::wide` and an inline site.
      {:noreply, s1} =
        Builder.handle_event("insert", %{"name" => "composite:1", "at" => 3, "as" => "link"}, s)

      {:noreply, s1} = Builder.handle_event("toggle_layer_detail", %{"index" => "3"}, s1)
      html = BuilderFixture.render(s1)
      refute html =~ "declares nothing yet"
      assert html =~ ~s(phx-value-index="3" phx-value-kind="frame")

      # A disabled layer still lists what it declares.
      {:noreply, s2} = Builder.handle_event("toggle_layer", %{"index" => "3"}, s1)
      assert BuilderFixture.render(s2) =~ ~s(phx-value-index="3" phx-value-kind="frame")
    end

    test "the composer takes only its kind; the workspace takes anything", %{socket: s} do
      {:noreply, opened} = Builder.handle_event("add_layer", %{"name" => "style:1"}, s)

      {:noreply, refused} =
        Builder.handle_event("insert", %{"name" => "frame:1", "at" => 0}, opened)

      assert refused.assigns.notice == "a style composer takes a style; Frame::wide is a frame"
      assert BuilderFixture.layers(refused) == BuilderFixture.layers(opened)

      {:noreply, stacked} =
        Builder.handle_event("insert", %{"name" => "style:2", "at" => 0}, opened)

      assert BuilderFixture.names(stacked) == ["Styles::faint", "Styles::thick"]
      assert BuilderFixture.design(stacked) == %{style: %{opacity: 0.4, stroke_width: 5}}

      {:noreply, s} = Builder.handle_event("insert", %{"name" => "frame:1", "at" => 0}, s)
      {:noreply, s} = Builder.handle_event("insert", %{"name" => "style:1", "at" => 0}, s)
      assert length(BuilderFixture.layers(s)) == 5
    end

    test "saving one bare site writes the body; saving a stack writes structure", %{socket: s} do
      {:noreply, opened} = Builder.handle_event("add_layer", %{"name" => "style:1"}, s)

      {:noreply, edited} =
        Builder.handle_event("edit", %{"_target" => ["opacity"], "opacity" => "0.5"}, opened)

      {:noreply, saved} =
        Builder.handle_event("put_design", %{"name" => "Styles::thicker"}, edited)

      assert saved.assigns.notice == nil
      assert saved.assigns.open == %{id: {:style, 1}, name: "Styles::thicker", kind: :style}

      assert {:ok, %{fragment: %{style: %{stroke_width: 5, opacity: 0.5}}}} =
               Recording.get({:style, 1}, %{})

      {:noreply, stacked} =
        Builder.handle_event("insert", %{"name" => "style:2", "at" => 0, "as" => "link"}, opened)

      {:noreply, _saved} =
        Builder.handle_event("put_design", %{"name" => "Styles::both"}, stacked)

      assert {:ok, %{name: "Styles::both", fragment: %{composite: %{uses: uses}}}} =
               Recording.get({:style, 1}, %{})

      assert [%Use{ref: {:style, 2}}, %Use{ref: nil, local: %{style: %{stroke_width: 5}}}] = uses
    end

    test "a new fragment of a kind starts empty and valid, and is saved under a new id", %{
      socket: s
    } do
      {:noreply, new} = Builder.handle_event("new_fragment", %{"kind" => "scale"}, s)
      assert new.assigns.open == %{id: nil, name: nil, kind: :scale}
      assert BuilderFixture.layers(new) == [{"new scale", %{scale: %{}}}]
      refute BuilderFixture.render(new) =~ "vis-builder-error"

      {:noreply, saved} = Builder.handle_event("put_design", %{"name" => "Scales::hour"}, new)
      assert %{id: {:scale, _}, name: "Scales::hour", kind: :scale} = saved.assigns.open
      assert {:ok, %{fragment: %{scale: %{}}}} = Recording.get(saved.assigns.open.id, %{})
    end

    test "a composite entry opens as its sites, labelled by the store, with its vars", %{
      socket: s
    } do
      {:noreply, opened} = Builder.handle_event("add_layer", %{"name" => "composite:1"}, s)

      assert BuilderFixture.names(opened) == ["Frame::wide", "local"]
      assert opened.assigns.stack_vars == %{unit: %{default: "%"}}

      assert BuilderFixture.design(opened) ==
               %{version: 1, frame: %{size: %{width: 900}}, vars: %{unit: %{default: "%"}}}

      html = BuilderFixture.render(opened)
      assert html =~ "Charts"
      assert html =~ ~s(class="vis-builder-preview")

      {:noreply, saved} = Builder.handle_event("put_design", %{"name" => "Charts::pair"}, opened)
      assert saved.assigns.notice == nil

      assert {:ok, %{fragment: %{composite: %{vars: %{unit: %{default: "%"}}}}}} =
               Recording.get({:composite, 1}, %{})
    end

    test "what does not flatten to its kind, or is not valid as one, is refused", %{socket: s} do
      {:noreply, lie} = Builder.handle_event("add_layer", %{"name" => "style:3"}, s)
      {:noreply, refused} = Builder.handle_event("put_design", %{"name" => "x"}, lie)

      assert refused.assigns.notice ==
               "this was opened as a style and is now a frame; a saved style must still be one"

      {:noreply, odd} = Builder.handle_event("add_layer", %{"name" => "style:4"}, s)
      {:noreply, refused} = Builder.handle_event("put_design", %{"name" => "x"}, odd)
      assert refused.assigns.notice =~ "not a valid style"
      assert BuilderFixture.render(odd) =~ "vis-builder-error"
    end
  end

  describe "the context panel over a layer, and the typed controls (spec/14 §19.5, §19.10)" do
    setup do
      %{socket: BuilderFixture.socket(BuilderFixture.layers(), store: Library)}
    end

    test "a layer's mask is the › Mask item under its row, not the context panel (spec/14 §18.8, #316)",
         %{
           socket: s
         } do
      html = BuilderFixture.render(s)
      assert html =~ ~s(<h3 class="vis-builder-context-title">house</h3>)
      # No checkboxes in the context panel; the item appears once the row is open.
      refute html =~ ~s(class="vis-builder-masks")
      refute html =~ "vis-builder-layer-mask-toggle"

      {:noreply, open} = Builder.handle_event("toggle_layer_detail", %{"index" => "0"}, s)
      html = BuilderFixture.render(open)
      assert html =~ ~s(phx-click="toggle_layer_mask" phx-value-index="0")
      assert html =~ "› Mask</button>"
      refute html =~ ~s(class="vis-builder-masks")
      # The item is the open row's first line, the kinds beneath it (#319).
      {mask_at, _} = :binary.match(html, "vis-builder-layer-mask\"")
      {kinds_at, _} = :binary.match(html, "vis-builder-layer-detail\"")
      assert mask_at < kinds_at

      {:noreply, s} = Builder.handle_event("toggle_layer_mask", %{"index" => "0"}, open)
      html = BuilderFixture.render(s)
      assert html =~ "⌄ Mask</button>"
      assert html =~ ~s(<form class="vis-builder-masks" phx-change="mask")
      assert html =~ ~s(<input type="hidden" name="_index" value="0">)
      assert html =~ ~s(name="frame.margin" value="true">)
      refute html =~ ~s(name="frame.margin" value="true" checked>)

      {:noreply, masked} =
        Builder.handle_event(
          "mask",
          %{"_target" => ["frame.margin"], "_index" => "0", "frame.margin" => "true"},
          s
        )

      assert hd(masked.assigns.uses).mask == [[:frame, :margin]]
      assert BuilderFixture.render(masked) =~ ~s(name="frame.margin" value="true" checked>)

      # The house's contribution no longer carries the margin, so the layers below show through.
      {_house, house} = hd(BuilderFixture.layers(masked))
      refute Map.has_key?(house.frame, :margin)
      assert Map.has_key?(house.frame, :size)

      # An unchecked box submits nothing, which is the path leaving.
      {:noreply, back} =
        Builder.handle_event("mask", %{"_target" => ["frame.margin"], "_index" => "0"}, masked)

      assert hd(back.assigns.uses).mask == []

      # The form names the layer: a row other than the selected one writes its own mask.
      {:noreply, other} =
        Builder.handle_event(
          "mask",
          %{"_target" => ["theme"], "_index" => "1", "theme" => "true"},
          back
        )

      assert Enum.at(other.assigns.uses, 1).mask == [[:theme]]
      assert hd(other.assigns.uses).mask == []
    end

    test "a disabled layer is said to be, not drawn as every box checked", %{socket: s} do
      {:noreply, off} = Builder.handle_event("toggle_layer", %{"index" => "0"}, s)
      {:noreply, off} = Builder.handle_event("toggle_layer_detail", %{"index" => "0"}, off)
      {:noreply, off} = Builder.handle_event("toggle_layer_mask", %{"index" => "0"}, off)
      html = BuilderFixture.render(off)
      assert html =~ "disabled — every key is masked"
      refute html =~ ~s(class="vis-builder-masks")

      # And a mask event on it changes nothing.
      {:noreply, same} =
        Builder.handle_event("mask", %{"_target" => ["theme"], "theme" => "true"}, off)

      assert hd(same.assigns.uses).mask == :all
    end

    test "the layer's free variables are named, pointing at the Variables tab" do
      s = BuilderFixture.socket(BuilderFixture.parameterised(), selected: 3)
      assert BuilderFixture.render(s) =~ "needs var(:accent), var(:ticks)"
    end

    test "a colour field is a well showing its colour, and no select or picker" do
      html = at_node("styles.series", selected: 0)

      assert html =~
               ~s(<span class="vis-builder-well" style="--vis-builder-swatch: #3b6fa8" title="series_1" role="img" aria-label="stroke: series_1" data-builder-well="stroke">)

      refute html =~ ~s(name="stroke.slot")
      refute html =~ ~s(<input type="color" name="stroke")
      refute html =~ "stroke.mode"

      # A hex is itself, none is hatched, unset is empty, a slot the theme lacks has no colour.
      theme = Visualize.Theme.default()
      assert Editor.well("#123456", theme) == %{colour: "#123456", none?: false, word: "#123456"}
      assert Editor.well(:none, theme) == %{colour: nil, none?: true, word: "none"}
      assert Editor.well(nil, theme) == %{colour: nil, none?: false, word: nil}
      assert Editor.well(:nonsense, theme) == %{colour: nil, none?: false, word: "nonsense"}
      assert Editor.well({:series, 2}, theme).colour == Enum.at(theme.series, 1)

      # The chooser's controls still write the same key: a slot is the atom, a hex the
      # string, blank removes.
      assert Editor.change(:style, %{"_target" => ["fill.slot"], "fill.slot" => "axis"}) ==
               {:fill, {:ok, :axis}}

      assert Editor.change(:style, %{"_target" => ["fill"], "fill" => "#3b6fa8"}) ==
               {:fill, {:ok, "#3b6fa8"}}

      assert Editor.change(:style, %{"_target" => ["fill.slot"], "fill.slot" => ""}) ==
               {:fill, :error}
    end

    test "a reference offers what the document declares and what the library holds, by id" do
      store = Visualize.Chart.BuilderTest.Styles

      s =
        BuilderFixture.socket(BuilderFixture.layers(),
          store: store,
          selected: 2,
          node_label: "marks[0]",
          facet: :style
        )

      html = BuilderFixture.render(s)
      assert html =~ ~s(<option value="series" selected>series</option>)
      assert html =~ ~s(<option value="style:1">style:1</option>)

      # And the id reads back as an id, never as an atom.
      assert Editor.parse({:ref, :style}, "style:1") == {:ok, {:style, 1}}
      assert Editor.parse({:ref, :style}, "frame:1") == {:ok, :"frame:1"}
    end
  end

  describe "deploy is the other verb (spec/14 §19.6, D-103)" do
    setup do
      %{
        socket:
          BuilderFixture.socket(BuilderFixture.layers(), store: Library, on_deploy: :deployed)
      }
    end

    test "the flat design is sent, and never a composite", %{socket: s} do
      {:noreply, s} = Builder.handle_event("insert", %{"name" => "composite:1", "at" => 0}, s)
      {:noreply, deployed} = Builder.handle_event("deploy", %{}, s)

      assert_received {:deployed, "b", design}
      refute Map.has_key?(design, :composite)
      assert design.frame.kind == :cartesian
      assert {:ok, _applied} = Chart.apply(design, sources: BuilderFixture.sources())
      assert deployed.assigns.notice == nil

      # Save still carries the structure: the two verbs are different.
      {:noreply, _} = Builder.handle_event("save", %{}, s)
      assert_received {:visualize_chart_saved, "b", %{composite: _}}
    end

    test "a reference that showed through is named", %{socket: s} do
      # A site whose entry the store no longer holds (D-100): the library lists design:2
      # but cannot get it.
      uses = s.assigns.uses
      s = Phoenix.Component.assign(s, :uses, uses ++ [Use.new(Library.missing_id(), uses)])
      {:noreply, deployed} = Builder.handle_event("deploy", %{}, s)
      assert_received {:deployed, "b", _design}

      assert deployed.assigns.notice ==
               "deployed with 1 reference(s) showing through: composite:2"
    end

    test "a stack that reaches itself is refused, and nothing is sent" do
      store = Visualize.Chart.BuilderTest.Cyclic
      s = BuilderFixture.socket([], store: store, on_deploy: :deployed)

      {:noreply, s} =
        Builder.handle_event("insert", %{"name" => "composite:1", "at" => 0, "as" => "link"}, s)

      {:noreply, refused} = Builder.handle_event("deploy", %{}, s)
      refute_received {:deployed, _, _}
      assert refused.assigns.notice =~ "refers to itself"
    end

    test "not while a style is open: there is no chart to deploy" do
      store = Visualize.Chart.BuilderTest.Styles
      s = BuilderFixture.socket(BuilderFixture.layers(), store: store, on_deploy: :deployed)
      {:noreply, opened} = Builder.handle_event("add_layer", %{"name" => "style:1"}, s)
      refute BuilderFixture.render(opened) =~ "vis-builder-deploy"

      {:noreply, refused} = Builder.handle_event("deploy", %{}, opened)
      refute_received {:deployed, _, _}
      assert refused.assigns.notice == "deploy a composite; a style is not a chart"
    end

    test "a design is not a kind to start", %{socket: s} do
      refute :design in Visualize.Chart.Builder.Stack.kinds()
      refute BuilderFixture.render(s) =~ ~s(<option value="design">)

      {:noreply, refused} = Builder.handle_event("new_fragment", %{"kind" => "design"}, s)
      assert refused.assigns.open == nil
      assert refused.assigns.notice == "a design is what Deploy makes; start a composite instead"
    end
  end

  describe "a site's key (spec/14 §19.3, §19.6)" do
    test "a keyless style site is a fault at the row, the panel offers the key, and setting it places it" do
      store = Visualize.Chart.BuilderTest.Styles
      s = BuilderFixture.socket(BuilderFixture.layers(), store: store)
      {:noreply, s} = Builder.handle_event("insert", %{"name" => "style:1", "at" => 3}, s)
      {:noreply, s} = Builder.handle_event("select_layer", %{"index" => "3"}, s)

      html = BuilderFixture.render(s)
      assert html =~ ~s(class="vis-builder-declared-as" phx-change="set_key")
      assert html =~ "not placed: a style needs a name to be declared under"
      assert html =~ "not placed: Styles::thick"

      refute Map.has_key?(BuilderFixture.design(s), :styles) and
               Map.has_key?(BuilderFixture.design(s).styles, :thick)

      {:noreply, deploy} = Builder.handle_event("deploy", %{}, s)

      assert deploy.assigns.notice ==
               "not deployed: Styles::thick need a key to be declared under"

      refute_received {:visualize_chart_deployed, _, _}

      {:noreply, keyed} = Builder.handle_event("set_key", %{"key" => "thick"}, s)
      assert Enum.at(keyed.assigns.uses, 3).key == :thick
      assert BuilderFixture.design(keyed).styles.thick == %{stroke_width: 5}
      refute BuilderFixture.render(keyed) =~ "not placed"

      {:noreply, blank} = Builder.handle_event("set_key", %{"key" => " "}, keyed)
      assert Enum.at(blank.assigns.uses, 3).key == nil
    end

    test "a source site chooses its key from the pool, and the pick fills its fields (§19.10)" do
      s =
        BuilderFixture.socket(BuilderFixture.layers(),
          sources: %{primary: BuilderFixture.sources().primary, other: [%{b: 1, a: 2}]}
        )

      {:noreply, s} = Builder.handle_event("add_site", %{"kind" => "source"}, s)
      html = BuilderFixture.render(s)

      # A list of the pool's names in ls order with none first, and a box beneath for a
      # name the pool lacks; a style site keeps the box alone.
      assert html =~
               ~s(<div class="vis-builder-pool" role="radiogroup" aria-label="a source of the pool">)

      assert html =~ ~r|<input type="radio" name="key" value="" checked>\s*none|
      {other_at, _} = :binary.match(html, ~s(<input type="radio" name="key" value="other">))
      {primary_at, _} = :binary.match(html, ~s(<input type="radio" name="key" value="primary">))
      assert other_at < primary_at
      refute html =~ ~s(<select id="b-masks-key")
      assert html =~ ~s(type="text" name="key.other" class="vis-builder-declared-name")

      assert html =~
               ~s(phx-hook="BuilderHook" phx-target="-1" data-builder-target="-1" data-builder-scope="pool")

      pick = fn socket, name ->
        Builder.handle_event(
          "set_key",
          %{"_target" => ["key"], "key" => name, "key.other" => ""},
          socket
        )
      end

      {:noreply, picked} = pick.(s, "other")
      site = Visualize.Chart.Builder.Stack.get(picked.assigns.uses, picked.assigns.selected)
      assert site.key == :other
      assert site.local == %{source: %{fields: [:a, :b]}}

      assert BuilderFixture.render(picked) =~
               ~r|vis-builder-pool-name-on">\s*<input type="radio" name="key" value="other" checked>|

      # Fields already declared are left alone; the box takes a name the pool lacks, kept
      # marked in the list.
      {:noreply, repicked} = pick.(picked, "primary")

      assert Visualize.Chart.Builder.Stack.get(repicked.assigns.uses, repicked.assigns.selected).local ==
               %{source: %{fields: [:a, :b]}}

      {:noreply, odd} =
        Builder.handle_event(
          "set_key",
          %{"_target" => ["key.other"], "key" => "other", "key.other" => "elsewhere"},
          s
        )

      assert Visualize.Chart.Builder.Stack.get(odd.assigns.uses, odd.assigns.selected).key ==
               :elsewhere

      assert BuilderFixture.render(odd) =~
               ~r|vis-builder-pool-name-on">\s*<input type="radio" name="key" value="elsewhere" checked>|

      # The source's default is the same list, with its own box.
      {:noreply, form} = Builder.handle_event("select_node", %{"node" => "source"}, picked)
      form_html = BuilderFixture.render(form)

      assert form_html =~
               ~s(<div class="vis-builder-pool" role="radiogroup" aria-label="default">)

      assert form_html =~ ~s(<input type="radio" name="default" value="primary">)
      assert form_html =~ ~s(name="default.other")

      {:noreply, defaulted} =
        Builder.handle_event(
          "edit",
          %{"_target" => ["default.other"], "default.other" => "gitlab_uptime"},
          form
        )

      assert Visualize.Chart.Builder.Stack.get(defaulted.assigns.uses, defaulted.assigns.selected).local.source.default ==
               :gitlab_uptime

      {:noreply, defaulted} =
        Builder.handle_event(
          "edit",
          %{"_target" => ["default"], "default" => "primary"},
          defaulted
        )

      assert Visualize.Chart.Builder.Stack.get(defaulted.assigns.uses, defaulted.assigns.selected).local.source.default ==
               :primary

      # A style site still types its name, with no list.
      {:noreply, style} = Builder.handle_event("add_site", %{"kind" => "style"}, s)
      style_html = BuilderFixture.render(style)
      assert style_html =~ ~s(type="text" name="key" class="vis-builder-declared-name")
      refute style_html =~ ~s(class="vis-builder-pool")

      # The stylesheet lays the list out in columns, bounded and scrolling.
      css = Visualize.Chart.Builder.Styles.css()

      assert css =~
               ~r/\.vis-builder-pool \{[^}]*columns: 9em auto;[^}]*max-height: 12em;[^}]*overflow-y: auto;/s
    end

    test "selecting a layer opens the layer's context, and a host may hide a source's default" do
      pool = %{primary: BuilderFixture.sources().primary, other: [%{b: 1, a: 2}]}
      s = BuilderFixture.socket(BuilderFixture.layers(), sources: pool)
      {:noreply, s} = Builder.handle_event("add_site", %{"kind" => "source"}, s)
      assert s.assigns.context == :inspect

      # A colour picked leaves the context on the chooser; selecting the site brings the
      # layer's context — and the source list — back.
      {:noreply, s} = Builder.handle_event("context", %{"panel" => "colour"}, s)

      refute BuilderFixture.render(s) =~
               ~s(class="vis-builder-pool" role="radiogroup" aria-label="a source of the pool")

      {:noreply, s} = Builder.handle_event("select_layer", %{"index" => "1"}, s)
      assert s.assigns.context == :inspect

      assert BuilderFixture.render(s) =~
               ~s(class="vis-builder-pool" role="radiogroup" aria-label="a source of the pool")

      # A host that binds by name alone keeps default out of the form.
      {:noreply, form} = Builder.handle_event("select_node", %{"node" => "source"}, s)
      assert BuilderFixture.render(form) =~ ~s(phx-value-field="default")
      {:ok, without} = Builder.update(%{source_defaults: false}, form)
      {:noreply, without} = Builder.handle_event("select_node", %{"node" => "source"}, without)
      html = BuilderFixture.render(without)
      refute html =~ ~s(phx-value-field="default")
      assert html =~ ~s(phx-value-field="fields")
    end

    test "a frame site offers no key" do
      s = BuilderFixture.socket(BuilderFixture.layers())
      refute BuilderFixture.render(s) =~ ~s(class="vis-builder-declared-as")
    end
  end

  describe "resolution is one rule (spec/14 §19.6, §19.10)" do
    defmodule Refs do
      @moduledoc false
      @behaviour Visualize.Chart.Builder.Store

      @entries %{
        {:style, 1} => %{name: "Styles::thick", fragment: %{style: %{stroke_width: 5}}},
        {:scale, 4} => %{
          name: "Scales::hour",
          fragment: %{scale: %{kind: :linear, domain: :auto}}
        },
        {:source, 2} => %{name: "Sources::alt", fragment: %{source: %{fields: [:t, :v]}}}
      }

      @impl true
      def list(_context) do
        for {{kind, _} = id, entry} <- @entries, do: %{id: id, name: entry.name, kind: kind}
      end

      @impl true
      def get({kind, _} = id, _context) do
        case Map.fetch(@entries, id) do
          {:ok, entry} -> {:ok, Map.merge(entry, %{id: id, kind: kind})}
          :error -> :error
        end
      end

      @impl true
      def put(_entry, _context), do: {:ok, {:composite, 9}}

      @impl true
      def delete(_id, _context), do: :ok

      @impl true
      def import(bundle, context),
        do: Visualize.Chart.Builder.Store.relocate(bundle, context, &put/2)
    end

    setup do
      s = BuilderFixture.socket(BuilderFixture.layers(), store: Refs, on_deploy: :deployed)
      {:noreply, s} = Builder.handle_event("select_layer", %{"index" => "2"}, s)
      {:noreply, s} = Builder.handle_event("select_node", %{"node" => "marks[0]"}, s)
      %{socket: s}
    end

    test "preview and deploy resolve every id the same way, and nothing survives as an id", %{
      socket: s
    } do
      {:noreply, s} =
        Builder.handle_event("insert", %{"scope" => "style", "name" => "style:1", "at" => 1}, s)

      # The shared layer's x axis refers to a scale; the drop lands on its `scale` field.
      {:noreply, s} = Builder.handle_event("select_layer", %{"index" => "1"}, s)
      {:noreply, s} = Builder.handle_event("select_node", %{"node" => "frame.axes[0]"}, s)

      {:noreply, s} =
        Builder.handle_event(
          "insert",
          %{"scope" => "ref", "field" => "scale", "name" => "scale:4"},
          s
        )

      # The site holds the id; the design holds the body under a synthesised key.
      assert get_in(Enum.at(s.assigns.uses, 1).local, [:frame, :axes, Access.at(0), :scale]) ==
               {:scale, 4}

      design = BuilderFixture.design(s)
      assert hd(design.frame.axes).scale == :"scale:4"
      assert design.frame.scales[:"scale:4"] == %{kind: :linear, domain: :auto}
      assert hd(design.marks).style == [:series, %{stroke_width: 5}]
      refute inspect(design) =~ "{:style, 1}"
      refute inspect(design) =~ "{:scale, 4}"

      {:noreply, _} = Builder.handle_event("deploy", %{}, s)
      assert_received {:deployed, "b", deployed}
      assert deployed == design

      # And it draws with the library's style.
      assert {:ok, applied} = Chart.apply(deployed, sources: BuilderFixture.sources())

      assert Chart.Style.node(Chart.to_map(applied.chart).styles, hd(deployed.marks).style).stroke_width ==
               5
    end

    test "a wrong kind on a field is refused by name; a field that is not a reference too", %{
      socket: s
    } do
      {:noreply, axis} = Builder.handle_event("select_layer", %{"index" => "1"}, s)
      {:noreply, axis} = Builder.handle_event("select_node", %{"node" => "frame.axes[0]"}, axis)

      {:noreply, refused} =
        Builder.handle_event(
          "insert",
          %{"scope" => "ref", "field" => "scale", "name" => "style:1"},
          axis
        )

      assert refused.assigns.notice == "a scale field takes a scale; Styles::thick is a style"

      {:noreply, refused} =
        Builder.handle_event(
          "insert",
          %{"scope" => "ref", "field" => "type", "name" => "scale:4"},
          s
        )

      assert refused.assigns.notice == "type is not a reference field"
    end

    test "the select offers the library's ids for scale and source, and the field is a drop target",
         %{socket: s} do
      {:noreply, axis} = Builder.handle_event("select_layer", %{"index" => "1"}, s)
      {:noreply, axis} = Builder.handle_event("select_node", %{"node" => "frame.axes[0]"}, axis)
      html = BuilderFixture.render(axis)
      assert html =~ ~s(<option value="scale:4">scale:4</option>)
      assert html =~ ~s(data-builder-ref="scale")
      assert html =~ ~s(class="vis-builder-form" phx-change="edit" phx-hook="BuilderHook")

      {:noreply, s} = Builder.handle_event("facet", %{"facet" => "binding"}, s)
      assert BuilderFixture.render(s) =~ ~s(<option value="source:2">source:2</option>)
    end

    test "a missing id is a mask at the site, and reported", %{socket: s} do
      {:noreply, s} = Builder.handle_event("select_layer", %{"index" => "1"}, s)
      {:noreply, s} = Builder.handle_event("select_node", %{"node" => "frame.axes[0]"}, s)

      {:noreply, s} =
        Builder.handle_event("edit", %{"_target" => ["scale"], "scale" => "scale:9"}, s)

      assert get_in(Enum.at(s.assigns.uses, 1).local, [:frame, :axes, Access.at(0), :scale]) ==
               {:scale, 9}

      design = BuilderFixture.design(s)
      refute Map.has_key?(hd(design.frame.axes), :scale)

      {:noreply, deployed} = Builder.handle_event("deploy", %{}, s)
      assert deployed.assigns.notice == "deployed with 1 reference(s) showing through: scale:9"
    end
  end

  describe "a fill is a fill style (spec/14 §18.6, §2.7)" do
    setup do
      s = BuilderFixture.socket(BuilderFixture.layers(), store: Visualize.Chart.BuilderTest.Refs)
      {:noreply, s} = Builder.handle_event("select_node", %{"node" => "styles.series"}, s)
      %{socket: s}
    end

    defp fill_of(s), do: get_in(hd(s.assigns.uses).local, [:styles, :series, :fill])
    defp defs_of(s), do: get_in(hd(s.assigns.uses).local, [:defs]) || %{}

    test "the fill group opens with four glyphs, and none writes :none, solid a colour", %{
      socket: s
    } do
      html = BuilderFixture.render(s)
      assert html =~ ~s(aria-label="fill style")

      for style <- ~w(none solid linear radial) do
        assert html =~ ~s(<input type="radio" name="fill_style" value="#{style}")
      end

      # Unset shows as solid; none hatches the well; solid on none is the first series.
      assert html =~ ~s(name="fill_style" value="solid" checked)

      {:noreply, none} =
        Builder.handle_event("edit", %{"_target" => ["fill_style"], "fill_style" => "none"}, s)

      assert fill_of(none) == :none
      assert BuilderFixture.render(none) =~ ~s(class="vis-builder-well vis-builder-well-none")

      {:noreply, solid} =
        Builder.handle_event(
          "edit",
          %{"_target" => ["fill_style"], "fill_style" => "solid"},
          none
        )

      assert fill_of(solid) == :series_1
      refute BuilderFixture.render(solid) =~ "vis-builder-gradient"
    end

    test "linear declares the gradient named for the style under the layer's defs and shows its controls",
         %{socket: s} do
      {:noreply, s} =
        Builder.handle_event("edit", %{"_target" => ["fill"], "fill" => "#abcdef"}, s)

      {:noreply, s} =
        Builder.handle_event("edit", %{"_target" => ["fill_style"], "fill_style" => "linear"}, s)

      assert fill_of(s) == {:paint, :series_fill}

      assert defs_of(s) == %{
               series_fill: %{
                 kind: :linear,
                 stops: [
                   %{offset: 0, colour: "#abcdef", opacity: 0.8},
                   %{offset: 1, colour: "#abcdef", opacity: 0.1}
                 ]
               }
             }

      html = BuilderFixture.render(s)
      assert html =~ ~s(name="fill_style" value="linear" checked)
      # The fill's wells are the first and last stops — no third swatch — in the colours
      # column; the numbers column holds the opacity then the angle as a ranged box.
      refute html =~ ~s(data-builder-well="fill")

      assert html =~
               ~s(--vis-builder-swatch: #abcdef" title="#abcdef" role="img" aria-label="stop 0: #abcdef" data-builder-well="fill.stop.0")

      assert html =~ ~s(data-builder-well="fill.stop.1")
      refute html =~ ~s(name="fill.stop.1.opacity")

      colours =
        html
        |> String.split(~s(class="vis-builder-fill-colours"))
        |> Enum.at(1)
        |> String.split("vis-builder-fill-numbers")
        |> hd()

      assert colours =~ ~s(fill.stop.0) and colours =~ ~s(fill.stop.1)

      # The opacity sits beside the style at the top, titled opacity; the colours are titled
      # colour; the angle sits under the opacity.
      {style_at, _} = :binary.match(html, ~s(<span class="vis-builder-key">style</span>))
      {opacity_at, _} = :binary.match(html, ~s(name="fill_opacity"))
      {colours_at, _} = :binary.match(html, ~s(class="vis-builder-fill-colours"))
      assert style_at < opacity_at and opacity_at < colours_at

      assert html =~
               ~r|phx-value-field="fill_opacity" phx-target="-1">\s*<span class="vis-builder-key">\s*opacity\s*<|

      assert html =~
               ~r|phx-value-field="fill" phx-target="-1">\s*<span class="vis-builder-key">\s*colour\s*<|

      numbers =
        html
        |> String.split(~s(class="vis-builder-fill-numbers"))
        |> Enum.at(1)
        |> String.split("</fieldset>")
        |> hd()

      refute numbers =~ ~s(name="fill_opacity")
      assert numbers =~ ~s(<input type="text" name="fill.angle" value="180")

      assert numbers =~
               ~s(name="fill.angle.range" class="vis-builder-range vis-builder-scrubber" style="--vis-builder-scrub: 50.0%")

      refute html =~ ~s(name="fill.centre.x")
      # And the preview carries the gradient.
      assert html =~ "<linearGradient"
      assert html =~ ~s(-series_fill)

      # The stop wells and the angle write the gradient where it is declared.
      {:noreply, s} =
        Builder.handle_event("drop_colour", %{"field" => "fill.stop.1", "colour" => "axis"}, s)

      {:noreply, s} =
        Builder.handle_event(
          "edit",
          %{"_target" => ["fill.stop.0"], "fill.stop.0" => "#123456"},
          s
        )

      {:noreply, s} =
        Builder.handle_event(
          "edit",
          %{"_target" => ["fill.angle.range"], "fill.angle.range" => "90"},
          s
        )

      gradient = defs_of(s).series_fill
      assert gradient.angle == 90

      assert gradient.stops == [
               %{offset: 0, colour: "#123456", opacity: 0.8},
               %{offset: 1, colour: :axis, opacity: 0.1}
             ]

      # A stop well selected opens the chooser on that stop.
      {:noreply, picked} = Builder.handle_event("select_field", %{"field" => "fill.stop.1"}, s)
      assert picked.assigns.context == :colour
      html = BuilderFixture.render(picked)
      assert html =~ ~s(<h3 class="vis-builder-context-title">fill.stop.1</h3>)
      assert html =~ ~s(name="fill.stop.1.slot" value="axis" checked)

      # Radial keeps the stops and shows a centre; solid takes the first stop's colour.
      {:noreply, radial} =
        Builder.handle_event("edit", %{"_target" => ["fill_style"], "fill_style" => "radial"}, s)

      assert defs_of(radial).series_fill.kind == :radial and
               defs_of(radial).series_fill.stops == gradient.stops

      {:noreply, radial} =
        Builder.handle_event(
          "edit",
          %{"_target" => ["fill.centre.y"], "fill.centre.y" => "0.25"},
          radial
        )

      assert defs_of(radial).series_fill.centre == [0.5, 0.25]
      assert BuilderFixture.render(radial) =~ ~s(name="fill.centre.y")

      {:noreply, solid} =
        Builder.handle_event(
          "edit",
          %{"_target" => ["fill_style"], "fill_style" => "solid"},
          radial
        )

      assert fill_of(solid) == "#123456"
      assert Map.has_key?(defs_of(solid), :series_fill)
    end

    test "on a style site the gradient becomes a keyed gradient site just below it" do
      site = %{
        Visualize.Chart.Use.new(nil, [])
        | ref: nil,
          local: %{style: %{stroke: "#000"}},
          key: :thick
      }

      s = BuilderFixture.socket([])

      s =
        Phoenix.Component.assign(s,
          uses: [site],
          labels: %{site.id => "style thick"},
          selected: site.id
        )

      {:noreply, s} =
        Builder.handle_event("edit", %{"_target" => ["fill_style"], "fill_style" => "linear"}, s)

      # Named for the style as the chart knows it, `styles.thick` (§18.6, §18.15).
      [style, gradient] = s.assigns.uses
      assert style.local == %{style: %{stroke: "#000", fill: {:paint, :thick_fill}}}
      assert gradient.key == :thick_fill
      assert gradient.local.gradient.kind == :linear
      assert s.assigns.labels[gradient.id] == "gradient thick_fill"

      {:noreply, s} =
        Builder.handle_event("edit", %{"_target" => ["fill.angle"], "fill.angle" => "45"}, s)

      assert Enum.at(s.assigns.uses, 1).local.gradient.angle == 45
    end
  end

  describe "signals are the chart's sources while it is designed (spec/14 §19.10)" do
    setup do
      %{
        socket:
          BuilderFixture.socket(BuilderFixture.layers(), store: Visualize.Chart.BuilderTest.Refs)
      }
    end

    test "+ declares a sine, the tab edits it in place, and × removes it", %{socket: s} do
      assert s.assigns.signals == %{}
      {:noreply, s} = Builder.handle_event("add_signal", %{}, s)
      # Adding a signal opens the sources root, where the signals panel stands (#314).
      assert s.assigns.context == :inspect
      assert String.starts_with?(s.assigns.node_label, "sources")
      assert BuilderFixture.render(s) =~ ~s(class="vis-builder-sources")
      assert %{signal_1: %{kind: :sine, fields: [:t, :value], window: 24}} = s.assigns.signals

      # The signal is a source of the chart at once: declared in the selected layer with
      # its fields, listed under the sources tab, offered to a mark's data (§19.10).
      {_, house} = hd(BuilderFixture.layers(s))
      # The signal's first field is its time, the rest its numbers (#369).
      assert house.sources.signal_1 == %{fields: [:t, :value], types: %{t: :time, value: :number}}
      {:noreply, sources} = Builder.handle_event("select_root", %{"root" => "sources"}, s)
      assert BuilderFixture.render(sources) =~ ~s(title="sources.signal_1 — in house")
      {:noreply, marks} = Builder.handle_event("select_node", %{"node" => "marks[0]"}, s)
      {:noreply, marks} = Builder.handle_event("select_layer", %{"index" => "2"}, marks)
      {:noreply, marks} = Builder.handle_event("select_node", %{"node" => "marks[0]"}, marks)
      assert BuilderFixture.render(marks) =~ ~s(<option value="signal_1">signal_1</option>)
      # A second signal with a source already declared leaves the declaration alone.
      {:noreply, s2} = Builder.handle_event("add_signal", %{}, s)
      {:noreply, s2} = Builder.handle_event("remove_signal", %{"name" => "signal_2"}, s2)

      assert Map.keys(elem(hd(BuilderFixture.layers(s2)), 1).sources) |> Enum.sort() == [
               :signal_1,
               :signal_2
             ]

      html = BuilderFixture.render(s)
      assert html =~ ~s(<form class="vis-builder-signals" phx-change="edit_signal")
      assert html =~ ~s(<legend class="vis-builder-signal-name">)
      assert html =~ ~s(<select name="signal_1.kind">)
      assert html =~ ~s(<input type="text" name="signal_1.fields" value="t, value")
      assert html =~ ~s(name="signal_1.window" value="24")
      assert html =~ ~s(phx-click="play")

      {:noreply, s} =
        Builder.handle_event(
          "edit_signal",
          %{"_target" => ["signal_1.fields"], "signal_1.fields" => "hour, cpu, mem"},
          s
        )

      {:noreply, s} =
        Builder.handle_event(
          "edit_signal",
          %{"_target" => ["signal_1.kind"], "signal_1.kind" => "square"},
          s
        )

      {:noreply, s} =
        Builder.handle_event(
          "edit_signal",
          %{"_target" => ["signal_1.window"], "signal_1.window" => "6"},
          s
        )

      assert %{fields: [:hour, :cpu, :mem], kind: :square, window: 6} = s.assigns.signals.signal_1

      # A second is named past the first; removing leaves the other.
      {:noreply, s} = Builder.handle_event("add_signal", %{}, s)
      assert Map.keys(s.assigns.signals) |> Enum.sort() == [:signal_1, :signal_2]
      {:noreply, s} = Builder.handle_event("remove_signal", %{"name" => "signal_1"}, s)
      assert Map.keys(s.assigns.signals) == [:signal_2]
    end

    test "the pool is the host's under the signals at the tick; a source picks a signal and takes its fields",
         %{socket: s} do
      {:noreply, s} = Builder.handle_event("add_signal", %{}, s)

      {:noreply, s} =
        Builder.handle_event(
          "edit_signal",
          %{"_target" => ["signal_1.fields"], "signal_1.fields" => "hour, cpu"},
          s
        )

      # The declared-as list offers the signal beside the host's pool.
      {:noreply, s} = Builder.handle_event("add_site", %{"kind" => "source"}, s)
      html = BuilderFixture.render(s)
      assert html =~ ~s(<input type="radio" name="key" value="signal_1">)
      assert html =~ ~s(<input type="radio" name="key" value="primary">)

      {:noreply, s} =
        Builder.handle_event(
          "set_key",
          %{"_target" => ["key"], "key" => "signal_1", "key.other" => ""},
          s
        )

      site = Visualize.Chart.Builder.Stack.get(s.assigns.uses, s.assigns.selected)
      assert site.local == %{source: %{fields: [:cpu, :hour]}}

      # The signal draws: a mark over it renders, and the tick moves the rows.
      {:noreply, s} = Builder.handle_event("select_chart", %{"chart" => "1"}, s)
      {:noreply, s} = Builder.handle_event("add_site", %{"kind" => "mark"}, s)
      {:noreply, s} = Builder.handle_event("edit", %{"_target" => ["type"], "type" => "line"}, s)

      {:noreply, s} =
        Builder.handle_event("edit", %{"_target" => ["data"], "data" => "signal_1"}, s)

      {:noreply, s} =
        Builder.handle_event(
          "edit",
          %{"_target" => ["channels"], "channels" => "%{x: :hour, y: :cpu}"},
          s
        )

      before = BuilderFixture.render(s)
      assert before =~ ~s(class="mark mark-line")

      {:noreply, playing} = Builder.handle_event("play", %{}, s)
      assert playing.assigns.playing
      assert_receive {:visualize_chart_tick, "b"}, 1000
      {:ok, ticked} = Builder.update(%{tick: :next}, playing)
      assert ticked.assigns.tick == 1
      refute BuilderFixture.render(ticked) == before
      {:noreply, paused} = Builder.handle_event("pause", %{}, ticked)
      {:ok, still} = Builder.update(%{tick: :next}, paused)
      assert still.assigns.tick == 1

      # Save carries the signals with the chart's structure.
      {:noreply, _} = Builder.handle_event("save", %{}, still)
      assert_received {:visualize_chart_saved, "b", %{composite: %{signals: %{signal_1: _}}}}
    end
  end

  describe "the context's icon row (spec/14 §19.10)" do
    setup do
      s = BuilderFixture.socket(BuilderFixture.layers(), store: Visualize.Chart.BuilderTest.Refs)
      {:noreply, s} = Builder.handle_event("select_node", %{"node" => "styles.series"}, s)
      %{socket: s}
    end

    test "two icons and the variables tab, one open; inspect is the default", %{socket: s} do
      html = BuilderFixture.render(s)
      assert html =~ ~s(<nav class="vis-builder-context-icons" aria-label="context panels">)

      for panel <- ~w(inspect colour variables) do
        assert html =~ ~s(phx-click="context" phx-value-panel="#{panel}")
      end

      # The icon row is the two modes of the selected node; variables is the node row's
      # last tab (#363).
      [_, icons] = String.split(html, ~s(class="vis-builder-context-icons"), parts: 2)
      refute icons =~ ~s(phx-value-panel="variables")
      assert Regex.scan(~r/class="vis-builder-context-icon[ "]/, icons) |> length() == 2

      # The signals and the font panel are under their roots now (#314): no panel of theirs,
      # and a stale click on one is a no-op.
      for panel <- ~w(sources font) do
        refute html =~ ~s(phx-value-panel="#{panel}")
        {:noreply, same} = Builder.handle_event("context", %{"panel" => panel}, s)
        assert same.assigns.context == :inspect
      end

      assert html =~
               ~s(class="vis-builder-context-icon vis-builder-context-icon-on" title="inspect")

      assert html =~ ~s(class="vis-builder-layer-context")
      refute html =~ ~s(class="vis-builder-picker")
      refute html =~ ~s(class="vis-builder-variables")

      {:noreply, vars} = Builder.handle_event("context", %{"panel" => "variables"}, s)
      html = BuilderFixture.render(vars)
      assert html =~ ~s(class="vis-builder-variables")
      refute html =~ ~s(class="vis-builder-layer-context")

      {:noreply, same} = Builder.handle_event("context", %{"panel" => "nonsense"}, s)
      assert same.assigns.context == :inspect
    end

    test "the chooser: patches above the picker, each draggable, writing the selected colour field",
         %{
           socket: s
         } do
      {:noreply, s} = Builder.handle_event("select_field", %{"field" => "stroke"}, s)
      assert s.assigns.context == :colour
      html = BuilderFixture.render(s)

      assert html =~ ~s(<form id="b-picker" class="vis-builder-picker" phx-change="edit")
      assert html =~ ~s(data-builder-scope="colour")
      assert html =~ ~s(<h3 class="vis-builder-context-title">stroke</h3>)

      for slot <- Visualize.Theme.colour_slots(Visualize.Theme.default()) do
        assert html =~ ~s(name="stroke.slot" value="#{slot}")
        assert html =~ ~s(draggable="true" data-builder-colour="#{slot}")
      end

      assert html =~ ~s(class="vis-builder-swatch vis-builder-swatch-on" title="series_1")
      assert length(Regex.scan(~r/class="vis-builder-hue"/, html)) >= 35
      assert html =~ ~s(<input type="color" name="stroke" class="vis-builder-colour")
      refute html =~ "stroke.var"

      # The patches come before the hues and the picker.
      {swatches, _} = :binary.match(html, ~s(aria-label="theme slots"))
      {hues, _} = :binary.match(html, ~s(aria-label="hues"))
      {picker, _} = :binary.match(html, ~s(<input type="color" name="stroke"))
      assert swatches < hues and hues < picker

      {:noreply, s} =
        Builder.handle_event("edit", %{"_target" => ["stroke.slot"], "stroke.slot" => "axis"}, s)

      assert get_in(hd(s.assigns.uses).local, [:styles, :series, :stroke]) == :axis

      # With no colour field selected the panel shows the colours and writes nothing.
      {:noreply, off} = Builder.handle_event("select_field", %{"field" => "stroke_width"}, s)
      {:noreply, off} = Builder.handle_event("context", %{"panel" => "colour"}, off)
      html = BuilderFixture.render(off)
      assert html =~ "click a colour well to set it here"
      assert html =~ ~s(disabled)
    end

    test "a patch dropped on a well writes it, selected or not; a non-colour key refuses", %{
      socket: s
    } do
      assert s.assigns.field == nil

      {:noreply, s} =
        Builder.handle_event("drop_colour", %{"field" => "fill", "colour" => "axis"}, s)

      assert get_in(hd(s.assigns.uses).local, [:styles, :series, :fill]) == :axis

      {:noreply, s} =
        Builder.handle_event("drop_colour", %{"field" => "fill", "colour" => "#abcdef"}, s)

      assert get_in(hd(s.assigns.uses).local, [:styles, :series, :fill]) == "#abcdef"
      assert BuilderFixture.render(s) =~ ~s(--vis-builder-swatch: #abcdef" title="#abcdef")

      {:noreply, refused} =
        Builder.handle_event("drop_colour", %{"field" => "stroke_width", "colour" => "axis"}, s)

      assert refused.assigns.notice == "stroke_width is not a colour"
      assert get_in(hd(refused.assigns.uses).local, [:styles, :series, :stroke_width]) == 2
    end

    test "the font panel: families in their face, size, the face list, anchor — for a node with font keys",
         %{
           socket: s
         } do
      {:noreply, s} = Builder.handle_event("select_field", %{"field" => "font_family"}, s)
      # A font key leaves inspect where it is: the font panel is under the styles root (#314).
      assert s.assigns.context == :inspect
      html = BuilderFixture.render(s)
      assert html =~ ~s(<form class="vis-builder-fonts" phx-change="edit")
      assert html =~ ~s(class="vis-builder-face" style="font-family: Georgia")
      assert html =~ ~s(name="font_size.range")
      refute html =~ ~s(name="font_weight")
      assert html =~ ~s(<input type="radio" name="font_face" value="bold_italic")
      assert html =~ ~s(<input type="radio" name="text_anchor" value="middle")

      # The face list is one control over two keys (§18.6): a face writes both, and the
      # node then shows that face; the form shows the same list in font_weight's place
      # and no font_style row.
      {:noreply, faced} =
        Builder.handle_event(
          "edit",
          %{"_target" => ["font_face"], "font_face" => "light_italic"},
          s
        )

      style = get_in(hd(faced.assigns.uses).local, [:styles, :series])
      assert style.font_weight == :light and style.font_style == :italic
      faced_html = BuilderFixture.render(faced)

      assert faced_html =~
               ~s(name="font_face" value="light_italic" checked aria-label="light italic")

      # The form's face is a dropdown wearing the chosen face — the form is under the
      # inspect tab, the panel keeps its list.
      {:noreply, inspected} = Builder.handle_event("context", %{"panel" => "inspect"}, faced)
      faced_html = BuilderFixture.render(inspected)
      refute faced_html =~ ~s(phx-value-field="font_style")

      assert faced_html =~
               ~s(<select name="font_face" class="vis-builder-face-select" style="font-weight: 300; font-style: italic" aria-label="face">)

      assert faced_html =~
               ~r|<option value="light_italic" style="font-weight: 300; font-style: italic" selected>\s*light italic\s*</option>|

      assert faced_html =~
               ~r|<option value="bold" style="font-weight: 700; font-style: normal">\s*bold\s*</option>|

      assert length(Regex.scan(~r/class="vis-builder-face-list/, BuilderFixture.render(faced))) ==
               1

      {:noreply, s} =
        Builder.handle_event(
          "edit",
          %{"_target" => ["font_family"], "font_family" => "Georgia"},
          s
        )

      assert get_in(hd(s.assigns.uses).local, [:styles, :series, :font_family]) == "Georgia"

      # Under another root there is no font panel; under styles with a node that has no
      # font keys it says which to open.
      {:noreply, frame} = Builder.handle_event("select_node", %{"node" => "frame"}, s)
      refute BuilderFixture.render(frame) =~ ~s(class="vis-builder-fonts")
    end

    test "selecting a node or a layer clears the field", %{socket: s} do
      {:noreply, s} = Builder.handle_event("select_field", %{"field" => "stroke"}, s)
      assert s.assigns.field == "stroke"

      {:noreply, node} = Builder.handle_event("select_node", %{"node" => "frame"}, s)
      assert node.assigns.field == nil

      {:noreply, layer} = Builder.handle_event("select_layer", %{"index" => "2"}, s)
      assert layer.assigns.field == nil
    end
  end

  describe "what the design still needs is marked where it is (spec/14 §18.7, §18.13)" do
    test "a tab with a fault under it is orange with the count, and so is the field" do
      # A mark with no data: `marks[0].data` is required.
      layers = [
        {:house,
         %{
           version: 1,
           sources: %{primary: %{fields: [:t, :v]}},
           frame: %{kind: :cartesian, scales: %{x: %{kind: :linear}, y: %{kind: :linear}}}
         }},
        {:panel,
         %{marks: [%{id: :m, type: :line, channels: %{x: :t, y: :v}, scales: %{x: :x, y: :y}}]}}
      ]

      s = BuilderFixture.socket(layers, selected: 1, node_label: "marks[0]", facet: :binding)
      html = BuilderFixture.render(s)

      assert html =~ ~s(class="vis-builder-node vis-builder-node-open vis-builder-node-needs")
      assert html =~ "marks of the chart — 1 thing still needed"
      refute html =~ ~s(title="frame of this layer — )

      # The field that must have a value and has none, and its words under the control.
      assert html =~
               ~s(class="vis-builder-field vis-builder-field-needs" data-builder-ref="data")

      assert html =~ "data: is required"

      # Supplying it clears both.
      {:noreply, s} =
        Builder.handle_event("edit", %{"_target" => ["data"], "data" => "primary"}, s)

      html = BuilderFixture.render(s)
      refute html =~ ~s(vis-builder-field-needs" data-builder-ref="data")
      refute html =~ "vis-builder-node-needs"
    end

    test "a tab of another layer's root is marked too, since the need is the design's", %{} do
      layers = [
        {:house, %{version: 1, frame: %{kind: :cartesian}}},
        {:panel, %{marks: [%{id: :m, type: :line}]}}
      ]

      s = BuilderFixture.socket(layers, selected: 0)
      html = BuilderFixture.render(s)

      assert html =~ ~s(class="vis-builder-node vis-builder-node-needs")
      assert html =~ "still needed"
    end

    test "a chip for a child node with a fault is marked; a settled stack marks nothing" do
      s = BuilderFixture.socket(BuilderFixture.layers(), selected: 2, node_label: "marks[0]")
      settled = BuilderFixture.render(s)
      refute settled =~ "vis-builder-node-needs"
      refute settled =~ "vis-builder-field-needs"

      layers = [
        {:only,
         %{
           version: 1,
           frame: %{kind: :cartesian},
           marks: [%{id: :m, type: :line, data: :p, channels: %{x: :a}}]
         }}
      ]

      s = BuilderFixture.socket(layers, node_label: "marks[0]")
      html = BuilderFixture.render(s)

      # The mark's page: the section holding the faulty channels is marked.
      assert html =~ ~s(class="vis-builder-section vis-builder-section-needs")
    end

    test "the stylesheet has the needs token and every marking rule uses it" do
      css = Visualize.Chart.Builder.css()
      assert css =~ "--vis-builder-needs:"

      for rule <- ~w(.vis-builder-node-needs .vis-builder-chip-needs .vis-builder-field-needs) do
        [block] = Regex.run(~r/#{Regex.escape(rule)} \{[^}]*\}/, css)
        assert block =~ "var(--vis-builder-needs)"
      end
    end
  end

  describe "a list of scalars is a list of items (spec/14 §18.6, §19.9)" do
    setup do
      # The shared layer declares the source; its fields are the list.
      s =
        BuilderFixture.socket(BuilderFixture.layers(), selected: 1, node_label: "sources.primary")

      %{socket: s}
    end

    test "each field is a row with an ×, and a + box adds one read by the element's type", %{
      socket: s
    } do
      html = BuilderFixture.render(s)
      assert html =~ ~s(class="vis-builder-items")
      refute html =~ ~s(<textarea name="fields">)

      # A source with rows shows the columns to tick, the declared ones highlighted, and
      # no text rows; the + box stays beneath (§18.6).
      assert html =~
               ~s(class="vis-builder-pool vis-builder-picks" role="group" aria-label="fields: the columns the rows have")

      assert html =~
               ~r|class="vis-builder-pool-name vis-builder-pool-name-on" title="t">\s*<input type="checkbox" name="fields.pick\[\]" value="t" checked>|

      assert html =~ ~r|class="vis-builder-pool-name vis-builder-pool-name-on" title="v">|
      refute html =~ ~s(<span class="vis-builder-item-text">t</span>)
      assert html =~ ~s(name="fields.add" class="vis-builder-item-box" placeholder="+ add")

      # Ticking writes the whole list in the list's order; unticking removes; a declared
      # column the rows lack is highlighted and marked.
      {:noreply, ticked} =
        Builder.handle_event(
          "edit",
          %{"_target" => ["fields.pick"], "fields.pick" => ["t"], "_node" => "sources.primary"},
          s
        )

      {_, shared} = Enum.at(BuilderFixture.layers(ticked), 1)
      assert shared.sources.primary.fields == [:t]

      {:noreply, promised} =
        Builder.handle_event(
          "list_add",
          %{"field" => "fields", "fields.add" => "w", "key" => "Enter"},
          ticked
        )

      promised_html = BuilderFixture.render(promised)

      assert promised_html =~
               ~r|class="vis-builder-pool-name vis-builder-pool-name-on vis-builder-pool-name-missing" title="w — not in the rows">|

      {:noreply, none} =
        Builder.handle_event(
          "edit",
          %{"_target" => ["fields.pick"], "_node" => "sources.primary"},
          promised
        )

      {_, shared} = Enum.at(BuilderFixture.layers(none), 1)
      refute Map.has_key?(shared.sources.primary, :fields)

      # A source with no rows under its name is the items list as before.
      unbound =
        BuilderFixture.socket(BuilderFixture.layers(),
          selected: 1,
          node_label: "sources.primary",
          sources: %{}
        )

      unbound_html = BuilderFixture.render(unbound)
      refute unbound_html =~ "vis-builder-picks"
      assert unbound_html =~ ~s(<span class="vis-builder-item-text">t</span>)

      assert unbound_html =~
               ~s(phx-click="list_remove" phx-value-field="fields" phx-value-node="sources.primary" phx-value-index="0")

      {:noreply, s} =
        Builder.handle_event(
          "list_add",
          %{"field" => "fields", "fields.add" => "w", "key" => "Enter"},
          s
        )

      {_, shared} = Enum.at(BuilderFixture.layers(s), 1)
      assert shared.sources.primary.fields == [:t, :v, :w]

      {:noreply, s} =
        Builder.handle_event("list_remove", %{"field" => "fields", "index" => "0"}, s)

      {_, shared} = Enum.at(BuilderFixture.layers(s), 1)
      assert shared.sources.primary.fields == [:v, :w]

      # A blank adds nothing; a field the node lacks changes nothing.
      {:noreply, same} =
        Builder.handle_event("list_add", %{"field" => "fields", "fields.add" => " "}, s)

      assert same.assigns.uses == s.assigns.uses

      {:noreply, same} =
        Builder.handle_event("list_add", %{"field" => "nope", "nope.add" => "x"}, s)

      assert same.assigns.uses == s.assigns.uses
    end

    test "a chip dropped on a field list adds the variable as an item, and a field is a channel" do
      # `ycol` typed by a mark's channel fits a field list.
      house = %{
        version: 1,
        vars: %{ycol: %{}},
        marks: [%{id: :m, type: :line, data: :primary, channels: %{x: :t, y: Chart.var(:ycol)}}]
      }

      s =
        BuilderFixture.socket(
          [{:house, house}, {:shared, elem(Enum.at(BuilderFixture.layers(), 1), 1)}],
          selected: 1,
          node_label: "sources.primary"
        )

      {:noreply, s} =
        Builder.handle_event("bind_field", %{"field" => "fields", "name" => "ycol"}, s)

      {_, shared} = Enum.at(BuilderFixture.layers(s), 1)
      assert shared.sources.primary.fields == [:t, :v, Chart.var(:ycol)]

      html = BuilderFixture.render(s)

      assert html =~
               ~s|<span class="vis-builder-var-chip vis-builder-var-chip-bound">var(:ycol)</span>|

      # It applies once the variable names a column.
      design = BuilderFixture.design(s)

      assert {:ok, _} =
               Chart.apply(Map.put(design, :frame, Map.merge(design.frame, %{kind: :cartesian})),
                 sources: BuilderFixture.sources(),
                 vars: %{ycol: :v}
               )

      # A variable typed as something else is refused by name.
      {:noreply, s} =
        Builder.handle_event("create_variable", %{"name" => "w", "default" => "5"}, s)

      # (create put the var site at the bottom, so the house is now the second row)
      {:noreply, s} = Builder.handle_event("select_layer", %{"index" => "1"}, s)
      {:noreply, s} = Builder.handle_event("select_node", %{"node" => "marks[0]"}, s)
      {:noreply, s} = Builder.handle_event("bind_field", %{"field" => "type", "name" => "w"}, s)
      assert s.assigns.notice == nil
      {:noreply, s} = Builder.handle_event("select_layer", %{"index" => "2"}, s)
      {:noreply, s} = Builder.handle_event("select_node", %{"node" => "sources.primary"}, s)

      {:noreply, refused} =
        Builder.handle_event("bind_field", %{"field" => "fields", "name" => "w"}, s)

      assert refused.assigns.notice =~ "w is a choice; fields takes a :field"
    end
  end

  describe "the + on the Layers title (spec/14 §18.8)" do
    test "opens a menu of the single kinds, and adds an empty site below the selection" do
      s = BuilderFixture.socket(BuilderFixture.layers())
      html = BuilderFixture.render(s)

      assert html =~
               ~s(class="vis-builder-add" title="add an empty site below the selected layer")

      refute html =~ "vis-builder-add-menu"

      {:noreply, s} = Builder.handle_event("adding", %{}, s)
      html = BuilderFixture.render(s)
      assert html =~ ~s(<div class="vis-builder-add-menu" role="menu")
      assert html =~ ~s(phx-click="add_site" phx-value-kind="style")
      refute html =~ ~s(phx-value-kind="composite")
      refute html =~ ~s(phx-value-kind="design")

      {:noreply, s} = Builder.handle_event("select_layer", %{"index" => "1"}, s)
      {:noreply, s} = Builder.handle_event("add_site", %{"kind" => "style"}, s)
      assert BuilderFixture.names(s) == [:house, :shared, "new style", :panel]
      assert BuilderFixture.selected(s) == 2
      assert Enum.at(s.assigns.uses, 2).local == %{style: %{}}
      assert s.assigns.adding == false

      # Keyless, so not placed until named — the honest state (§19.3).
      assert BuilderFixture.render(s) =~ "not placed: new style"

      {:noreply, refused} = Builder.handle_event("add_site", %{"kind" => "composite"}, s)
      assert refused.assigns.notice == "composite is not a kind a site can be"
    end

    test "with nothing selected the site is appended" do
      s = BuilderFixture.socket([])
      {:noreply, s} = Builder.handle_event("add_site", %{"kind" => "frame"}, s)
      assert BuilderFixture.names(s) == ["new frame"]
      assert BuilderFixture.selected(s) == 0
    end
  end

  describe "a host seeds a reference as a layer (spec/14 §19.9)" do
    test "an id becomes a use referring to it, labelled by the host or its position" do
      s =
        BuilderFixture.socket([{"House", Library.baseline_id()}, Library.baseline_id()],
          store: Library
        )

      assert BuilderFixture.names(s) == ["House", "1"]
      assert Enum.map(s.assigns.uses, & &1.ref) == [Library.baseline_id(), Library.baseline_id()]

      assert BuilderFixture.layers(s) ==
               [
                 {"House", %{version: 1, frame: %{kind: :cartesian}}},
                 {"1", %{version: 1, frame: %{kind: :cartesian}}}
               ]
    end
  end

  describe "the keyboard has every gesture the pointer has (spec/14 §18.17)" do
    setup do
      %{socket: BuilderFixture.socket(BuilderFixture.layers(), store: Library)}
    end

    test "a layer row is reachable and says what it is and what its keys do", %{socket: s} do
      html = BuilderFixture.render(s)

      assert html =~
               ~s(id="b-layers-row-0" class="vis-builder-layer vis-builder-layer-selected" data-builder-layer="0" draggable="true" role="button" tabindex="0")

      assert html =~
               ~s(aria-label="house, layer 1 of 3, selected: Enter to edit, arrows to move, Right to show what it declares, drag to reorder")

      assert html =~ ~s(phx-keydown="layer_key")
    end

    test "Enter selects; the arrows move, and focus follows the row", %{socket: s} do
      {:noreply, s} = Builder.handle_event("layer_key", %{"key" => "Enter", "index" => "2"}, s)
      assert BuilderFixture.selected(s) == 2

      {:noreply, up} = Builder.handle_event("layer_key", %{"key" => "ArrowUp", "index" => "2"}, s)
      assert BuilderFixture.names(up) == [:house, :panel, :shared]
      assert BuilderFixture.selected(up) == 1

      assert [["vis:focus", %{id: "b-layers-row-1"}]] = up.private.live_temp[:push_events]

      {:noreply, down} =
        Builder.handle_event("layer_key", %{"key" => "ArrowDown", "index" => "1"}, up)

      assert BuilderFixture.names(down) == [:house, :shared, :panel]

      # The ends are the ends, and a key that means nothing here changes nothing.
      {:noreply, top} =
        Builder.handle_event("layer_key", %{"key" => "ArrowUp", "index" => "0"}, s)

      assert BuilderFixture.names(top) == BuilderFixture.names(s)
      {:noreply, same} = Builder.handle_event("layer_key", %{"key" => "x", "index" => "0"}, s)
      assert same.assigns.uses == s.assigns.uses
    end

    test "a library item: Enter opens, Insert adds above the selected layer", %{socket: s} do
      html = BuilderFixture.render(s)
      assert html =~ ~s(phx-keydown="fragment_key")

      assert html =~
               ": Enter to open, Insert to copy above the selected layer (I to link), drag into the stack or onto the chart (Alt to link)\""

      {:noreply, s} = Builder.handle_event("select_layer", %{"index" => "1"}, s)

      {:noreply, added} =
        Builder.handle_event("fragment_key", %{"key" => "Insert", "name" => "composite:1"}, s)

      assert BuilderFixture.names(added) == [:house, :shared, "baseline", :panel]
      assert %Use{ref: nil} = Enum.at(added.assigns.uses, 2)

      {:noreply, linked} =
        Builder.handle_event("fragment_key", %{"key" => "I", "name" => "composite:1"}, s)

      assert BuilderFixture.names(linked) == [:house, :shared, "baseline", :panel]
      assert %Use{ref: {:composite, 1}} = Enum.at(linked.assigns.uses, 2)

      {:noreply, opened} =
        Builder.handle_event("fragment_key", %{"key" => "Enter", "name" => "composite:1"}, s)

      assert opened.assigns.open.id == Library.baseline_id()
    end
  end

  describe "an edit goes to the layer that owns the node (spec/14 §18.15)" do
    setup do
      %{socket: BuilderFixture.socket(BuilderFixture.layers())}
    end

    test "editing a node another layer declares writes there, not to the selected layer", %{
      socket: s
    } do
      # `house` is selected; `primary` is `shared`'s.
      assert BuilderFixture.selected(s) == 0

      {:noreply, s} =
        Builder.handle_event(
          "edit",
          %{"_target" => ["default"], "default" => "other", "_node" => "sources.primary"},
          s
        )

      [{:house, house}, {:shared, shared}, _panel] = BuilderFixture.layers(s)
      assert shared.sources.primary == %{fields: [:t, :v], default: :other}
      refute Map.has_key?(house, :sources)
      assert BuilderFixture.selected(s) == 0
    end

    test "a key a higher layer overrides is written where its value comes from", %{socket: s} do
      # `shared` owns the frame node; `house` gives its size and is badged on the width.
      {:noreply, s} = Builder.handle_event("select_layer", %{"index" => "2"}, s)

      {:noreply, s} =
        Builder.handle_event(
          "edit",
          %{"_target" => ["width"], "width" => "500", "_node" => "frame.size"},
          s
        )

      [{:house, house}, {:shared, shared}, {:panel, panel}] = BuilderFixture.layers(s)
      assert house.frame.size.width == 500
      refute Map.has_key?(shared.frame, :size)
      refute Map.has_key?(panel, :frame)
    end

    test "a node two layers declare is written to the highest, which the tag names" do
      s =
        BuilderFixture.socket([
          {:house,
           %{version: 1, frame: %{kind: :cartesian}, styles: %{series: %{stroke_width: 2}}}},
          {:panel, %{styles: %{series: %{stroke_width: 4}}}}
        ])

      {:noreply, s} = Builder.handle_event("select_node", %{"node" => "styles.series"}, s)
      assert BuilderFixture.render(s) =~ ~s(title="styles.series — in panel")

      {:noreply, s} =
        Builder.handle_event(
          "edit",
          %{"_target" => ["stroke_width"], "stroke_width" => "7", "_node" => "styles.series"},
          s
        )

      [{:house, house}, {:panel, panel}] = BuilderFixture.layers(s)
      assert house.styles.series.stroke_width == 2
      assert panel.styles.series.stroke_width == 7
    end

    test "a keyed site is written at its own path", %{socket: s} do
      {:noreply, s} = Builder.handle_event("add_site", %{"kind" => "source"}, s)
      {:noreply, s} = Builder.handle_event("set_key", %{"key" => "other", "key.other" => ""}, s)
      site = Visualize.Chart.Builder.Stack.get(s.assigns.uses, s.assigns.selected)
      assert site.key == :other

      # Its node is the chart's `sources.other`, tagged with the site; a write from the
      # composed page lands in the site's `source` body. The selection moves back to
      # `house`, which owns nothing of it, to show the owner is what routes the write.
      {:noreply, s} = Builder.handle_event("select_layer", %{"index" => "0"}, s)
      {:noreply, s} = Builder.handle_event("select_root", %{"root" => "sources"}, s)
      html = BuilderFixture.render(s)
      assert html =~ ~s(title="sources.other — in new source")

      {:noreply, s} =
        Builder.handle_event(
          "edit",
          %{"_target" => ["default"], "default" => "primary", "_node" => "sources.other"},
          s
        )

      assert Visualize.Chart.Builder.Stack.get(s.assigns.uses, site.id).local ==
               %{source: %{default: :primary}}
    end

    test "a new declaration goes to the selected layer", %{socket: s} do
      # `shared` declares the sources; a signal added with `house` selected declares its
      # source in `house` (§19.10), and the page lists both, each tagged.
      {:noreply, s} = Builder.handle_event("add_signal", %{}, s)
      [{:house, house}, {:shared, shared}, _panel] = BuilderFixture.layers(s)

      assert house.sources == %{
               signal_1: %{fields: [:t, :value], types: %{t: :time, value: :number}}
             }

      assert shared.sources == %{primary: %{fields: [:t, :v]}}

      {:noreply, s} = Builder.handle_event("select_root", %{"root" => "sources"}, s)
      html = BuilderFixture.render(s)
      assert html =~ ~s(title="sources.primary — in shared")
      assert html =~ ~s(title="sources.signal_1 — in house")
    end

    test "a site the design has no node of shows its own form, untagged", %{socket: s} do
      {:noreply, s} = Builder.handle_event("add_site", %{"kind" => "style"}, s)
      html = BuilderFixture.render(s)
      refute html =~ "vis-builder-section-layer"
      assert html =~ ~s(<input type="hidden" name="_node" value="style">)

      {:noreply, s} =
        Builder.handle_event(
          "edit",
          %{"_target" => ["stroke_width"], "stroke_width" => "3", "_node" => "style"},
          s
        )

      assert Visualize.Chart.Builder.Stack.get(s.assigns.uses, s.assigns.selected).local ==
               %{style: %{stroke_width: 3}}
    end
  end

  describe "reaching a root the selected layer does not declare (spec/14 §18.13, §18.15)" do
    setup do
      host = %{id: "b", layers: BuilderFixture.layers(), sources: BuilderFixture.sources()}
      {:ok, socket} = Builder.mount(%Socket{})
      {:ok, socket} = Builder.update(host, socket)
      %{socket: socket}
    end

    test "clicking it opens it as the chart declares it, with no move", %{socket: s} do
      # `house` is selected and declares no marks; `panel` does — the page shows them
      # tagged `panel`, and the selection stays.
      assert BuilderFixture.selected(s) == 0

      {:noreply, s} = Builder.handle_event("select_root", %{"root" => "marks"}, s)

      assert BuilderFixture.selected(s) == 0
      assert s.assigns.node_label == "marks[0]"
      assert BuilderFixture.render(s) =~ ~s(title="marks[0] — in panel")
    end

    test "a root the selected layer does declare opens there, with no move", %{socket: s} do
      {:noreply, s} = Builder.handle_event("select_root", %{"root" => "frame"}, s)

      assert BuilderFixture.selected(s) == 0
      assert s.assigns.node_label == "frame"
    end

    test "from a site the design has no node of, a root takes the person to the highest layer that declares it",
         %{socket: s} do
      # A new, keyless style site shows its own form; the frame is `house`'s and `shared`'s,
      # and `shared` is the higher.
      {:noreply, s} = Builder.handle_event("add_site", %{"kind" => "style"}, s)

      assert BuilderFixture.render(s) =~
               ~s(title="frame — this site declares none; opens the layer that does")

      {:noreply, s} = Builder.handle_event("select_root", %{"root" => "frame"}, s)

      # The new site sits at 1, below `house`; `shared` is at 2.
      assert BuilderFixture.selected(s) == 2
      assert s.assigns.node_label == "frame"
    end

    test "a root that is not itself a node opens its first member", %{socket: s} do
      # `styles` exists only as the map its members live in.
      {:noreply, s} = Builder.handle_event("select_root", %{"root" => "styles"}, s)
      assert s.assigns.node_label == "styles.series"
    end

    test "a root nothing declares changes nothing", %{socket: s} do
      {:noreply, missed} = Builder.handle_event("select_root", %{"root" => "nothing"}, s)
      assert BuilderFixture.selected(missed) == BuilderFixture.selected(s)
      assert missed.assigns.node_label == s.assigns.node_label
    end
  end

  describe "a variable is a chip (spec/14 §19.9)" do
    setup do
      house = %{
        version: 1,
        styles: %{series: %{stroke: Chart.var(:color), stroke_width: 2}},
        frame: %{kind: :cartesian, size: %{width: 400, height: 200}},
        vars: %{color: %{default: :series_1}, unit: %{default: "%"}},
        labels: [%{id: :t, anchor: :title, text: ["u ", Chart.var(:unit)]}]
      }

      host = %{id: "b", layers: [{:house, house}], sources: %{}}
      {:ok, socket} = Builder.mount(%Socket{})
      {:ok, socket} = Builder.update(host, socket)

      {:noreply, socket} =
        Builder.handle_event("select_node", %{"node" => "styles.series"}, socket)

      %{socket: socket}
    end

    test "a bound field renders the chip in place of its control, with an × that unbinds", %{
      socket: s
    } do
      html = BuilderFixture.render(s)
      assert html =~ ~s(class="vis-builder-var-chip vis-builder-var-chip-bound")
      assert html =~ "var(:color)"
      assert html =~ ~s(phx-click="unbind_field" phx-value-field="stroke")
      refute html =~ ~s(data-builder-well="stroke")
      refute html =~ "stroke.mode"
      refute html =~ "stroke.var"

      {:noreply, unbound} = Builder.handle_event("unbind_field", %{"field" => "stroke"}, s)
      {_, house} = hd(BuilderFixture.layers(unbound))
      refute Map.has_key?(house.styles.series, :stroke)
      assert BuilderFixture.render(unbound) =~ ~s(data-builder-well="stroke")
    end

    test "a chip dropped on a field binds it; a mismatch is refused by name; untyped takes the type",
         %{
           socket: s
         } do
      # `color` is a colour by its use at stroke; fill takes it.
      {:noreply, s} =
        Builder.handle_event("bind_field", %{"field" => "fill", "name" => "color"}, s)

      {_, house} = hd(BuilderFixture.layers(s))
      assert house.styles.series.fill == Chart.var(:color)

      # `unit` is text by its use in a label; a colour field refuses it by name.
      {:noreply, refused} =
        Builder.handle_event("bind_field", %{"field" => "opacity", "name" => "unit"}, s)

      assert refused.assigns.notice =~ "unit is a :text; opacity takes a :size"
      {_, house} = hd(BuilderFixture.layers(refused))
      refute Map.has_key?(house.styles.series, :opacity)

      # A variable used nowhere takes the control's type by landing there.
      {:noreply, s} =
        Builder.handle_event("create_variable", %{"name" => "fresh", "default" => ""}, s)

      {:noreply, s} =
        Builder.handle_event("bind_field", %{"field" => "opacity", "name" => "fresh"}, s)

      [fresh] =
        Enum.filter(
          Variables.list(BuilderFixture.layers(s), BuilderFixture.design(s)),
          &(&1.name == :fresh)
        )

      assert fresh.type == :size

      # And the field row carries every key as a drop target, in the field's markup.
      assert BuilderFixture.render(s) =~ ~s(data-builder-bind="stroke_width")
    end

    test "a chip dropped on a strip tab binds the first key of that root it fits", %{socket: s} do
      {:noreply, s} = Builder.handle_event("bind_root", %{"root" => "frame", "name" => "unit"}, s)
      # The frame's first text-typed key... there is none: refused, nothing written.
      assert s.assigns.notice == "nothing under frame takes unit"

      {:noreply, s} =
        Builder.handle_event("create_variable", %{"name" => "w", "default" => "500"}, s)

      {:noreply, s} = Builder.handle_event("bind_root", %{"root" => "frame", "name" => "w"}, s)
      {_, house} = hd(Enum.filter(BuilderFixture.layers(s), fn {l, _} -> l == :house end))

      assert house.frame.kind == Chart.var(:w) or
               Enum.any?(Map.values(house.frame), &(&1 == Chart.var(:w)))

      assert BuilderFixture.render(s) =~ ~s(data-builder-bind-root="frame")
    end

    test "a field's value is promoted to a variable named for its key, and the field bound", %{
      socket: s
    } do
      {:noreply, s} = Builder.handle_event("promote", %{"field" => "stroke_width"}, s)
      assert hd(BuilderFixture.names(s)) == "var stroke_width"
      {_, house} = List.last(BuilderFixture.layers(s))
      assert house.styles.series.stroke_width == Chart.var(:stroke_width)
      assert BuilderFixture.design(s).vars.stroke_width == %{default: 2}

      # A second promotion of the same key takes the next free name.
      {:noreply, s} = Builder.handle_event("unbind_field", %{"field" => "stroke_width"}, s)

      {:noreply, s} =
        Builder.handle_event("edit", %{"_target" => ["stroke_width"], "stroke_width" => "4"}, s)

      {:noreply, s} = Builder.handle_event("promote", %{"field" => "stroke_width"}, s)
      assert hd(BuilderFixture.names(s)) == "var stroke_width_2"

      # A field with no value has nothing to promote.
      {:noreply, none} = Builder.handle_event("promote", %{"field" => "opacity"}, s)
      assert none.assigns.notice == "opacity has no value to promote"
    end
  end

  describe "a text field is a text field (spec/14 §7.1, §18.6, §19.9)" do
    test "a label's text renders as a box holding the string, whichever form the layer holds" do
      # The panel layer carries the label, as a list of parts, under its content facet.
      s =
        BuilderFixture.socket(BuilderFixture.parameterised(),
          selected: 2,
          node_label: "labels[0]",
          facet: :content
        )

      html = BuilderFixture.render(s)

      # The fixture's label is a list of parts; the box shows the string with its hole.
      assert html =~
               ~S|<input type="text" name="text" value="Uptime — #{var(:unit)}" data-builder-text="true">|

      refute html =~ ~s(<textarea name="text")
      refute html =~ "unbind_field"

      # A change writes the string, and the design reads it as one text.
      {:noreply, s} =
        Builder.handle_event(
          "edit",
          %{"_target" => ["text"], "text" => ~S|Up #{var(:unit)} now|},
          s
        )

      {_, panel} = Enum.at(BuilderFixture.layers(s), 2)
      assert hd(panel.labels).text == ~S|Up #{var(:unit)} now|

      assert Enum.map(Chart.free_vars(BuilderFixture.layers(s)), & &1.name) == [
               :accent,
               :ticks,
               :unit
             ]
    end

    test "a chip dropped on a text field is not a binding: the hook inserts at the caret", %{} do
      # The panel layer carries the label, as a list of parts, under its content facet.
      s =
        BuilderFixture.socket(BuilderFixture.parameterised(),
          selected: 2,
          node_label: "labels[0]",
          facet: :content
        )

      {:noreply, same} =
        Builder.handle_event("bind_field", %{"field" => "text", "name" => "ticks"}, s)

      assert same.assigns.uses == s.assigns.uses
      assert same.assigns.notice == nil

      js = Visualize.Hooks.Builder.js_hook()
      assert js =~ "insertAtCaret"
      assert js =~ "[data-builder-text]"
      assert js =~ ~S|'\#{var(:' + name + ')}'| or js =~ ~S|'#{var(:' + name + ')}'|
    end

    test "meta.name is a text: a title can carry a variable in its middle" do
      s =
        BuilderFixture.socket([
          {:only,
           %{meta: %{name: ~S|Uptime for #{var(:host)}|}, vars: %{host: %{default: "db1"}}}}
        ])

      assert Enum.map(Chart.free_vars(BuilderFixture.layers(s)), & &1.name) == [:host]

      assert {:ok, applied} =
               Chart.apply(Map.merge(BuilderFixture.design(s), %{frame: %{kind: :cartesian}}),
                 vars: %{host: "db2"}
               )

      assert applied.chart.meta.name == "Uptime for db2"
    end
  end

  describe "the variables tab (spec/14 §18.13, #363)" do
    test "ends the node row, set off from the roots, badged with the variables still needing a value" do
      s = BuilderFixture.socket(BuilderFixture.parameterised())
      html = BuilderFixture.render(s)
      [_, nodes] = String.split(html, ~s(class="vis-builder-nodes"), parts: 2)
      [nodes, _] = String.split(nodes, "</nav>", parts: 2)

      assert List.last(tabs(nodes, "vis-builder-node")) == "variables"

      # `ticks` and `unit` have defaults; `accent` has neither a default nor a binding.
      unbound = Variables.unbound(BuilderFixture.layers(s), BuilderFixture.design(s), %{})
      assert Enum.map(unbound, & &1.name) == [:accent]

      assert nodes =~
               ~s(class="vis-builder-node vis-builder-node-needs vis-builder-node-variables" title="variables — 1 thing still needed" aria-label="variables" aria-pressed="false" data-builder-promote-target="true" phx-click="context" phx-value-panel="variables")

      assert nodes =~ ~s(<span class="vis-builder-node-badge">1</span></button>)

      # A binding takes a variable off the badge, as a default already had.
      {:noreply, bound} =
        Builder.handle_event("set_var", %{"_target" => ["accent"], "accent" => "#ff0000"}, s)

      [_, nodes] =
        String.split(BuilderFixture.render(bound), ~s(class="vis-builder-nodes"), parts: 2)

      assert nodes =~
               ~s(class="vis-builder-node vis-builder-node-variables" title="variables" aria-label="variables")

      [_, tab] = String.split(nodes, ~s(aria-label="variables"), parts: 2)
      refute tab =~ ~s(vis-builder-node-badge)
    end

    test "opens the panel in place of the page with no root open; a root brings the page back" do
      s = BuilderFixture.socket(BuilderFixture.parameterised())
      {:noreply, s} = Builder.handle_event("select_node", %{"node" => "styles.series"}, s)
      assert BuilderFixture.render(s) =~ ~s(aria-label="styles" data-builder-bind-root="styles")
      assert BuilderFixture.render(s) =~ ~r/vis-builder-node-open[^>]*aria-label="styles"/

      {:noreply, up} = Builder.handle_event("context", %{"panel" => "variables"}, s)
      assert up.assigns.context == :variables
      html = BuilderFixture.render(up)
      assert html =~ ~s(class="vis-builder-variables")
      refute html =~ ~s(class="vis-builder-inspect")

      # The tab is the open one, and no root is.
      assert html =~
               ~s(class="vis-builder-node vis-builder-node-open vis-builder-node-needs vis-builder-node-variables")

      assert Regex.scan(~r/vis-builder-node-open/, html) |> length() == 1
      assert html =~ ~s(aria-pressed="true" data-builder-promote-target="true")

      {:noreply, back} = Builder.handle_event("select_root", %{"root" => "styles"}, up)
      assert back.assigns.context == :inspect
      assert back.assigns.node_label == "styles.series"
      html = BuilderFixture.render(back)
      assert html =~ ~r/vis-builder-node-open[^>]*aria-label="styles"/
      refute html =~ ~s(vis-builder-node-open vis-builder-node-needs vis-builder-node-variables)
    end

    test "a field's promote handle dropped on the tab promotes, as on the panel's create area" do
      s = BuilderFixture.socket(BuilderFixture.parameterised())
      {:noreply, s} = Builder.handle_event("select_node", %{"node" => "styles.series"}, s)

      {:noreply, promoted} =
        Builder.handle_event("promote", %{"field" => "stroke_width", "scope" => "root"}, s)

      assert %Visualize.Chart.Var{name: name} =
               BuilderFixture.design(promoted).styles.series.stroke_width

      assert to_string(name) =~ "stroke_width"
    end
  end

  describe "the variable panel (spec/14 §19.10)" do
    test "lists the composition's variables alphabetically, typed by first use, with their uses as links" do
      s = BuilderFixture.socket(BuilderFixture.parameterised(), context: :variables)
      html = BuilderFixture.render(s)

      # Not a root: the tab that ends the node row opens the panel (#363), it selects no
      # root and binds nothing dropped on it.
      refute html =~ ~s(phx-value-root="variables")
      refute html =~ ~s(data-builder-bind-root="variables")

      [_, context] =
        String.split(html, ~s(class="vis-builder-context" phx-hook="BuilderHook"), parts: 2)

      assert context =~ ~s(class="vis-builder-variables")

      chips = Regex.scan(~r/data-builder-variable="(\w+)"/, context) |> Enum.map(&List.last/1)
      assert chips == ~w(accent ticks unit)

      vars = Variables.list(BuilderFixture.layers(s), BuilderFixture.design(s))

      # The type is the schema's at the first use, whole: a style site's one_of, an axis's ticks'.
      assert Enum.map(vars, & &1.name) == [:accent, :ticks, :unit]
      assert Enum.find(vars, &(&1.name == :unit)).type == :text
      assert match?({:one_of, [{:ref, :style} | _]}, Enum.find(vars, &(&1.name == :accent)).type)

      assert Enum.find(vars, &(&1.name == :unit)).default == "%"

      {:noreply, s} = Builder.handle_event("expand_variable", %{"name" => "ticks"}, s)
      html = BuilderFixture.render(s)

      assert html =~
               ~s(phx-click="inspect" phx-value-path="frame.axes[0].ticks" phx-value-layer="3")

      assert html =~ ~s(<h4 class="vis-builder-site-name">params</h4>)

      {:noreply, s} = Builder.handle_event("expand_variable", %{"name" => "ticks"}, s)
      refute BuilderFixture.render(s) =~ ~s(phx-value-path="frame.axes[0].ticks")
    end

    test "find filters the list and highlights the fields bound to the name" do
      s =
        BuilderFixture.socket(BuilderFixture.parameterised(),
          selected: 3,
          node_label: "marks[0]",
          facet: :style,
          context: :variables
        )

      {:noreply, s} = Builder.handle_event("find_variable", %{"find" => "acc"}, s)
      html = BuilderFixture.render(s)
      assert html =~ ~s(data-builder-variable="accent")
      refute html =~ ~s(data-builder-variable="unit")

      {:noreply, s} = Builder.handle_event("find_variable", %{"find" => "accent"}, s)
      html = BuilderFixture.render(s)
      assert html =~ ~s(class="vis-builder-var-chip vis-builder-var-chip-found")
      # The fields are in the form, under the inspect tab; the find holds across tabs.
      {:noreply, inspected} = Builder.handle_event("context", %{"panel" => "inspect"}, s)
      assert BuilderFixture.render(inspected) =~ "vis-builder-field-found"
    end

    test "create declares a var site keyed by the name, with the default", %{} do
      s = BuilderFixture.socket(BuilderFixture.layers())

      {:noreply, s} =
        Builder.handle_event("create_variable", %{"name" => "gap", "default" => "12"}, s)

      assert hd(BuilderFixture.names(s)) == "var gap"
      assert hd(s.assigns.uses).key == :gap
      assert BuilderFixture.design(s).vars.gap == %{default: 12}

      {:noreply, blank} =
        Builder.handle_event("create_variable", %{"name" => " ", "default" => ""}, s)

      assert blank.assigns.notice == "a variable needs a name"
    end

    test "the declaration's default is set from the expanded chip; an undeclared one gets a site" do
      s = BuilderFixture.socket(BuilderFixture.parameterised(), context: :variables)
      refute BuilderFixture.render(s) =~ ~s(phx-value-root="vars")

      # `ticks` is declared by the params layer with default 3: its default follows.
      {:noreply, s} = Builder.handle_event("expand_variable", %{"name" => "ticks"}, s)

      assert BuilderFixture.render(s) =~
               ~s(<form class="vis-builder-variable-default" phx-change="set_default")

      # The params layer declares it under vars: the write lands there, no site is added.
      {:noreply, s} =
        Builder.handle_event("set_default", %{"_target" => ["ticks"], "ticks" => "8"}, s)

      assert length(BuilderFixture.names(s)) == 4
      assert BuilderFixture.design(s).vars.ticks == %{default: 8}

      {:noreply, s} =
        Builder.handle_event("set_default", %{"_target" => ["ticks"], "ticks" => ""}, s)

      assert BuilderFixture.design(s).vars.ticks == %{}

      # A variable nobody declares gets a var site on top, which is what wins.
      {:noreply, s} =
        Builder.handle_event("set_default", %{"_target" => ["fresh"], "fresh" => "1"}, s)

      assert List.last(BuilderFixture.names(s)) == "var fresh"
      assert BuilderFixture.design(s).vars.fresh == %{default: 1}

      {:noreply, s} =
        Builder.handle_event("set_default", %{"_target" => ["fresh"], "fresh" => "2"}, s)

      assert length(BuilderFixture.names(s)) == 5
      assert BuilderFixture.design(s).vars.fresh == %{default: 2}
    end

    test "the value the preview binds is set from the expanded chip" do
      s = BuilderFixture.socket(BuilderFixture.parameterised(), context: :variables)

      {:noreply, s} =
        Builder.handle_event("set_var", %{"_target" => ["ticks"], "ticks" => "6"}, s)

      assert s.assigns.bindings == %{ticks: 6}
      {:noreply, s} = Builder.handle_event("expand_variable", %{"name" => "ticks"}, s)
      assert BuilderFixture.render(s) =~ ~s(name="ticks" value="6" placeholder="3")
    end
  end

  describe "the library's two views (spec/14 §19.8)" do
    test "group is the default, and the switch is there" do
      html = rendered(:builder_store)

      assert html =~
               ~s(class="vis-builder-view vis-builder-view-on" phx-click="library_view" phx-value-view="group")

      assert html =~ ~s(class="vis-builder-view" phx-click="library_view" phx-value-view="kind")
      assert html =~ ~s(phx-value-name="Uncategorised" phx-target="-1">▾ Uncategorised</button>)
    end

    test "by kind shows every usual kind, empty or not, and the entry under its own" do
      html =
        render_component(Builder, %{
          id: "b",
          layers: BuilderFixture.layers(),
          store: Library,
          styles: false,
          library_view: :kind
        })

      # An empty kind is a heading that says so: information, not a bug.
      assert html =~ ~s(<h3 class="vis-builder-category-name vis-builder-category-empty">)
      assert html =~ ~s(phx-value-name="style" phx-target="-1">▾ style</button>)

      assert html =~ ~s(<p class="vis-builder-kind-empty">none yet</p>)

      # The fixture's entries are composites; design is not a kind (§19.8).
      refute html =~ ~s(phx-value-name="design")
      assert html =~ ~s(phx-value-name="composite" phx-target="-1">▾ composite</button>)
      assert html =~ ~s(data-builder-fragment="composite:1")
    end

    test "the switch changes the view" do
      {:ok, s} = Builder.mount(%Socket{})
      {:ok, s} = Builder.update(%{id: "b", layers: [], store: Library}, s)
      assert s.assigns.library_view == :group

      {:noreply, s} = Builder.handle_event("library_view", %{"view" => "kind"}, s)
      assert s.assigns.library_view == :kind

      {:noreply, s} = Builder.handle_event("library_view", %{"view" => "group"}, s)
      assert s.assigns.library_view == :group
    end

    test "a top-level header folds its section, says what it hides, and unfolds (#355)" do
      {:ok, s} = Builder.mount(%Socket{})
      {:ok, s} = Builder.update(%{id: "b", layers: BuilderFixture.layers(), store: Library}, s)
      assert s.assigns.library_folded == MapSet.new()

      html = fn s -> render_component(Builder, Map.put(s.assigns, :styles, false)) end
      open = html.(s)
      assert open =~ ~s(aria-expanded="true" title="hide Components")
      assert open =~ ~s(class="vis-builder-item vis-builder-component")

      {:noreply, s} = Builder.handle_event("library_toggle", %{"name" => "Components"}, s)
      assert s.assigns.library_folded == MapSet.new(["Components"])
      folded = html.(s)

      assert folded =~
               ~s(aria-expanded="false" title="show Components" phx-click="library_toggle" phx-value-name="Components")

      assert folded =~ ~s(▸ Components<span class="vis-builder-category-count">()
      refute folded =~ ~s(class="vis-builder-item vis-builder-component")
      # The other headers are untouched.
      assert folded =~ ~s(aria-expanded="true" title="hide Uncategorised")

      # The fold survives a view switch and a store change.
      {:noreply, s} = Builder.handle_event("library_view", %{"view" => "kind"}, s)
      {:noreply, s} = Builder.handle_event("library_view", %{"view" => "group"}, s)
      {:ok, s} = Builder.update(%{id: "b", layers: BuilderFixture.layers(), store: Library}, s)
      assert s.assigns.library_folded == MapSet.new(["Components"])

      {:noreply, s} = Builder.handle_event("library_toggle", %{"name" => "Components"}, s)
      assert s.assigns.library_folded == MapSet.new()
      assert html.(s) =~ ~s(class="vis-builder-item vis-builder-component")
    end

    test "a host seeds the folded headers once (#355)" do
      html =
        render_component(Builder, %{
          id: "b",
          layers: BuilderFixture.layers(),
          store: Library,
          styles: false,
          library_folded: MapSet.new(["Uncategorised"])
        })

      assert html =~ ~s(aria-expanded="false" title="show Uncategorised")
      assert html =~ ~s(aria-expanded="true" title="hide Components")
    end
  end

  describe "every form intercepts its submit (spec/14 §18.7, #274)" do
    # The builder in every state that renders a form: each context panel, a mark's page
    # with its style stack, a source's page, the parameters form, and the store's toolbar.
    defp forms_in(html), do: Regex.scan(~r/<form\b[^>]*>/, html) |> List.flatten()

    test "a form without phx-submit fails here rather than reloading a page in a browser" do
      s = BuilderFixture.socket(BuilderFixture.layers(), store: BuilderFixture.Library)

      states =
        for context <- [:inspect, :sources, :colour, :font, :variables],
            label <- ["frame", "marks[0]", "sources.primary", "styles.series", "labels[0]"],
            selected <- [0, 2] do
          {:noreply, s1} =
            Builder.handle_event("select_layer", %{"index" => to_string(selected)}, s)

          {:noreply, s1} = Builder.handle_event("select_node", %{"node" => label}, s1)
          {:noreply, s1} = Builder.handle_event("context", %{"panel" => to_string(context)}, s1)
          s1
        end

      {:noreply, with_signal} = Builder.handle_event("add_signal", %{}, s)
      {:noreply, adding} = Builder.handle_event("adding", %{}, s)
      {:noreply, expanded} = Builder.handle_event("expand_variable", %{"name" => "unit"}, s)

      htmls =
        Enum.map(states ++ [with_signal, adding, expanded], &BuilderFixture.render/1) ++
          Enum.map(Keyword.keys(BuilderFixture.cases()), &rendered/1)

      forms = htmls |> Enum.flat_map(&forms_in/1) |> Enum.uniq()
      assert forms != []

      for form <- forms do
        assert form =~ ~s(phx-submit="), "a form a browser would submit as a GET: " <> form
      end
    end

    test "submitted is a no-op: the socket is unchanged" do
      s = BuilderFixture.socket(BuilderFixture.layers())

      assert {:noreply, ^s} =
               Builder.handle_event("submitted", %{"_node" => "frame", "width" => "1"}, s)
    end
  end

  describe "the stylesheet (spec/14 §18.13, D-94)" do
    test "every rule is scoped under .vis-builder" do
      selectors =
        Builder.css()
        |> String.replace(~r{/\*.*?\*/}s, "")
        |> String.split("}")
        |> Enum.flat_map(fn block ->
          case String.split(block, "{", parts: 2) do
            [selector, _body] -> String.split(selector, ",")
            _other -> []
          end
        end)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "@")))

      assert selectors != []

      for selector <- selectors do
        assert String.starts_with?(selector, ".vis-builder"),
               "a rule escapes the component: " <> inspect(selector)
      end
    end

    test "every property used is declared on .vis-builder" do
      css = Builder.css()

      declared =
        ~r{--vis-builder-[a-z-]+(?=\s*:)}
        |> Regex.scan(css)
        |> Enum.map(&hd/1)
        |> MapSet.new()

      used =
        ~r{var\((--vis-builder-[a-z-]+)}
        |> Regex.scan(css)
        |> Enum.map(&List.last/1)
        |> MapSet.new()

      assert MapSet.subset?(used, declared),
             "used but never declared: " <> inspect(MapSet.difference(used, declared))

      assert "--vis-builder-accent" in declared
    end

    test "the strips never give up height to the workspace" do
      css = Visualize.Chart.Builder.css()
      [nodes] = Regex.run(~r/\.vis-builder-nodes \{[^}]*\}/, css)
      [chips] = Regex.run(~r/\.vis-builder-chips \{[^}]*\}/, css)
      [workspace] = Regex.run(~r/\.vis-builder-workspace \{[^}]*\}/, css)

      # A flex item that scrolls sideways has a minimum height of zero, so a tall form once
      # squeezed both rows to a sliver; the workspace is what scrolls instead.
      assert nodes =~ "flex: 0 0 auto"
      assert chips =~ "flex: 0 0 auto"
      assert workspace =~ "overflow-y: auto"
      assert workspace =~ "flex: 1 1 auto"
    end

    test "the main column fills its grid track whatever a host says about <main>" do
      css = Visualize.Chart.Builder.css()
      [main] = Regex.run(~r/\.vis-builder-main \{[^}]*\}/, css)
      assert main =~ "width: 100%"
      assert main =~ "max-width: none"
      assert main =~ "margin: 0"
    end

    test "the builder renders the stylesheet once, and not at all when the host ships it" do
      html = render_component(Builder, %{id: "b", layers: BuilderFixture.layers()})
      assert length(String.split(html, "<style")) == 2
      assert html =~ "--vis-builder-accent"

      without =
        render_component(Builder, %{id: "b", layers: BuilderFixture.layers(), styles: false})

      refute without =~ "<style"
      assert without =~ ~s(<div id="b" class="vis-builder">)
    end
  end

  describe "saving (spec/14 §18.2)" do
    test "sends exactly the stack of the layers, under the tag and the id given" do
      layers = BuilderFixture.layers()

      {:noreply, _socket} =
        Builder.handle_event("save", %{}, BuilderFixture.socket(layers, on_save: :kept))

      assert_received {:kept, "b", structure}
      assert %{composite: %{uses: [_, _, _]}} = structure
      {:ok, design, _missing} = Chart.flatten(structure, fn _id -> :error end)
      assert design == Chart.stack(layers)
    end

    test "the default tag is the documented one" do
      {:noreply, _socket} =
        Builder.handle_event("save", %{}, BuilderFixture.socket(BuilderFixture.layers()))

      assert_received {:visualize_chart_saved, "b", _design}
    end

    test "a disabled layer is not in the design that is sent" do
      layers = BuilderFixture.layers()
      socket = BuilderFixture.socket(layers, disabled: MapSet.new([2]))
      {:noreply, _socket} = Builder.handle_event("save", %{}, socket)

      assert_received {:visualize_chart_saved, "b", structure}
      {:ok, design, _missing} = Chart.flatten(structure, fn _id -> :error end)
      assert design == Chart.stack(Enum.take(layers, 2))
      refute Map.has_key?(design, :marks)
    end
  end

  describe "the store (spec/14 §18.3)" do
    test "clicking a stored fragment opens it as the stack; dragging it in adds it as the highest layer" do
      layers = BuilderFixture.layers()
      socket = BuilderFixture.socket(layers, store: Library)

      {:noreply, opened} = Builder.handle_event("add_layer", %{"name" => "composite:1"}, socket)
      assert opened.assigns.open.id == Library.baseline_id()

      # A composite entry opens as its sites: the baseline is one inline frame site.
      assert BuilderFixture.layers(opened) == [{"local", %{frame: %{kind: :cartesian}}}]

      # A drop is a copy: the site's own body, and nothing the store adds (spec/14 §18.17).
      {:noreply, added} =
        Builder.handle_event("insert", %{"name" => "composite:1", "at" => 3}, socket)

      assert BuilderFixture.layers(added) ==
               layers ++ [{"baseline", %{frame: %{kind: :cartesian}}}]

      assert %Use{ref: nil, local: %{frame: %{kind: :cartesian}}} = List.last(added.assigns.uses)
      assert added.assigns.notice == nil

      # A link resolves through the store, flattened.
      {:noreply, linked} =
        Builder.handle_event(
          "insert",
          %{"name" => "composite:1", "at" => 3, "as" => "link"},
          socket
        )

      assert BuilderFixture.layers(linked) ==
               layers ++ [{"baseline", %{version: 1, frame: %{kind: :cartesian}}}]

      assert %Use{ref: {:composite, 1}} = List.last(linked.assigns.uses)
    end

    test "a name the store does not hold is a notice and changes no layer" do
      layers = BuilderFixture.layers()
      socket = BuilderFixture.socket(layers, store: Library)
      {:noreply, missing} = Builder.handle_event("add_layer", %{"name" => "composite:2"}, socket)
      {:noreply, absent} = Builder.handle_event("add_layer", %{"name" => "nope"}, socket)

      assert BuilderFixture.layers(missing) == layers
      assert missing.assigns.notice == "no fragment is stored under composite:2"
      assert absent.assigns.notice == "no fragment is stored under nope"
    end

    test "put/2 keeps the stacked design, and its refusal is shown and not interpreted" do
      layers = BuilderFixture.layers()
      library = BuilderFixture.socket(layers, store: Library)
      {:noreply, kept} = Builder.handle_event("put_design", %{"name" => "x"}, library)

      {:noreply, refused} =
        Builder.handle_event(
          "put_design",
          %{"name" => "x"},
          BuilderFixture.socket(layers, store: Refusing)
        )

      assert kept.assigns.notice == nil
      assert refused.assigns.notice == "the store refused the design: :read_only"
    end
  end

  describe "editing (spec/14 §18.7)" do
    test "the open node and the open tab are the component's own state" do
      socket = BuilderFixture.socket(BuilderFixture.layers())
      {:noreply, moved} = Builder.handle_event("select_node", %{"node" => "frame.size"}, socket)
      {:noreply, tabbed} = Builder.handle_event("facet", %{"facet" => "style"}, socket)
      {:noreply, unknown} = Builder.handle_event("facet", %{"facet" => "nonsense"}, socket)

      assert moved.assigns.node_label == "frame.size"
      assert moved.assigns.facet == nil
      assert tabbed.assigns.facet == :style
      assert unknown.assigns.facet == nil
    end

    test "a parsed value is written into the selected layer at the node's path" do
      socket = BuilderFixture.socket(BuilderFixture.layers(), node_label: "frame.size")
      params = %{"_target" => ["width"], "width" => "640", "height" => "200"}
      {:noreply, edited} = Builder.handle_event("edit", params, socket)

      assert {:house, house} = hd(BuilderFixture.layers(edited))
      assert house.frame.size == %{width: 640, height: 200}
      assert Enum.drop(BuilderFixture.layers(edited), 1) == Enum.drop(BuilderFixture.layers(), 1)
    end

    test "a blank control removes the key, and an unchecked checkbox writes false" do
      socket =
        BuilderFixture.socket(BuilderFixture.layers(), selected: 1, node_label: "frame.axes[0]")

      blank = %{"_target" => ["ticks"], "ticks" => ""}
      {:noreply, removed} = Builder.handle_event("edit", blank, socket)

      assert {:shared, shared} = Enum.at(BuilderFixture.layers(removed), 1)
      assert hd(shared.frame.axes) == %{scale: :x, side: :bottom}

      {:noreply, unchecked} = Builder.handle_event("edit", %{"_target" => ["grid"]}, socket)
      assert {:shared, off} = Enum.at(BuilderFixture.layers(unchecked), 1)
      assert hd(off.frame.axes).grid == false
    end

    test "a key the node kind does not declare changes nothing" do
      socket = BuilderFixture.socket(BuilderFixture.layers())
      params = %{"_target" => ["stoke_width"], "stoke_width" => "3"}
      {:noreply, edited} = Builder.handle_event("edit", params, socket)

      assert BuilderFixture.layers(edited) == BuilderFixture.layers()
    end

    test "a chart layer becomes the map it is, which is the same design" do
      {:ok, chart} = Chart.from_map(Chart.stack(BuilderFixture.layers()))
      socket = BuilderFixture.socket([chart], node_label: "frame.size")
      params = %{"_target" => ["width"], "width" => "640"}
      {:noreply, edited} = Builder.handle_event("edit", params, socket)

      [{_name, layer}] = BuilderFixture.layers(edited)
      assert is_map(layer) and not is_struct(layer)
      assert layer.frame.size.width == 640
      assert Map.delete(layer.frame, :size) == Map.delete(Chart.to_map(chart).frame, :size)
    end

    test "the editor is rendered over the selected layer, with the design's faults" do
      html = rendered(:builder)
      assert html =~ ~s(class="vis-builder-page vis-builder-page-0")
      # `frame.size` is reachable through the `frame` root now that the strip is grouped;
      # the second row is asserted with the rest of the grouping above.
      assert html =~
               ~s(phx-value-root="frame" phx-target="-1"><svg class="vis-builder-icon vis-builder-icon-root vis-builder-icon-frame")

      refute html =~ "vis-builder-key-errors"
    end
  end

  describe "the graph selects (spec/14 §18.4, §18.16, spec/10 §16.3)" do
    test "the graph carries the hook in scope graph, the chart its paths and the open node" do
      html = at_node("marks[0]")

      assert html =~
               ~s(<div id="b-graph" class="vis-builder-graph" tabindex="0" phx-hook="BuilderHook" data-builder-target="-1" data-builder-scope="graph">)

      assert html =~ ~s(data-builder-selected="marks[0]")
      assert html =~ ~s(<g class="mark mark-line" data-node="marks[0]")
      assert html =~ ~s(<g class="frame" data-node="frame")
      assert html =~ ~s(data-node="frame.axes[1]")
      assert html =~ ~s(<text class="label" data-node="labels[0]")

      # The label is the resolved entry's. A sub-node the graph does not draw — a scale —
      # is carried as it is; the hook outlines the drawn node it is under, `frame`.
      assert at_node("frame.scales.x") =~ ~s(data-builder-selected="frame.scales.x")
    end

    test "pick opens the node in the layer that owns it" do
      # `house` is selected; the frame's word is `shared`'s (its scales and axes), the
      # mark and the label are `panel`'s (§18.15).
      s = BuilderFixture.socket(BuilderFixture.layers(), selected: 0)
      assert BuilderFixture.selected(s) == 0

      {:noreply, picked} = Builder.handle_event("pick", %{"node" => "marks[0]"}, s)
      assert BuilderFixture.selected(picked) == 2
      assert picked.assigns.node_label == "marks[0]"
      assert picked.assigns.context == :inspect
      assert BuilderFixture.render(picked) =~ ~s(data-builder-selected="marks[0]")

      {:noreply, picked} = Builder.handle_event("pick", %{"node" => "frame"}, s)
      assert BuilderFixture.selected(picked) == 1
      assert picked.assigns.node_label == "frame"

      {:noreply, picked} = Builder.handle_event("pick", %{"node" => "frame.axes[0]"}, s)
      assert BuilderFixture.selected(picked) == 1
      assert picked.assigns.node_label == "frame.axes[0]"

      {:noreply, picked} = Builder.handle_event("pick", %{"node" => "labels[0]"}, s)
      assert BuilderFixture.selected(picked) == 2
      assert picked.assigns.node_label == "labels[0]"
    end

    test "a pick for a node the chart does not have changes nothing" do
      s = BuilderFixture.socket(BuilderFixture.layers(), selected: 0, node_label: "frame")
      {:noreply, same} = Builder.handle_event("pick", %{"node" => "marks[7]"}, s)
      assert BuilderFixture.selected(same) == 0
      assert same.assigns.node_label == "frame"
    end

    test "the hook picks in scope graph and outlines the longest prefix of the open label" do
      js = Visualize.Hooks.Builder.js_hook()
      assert js =~ "if (this.scope === 'graph') {"
      assert js =~ "e.target.closest('[data-node]')"
      assert js =~ "this.push('pick', { node: node.getAttribute('data-node') })"
      assert js =~ "svg[data-builder-selected]"
      assert js =~ "label.startsWith(path + '.') || label.startsWith(path + '[')"
      assert js =~ "classList.toggle('vis-builder-graph-selected'"
      # Mounted and updated both outline: the render carries the label and the hook draws it.
      assert length(Regex.scan(~r/this\.outline\(\);/, js)) == 2
    end

    test "hover and the open node are outlined from the stylesheet, in the accent" do
      css = Builder.css()

      assert css =~
               ".vis-builder .vis-builder-graph [data-node]:hover:not(:has([data-node]:hover)) {"

      assert css =~ ".vis-builder .vis-builder-graph .vis-builder-graph-selected {"
      assert css =~ "outline: 2px solid var(--vis-builder-accent);"
    end
  end

  defp rendered(name),
    do: BuilderFixture.render_case(Keyword.fetch!(BuilderFixture.cases(), name))

  # A node tab is an icon named by its aria-label (spec/14 §18.13, #314); a chip is its text.
  defp tabs(html, "vis-builder-node") do
    ~r{<button[^>]*class="vis-builder-node(?: [^"]*)?"[^>]*aria-label="([^"]*)"}
    |> Regex.scan(html)
    |> Enum.map(&List.last/1)
  end

  defp tabs(html, class) do
    ~r{<button[^>]*class="#{class}(?: [^"]*)?"[^>]*>([^<]*)</button>}
    |> Regex.scan(html)
    |> Enum.map(&List.last/1)
  end

  # The builder rendered with a given node open, which is what selecting a tab does.
  # A selected position becomes the seeded use's id, which is one-based (spec/14 §19.3).
  defp at_node(label, opts \\ []) do
    opts =
      case Keyword.pop(opts, :selected) do
        {nil, rest} -> rest
        {index, rest} -> Keyword.put(rest, :selected, {:use, index + 1})
      end

    render_component(
      Builder,
      Enum.into(opts, %{
        id: "b",
        layers: BuilderFixture.layers(),
        sources: BuilderFixture.sources(),
        styles: false,
        node_label: label
      })
    )
  end
end
