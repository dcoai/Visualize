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

  doctest ExamplesWeb.ChartPanels.Explain

  test "a module names its panels, and every page explains" do
    assert ChartPanels.of(ColorsChart) == [:dark_mode, :explain]
    assert ChartPanels.of(BarChart) == [:explain]

    assert html(mounted("colors")) =~ ~s(id="chart-panel-dark_mode-colors")
    refute html(mounted("bar")) =~ "chart-panel-dark_mode"
    assert html(mounted("bar")) =~ ~s(id="chart-panel-explain-bar")
  end

  test "the implicit drawing carries the dark-mode rule, color_scheme: false none" do
    %{implicit: implicit, fixed: fixed} = DarkMode.drawings(ColorsChart)

    assert implicit =~ @rule
    refute fixed =~ "prefers-color-scheme"

    # Three roots on one page, the chart above among them, and no two share an id: the
    # rule is scoped to its root's id, which the panel gives each drawing (D-188), so both
    # keep the design's own title.
    assert implicit =~ ~s(<title id="dark-mode-implicit-title">Colors</title>)
    assert fixed =~ ~s(<title id="dark-mode-fixed-title">Colors</title>)
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
    assert [dark_mode: %{scheme: :dark}, explain: _] = kept.assigns.panels

    {:noreply, stepped} = ChartLive.handle_params(%{"chart" => "paints"}, "/chart/paints", s)
    assert [explain: %{open: false}] = stepped.assigns.panels
    {:noreply, back} = ChartLive.handle_params(%{"chart" => "colors"}, "/chart/colors", stepped)
    assert [dark_mode: %{scheme: :system}, explain: _] = back.assigns.panels
  end

  test "the Composition chart is drawn under ZoomHook, its budget line non-scaling" do
    assert ChartPanels.of(CompositionChart) == [:zoom, :units, :explain]
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

  # The units (#786, spec/14 §3.9, §11): one length in six units, each stored as `$unit`
  # JSON and resolved to the same user units, read from the chart's own design.
  test "the Composition chart's units panel shows each unit stored as $unit JSON, all one length" do
    %{rows: rows} = ExamplesWeb.ChartPanels.Units.init(CompositionChart)
    assert Enum.map(rows, & &1.name) == CompositionChart.unit_names()
    assert Enum.map(rows, & &1.dash) |> hd() == ~s({"$unit":[48,"px"]})
    assert ~s({"$unit":[0.5,"in"]}) in Enum.map(rows, & &1.dash)
    assert Enum.all?(rows, &(&1.dash_px == 48.0 and &1.width_px == 6.0))

    page = html(mounted("composition"))
    [_, panel] = String.split(page, ~s(id="chart-panel-units-composition"), parts: 2)
    assert panel =~ "{&quot;$unit&quot;:[12.7,&quot;mm&quot;]}"
    assert panel =~ "48.00 dash, 6.00 wide"
  end

  defp event(s, name, params) do
    {:noreply, s} = ChartLive.handle_event(name, params, s)
    s
  end

  test "a click explains the element: its parts and the layers that set them" do
    s = mounted("composition")
    closed = html(s)
    assert closed =~ "Explain an element"
    refute closed =~ ~s(data-builder-scope="graph")

    s = event(s, "chart_panel", %{"panel" => "explain", "action" => "open"})
    page = html(s)
    assert page =~ ~s(phx-hook="BuilderHook" data-builder-scope="graph")
    assert page =~ ~s(data-node="marks[0]")
    assert page =~ "Nothing picked yet."

    # The bar's style is chosen by its row's state, so it is explained per state, the
    # first at once: a palette name, a list, a style that extends another.
    s = event(s, "pick", %{"node" => "marks[0]", "scope" => "graph"})
    page = html(s)
    assert page =~ ~s(data-builder-selected="marks[0]")
    assert page =~ "why marks[0] looks as it does"

    for word <- ["state = good", "state = degraded", "state = down"],
        do: assert(page =~ word)

    s = event(s, "chart_panel", %{"panel" => "explain", "datum" => "2"})
    [explain] = for {:explain, state} <- s.assigns.panels, do: state

    assert [%{layer: :theme}, %{layer: :kind}, %{layer: :field, style: "down", via: ["bad"]}] =
             explain.look.parts.stroke.chain

    assert html(s) =~ "via bad"

    # The trend's thick line: two palette entries stacked over the kind's defaults.
    s = event(s, "pick", %{"node" => "marks[2]"})
    [explain] = for {:explain, state} <- s.assigns.panels, do: state
    assert explain.data == []

    assert Enum.map(explain.look.parts.stroke.chain, &{&1.layer, &1.style}) ==
             [theme: nil, kind: nil, kind: nil, palette: "style_3", palette: "thick"]

    # A frame's own group, and a frame the design lacks, explain nothing.
    for node <- ["frames.status", "frames.nope.legend"] do
      s = event(s, "pick", %{"node" => node})
      assert html(s) =~ "has no style of its own to explain"
    end

    # The hook's drag and menu gestures move nothing here.
    assert {:noreply, ^s} = ChartLive.handle_event("move", %{"node" => "labels[0]"}, s)
    assert {:noreply, ^s} = ChartLive.handle_event("menu", %{"node" => "marks[0]"}, s)

    closed = event(s, "chart_panel", %{"panel" => "explain", "action" => "close"})
    refute html(closed) =~ ~s(data-builder-scope="graph")
  end
end
