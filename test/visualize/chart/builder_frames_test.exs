defmodule Visualize.Chart.BuilderFramesTest do
  @moduledoc """
  Frames in the builder (spec/14 §18.4, §18.16, #386): the graph is the box the design is
  drawn at, every frame of it, and a point on the graph is read in the frame under it.
  """
  use ExUnit.Case, async: true

  alias Visualize.BuilderFixture
  alias Visualize.Chart.Builder

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

      axes =
        for %{local: %{axis: body}} <- s.assigns.uses, do: body

      assert axes == [%{scale: :y, side: :left}]
    end
  end
end
