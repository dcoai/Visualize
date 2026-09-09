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
        on_save: :visualize_chart_saved
      ]
      |> Keyword.merge(opts)
      |> Map.new()

    Phoenix.Component.assign(%Socket{}, assigns)
  end
end
