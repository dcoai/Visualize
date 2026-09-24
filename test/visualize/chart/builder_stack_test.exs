defmodule Visualize.Chart.Builder.StackTest do
  @moduledoc """
  The stack panel and the inspector (spec/14 §18.8-§18.10, spec/10 §15, D-87).

  Both panels are rendered alone over `Visualize.BuilderFixture`'s layers and held to
  `test/support/builder/<name>.html`; the reorder, move, disable and inspect events are
  driven through the component's `handle_event/3`.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Visualize.BuilderFixture
  alias Visualize.Chart
  alias Visualize.Chart.Builder
  alias Visualize.Chart.Builder.Layers

  doctest Layers

  for name <- ~w(layers layers_disabled inspector inspector_overrides)a do
    test "#{name} renders as recorded" do
      c = Keyword.fetch!(BuilderFixture.cases(), unquote(name))
      assert BuilderFixture.golden(unquote(name)) == BuilderFixture.render_case(c)
    end
  end

  describe "the stack panel (spec/14 §18.8)" do
    test "the layers are in the order stack/1 reads them, the higher last" do
      html = rendered(:layers)

      names =
        ~r|<span class="vis-builder-layer-name">(\w+)</span>|
        |> Regex.scan(html)
        |> Enum.map(fn [_, name] -> name end)

      assert names == ~w(house shared panel)
    end

    test "a layer with no name is its position, as seed/1 and explain/1 name it" do
      {uses, labels} = Visualize.Chart.Builder.Stack.seed([%{version: 1}, %{theme: :dark}])

      rows =
        for {use, row} <- Enum.zip(uses, BuilderFixture.rows()),
            do: %{row | name: Visualize.Chart.Builder.Stack.label(labels, use)}

      html = render_component(&Layers.panel/1, %{id: "l", rows: rows})

      assert html =~ ~s(<span class="vis-builder-layer-name">0</span>)
      assert html =~ ~s(<span class="vis-builder-layer-name">1</span>)
    end

    test "the selected layer and the disabled ones are marked, and a disabled one offers to enable" do
      html = rendered(:layers_disabled)

      assert html =~
               ~s(class="vis-builder-layer vis-builder-layer-disabled" style="--vis-builder-depth: 0" data-builder-layer="0")

      assert html =~
               ~s(class="vis-builder-layer vis-builder-layer-selected" style="--vis-builder-depth: 0" data-builder-layer="2")

      # The toggle is an eye (spec/14 §18.8): struck for a disabled layer, open otherwise;
      # the word stays the button's text.
      assert html =~
               ~s(phx-value-index="0"><svg class="vis-builder-icon vis-builder-icon-eye_off")

      assert html =~ ~s(<span class="vis-builder-action-label">Enable</span>)

      assert html =~
               ~s(phx-value-index="2"><svg class="vis-builder-icon vis-builder-icon-eye")

      assert html =~ ~s(<span class="vis-builder-action-label">Disable</span>)
      # The fixture's layers are the host's, inline: no lock on any of them.
      refute html =~ "vis-builder-layer-lock"
    end

    test "the list is the hook element and every layer is draggable at its position" do
      html = rendered(:layers)

      assert html =~
               ~s(<ol id="b-layers" class="vis-builder-layers" phx-hook="BuilderHook" data-builder-stack="true">)

      assert length(Regex.scan(~r/draggable="true"/, html)) == 3

      targeted =
        render_component(&Layers.panel/1, %{
          id: "l",
          rows: BuilderFixture.rows(),
          target: "c1"
        })

      assert targeted =~ ~s(data-builder-target="c1")
    end
  end

  describe "the inspector (spec/14 §18.9)" do
    test "one row per entry of explain/1, in its order, with the value inspected" do
      html = rendered(:inspector)
      entries = Chart.explain(BuilderFixture.layers())

      assert length(Regex.scan(~r/class="vis-builder-entry"/, html)) == length(entries)
      assert html =~ ~s(<td class="vis-builder-entry-path">frame.axes[0].scale</td>)
      assert html =~ ~s(<td class="vis-builder-entry-value">:x</td>)
      assert html =~ ~s(<td class="vis-builder-entry-layer">shared</td>)
    end

    test "a row carries its path and the position of the layer that set it" do
      html = rendered(:inspector)
      assert html =~ ~s(data-builder-path="marks[0].channels.x" data-builder-layer="2")
      assert html =~ ~s(data-builder-path="theme" data-builder-layer="0")
    end

    test "overrode names the overridden layers, lowest first, and is empty where none are" do
      html = rendered(:inspector_overrides)
      assert html =~ ~s(<td class="vis-builder-entry-overrode">house</td>)
      assert html =~ ~s(<td class="vis-builder-entry-overrode"></td>)
    end
  end

  describe "seeding (spec/14 §18.2, #272)" do
    test "a nil layer is refused with its name, bare or named" do
      assert_raise ArgumentError, ~r/layer "Uptime::house" is nil/, fn ->
        Visualize.Chart.Builder.Stack.seed([{"Uptime::house", nil}])
      end

      assert_raise ArgumentError, ~r/layer "1" is nil/, fn ->
        Visualize.Chart.Builder.Stack.seed([%{frame: %{}}, nil])
      end
    end
  end

  describe "the events (spec/14 §18.8, §18.10)" do
    test "selecting a layer opens its root node" do
      socket = BuilderFixture.socket(BuilderFixture.layers(), node_label: "frame.margin")
      {:noreply, chosen} = Builder.handle_event("select_layer", %{"index" => "2"}, socket)
      {:noreply, absent} = Builder.handle_event("select_layer", %{"index" => "9"}, socket)

      assert BuilderFixture.selected(chosen) == 2
      assert chosen.assigns.node_label == "design"
      assert BuilderFixture.selected(absent) == 0
    end

    test "disabling drops the layer from the design and keeps it in the list" do
      socket = BuilderFixture.socket(BuilderFixture.layers())
      {:noreply, off} = Builder.handle_event("toggle_layer", %{"index" => "0"}, socket)
      {:noreply, on} = Builder.handle_event("toggle_layer", %{"index" => "0"}, off)

      assert BuilderFixture.layers(off) == BuilderFixture.layers()
      assert BuilderFixture.disabled(off) == MapSet.new([0])
      # Flatten writes the version a deployed design carries (§19.8); the house wrote it before.
      assert BuilderFixture.design(off) ==
               Map.put(Chart.stack(Enum.drop(BuilderFixture.layers(), 1)), :version, 1)

      assert BuilderFixture.disabled(on) == MapSet.new()
    end

    test "a move changes precedence, and the selection and the disabled set follow their layers" do
      socket =
        BuilderFixture.socket(BuilderFixture.layers(), selected: 2, disabled: MapSet.new([0]))

      {:noreply, moved} =
        Builder.handle_event("reorder", %{"from" => 2, "to" => 0}, socket)

      [house, shared, panel] = BuilderFixture.layers()
      assert BuilderFixture.layers(moved) == [panel, house, shared]
      assert BuilderFixture.selected(moved) == 0
      assert BuilderFixture.disabled(moved) == MapSet.new([1])
    end

    test "a move off either end changes nothing" do
      socket = BuilderFixture.socket(BuilderFixture.layers())
      {:noreply, up} = Builder.handle_event("reorder", %{"from" => 0, "to" => -1}, socket)

      {:noreply, down} =
        Builder.handle_event("reorder", %{"from" => 2, "to" => 3}, socket)

      {:noreply, same} =
        Builder.handle_event("reorder", %{"from" => 1, "to" => 1}, socket)

      for unchanged <- [up, down, same] do
        assert BuilderFixture.layers(unchanged) == BuilderFixture.layers()
      end
    end

    test "the hook's reorder is the same move, with the integers it pushes" do
      socket = BuilderFixture.socket(BuilderFixture.layers())
      {:noreply, dropped} = Builder.handle_event("reorder", %{"from" => 0, "to" => 2}, socket)

      [house, shared, panel] = BuilderFixture.layers()
      assert BuilderFixture.layers(dropped) == [shared, panel, house]
    end

    test "inspecting selects the layer and opens the deepest node that owns the path" do
      socket = BuilderFixture.socket(BuilderFixture.layers())

      {:noreply, deep} =
        Builder.handle_event(
          "inspect",
          %{"path" => "marks[0].channels.x", "layer" => "2"},
          socket
        )

      {:noreply, shallow} =
        Builder.handle_event("inspect", %{"path" => "theme", "layer" => "0"}, socket)

      assert BuilderFixture.selected(deep) == 2
      assert deep.assigns.node_label == "marks[0].channels"
      assert BuilderFixture.selected(shallow) == 0
      assert shallow.assigns.node_label == "design"
    end

    test "both panels are rendered by the component, targeted at it" do
      html = BuilderFixture.render_case(Keyword.fetch!(BuilderFixture.cases(), :builder))
      assert html =~ ~s(<ol id="builder-layers" class="vis-builder-layers" phx-hook="BuilderHook")
      assert html =~ ~s(<table id="builder-inspector" class="vis-builder-inspector")
      # The layers, the inspector, the editor's form, the node strip, the context's edge
      # and the graph (spec/14 §18.16): every hook instance is targeted at the component
      # (the variables panel and the pool list when theirs are open).
      assert length(Regex.scan(~r/data-builder-target="-1"/, html)) == 6
    end
  end

  defp rendered(name),
    do: BuilderFixture.render_case(Keyword.fetch!(BuilderFixture.cases(), name))
end
