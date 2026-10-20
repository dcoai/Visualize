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
end
