defmodule Visualize.Chart.BuilderFramesTest do
  @moduledoc """
  Frames in the builder (spec/14 §18.4, §18.16, #386): the graph is the box the design is
  drawn at, every frame of it, and a point on the graph is read in the frame under it.
  """
  use ExUnit.Case, async: true

  alias Visualize.BuilderFixture
  alias Visualize.Chart.Builder
  alias Visualize.Chart.Builder.Writes

  defp two, do: BuilderFixture.two_frames()

  defp svg(html) do
    [tag] = Regex.run(~r/<svg class="vis-builder-chart"[^>]*>/, html)
    tag
  end

  describe "the graph is the box (spec/14 §18.4, #613)" do
    test "a design of two frames, neither called main, draws both" do
      html = BuilderFixture.render(BuilderFixture.socket(two()))

      assert html =~ ~s(data-node="frames.history")
      assert html =~ ~s(data-node="frames.now")

      assert svg(html) =~
               ~s(data-builder-frames="history 0 0 300 400 20 20 30 40;now 300 0 300 400 20 20 30 40")
    end

    test "the chart sits in a box that hosts ResizeHook and reports to the builder" do
      html = BuilderFixture.render(BuilderFixture.socket(two()))

      assert html =~
               ~s(<div id="b-box" class="vis-builder-box" phx-hook="ResizeHook" data-resize-event="graph_size" data-resize-target="-1">)

      # Before a measurement, the render's default size.
      assert svg(html) =~ ~s(width="600" height="400")
      assert svg(html) =~ ~s(viewBox="0 0 600 400")
    end

    test "graph_size redraws at the measured size with the same fractions" do
      s = BuilderFixture.socket(two())

      {:noreply, s} =
        Builder.handle_event("graph_size", %{"width" => 1000, "height" => 500}, s)

      assert s.assigns.graph_size == {1000, 500}
      tag = svg(BuilderFixture.render(s))
      assert tag =~ ~s(viewBox="0 0 1000 500")

      assert tag =~
               ~s(data-builder-frames="history 0 0 500 500 20 20 30 40;now 500 0 500 500 20 20 30 40")
    end

    test "a size too small to draw in keeps the last one" do
      s = BuilderFixture.socket(two())
      {:noreply, s} = Builder.handle_event("graph_size", %{"width" => 900, "height" => 450}, s)
      {:noreply, s} = Builder.handle_event("graph_size", %{"width" => 0, "height" => 0}, s)
      assert s.assigns.graph_size == {900, 450}
    end

    test "a drop is read in the frame under the pointer, at the measured size" do
      s = BuilderFixture.socket(two())
      {:noreply, s} = Builder.handle_event("graph_size", %{"width" => 800, "height" => 400}, s)

      # x 410 is 10 px into `now`, inside its own left margin: the left band, so a y axis.
      # Read as one frame over the whole graph it would have been the plot, a bottom axis.
      {:noreply, s} =
        Builder.handle_event("place", %{"component" => "axis", "x" => 410, "y" => 200}, s)

      # In a design of two frames the axis is written into `now` itself (#615).
      assert Writes.composed(s).frames.now.axes == [%{scale: :y, side: :left}]
    end
  end

  describe "frames are placed on the graph (spec/14 §18.16, #614)" do
    defp at_frame(s, name) do
      {:noreply, s} = Builder.handle_event("graph_size", %{"width" => 800, "height" => 400}, s)
      {:noreply, s} = Builder.handle_event("pick", %{"node" => "frames.#{name}"}, s)
      s
    end

    defp boxes(s), do: for(%{local: %{frames: frames}} <- s.assigns.uses, do: frames)

    test "the open frame is outlined with four corner handles, and nothing else is" do
      html = BuilderFixture.render(at_frame(BuilderFixture.socket(two()), :now))

      assert html =~
               ~s(<g class="vis-builder-frame-overlay" data-builder-frame-box="now"><rect class="vis-builder-frame-outline" x="400" y="0" width="400" height="400">)

      # Each handle centred on its corner, kept on the chart at its edges.
      for {at, x, y} <- [{"nw", 395, 0}, {"ne", 790, 0}, {"sw", 395, 390}, {"se", 790, 390}] do
        assert html =~ ~s(data-builder-frame-handle="#{at}" x="#{x}" y="#{y}" width="10")
      end

      {:noreply, s} =
        Builder.handle_event(
          "pick",
          %{"node" => "marks[0]"},
          at_frame(BuilderFixture.socket(two()), :now)
        )

      refute BuilderFixture.render(s) =~ "vis-builder-frame-overlay"
    end

    test "frame_box writes the box as fractions in the frame's owner, the frame left open" do
      s = at_frame(BuilderFixture.socket(two()), :now)

      {:noreply, s} =
        Builder.handle_event(
          "frame_box",
          %{"frame" => "now", "box" => [0.5, 0.0, 0.5, 0.49999]},
          s
        )

      assert [%{now: %{box: [0.5, 0, 0.5, 0.5]}}] = boxes(s)
      assert s.assigns.node_label == "frames.now"

      assert BuilderFixture.render(s) =~
               ~s(data-builder-frames="history 0 0 400 400 20 20 30 40;now 400 0 400 200 20 20 30 40")
    end

    test "a box out of range is kept inside the whole and at least a twentieth on a side" do
      s = at_frame(BuilderFixture.socket(two()), :now)

      {:noreply, s} =
        Builder.handle_event("frame_box", %{"frame" => "now", "box" => [0.9, -0.2, 0.5, 0.01]}, s)

      assert [%{now: %{box: [0.5, 0, 0.5, 0.05]}}] = boxes(s)
    end

    test "a name that is no frame, or a box that does not read, changes nothing" do
      s = at_frame(BuilderFixture.socket(two()), :now)

      {:noreply, same} =
        Builder.handle_event("frame_box", %{"frame" => "nope", "box" => [0, 0, 1, 1]}, s)

      assert same.assigns.uses == s.assigns.uses

      {:noreply, same} =
        Builder.handle_event("frame_box", %{"frame" => "now", "box" => [0, 0, "x", 1]}, s)

      assert same.assigns.uses == s.assigns.uses
    end

    test "a box replaces a frame's cell and span" do
      [{name, layer}] = two()

      layer =
        layer
        |> Map.put(:layout, %{columns: [1, 1]})
        |> update_in(
          [:frames, :now],
          &(&1 |> Map.delete(:box) |> Map.merge(%{cell: [1, 0], span: [1, 1]}))
        )

      s = at_frame(BuilderFixture.socket([{name, layer}]), :now)

      {:noreply, s} =
        Builder.handle_event("frame_box", %{"frame" => "now", "box" => [0.25, 0, 0.5, 1]}, s)

      assert [now] = for(frames <- boxes(s), do: frames.now)
      assert now.box == [0.25, 0, 0.5, 1]
      refute Map.has_key?(now, :cell) or Map.has_key?(now, :span)
    end

    test "a frame the library owns refuses the write with its notice" do
      s = BuilderFixture.socket(BuilderFixture.layers(), store: BuilderFixture.Library)
      {:noreply, s} = Builder.handle_event("insert", %{"name" => "composite:1", "at" => 3}, s)
      s = at_frame(s, :main)

      {:noreply, refused} =
        Builder.handle_event("frame_box", %{"frame" => "main", "box" => [0, 0, 0.5, 1]}, s)

      assert refused.assigns.uses == s.assigns.uses
      assert refused.assigns.notice =~ "is from the library — open it to edit"
    end

    test "the frame's page has a place section: its box read, z and background its fields" do
      html = BuilderFixture.render(at_frame(BuilderFixture.socket(two()), :now))

      assert html =~
               "box x 0.5 · y 0 · w 0.5 · h 1 — drag the frame on the graph to move it, its corners to resize it; arrows nudge it"

      assert html =~ ~s(phx-value-section="frames.now:place")
      assert html =~ ~s(name="z")
      assert html =~ ~s(data-builder-well="background")
    end
  end

  describe "a node placed on the graph goes to the frame under the pointer (spec/14 §18.16, #615)" do
    defp measured(layers) do
      s = BuilderFixture.socket(layers)
      {:noreply, s} = Builder.handle_event("graph_size", %{"width" => 800, "height" => 400}, s)
      s
    end

    defp place(s, component, x, y) do
      {:noreply, s} =
        Builder.handle_event("place", %{"component" => component, "x" => x, "y" => y}, s)

      s
    end

    defp sites(s, kind), do: for(%{local: %{^kind => body}} <- s.assigns.uses, do: body)

    # `now` with no scales of its own, its source typed, so a placed mark derives them.
    defp bare_now do
      [{name, layer}] = two()

      layer =
        layer
        |> update_in([:frames, :now], &Map.delete(&1, :scales))
        |> put_in([:sources, :primary, :types], %{t: :number, v: :number})

      [{name, layer}]
    end

    test "a mark or a label dropped over the second frame says that frame" do
      s = measured(two()) |> place("mark:line", 600, 200) |> place("title", 600, 5)
      assert [%{type: :line, frame: :now}] = sites(s, :mark)
      assert [%{anchor: :title, frame: :now}] = sites(s, :label)

      s = measured(two()) |> place("label", 100, 200)
      assert [%{frame: :history}] = sites(s, :label)
    end

    test "an axis dropped in a frame's margin is that frame's, its scale declared there" do
      s = measured(bare_now()) |> place("axis", 410, 200)
      design = Writes.composed(s)
      assert design.frames.now.axes == [%{scale: :y, side: :left}]
      assert design.frames.now.scales == %{y: %{kind: :linear, domain: :auto}}
      # `history` is untouched, and nothing landed in a frame called main.
      assert design.frames.history.axes == [%{scale: :x, side: :bottom}]
      refute Map.has_key?(design.frames, :main)
      assert s.assigns.node_label == "frames.now.axes[0]"
    end

    test "a legend dropped in a frame takes that frame's colour scale" do
      [{name, layer}] = two()
      layer = put_in(layer, [:frames, :now, :scales, :c], %{kind: :ordinal, domain: ["a"]})
      s = measured([{name, layer}]) |> place("legend", 790, 20)
      assert %{scale: :c} = Writes.composed(s).frames.now.legend
      refute Map.has_key?(Writes.composed(s).frames.history, :legend)
    end

    test "a mark placed in a frame derives that frame's scales from its channels" do
      s = measured(bare_now()) |> place("mark:line", 600, 200)
      design = Writes.composed(s)
      assert %{x: %{kind: :linear}, y: %{kind: :linear}} = design.frames.now.scales
      assert Map.keys(design.frames.history.scales) == [:x, :y]
    end

    test "the keyboard twin places in the open node's frame" do
      s = measured(two())
      {:noreply, s} = Builder.handle_event("pick", %{"node" => "marks[1]"}, s)

      {:noreply, s} =
        Builder.handle_event("component_key", %{"key" => "Insert", "component" => "mark:area"}, s)

      assert [%{type: :area, frame: :now}] = sites(s, :mark)
    end

    test "a mark's axes section is its frame's, and a tick writes there" do
      s = measured(two())
      {:noreply, s} = Builder.handle_event("pick", %{"node" => "marks[1]"}, s)
      html = BuilderFixture.render(s)
      assert html =~ ~s(phx-value-frame="now")
      refute html =~ ~s(phx-value-frame="history")

      {:noreply, s} =
        Builder.handle_event(
          "toggle_axis",
          %{"scale" => "y", "side" => "left", "frame" => "now"},
          s
        )

      assert Writes.composed(s).frames.now.axes == [%{scale: :y, side: :left}]
      assert Writes.composed(s).frames.history.axes == [%{scale: :x, side: :bottom}]

      # Unticked again, it leaves `now`; the grid of `history`'s x is its own.
      {:noreply, s} =
        Builder.handle_event(
          "toggle_axis",
          %{"scale" => "y", "side" => "left", "frame" => "now"},
          s
        )

      refute Map.has_key?(Writes.composed(s).frames.now, :axes)

      {:noreply, s} =
        Builder.handle_event("toggle_grid", %{"scale" => "x", "frame" => "history"}, s)

      assert [%{grid: true}] = Writes.composed(s).frames.history.axes
    end

    test "the add-axes step names the frame the mark is drawn in" do
      [{name, layer}] = two()
      layer = update_in(layer, [:frames, :history], &Map.delete(&1, :axes))
      design = Visualize.Chart.stack([{name, layer}])
      [step] = Visualize.Chart.Builder.Steps.steps(design)
      assert step.path == [:frames, :history, :axes]
    end
  end
end
