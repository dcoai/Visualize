defmodule ExamplesWeb.ThemePickerTest do
  @moduledoc """
  The chart page's theme picker (spec/14 §12.6, #792, work item #794): a button per theme
  of `Examples.Themes`, the picked one marked; a press looks its key up in the same list,
  so Print applies the print theme and an unlisted word changes nothing.
  """
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  alias Examples.Themes
  alias ExamplesWeb.ChartLive

  @endpoint ExamplesWeb.Endpoint

  doctest ExamplesWeb.ThemePicker

  defp page(slug) do
    {:ok, s} = ChartLive.mount(%{"chart" => slug}, %{}, %Phoenix.LiveView.Socket{})
    s
  end

  defp html(s), do: rendered_to_string(ChartLive.render(Map.put(s.assigns, :__changed__, %{})))

  defp svg(s), do: s.assigns.still_frame.svg

  test "the picker offers a button per listed theme, Default marked, and no Color Style bar" do
    html = html(page("bar"))

    for theme <- Themes.list() do
      assert html =~ ~s(phx-value-theme="#{theme.key}"), theme.key
      assert html =~ ">#{theme.name}</span>", theme.key
    end

    assert [_] = Regex.scan(~r/aria-pressed="true"[^>]*class="theme-btn active"/, html)
    assert html =~ ~r/data-theme="default"\s+aria-pressed="true"/
    refute html =~ "Color Style"
    refute html =~ "change_palette"
  end

  test "Print applies the print theme: its paper, its ink and its hatched roles" do
    s = page("composition")
    refute svg(s) =~ "<pattern"

    {:noreply, s} = ChartLive.handle_event("theme", %{"theme" => "print"}, s)
    assert s.assigns.theme == "print"
    print = Visualize.Theme.print()

    # The role styles' fills are hatches of the role's color (spec/08 §7.2).
    assert svg(s) =~ "<pattern"
    assert svg(s) =~ "var(--vis-text, #{print.text})"
    assert html(s) =~ ~s(style="background-color: #{print.background}")
    assert html(s) =~ ~r/data-theme="print"\s+aria-pressed="true"/
  end

  test "a host theme recolors the chart, and its page is the chart box's" do
    s = page("bar")
    {:noreply, s} = ChartLive.handle_event("theme", %{"theme" => "sunrise"}, s)
    sunrise = Themes.theme("sunrise")

    assert svg(s) =~ hd(sunrise.series)
    assert html(s) =~ ~s(style="background-color: #{sunrise.background}")
  end

  test "a word the list lacks changes nothing and makes no atom" do
    s = page("bar")
    {:noreply, s} = ChartLive.handle_event("theme", %{"theme" => "winter"}, s)
    word = "no_theme_#{System.unique_integer([:positive])}"
    {:noreply, same} = ChartLive.handle_event("theme", %{"theme" => word}, s)

    assert same.assigns.theme == "winter"
    assert_raise ArgumentError, fn -> String.to_existing_atom(word) end
  end

  test "the page as served carries the picker, Default marked" do
    html = build_conn() |> get("/chart/bar") |> html_response(200)
    assert html =~ ~r/data-theme="default"\s+aria-pressed="true"/
    assert html =~ ~s(phx-click="theme")
  end

  describe "What this theme changes (#795)" do
    test "Default is the baseline; the links go to the explain panel and the lab" do
      html = html(page("bar"))
      assert html =~ ~s(id="theme-changes")
      assert html =~ "Default is the baseline"
      assert html =~ ~s(href="#chart-panel-explain-bar")
      assert html =~ ~s(id="open-in-theme-lab" href="/theme-lab?theme=default")
    end

    test "Color-safe on a bar chart: only the status ramp changes, and the chart draws none of it" do
      {:noreply, s} = ChartLive.handle_event("theme", %{"theme" => "color_safe"}, page("bar"))
      html = html(s)

      assert s.assigns.theme_drawn == {"color_safe", "bar", []}
      assert html =~ "Color-safe changes, from Default:"
      assert html =~ ":status (the roles :good, :warning and :bad follow it)"
      assert html =~ "not drawn by this chart"
      assert html =~ "This chart draws none of them, so it looks as it does under Default."
      assert html =~ ~s(href="/theme-lab?theme=color_safe")
    end

    test "Print on Composition: the hatched role styles are drawn here" do
      {:noreply, s} = ChartLive.handle_event("theme", %{"theme" => "print"}, page("composition"))
      {"print", "composition", drawn} = s.assigns.theme_drawn
      assert :styles in drawn and :ramps in drawn

      html = html(s)

      assert html =~
               ~r/data-aspect="styles">\s*<strong>Palette styles<\/strong>: :bad, :good, :info, :warning \(:bad, :good, :info, :warning hatched\)\s*<span class="theme-drawn">drawn here/

      assert html =~ "This chart draws #{length(drawn)} of the 3."
      refute html =~ "Measuring"
    end

    test "an answer is shown only for the theme and chart it was measured for" do
      {:noreply, s} = ChartLive.handle_event("theme", %{"theme" => "winter"}, page("bar"))
      measured = s.assigns.theme_drawn

      # A late answer for another pick changes nothing; the current one is kept.
      stale = ExamplesWeb.ThemePicker.measured(s, {:ok, {"dark", "bar", [:page]}})
      assert stale.assigns.theme_drawn == measured
      assert ExamplesWeb.ThemePicker.measured(s, {:exit, :killed}) == s

      # While measuring the lines are unmarked.
      waiting = Phoenix.Component.assign(s, theme_drawn: nil)
      assert html(waiting) =~ "Measuring which of these this chart draws"
      refute html(waiting) =~ "drawn here"
    end

    test "Why it looks as it does explains the chart under the picked theme" do
      s = page("bar")

      {:noreply, s} =
        ChartLive.handle_event("chart_panel", %{"panel" => "explain", "action" => "open"}, s)

      {:noreply, s} = ChartLive.handle_event("pick", %{"node" => "marks[0]"}, s)
      [explain: was, formats: _] = s.assigns.panels
      assert was.svg =~ "var(--vis-series-1, #{hd(Visualize.Theme.default().series)})"

      {:noreply, s} = ChartLive.handle_event("theme", %{"theme" => "sunrise"}, s)
      [explain: now, formats: _] = s.assigns.panels
      sunrise = Themes.theme("sunrise")

      assert now.open and now.node == "marks[0]" and now.look != nil
      assert now.svg =~ "var(--vis-series-1, #{hd(sunrise.series)})"
      # A series slot is named, not resolved, in the stack, so the bar's look is the same.

      # A role style is the theme's: under Print the service bars' :good is a hatch.
      c = page("composition")
      open = %{"panel" => "explain", "action" => "open"}
      {:noreply, c} = ChartLive.handle_event("chart_panel", open, c)
      {:noreply, c} = ChartLive.handle_event("pick", %{"node" => "marks[0]"}, c)
      solid = Keyword.fetch!(c.assigns.panels, :explain)
      {:noreply, c} = ChartLive.handle_event("theme", %{"theme" => "print"}, c)
      hatched = Keyword.fetch!(c.assigns.panels, :explain)

      assert hatched.node == "marks[0]" and hatched.datum == solid.datum
      refute inspect(solid.look) =~ ":hatch"
      assert inspect(hatched.look, limit: :infinity) =~ ":hatch"

      # A step to another chart keeps the theme for its explain panel too.
      {:noreply, s} = ChartLive.handle_params(%{"chart" => "line"}, "/chart/line", s)
      [explain: line, formats: _] = s.assigns.panels

      assert ExamplesWeb.ChartPanels.Explain.event(line, %{"action" => "open"}).svg =~
               hd(sunrise.series)
    end
  end
end
