defmodule ExamplesWeb.ChartLiveAccessTest do
  @moduledoc """
  The chart page is accessible (spec/14 §21, #557, #558): on SVG the chart's own root
  names it; on a canvas the wrapper of the layers is the named image and every SVG layer
  is hidden; on both the chart is one keyboard stop carrying its points, the hidden data
  table follows it, and the summary is shown under it.
  """
  use ExUnit.Case, async: true

  alias ExamplesWeb.ChartLive

  defp html(slug, backend) do
    {:ok, s} = ChartLive.mount(%{"chart" => slug}, %{}, %Phoenix.LiveView.Socket{})
    {:noreply, s} = ChartLive.handle_event("set_backend", %{"backend" => to_string(backend)}, s)

    ChartLive.render(Map.put(s.assigns, :__changed__, %{}))
    |> Phoenix.LiveViewTest.rendered_to_string()
    |> String.replace(~r/data-binary="[^"]*"/, ~s(data-binary=""))
  end

  test "on SVG: one keyboard stop with the points, the root named, the table and the summary" do
    page = html("line", :svg)

    assert page =~
             ~r/<div id="chart-keys" phx-hook="KeyboardHook"[^>]* data-keyboard-name="Line Chart"/

    assert page =~ ~s(data-keyboard-points="[{&quot;name&quot;:&quot;y&quot;)

    assert page =~
             ~r/<svg aria-describedby="vis-[a-z0-9]+-desc" aria-label="Line Chart"/

    assert page =~ ~s(<div class="vis-data-table" id="chart-data" style="position:absolute;)
    assert page =~ "<strong>Text alternative:</strong> Line chart, 1 series (y) of 51 points."
  end

  test "on a canvas: the wrapper is the named image, described by the summary, and the layers are hidden" do
    page = html("line", :canvas)

    assert page =~
             ~r/class="hybrid-wrapper" style="[^"]*" role="img" aria-label="Line Chart" aria-describedby="chart-access-summary"/

    assert page =~ ~s{<p id="chart-access-summary" hidden>Line chart, 1 series (y) of 51 points.}
    assert page =~ ~s(<svg aria-hidden="true")
    assert page =~ ~s(phx-hook="KeyboardHook")
  end

  test "the resize hook's reduced_motion compiles the chart to step, and its change alone redraws it" do
    {:ok, s} = ChartLive.mount(%{"chart" => "line"}, %{}, %Phoenix.LiveView.Socket{})
    {:noreply, s} = ChartLive.handle_event("set_backend", %{"backend" => "canvas"}, s)
    assert [{_name, %{motion: :full}}] = s.assigns.still_state.compiled

    resize = %{"width" => 600, "height" => 0, "reduced_motion" => true}
    {:noreply, s} = ChartLive.handle_event("resize", resize, s)
    assert s.assigns.motion == :reduce
    assert [{_name, %{motion: :reduce}}] = s.assigns.still_state.compiled

    # The same width with the preference turned off: drawn again, easing.
    {:noreply, s} = ChartLive.handle_event("resize", %{resize | "reduced_motion" => false}, s)
    assert s.assigns.motion == :full
    assert [{_name, %{motion: :full}}] = s.assigns.still_state.compiled
  end
end
