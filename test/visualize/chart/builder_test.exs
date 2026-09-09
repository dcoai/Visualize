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
      assert html =~ ~s(phx-value-node="frame.size")
      refute html =~ "vis-builder-key-errors"
    end
  end

  defp rendered(name),
    do: BuilderFixture.render_case(Keyword.fetch!(BuilderFixture.cases(), name))

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
        theme: nil
      ]
      |> Keyword.merge(opts)
      |> Map.new()

    Phoenix.Component.assign(%Socket{}, assigns)
  end
end
