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

    test "the library is offered only when a store is given" do
      plain = rendered(:builder)
      stored = rendered(:builder_store)
      refute plain =~ "vis-builder-store"
      assert stored =~ ~s(<select name="name" class="vis-builder-store">)
      assert stored =~ ~s(<option value="baseline">baseline</option>)
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
      assert main =~ ~s(<nav class="vis-builder-nodes">)
      assert main =~ ~s(class="vis-builder-editor")
      assert main =~ ~s(class="vis-builder-preview")
    end

    test "the top row is one tab per root, in the order the walk reaches it" do
      html = rendered(:builder)
      assert html =~ ~s(class="vis-builder-node vis-builder-node-open")

      roots =
        BuilderFixture.layers()
        |> hd()
        |> then(fn {_name, layer} -> layer end)
        |> Editor.nodes()
        |> Enum.map(&(&1.label |> String.split(~r/[.\[]/, parts: 2) |> hd()))
        |> Enum.uniq()

      assert tabs(html, "vis-builder-node") == roots
      assert roots == ["design", "styles", "frame"]
    end

    test "a root that is not itself a node opens its first member" do
      # `styles` exists only as the map its members live in, so its tab opens `styles.series`
      # rather than a node the fragment does not have.
      html = rendered(:builder)
      assert html =~ ~s(phx-value-node="styles.series" phx-target="-1">styles</button>)
    end

    test "the open root's children are the second row, labelled by what they add" do
      refute rendered(:builder) =~ "vis-builder-subnodes"

      html = at_node("frame")
      assert html =~ ~s(<nav class="vis-builder-subnodes">)
      assert tabs(html, "vis-builder-subnode") == ["size", "margin"]

      # The root stays marked while a child is open, so the strip says where you are.
      open = at_node("frame.size")
      assert open =~ ~s(class="vis-builder-node vis-builder-node-open")
      assert open =~ ~s(class="vis-builder-subnode vis-builder-subnode-open")
      assert open =~ ~s(phx-value-node="frame.size" phx-target="-1">size</button>)
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
      assert names(socket) == [:panel, :house, :shared]

      {:ok, socket} = Builder.update(host, socket)
      assert names(socket) == [:panel, :house, :shared]
    end

    test "a move, an added layer and a node edit all survive it", %{host: host, socket: socket} do
      {:noreply, moved} =
        Builder.handle_event("move_layer", %{"index" => "0", "to" => "2"}, socket)

      {:ok, moved} = Builder.update(host, moved)
      assert names(moved) == [:shared, :panel, :house]

      stored = Map.put(host, :store, Library)
      {:ok, socket} = Builder.update(stored, socket)
      {:noreply, added} = Builder.handle_event("add_layer", %{"name" => "baseline"}, socket)
      {:ok, added} = Builder.update(stored, added)
      assert length(added.assigns.layers) == length(host.layers) + 1

      {:noreply, edited} =
        Builder.handle_event("edit", %{"_target" => ["version"], "version" => "2"}, socket)

      {:ok, edited} = Builder.update(host, edited)
      assert {_name, %{version: 2}} = hd(edited.assigns.layers)
    end

    test "a host that changes its list replaces the stack", %{socket: socket} do
      {:noreply, socket} = Builder.handle_event("reorder", %{"from" => 2, "to" => 0}, socket)
      assert names(socket) == [:panel, :house, :shared]

      replaced = %{id: "b", layers: [{:only, %{version: 1}}], sources: %{}}
      {:ok, socket} = Builder.update(replaced, socket)
      assert names(socket) == [:only]
    end

    test "an imported document is not overwritten by the host's stack", %{
      host: host,
      socket: socket
    } do
      {:ok, document} =
        BuilderFixture.layers() |> Chart.stack() |> Chart.from_map!() |> Chart.to_json()

      {:noreply, socket} = Builder.handle_event("import", %{"document" => document}, socket)
      assert names(socket) == [:imported]

      {:ok, socket} = Builder.update(host, socket)
      assert names(socket) == [:imported]
    end
  end

  describe "the row actions (spec/14 §18.8)" do
    test "every action carries an accessible name and hides its word" do
      html = BuilderFixture.render_case(Keyword.fetch!(BuilderFixture.cases(), :layers))

      for {class, label} <- [
            {"vis-builder-layer-select", "Edit house"},
            {"vis-builder-layer-up", "Move house up"},
            {"vis-builder-layer-down", "Move house down"},
            {"vis-builder-layer-toggle", "Disable house"}
          ] do
        assert html =~ ~s(class="#{class}")
        assert html =~ ~s(title="#{label}")
        assert html =~ ~s(aria-label="#{label}")
      end

      assert html =~ ~s(<span class="vis-builder-action-label">Edit</span>)
      assert html =~ ~s(<span class="vis-builder-action-label">Disable</span>)
    end

    test "no action rule is out-specified by the generic control rule" do
      # `.vis-builder button` is (0,1,1). A rule written as a bare `.vis-builder-layer-up` is
      # (0,1,0) and loses to it, which is how the icons were defeated the first time; every
      # action rule must therefore be compound.
      for class <- ~w(layer-select layer-up layer-down layer-toggle action-label) do
        bare = ~r/(^|,)\s*\.vis-builder-#{class}\b[^,{]*\{/m

        refute Regex.match?(bare, Builder.css()),
               "a bare .vis-builder-#{class} rule loses to `.vis-builder button`"
      end

      assert Builder.css() =~ ".vis-builder .vis-builder-layer-up"
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

      {_name, layer} = hd(s.assigns.layers)
      assert %{} = layer.styles.callout
      assert s.assigns.node_label == "styles.callout"
      assert s.assigns.notice == nil
    end

    test "a style may be added to a layer that carries no styles at all", %{socket: s} do
      {:noreply, s} = Builder.handle_event("select_layer", %{"index" => "1"}, s)
      {_name, shared} = Enum.at(s.assigns.layers, 1)
      refute Map.has_key?(shared, :styles)

      {:noreply, s} = Builder.handle_event("add_style", %{"name" => "callout"}, s)
      {_name, shared} = Enum.at(s.assigns.layers, 1)
      assert shared.styles.callout == %{}
    end

    test "a blank name is a notice and declares nothing", %{socket: s} do
      {:noreply, after_blank} = Builder.handle_event("add_style", %{"name" => "   "}, s)
      assert after_blank.assigns.notice == "a style needs a name"
      assert after_blank.assigns.layers == s.assigns.layers
    end

    test "selecting a style opens the layer that declares it", %{socket: s} do
      # `series` is the house layer's, which is 0; move off it first so the move is visible.
      {:noreply, s} = Builder.handle_event("select_layer", %{"index" => "2"}, s)
      assert s.assigns.selected == 2

      {:noreply, s} = Builder.handle_event("select_style", %{"name" => "series"}, s)
      assert s.assigns.selected == 0
      assert s.assigns.node_label == "styles.series"
    end

    test "a style nothing declares changes nothing", %{socket: s} do
      {:noreply, after_miss} = Builder.handle_event("select_style", %{"name" => "nope"}, s)
      assert after_miss.assigns.selected == s.assigns.selected
      assert after_miss.assigns.node_label == s.assigns.node_label
    end

    test "a mark's style is a select over the declared names, not a box" do
      html =
        render_component(Builder, %{
          id: "b",
          layers: BuilderFixture.layers(),
          sources: BuilderFixture.sources(),
          styles: false,
          selected: 2,
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
      {:noreply, _socket} = Builder.handle_event("save", %{}, socket(layers, on_save: :kept))

      assert_received {:kept, "b", design}
      assert design == Chart.stack(layers)
    end

    test "the default tag is the documented one" do
      {:noreply, _socket} = Builder.handle_event("save", %{}, socket(BuilderFixture.layers()))
      assert_received {:visualize_chart_saved, "b", _design}
    end

    test "a disabled layer is not in the design that is sent" do
      layers = BuilderFixture.layers()
      socket = socket(layers, disabled: MapSet.new([2]))
      {:noreply, _socket} = Builder.handle_event("save", %{}, socket)

      assert_received {:visualize_chart_saved, "b", design}
      assert design == Chart.stack(Enum.take(layers, 2))
      refute Map.has_key?(design, :marks)
    end
  end

  describe "the store (spec/14 §18.3)" do
    test "a stored fragment is added as the highest layer" do
      layers = BuilderFixture.layers()
      socket = socket(layers, store: Library)
      {:noreply, socket} = Builder.handle_event("add_layer", %{"name" => "baseline"}, socket)

      assert socket.assigns.layers ==
               layers ++ [{:baseline, %{version: 1, frame: %{kind: :cartesian}}}]

      assert socket.assigns.notice == nil
    end

    test "a name the store does not hold is a notice and changes no layer" do
      layers = BuilderFixture.layers()
      socket = socket(layers, store: Library)
      {:noreply, missing} = Builder.handle_event("add_layer", %{"name" => "missing"}, socket)
      {:noreply, absent} = Builder.handle_event("add_layer", %{"name" => "nope"}, socket)

      assert missing.assigns.layers == layers
      assert missing.assigns.notice == "no fragment is stored under missing"
      assert absent.assigns.notice == "no fragment is stored under nope"
    end

    test "put/2 keeps the stacked design, and its refusal is shown and not interpreted" do
      layers = BuilderFixture.layers()
      library = socket(layers, store: Library)
      {:noreply, kept} = Builder.handle_event("put_design", %{"name" => "x"}, library)

      {:noreply, refused} =
        Builder.handle_event("put_design", %{"name" => "x"}, socket(layers, store: Refusing))

      assert kept.assigns.notice == nil
      assert refused.assigns.notice == "the store refused the design: :read_only"
    end
  end

  describe "editing (spec/14 §18.7)" do
    test "the open node and the open tab are the component's own state" do
      socket = socket(BuilderFixture.layers())
      {:noreply, moved} = Builder.handle_event("select_node", %{"node" => "frame.size"}, socket)
      {:noreply, tabbed} = Builder.handle_event("facet", %{"facet" => "style"}, socket)
      {:noreply, unknown} = Builder.handle_event("facet", %{"facet" => "nonsense"}, socket)

      assert moved.assigns.node_label == "frame.size"
      assert moved.assigns.facet == nil
      assert tabbed.assigns.facet == :style
      assert unknown.assigns.facet == nil
    end

    test "a parsed value is written into the selected layer at the node's path" do
      socket = socket(BuilderFixture.layers(), node_label: "frame.size")
      params = %{"_target" => ["width"], "width" => "640", "height" => "200"}
      {:noreply, edited} = Builder.handle_event("edit", params, socket)

      assert {:house, house} = hd(edited.assigns.layers)
      assert house.frame.size == %{width: 640, height: 200}
      assert Enum.drop(edited.assigns.layers, 1) == Enum.drop(BuilderFixture.layers(), 1)
    end

    test "a blank control removes the key, and an unchecked checkbox writes false" do
      socket = socket(BuilderFixture.layers(), selected: 1, node_label: "frame.axes[0]")
      blank = %{"_target" => ["ticks"], "ticks" => ""}
      {:noreply, removed} = Builder.handle_event("edit", blank, socket)

      assert {:shared, shared} = Enum.at(removed.assigns.layers, 1)
      assert hd(shared.frame.axes) == %{scale: :x, side: :bottom}

      {:noreply, unchecked} = Builder.handle_event("edit", %{"_target" => ["grid"]}, socket)
      assert {:shared, off} = Enum.at(unchecked.assigns.layers, 1)
      assert hd(off.frame.axes).grid == false
    end

    test "a key the node kind does not declare changes nothing" do
      socket = socket(BuilderFixture.layers())
      params = %{"_target" => ["stoke_width"], "stoke_width" => "3"}
      {:noreply, edited} = Builder.handle_event("edit", params, socket)

      assert edited.assigns.layers == BuilderFixture.layers()
    end

    test "a chart layer becomes the map it is, which is the same design" do
      {:ok, chart} = Chart.from_map(Chart.stack(BuilderFixture.layers()))
      socket = socket([chart], node_label: "frame.size")
      params = %{"_target" => ["width"], "width" => "640"}
      {:noreply, edited} = Builder.handle_event("edit", params, socket)

      [layer] = edited.assigns.layers
      assert is_map(layer) and not is_struct(layer)
      assert layer.frame.size.width == 640
      assert Map.delete(layer.frame, :size) == Map.delete(Chart.to_map(chart).frame, :size)
    end

    test "the editor is rendered over the selected layer, with the design's faults" do
      html = rendered(:builder)
      assert html =~ ~s(<div class="vis-builder-editor">)
      # `frame.size` is reachable through the `frame` root now that the strip is grouped;
      # the second row is asserted with the rest of the grouping above.
      assert html =~ ~s(phx-value-node="frame" phx-target="-1">frame</button>)
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
  defp at_node(label) do
    render_component(Builder, %{
      id: "b",
      layers: BuilderFixture.layers(),
      sources: BuilderFixture.sources(),
      styles: false,
      node_label: label
    })
  end

  defp names(socket), do: Enum.map(socket.assigns.layers, fn {name, _layer} -> name end)

  defp socket(layers, opts \\ []) do
    assigns =
      [
        id: "b",
        layers: layers,
        disabled: MapSet.new(),
        notice: nil,
        store: nil,
        on_save: :visualize_chart_saved,
        selected: 0,
        facet: nil,
        node_label: "design",
        sources: BuilderFixture.sources(),
        vars: %{},
        bindings: %{},
        theme: nil
      ]
      |> Keyword.merge(opts)
      |> Map.new()

    Phoenix.Component.assign(%Socket{}, assigns)
  end
end
