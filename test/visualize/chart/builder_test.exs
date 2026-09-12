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
      assert html =~ ~s(class="vis-builder-toolbar")
      assert html =~ ~s(class="vis-builder-save")
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

      assert stored =~ ~s(<div class="vis-builder-panels vis-builder-panels-library">)
      assert stored =~ ~s(class="vis-builder-library-pane")
      assert stored =~ ~s(<h3 class="vis-builder-category-name">Uncategorised</h3>)
      assert stored =~ ~s(data-builder-fragment="composite:1")
      assert stored =~ ~s(class="vis-builder-put")
    end

    test "the three regions are rendered, the layers in the sidebar and the nodes as tabs" do
      html = rendered(:builder)

      assert html =~ ~s(<div class="vis-builder-panels">)
      assert html =~ ~s(<aside class="vis-builder-sidebar">)
      assert html =~ ~s(<main class="vis-builder-main">)
      assert html =~ ~s(<div class="vis-builder-workspace">)
      assert html =~ ~s(<div class="vis-builder-tray">)

      # The stack is inside the sidebar and the node strip inside the main column, which is
      # the whole of what the shell is: the panels themselves are unchanged.
      [_, sidebar] = String.split(html, ~s(<aside class="vis-builder-sidebar">), parts: 2)
      [sidebar, _] = String.split(sidebar, "</aside>", parts: 2)
      assert sidebar =~ ~s(class="vis-builder-layers")

      [_, main] = String.split(html, ~s(<main class="vis-builder-main">), parts: 2)
      assert main =~ ~s(class="vis-builder-nodes")
      assert main =~ ~s(class="vis-builder-editor")
      assert main =~ ~s(class="vis-builder-preview")
    end

    test "the top row is every root the design has, in the schema's order" do
      html = rendered(:builder)
      assert html =~ ~s(class="vis-builder-node vis-builder-node-open")

      # The selected layer is `house`, which declares three of them; the strip shows all
      # seven, because a person asks where the marks are, not which fragment holds them.
      # Neither the design's own root nor vars is a tab (§18.13): a declaration is the
      # variable panel's, and variables are chips in the context (§19.10).
      assert tabs(html, "vis-builder-node") == ~w(sources styles frame marks labels)
    end

    test "a root the selected layer does not declare is marked elsewhere" do
      html = rendered(:builder)

      assert html =~
               ~s(class="vis-builder-node vis-builder-node-elsewhere" title="marks — this layer declares none; opens the layer that does")

      # And one it does declare is not.
      assert html =~ ~s(class="vis-builder-node" title="frame of this layer")
    end

    test "the open root's children and the node's facets are one strip" do
      html = at_node("frame")
      assert html =~ ~s(<nav class="vis-builder-chips">)

      # Children first, then the facets, in one row of one kind of control.
      chips = tabs(html, "vis-builder-chip")
      assert Enum.take(chips, 2) == ["size", "margin"]
      assert Enum.drop(chips, 2) == Enum.map(Editor.facets(:frame), &to_string/1)

      # The root stays marked while a child is open, so the strip says where you are.
      open = at_node("frame.size")
      assert open =~ ~s(class="vis-builder-node vis-builder-node-open")
      assert open =~ ~s(class="vis-builder-chip vis-builder-chip-open")
      assert open =~ ~s(phx-value-node="frame.size")
    end

    test "a lone facet is not a chip, because it is not a choice" do
      # A style has one facet, so the strip over `styles.series` is the declared styles and
      # nothing else; the `style` chip it used to carry was a control that did nothing.
      assert Editor.facets(:style) == [:style]

      html = at_node("styles.series")
      assert tabs(html, "vis-builder-chip") == ["series"]
      refute html =~ ~s(phx-value-facet="style")
    end

    test "a node with one facet and no children has no strip at all" do
      html =
        render_component(Builder, %{
          id: "b",
          layers: [{:only, %{meta: %{name: "Uptime"}}}],
          styles: false,
          node_label: "meta"
        })

      assert Editor.facets(:meta) == [:content]
      assert html =~ ~s(phx-value-root="meta")
      refute html =~ ~s(class="vis-builder-chips")
    end

    test "a facet chip carries its facet and a node chip carries its node" do
      html = at_node("frame")
      assert html =~ ~s(phx-click="select_node" phx-value-node="frame.size")
      assert html =~ ~s(phx-click="facet" phx-value-facet="geometry")
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
               ~s(title="house, layer 1 of 3, selected: Enter to edit, arrows to move, drag to reorder")

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
      assert html =~ "style stack"
      assert html =~ ~s(class="vis-builder-opened")
      refute html =~ ~s(class="vis-builder-preview")
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
        Builder.handle_event("insert", %{"name" => "style:2", "at" => 0}, opened)

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
      assert html =~ "Layers"
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

    test "the selected layer's keys are mask checkboxes, checked where the mask holds them", %{
      socket: s
    } do
      html = BuilderFixture.render(s)
      assert html =~ ~s(<h3 class="vis-builder-context-title">house</h3>)
      assert html =~ ~s(<form class="vis-builder-masks" phx-change="mask")
      assert html =~ ~s(name="frame.margin" value="true">)
      refute html =~ ~s(name="frame.margin" value="true" checked>)

      {:noreply, masked} =
        Builder.handle_event(
          "mask",
          %{"_target" => ["frame.margin"], "frame.margin" => "true"},
          s
        )

      assert hd(masked.assigns.uses).mask == [[:frame, :margin]]
      assert BuilderFixture.render(masked) =~ ~s(name="frame.margin" value="true" checked>)

      # The house's contribution no longer carries the margin, so the layers below show through.
      {_house, house} = hd(BuilderFixture.layers(masked))
      refute Map.has_key?(house.frame, :margin)
      assert Map.has_key?(house.frame, :size)

      # An unchecked box submits nothing, which is the path leaving.
      {:noreply, back} = Builder.handle_event("mask", %{"_target" => ["frame.margin"]}, masked)
      assert hd(back.assigns.uses).mask == []
    end

    test "a disabled layer is said to be, not drawn as every box checked", %{socket: s} do
      {:noreply, off} = Builder.handle_event("toggle_layer", %{"index" => "0"}, s)
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
      {:noreply, s} = Builder.handle_event("insert", %{"name" => "composite:1", "at" => 0}, s)
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

      numbers =
        html
        |> String.split(~s(class="vis-builder-fill-numbers"))
        |> Enum.at(1)
        |> String.split("</fieldset>")
        |> hd()

      {opacity_at, _} = :binary.match(numbers, ~s(name="fill_opacity"))
      {angle_at, _} = :binary.match(numbers, ~s(name="fill.angle"))
      assert opacity_at < angle_at
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

      [style, gradient] = s.assigns.uses
      assert style.local == %{style: %{stroke: "#000", fill: {:paint, :style_fill}}}
      assert gradient.key == :style_fill
      assert gradient.local.gradient.kind == :linear
      assert s.assigns.labels[gradient.id] == "gradient style_fill"

      {:noreply, s} =
        Builder.handle_event("edit", %{"_target" => ["fill.angle"], "fill.angle" => "45"}, s)

      assert Enum.at(s.assigns.uses, 1).local.gradient.angle == 45
    end
  end

  describe "the context's icon row (spec/14 §19.10)" do
    setup do
      s = BuilderFixture.socket(BuilderFixture.layers(), store: Visualize.Chart.BuilderTest.Refs)
      {:noreply, s} = Builder.handle_event("select_node", %{"node" => "styles.series"}, s)
      %{socket: s}
    end

    test "four icons, one open; the layer's context is the default", %{socket: s} do
      html = BuilderFixture.render(s)
      assert html =~ ~s(<nav class="vis-builder-context-icons" aria-label="context panels">)

      for panel <- ~w(layer colour font variables) do
        assert html =~ ~s(phx-click="context" phx-value-panel="#{panel}")
      end

      assert html =~
               ~s(class="vis-builder-context-icon vis-builder-context-icon-on" title="layer")

      assert html =~ ~s(class="vis-builder-layer-context")
      refute html =~ ~s(class="vis-builder-picker")
      refute html =~ ~s(class="vis-builder-variables")

      {:noreply, vars} = Builder.handle_event("context", %{"panel" => "variables"}, s)
      html = BuilderFixture.render(vars)
      assert html =~ ~s(class="vis-builder-variables")
      refute html =~ ~s(class="vis-builder-layer-context")

      {:noreply, same} = Builder.handle_event("context", %{"panel" => "nonsense"}, s)
      assert same.assigns.context == :layer
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
      assert s.assigns.context == :font
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

      refute faced_html =~ ~s(phx-value-field="font_style")
      assert length(Regex.scan(~r/class="vis-builder-face-list/, faced_html)) == 2

      {:noreply, s} =
        Builder.handle_event(
          "edit",
          %{"_target" => ["font_family"], "font_family" => "Georgia"},
          s
        )

      assert get_in(hd(s.assigns.uses).local, [:styles, :series, :font_family]) == "Georgia"

      # A node with no font keys says which to open.
      {:noreply, frame} = Builder.handle_event("select_node", %{"node" => "frame"}, s)
      {:noreply, frame} = Builder.handle_event("context", %{"panel" => "font"}, frame)
      assert BuilderFixture.render(frame) =~ "open a style"
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
      assert html =~ "marks of this layer — 1 thing still needed"
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

    test "an elsewhere tab is marked too, since the need is the design's", %{} do
      layers = [
        {:house, %{version: 1, frame: %{kind: :cartesian}}},
        {:panel, %{marks: [%{id: :m, type: :line}]}}
      ]

      s = BuilderFixture.socket(layers, selected: 0)
      html = BuilderFixture.render(s)

      assert html =~
               ~s(class="vis-builder-node vis-builder-node-elsewhere vis-builder-node-needs")

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

      assert html =~ "vis-builder-chip vis-builder-chip-open vis-builder-chip-needs" or
               html =~ "vis-builder-chip vis-builder-chip-needs"
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
      assert html =~ ~s(<span class="vis-builder-item-text">t</span>)
      assert html =~ ~s(phx-click="list_remove" phx-value-field="fields" phx-value-index="0")
      assert html =~ ~s(name="fields.add" class="vis-builder-item-box" placeholder="+ add")
      refute html =~ ~s(<textarea name="fields">)

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
               ~s(aria-label="house, layer 1 of 3, selected: Enter to edit, arrows to move, drag to reorder")

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
               ~s(: Enter to open, Insert to add above the selected layer, drag into the stack")

      {:noreply, s} = Builder.handle_event("select_layer", %{"index" => "1"}, s)

      {:noreply, added} =
        Builder.handle_event("fragment_key", %{"key" => "Insert", "name" => "composite:1"}, s)

      assert BuilderFixture.names(added) == [:house, :shared, "baseline", :panel]

      {:noreply, opened} =
        Builder.handle_event("fragment_key", %{"key" => "Enter", "name" => "composite:1"}, s)

      assert opened.assigns.open.id == Library.baseline_id()
    end
  end

  describe "reaching a root the selected layer does not declare (spec/14 §18.13)" do
    setup do
      host = %{id: "b", layers: BuilderFixture.layers(), sources: BuilderFixture.sources()}
      {:ok, socket} = Builder.mount(%Socket{})
      {:ok, socket} = Builder.update(host, socket)
      %{socket: socket}
    end

    test "clicking it selects the layer that declares it, and opens it", %{socket: s} do
      # `house` is selected and declares no marks; `panel` does.
      assert BuilderFixture.selected(s) == 0

      {:noreply, s} = Builder.handle_event("select_root", %{"root" => "marks"}, s)

      assert BuilderFixture.selected(s) == 2
      assert s.assigns.node_label == "marks[0]"
    end

    test "a root the selected layer does declare opens there, with no move", %{socket: s} do
      {:noreply, s} = Builder.handle_event("select_root", %{"root" => "frame"}, s)

      assert BuilderFixture.selected(s) == 0
      assert s.assigns.node_label == "frame"
    end

    test "the highest layer wins when more than one declares it", %{socket: s} do
      # Both `house` and `shared` declare a frame; the higher is `shared`.
      {:noreply, s} = Builder.handle_event("select_layer", %{"index" => "2"}, s)
      {:noreply, s} = Builder.handle_event("select_root", %{"root" => "frame"}, s)

      assert BuilderFixture.selected(s) == 1
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

  describe "the variable panel (spec/14 §19.10)" do
    test "lists the composition's variables alphabetically, typed by first use, with their uses as links" do
      s = BuilderFixture.socket(BuilderFixture.parameterised(), context: :variables)
      html = BuilderFixture.render(s)

      # No tab: variables live in the context.
      refute html =~ ~s(phx-value-root="variables")
      [_, context] = String.split(html, ~s(<aside class="vis-builder-context">), parts: 2)
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
      assert html =~ "vis-builder-field-found"
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
      assert html =~ ~s(<h3 class="vis-builder-category-name">Uncategorised</h3>)
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
      assert html =~
               ~s(<h3 class="vis-builder-category-name vis-builder-category-empty">style</h3>)

      assert html =~ ~s(<p class="vis-builder-kind-empty">none yet</p>)

      # The fixture's entries are composites; design is not a kind (§19.8).
      refute html =~ ~s(>design</h3>)
      assert html =~ ~s(<h3 class="vis-builder-category-name">composite</h3>)
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

      {:noreply, added} =
        Builder.handle_event("insert", %{"name" => "composite:1", "at" => 3}, socket)

      assert BuilderFixture.layers(added) ==
               layers ++ [{"baseline", %{version: 1, frame: %{kind: :cartesian}}}]

      assert added.assigns.notice == nil
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
      assert html =~ ~s(<div class="vis-builder-editor">)
      # `frame.size` is reachable through the `frame` root now that the strip is grouped;
      # the second row is asserted with the rest of the grouping above.
      assert html =~ ~s(phx-value-root="frame" phx-target="-1">frame</button>)
      refute html =~ "vis-builder-key-errors"
    end
  end

  defp rendered(name),
    do: BuilderFixture.render_case(Keyword.fetch!(BuilderFixture.cases(), name))

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
