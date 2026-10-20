defmodule ExamplesWeb.ChartFormatsTest do
  @moduledoc """
  Every chart page's **Stored forms** (spec/14 §9, §11, §12.6, #781, work item #820): the
  chart's JSON read back equal, a style as a fragment read back equal, and the chart's own
  document refused — newer, and holding a misspelled and a retired tag — at its path.
  """
  use ExUnit.Case, async: true

  alias ExamplesWeb.ChartLive
  alias ExamplesWeb.ChartPanels.Formats
  alias Phoenix.LiveView.Socket

  defp html(s) do
    ChartLive.render(Map.put(s.assigns, :__changed__, %{}))
    |> Phoenix.LiveViewTest.rendered_to_string()
  end

  # One test a chart (spec/12 §6, #735).
  describe "every gallery chart's design and first style round-trip through JSON" do
    for {module, slug} <- Examples.Gallery.charts() do
      @module module
      test slug do
        forms = Formats.forms(@module)
        assert forms.round_trip, "the chart's JSON does not read back equal"
        assert forms.fragment == nil or forms.fragment.round_trip, "its style fragment"
        assert [{_, _, [newer]} | _] = forms.refused
        assert newer =~ "needs schema v99"
      end
    end
  end

  test "a chart's document with a misspelled and a retired tag is refused at the mark's style" do
    %{refused: [_newer, {_title, _change, faults}]} = Formats.forms(Examples.Charts.BarChart)
    assert Enum.any?(faults, &(&1 =~ ~s(marks[0].style[0]: "$feild" is not a tag)))
    assert Enum.any?(faults, &(&1 =~ ~s(marks[0].style[1]: "$styles" was removed)))
  end

  test "the panel opens on a chart page and shows the forms" do
    {:ok, s} = ChartLive.mount(%{"chart" => "bar"}, %{}, %Socket{})
    closed = html(s)
    assert closed =~ ~s(id="chart-panel-formats-bar")
    refute closed =~ "formats-body"

    params = %{"panel" => "formats", "action" => "open"}
    {:noreply, s} = ChartLive.handle_event("chart_panel", params, s)
    open = html(s)
    assert open =~ "formats-body"
    assert open =~ "equal to the chart"
    assert open =~ "needs schema v99"

    {:noreply, s} = ChartLive.handle_event("chart_panel", %{params | "action" => "close"}, s)
    refute html(s) =~ "formats-body"
  end
end
