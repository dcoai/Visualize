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

    # Where a chart shows a frame is the chart's (#616, D-165): a linked owner takes the box
    # into its own local, and refuses everything else as before.
    test "a frame the library owns takes its box into the site's own local" do
      s = BuilderFixture.socket(BuilderFixture.layers(), store: BuilderFixture.Library)
      {:noreply, s} = Builder.handle_event("insert", %{"name" => "composite:1", "at" => 3}, s)
      s = at_frame(s, :main)

      {:noreply, s} =
        Builder.handle_event("frame_box", %{"frame" => "main", "box" => [0, 0, 0.5, 1]}, s)

      assert s.assigns.notice == nil

      assert [%{frames: %{main: %{box: [0, 0, 0.5, 1]}}}] =
               for(%{ref: {:composite, 1}, local: local} <- s.assigns.uses, do: local)

      assert Writes.composed(s).frames.main.box == [0, 0, 0.5, 1]
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

  # A library holding one frame: a polar inset, its own margin.
  defmodule FrameLibrary do
    @moduledoc false
    @behaviour Visualize.Chart.Builder.Store

    @inset {:frame, 1}

    @impl true
    def list(_context), do: [%{id: @inset, name: "inset", kind: :frame}]

    @impl true
    def get(@inset, _context) do
      {:ok,
       %{
         id: @inset,
         name: "inset",
         kind: :frame,
         fragment: %{frames: %{main: %{kind: :polar, margin: %{top: 4}}}}
       }}
    end

    def get(_id, _context), do: :error

    @impl true
    def put(%{id: id}, _context), do: {:ok, id || {:frame, 2}}

    @impl true
    def delete(_id, _context), do: :ok

    @impl true
    def import(bundle, context),
      do: Visualize.Chart.Builder.Store.relocate(bundle, context, &put/2)
  end

  describe "new frames and the frames root (spec/14 §18.16, #616)" do
    defp sized(layers, opts \\ []) do
      s = BuilderFixture.socket(layers, opts)
      {:noreply, s} = Builder.handle_event("graph_size", %{"width" => 800, "height" => 400}, s)
      s
    end

    test "a frame dropped from the palette is a new frame, a quarter of the graph at the point" do
      {:noreply, s} =
        Builder.handle_event(
          "place",
          %{"component" => "frame", "x" => 700, "y" => 100},
          sized(BuilderFixture.layers())
        )

      design = Writes.composed(s)
      assert design.frames.frame_2 == %{kind: :cartesian, box: [0.5, 0, 0.5, 0.5]}
      assert s.assigns.node_label == "frames.frame_2"

      assert [%{frames: %{frame_2: _}}] =
               for(%{ref: nil, local: %{frames: %{frame_2: _}} = l} <- s.assigns.uses, do: l)

      # The one frame's mark and label now say it, so the design of two stays valid.
      assert Enum.map(design.marks, & &1.frame) == [:main]
      assert Enum.map(design.labels, & &1.frame) == [:main]
      assert {:ok, _} = Visualize.Chart.from_map(design)
    end

    test "+ frame, and the keyboard twin, place one at the centre under a fresh name" do
      s = sized(BuilderFixture.layers())
      {:noreply, s} = Builder.handle_event("add_frame", %{}, s)

      {:noreply, s} =
        Builder.handle_event("component_key", %{"key" => "Insert", "component" => "frame"}, s)

      frames = Writes.composed(s).frames
      assert frames.frame_2.box == [0.25, 0.25, 0.5, 0.5]
      assert frames.frame_3.box == [0.25, 0.25, 0.5, 0.5]
    end

    test "a library frame lands linked under a fresh key, its placement its own" do
      s = sized(BuilderFixture.layers(), store: FrameLibrary)

      {:noreply, s} =
        Builder.handle_event("place", %{"name" => "frame:1", "x" => 10, "y" => 390}, s)

      design = Writes.composed(s)
      assert %{kind: :polar, margin: %{top: 4}, box: [0, 0.5, 0.5, 0.5]} = design.frames.frame_2

      [use] = for %{ref: {:frame, 1}} = use <- s.assigns.uses, do: use
      assert use.key == :frame_2
      assert use.local == %{frames: %{main: %{box: [0, 0.5, 0.5, 0.5]}}}
      assert Visualize.Chart.Builder.Stack.linkage(use) == :edited

      # Dragged, it is written into the site's own local — not refused (D-165).
      {:noreply, s} =
        Builder.handle_event(
          "frame_box",
          %{"frame" => "frame_2", "box" => [0.5, 0.5, 0.5, 0.5]},
          s
        )

      assert s.assigns.notice == nil
      assert Writes.composed(s).frames.frame_2.box == [0.5, 0.5, 0.5, 0.5]

      # Anything else of it is still the library's.
      {:noreply, refused} =
        Builder.handle_event("pick", %{"node" => "frames.frame_2"}, s)

      {:noreply, refused} =
        Builder.handle_event(
          "edit",
          %{"_node" => "frames.frame_2", "kind" => "geo", "_target" => ["kind"]},
          refused
        )

      assert Writes.composed(refused).frames.frame_2.kind == :polar
    end

    test "the frames root: each frame's select bar, axes over its scales, and what it draws" do
      s = sized(two())
      {:noreply, s} = Builder.handle_event("select_root", %{"root" => "frames"}, s)
      {:noreply, s} = Builder.handle_event("pick", %{"node" => "frames.now"}, s)
      html = BuilderFixture.render(s)

      assert html =~ "+ frame"

      assert html =~
               ~s(phx-value-node="frames.history" phx-target="-1">select — place it on the graph)

      assert html =~ "selected — drag it on the graph"

      assert html =~ ~s(phx-value-node="marks[0]" phx-target="-1">line mark · marks[0])
      assert html =~ ~s(phx-value-node="marks[1]" phx-target="-1">line mark · marks[1])

      # Each frame's axes rows are its own.
      assert html =~ ~s(phx-value-frame="history")
      assert html =~ ~s(phx-value-frame="now")
    end
  end

  describe "layout sugar: frames on the grid (spec/14 §18.15, §18.16, #617)" do
    defp gridded, do: BuilderFixture.gridded_frames()

    defp opened_on_grid(frame) do
      s = BuilderFixture.socket(gridded())
      {:noreply, s} = Builder.handle_event("graph_size", %{"width" => 900, "height" => 400}, s)
      {:noreply, s} = Builder.handle_event("pick", %{"node" => "frames.#{frame}"}, s)
      s
    end

    test "the place section offers the grid's cells and the spans that fit" do
      [html] =
        Regex.run(
          ~r/<form id="[^"]*frames-now-grid".*?<\/form>/s,
          BuilderFixture.render(opened_on_grid(:now))
        )

      assert html =~ ~s(<option value="2,0" selected>column 2, row 0</option>)
      assert html =~ ~s(<option value="0,1">column 0, row 1</option>)
      # From column 2 of three, a span one column wide, one or two rows high.
      assert html =~ ~s(<option value="1,1" selected>1 × 1</option>)
      assert html =~ ~s(<option value="1,2">1 × 2</option>)
      refute html =~ ~s(<option value="2,1">2 × 1</option>)
    end

    test "the overlay carries the frame's cell and the grid, and draws the cells" do
      html = BuilderFixture.render(opened_on_grid(:now))
      assert html =~ ~s(data-builder-frame-cell="2 0 1 1")
      assert html =~ ~s(data-builder-grid="0 0.3333,0.3333 0.3333,0.6667 0.3333;0 0.5,0.5 0.5")
      assert length(Regex.scan(~r/class="vis-builder-grid-cell"/, html)) == 6
    end

    test "frame_cell writes the cell and span, keeps the span on the grid, and refuses a cell off it" do
      s = opened_on_grid(:now)

      {:noreply, s} =
        Builder.handle_event(
          "frame_cell",
          %{"frame" => "now", "cell" => "2,1", "span" => "1,1"},
          s
        )

      assert %{cell: [2, 1]} = now = Writes.composed(s).frames.now
      refute Map.has_key?(now, :span)

      # A span past the edge is kept to what fits.
      {:noreply, s} =
        Builder.handle_event(
          "frame_cell",
          %{"frame" => "now", "cell" => [1, 0], "span" => [3, 2]},
          s
        )

      assert %{cell: [1, 0], span: [2, 2]} = Writes.composed(s).frames.now

      {:noreply, refused} =
        Builder.handle_event("frame_cell", %{"frame" => "now", "cell" => "3,0"}, s)

      assert refused.assigns.uses == s.assigns.uses
      assert refused.assigns.notice == "cell 3, 0 is not on the layout's grid"
    end

    test "a cell chosen for a frame placed by its box replaces the box" do
      [{name, layer}] = gridded()

      layer =
        update_in(
          layer,
          [:frames, :now],
          &(&1 |> Map.delete(:cell) |> Map.put(:box, [0.7, 0, 0.3, 0.5]))
        )

      s = BuilderFixture.socket([{name, layer}])
      {:noreply, s} = Builder.handle_event("frame_cell", %{"frame" => "now", "cell" => "2,1"}, s)
      now = Writes.composed(s).frames.now
      assert now.cell == [2, 1]
      refute Map.has_key?(now, :box)
    end
  end
end
