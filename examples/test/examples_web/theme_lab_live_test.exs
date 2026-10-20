defmodule ExamplesWeb.ThemeLabLiveTest do
  @moduledoc """
  The Theme lab (#785, spec/08 §7): a host theme built in code, its color table, pinned
  steps, ramps, resolved colors, forced colors, palette and defaults, its contracts failing
  and holding, and the print theme's hatched roles on a grayscale view.
  """
  use ExUnit.Case, async: true

  import Phoenix.ConnTest

  alias Examples.ThemeLab
  alias ExamplesWeb.ThemeLabLive
  alias Visualize.Theme

  @endpoint ExamplesWeb.Endpoint

  test "the house theme holds its contracts, adds a name and pins two steps of red" do
    house = ThemeLab.house()
    assert Theme.check(house) == :ok
    assert "brand" in Theme.color_names(house)
    refute "brand" in Theme.color_names(Theme.default())

    assert {"brand", "#0b6e4f", true} in ThemeLab.table(house)
    # No CSS named color is listed, and the theme's own hues are.
    refute Enum.any?(ThemeLab.table(house), &(elem(&1, 0) == :aliceblue))
    assert Enum.any?(ThemeLab.table(house), &(elem(&1, 0) == :red))

    assert ThemeLab.step(house, 100) == {"#fde8e8", "var(--vis-red-100, #fde8e8)", true}
    assert {_literal, "oklch(from var(--vis-red" <> _, false} = ThemeLab.step(house, 300)
    assert Theme.stylesheet(house) =~ "--vis-red-100: #fde8e8;"
  end

  test "colors resolve to a literal, to CSS and to OKLCH, and the ramp is sampled" do
    rows = ThemeLab.resolved(ThemeLab.house())
    {_expr, _literal, css, oklch} = Enum.find(rows, &(elem(&1, 0) =~ "saturate"))
    assert css =~ "oklch(from var(--vis-brand, #0b6e4f)"
    assert oklch =~ ~r/^oklch\(0\.\d{3} 0\.\d{3} \d+\.\d\)$/

    stops = ThemeLab.ramp(ThemeLab.house(), :thermal)
    assert length(stops) == 11
    assert hd(stops) == {0.0, Theme.ramp(Theme.default(), :thermal, 0)}
  end

  test "the forced-colors block maps the furniture to system colors" do
    block = ThemeLab.forced_colors(ThemeLab.house())
    assert block =~ "@media (forced-colors: active)"
    assert block =~ ".vis-theme-house"
    assert block =~ "--vis-text: CanvasText;"
  end

  test "each refused case names its rule and what it measured; the fixed one draws" do
    assert {:error, [pale]} = ThemeLab.check("pale")
    assert pale =~ "theme.styles.good"
    assert pale =~ "1.34:1"
    assert pale =~ "WCAG 1.4.11"

    assert {:error, [hue]} = ThemeLab.check("hue")
    assert hue =~ "differ only in hue"

    assert {:error, [unknown]} = ThemeLab.check("unknown")
    assert unknown =~ ~s(names "crimson_brand", not a color of the theme's color table)

    assert {:ok, svg} = ThemeLab.check("holds")
    assert svg =~ "#b3261e"
  end

  test "the page renders every section before it connects" do
    html = build_conn() |> get("/theme-lab") |> html_response(200)

    for id <-
          ~w(house table steps ramps resolve palette forced contracts print),
        do: assert(html =~ ~s(id="panel-#{id}"), id)

    assert html =~ ~s(class="lab-pin" data-step="100")
    assert html =~ "1.34:1"
    # The house theme's title is its own: serif, in the brand.
    assert html =~ ~s(font-family="Georgia, serif")
    # The print theme hatches its roles; the grayscale view is on.
    assert html =~ "<pattern"
    assert html =~ ~s(class="lab-pair lab-gray")
  end

  test "the switches take only their own words" do
    {:ok, socket} = ThemeLabLive.mount(%{}, %{}, %Phoenix.LiveView.Socket{})
    assert socket.assigns.case == "pale"
    assert {:error, [_]} = socket.assigns.case_result

    {:noreply, socket} = ThemeLabLive.handle_event("case", %{"case" => "holds"}, socket)
    assert {:ok, _svg} = socket.assigns.case_result

    {:noreply, socket} = ThemeLabLive.handle_event("forced", %{"mode" => "forced"}, socket)
    assert socket.assigns.forced == "forced"

    {:noreply, socket} = ThemeLabLive.handle_event("gray", %{"mode" => "color"}, socket)
    assert socket.assigns.gray == "color"

    # A word no switch knows changes nothing and makes no atom.
    word = "no_such_case_#{System.unique_integer([:positive])}"

    for {event, key} <- [{"case", "case"}, {"forced", "mode"}, {"gray", "mode"}] do
      assert {:noreply, ^socket} = ThemeLabLive.handle_event(event, %{key => word}, socket)
    end

    assert_raise ArgumentError, fn -> String.to_existing_atom(word) end
  end

  describe "a chart page's theme in the lab (#795)" do
    test "Open in Theme lab lands on the lab with that theme, beside Default" do
      html = build_conn() |> get("/theme-lab?theme=sunrise") |> html_response(200)

      assert html =~ ~s(id="panel-picked")
      assert html =~ "Sunrise, beside Default"
      assert html =~ ~s(Visualize.Theme.new)
      assert html =~ "Holds every contract"
      # Its table where it differs, its title style, and the role chart under it.
      assert html =~ "#b52f21"
      assert html =~ ":title"
      assert html =~ ~s(id="theme-lab-picked")
      assert html =~ ~r/<a[^>]*aria-current="page"[^>]*>\s*Sunrise/
      # The lab's own panels follow, the house among them.
      assert html =~ ~s(id="panel-house")
    end

    test "a key the list lacks, or none, is the lab as it is, and makes no atom" do
      word = "no_theme_#{System.unique_integer([:positive])}"
      {:ok, socket} = ThemeLabLive.mount(%{"theme" => word}, %{}, %Phoenix.LiveView.Socket{})
      assert socket.assigns.picked == nil
      assert_raise ArgumentError, fn -> String.to_existing_atom(word) end

      html = build_conn() |> get("/theme-lab") |> html_response(200)
      refute html =~ ~s(id="panel-picked")
      assert html =~ ~r/href="\/theme-lab"[^>]*aria-current="page"/
    end

    test "the theme row patches between themes" do
      {:ok, socket} = ThemeLabLive.mount(%{}, %{}, %Phoenix.LiveView.Socket{})
      {:noreply, socket} = ThemeLabLive.handle_params(%{"theme" => "print"}, "/theme-lab", socket)
      assert socket.assigns.picked.key == "print"

      assert Enum.map(socket.assigns.picked.palette, &elem(&1, 0)) == [
               :good,
               :warning,
               :bad,
               :info
             ]

      assert socket.assigns.picked.violations == []
    end
  end

  describe "cues and the stored form (#816)" do
    test "each role's cue is the library's, and the chart draws every dash and glyph" do
      assert ThemeLab.cues() == [
               {:good, :circle, nil},
               {:warning, :triangle, "6 3"},
               {:bad, :cross, "2 3"},
               {:info, :square, "8 3 2 3"},
               {:neutral, :diamond, "1 4"}
             ]

      for theme <- [Theme.default(), Theme.print()] do
        svg = ThemeLab.cues_svg(theme, "cues")

        for {_role, _glyph, dash} <- ThemeLab.cues(),
            dash != nil,
            do: assert(svg =~ ~s(stroke-dasharray="#{dash}"))
      end
    end

    test "the house is stored as JSON and read back equal; refused documents name their paths" do
      %{json: json, round_trip: true} = ThemeLab.stored(ThemeLab.house())
      assert json =~ ~s("$version": 3)
      assert json =~ ~s("brand": "#0b6e4f")
      assert json =~ ~s("$steps")

      assert [{_, _, [newer]}, {_, _, faults}] = ThemeLab.refused()
      assert newer =~ "needs schema v99"
      assert Enum.any?(faults, &(&1 =~ ~s(theme.series[0]: "$colr" is not a tag)))
      assert Enum.any?(faults, &(&1 =~ ~s(theme.axis: "$styles" was removed)))
    end

    test "both panels render, and the cue charts follow the grayscale switch" do
      html = build_conn() |> get("/theme-lab") |> html_response(200)
      assert html =~ ~s(id="panel-cues")
      assert html =~ ~s(id="panel-json")
      assert html =~ ~s(id="theme-lab-cues-print")
      assert html =~ "equal to the house"

      {:ok, socket} = ThemeLabLive.mount(%{}, %{}, %Phoenix.LiveView.Socket{})
      {:noreply, socket} = ThemeLabLive.handle_event("gray", %{"mode" => "color"}, socket)

      html =
        Phoenix.LiveViewTest.rendered_to_string(
          ThemeLabLive.render(Map.put(socket.assigns, :__changed__, %{}))
        )

      refute html =~ ~s(class="lab-pair lab-gray")
      assert html =~ ~s(id="theme-lab-cues-default")
    end
  end
end
