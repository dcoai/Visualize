defmodule ExamplesWeb.ChartPanelsTest do
  @moduledoc """
  A chart page's own panels (spec/14 §12.6, #705): a module names them with `panels/0`, and
  the Colors chart's **Automatic dark mode** draws its design under the implicit theme
  beside `color_scheme: false`, with a switch that previews the viewer's scheme.
  """
  use ExUnit.Case, async: true

  alias Examples.Charts.{BarChart, ColorsChart, CompositionChart, Design}
  alias ExamplesWeb.ChartLive
  alias ExamplesWeb.ChartPanels
  alias ExamplesWeb.ChartPanels.DarkMode
  alias Phoenix.LiveView.Socket

  @rule "@media (prefers-color-scheme: dark)"

  defp mounted(slug) do
    {:ok, s} = ChartLive.mount(%{"chart" => slug}, %{}, %Socket{})
    s
  end

  defp html(s) do
    ChartLive.render(Map.put(s.assigns, :__changed__, %{}))
    |> Phoenix.LiveViewTest.rendered_to_string()
  end

  defp root_id(svg), do: Regex.run(~r/^<svg[^>]* id="([^"]+)"/, svg, capture: :all_but_first)

  # The implicit drawing as the page shows it: the first figure of the panel.
  defp shown(html) do
    [_, figure | _] = String.split(html, ~s(class="scheme-view scheme-))
    figure
  end

  test "a module names its panels; one that names none has none" do
    assert ChartPanels.of(ColorsChart) == [:dark_mode]
    assert ChartPanels.of(BarChart) == []

    assert html(mounted("colors")) =~ ~s(id="chart-panel-dark_mode-colors")
    refute html(mounted("bar")) =~ "chart-panel-"
  end

  test "the implicit drawing carries the dark-mode rule, color_scheme: false none" do
    %{implicit: implicit, fixed: fixed} = DarkMode.drawings(ColorsChart)

    assert implicit =~ @rule
    refute fixed =~ "prefers-color-scheme"

    # Three roots on one page, the chart above among them, and no two share an id: the
    # rule is scoped to its root's id.
    main = Design.render(ColorsChart, [])
    ids = Enum.map([implicit, fixed, main], &root_id/1)
    assert length(Enum.uniq(ids)) == 3
    [[implicit_id] | _] = ids
    assert implicit =~ "#" <> implicit_id <> " {"
  end

  test "the page's switch previews a scheme by the rule's own media condition" do
    s = mounted("colors")
    page = html(s)
    assert shown(page) =~ ~s(data-scheme="system")
    assert shown(page) =~ @rule

    for word <- ~w(system light dark) do
      assert page =~ ~s(phx-value-scheme="#{word}")
    end

    for {word, condition} <- [{"dark", "@media all"}, {"light", "@media not all"}] do
      {:noreply, s} =
        ChartLive.handle_event("chart_panel", %{"panel" => "dark_mode", "scheme" => word}, s)

      figure = shown(html(s))
      assert figure =~ ~s(data-scheme="#{word}")
      assert figure =~ condition
      refute figure =~ @rule
    end

    # A word that is no scheme, or a panel the chart lacks, changes nothing.
    for params <- [
          %{"panel" => "dark_mode", "scheme" => "sepia"},
          %{"panel" => "nope", "scheme" => "dark"}
        ] do
      {:noreply, same} = ChartLive.handle_event("chart_panel", params, s)
      assert same.assigns.panels == s.assigns.panels
    end
  end

  test "the panel's state is the chart's: a palette change keeps it, a step resets it" do
    s = mounted("colors")

    {:noreply, s} =
      ChartLive.handle_event("chart_panel", %{"panel" => "dark_mode", "scheme" => "dark"}, s)

    {:noreply, kept} = ChartLive.handle_event("change_palette", %{"palette" => "dark"}, s)
    assert [dark_mode: %{scheme: :dark}] = kept.assigns.panels

    {:noreply, stepped} = ChartLive.handle_params(%{"chart" => "paints"}, "/chart/paints", s)
    assert stepped.assigns.panels == []
    {:noreply, back} = ChartLive.handle_params(%{"chart" => "colors"}, "/chart/colors", stepped)
    assert [dark_mode: %{scheme: :system}] = back.assigns.panels
  end

  test "the Composition chart is drawn under ZoomHook, its budget line non-scaling" do
    assert ChartPanels.of(CompositionChart) == [:zoom]
    s = mounted("composition")
    page = html(s)

    [_, panel] = String.split(page, ~s(id="chart-panel-zoom-composition"), parts: 2)
    assert panel =~ ~s(phx-hook="ZoomHook")
    assert panel =~ ~s(phx-update="ignore")
    assert panel =~ ~s(data-zoom-event="chart_zoom")
    assert panel =~ ~s(<g class="zoom-container"><svg)
    # The budget line's stroke keeps its width; the trend lines' do not.
    assert panel =~ ~s(vector-effect="non-scaling-stroke")

    # The hook's report changes nothing on the page.
    params = %{"k" => 2.0, "x" => -10.0, "y" => -5.0}
    assert {:noreply, ^s} = ChartLive.handle_event("chart_zoom", params, s)
  end
end
