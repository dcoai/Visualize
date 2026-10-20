defmodule Examples.Themes.ChangesTest do
  @moduledoc """
  What a theme of the picker changes, and what a chart draws of it (spec/14 §12.6, #792,
  work item #795). Every gallery chart is measured under every option, one test a pair in
  the modules below, one an option: every chart the panel says draws none of what an
  option changes is drawn under it exactly as under Default. Here, each option other than
  Default changes what a witness chart draws.
  """
  use ExUnit.Case, async: true

  alias Examples.Themes
  alias Examples.Themes.Changes

  doctest Examples.Themes.Changes

  @options for entry <- Themes.list(), entry.key != "default", do: entry.key

  # A chart each option visibly changes, so no option is a button that does nothing. Print
  # and the color-safe theme reach few charts: Composition draws the status roles both
  # change.
  @witnesses %{
    "dark" => Examples.Charts.BarChart,
    "color_safe" => Examples.Charts.CompositionChart,
    "print" => Examples.Charts.CompositionChart,
    "sunrise" => Examples.Charts.BarChart,
    "winter" => Examples.Charts.BarChart,
    "sunset" => Examples.Charts.BarChart,
    "fall" => Examples.Charts.BarChart,
    "spring" => Examples.Charts.BarChart,
    "summer" => Examples.Charts.BarChart
  }

  test "every option other than Default changes what a gallery chart draws" do
    assert Enum.sort(Map.keys(@witnesses)) == Enum.sort(@options)

    for {key, module} <- @witnesses do
      assert Changes.drawn(module, Themes.theme(key)) != [], key
      refute Changes.svg(module, key) == Changes.svg(module, nil), key
    end

    # The evidence of #792: Color-safe changes only the status ramp, which a bar chart
    # does not draw, and Composition's roles do.
    assert Changes.drawn(Examples.Charts.BarChart, Themes.theme("color_safe")) == []
    assert Changes.drawn(Examples.Charts.CompositionChart, Themes.theme("color_safe")) == [:ramps]
  end

  test "what each built-in theme changes, read field by field" do
    assert Changes.of(Themes.theme("print")) == [
             page: [:surface, :text, :axis, :grid],
             ramps: [:status],
             styles: [:bad, :good, :info, :warning]
           ]

    print = Themes.theme("print")

    assert Changes.hatched(print, [:bad, :good, :info, :warning]) == [
             :bad,
             :good,
             :info,
             :warning
           ]

    assert [page: _, series: 10, colors: _, ramps: [:diverging, :sequential, :thermal]] =
             Changes.of(Themes.theme("dark"))
  end

  test "a host theme changes its page, series, hues, sequential ramp, title and grid" do
    for key <- ~w(sunrise winter sunset fall spring summer) do
      assert [
               page: [:background, :surface, :text, :axis, :grid],
               series: 8,
               colors: [:amber, :blue, :gray, :green, :info, :neutral, :red],
               ramps: [:sequential],
               styles: [:grid, :title]
             ] == Changes.of(Themes.theme(key)),
             key
    end
  end

  test "only/2 is Default with one aspect taken, unchecked" do
    print = Themes.theme("print")
    styles = Changes.only(print, :styles)

    assert styles.styles == print.styles
    assert styles.background == Themes.default().background
    assert styles.ramps == Themes.default().ramps
    assert Changes.only(print, :page).text == print.text
  end

  test "a chart drawn under Default draws nothing Default changes" do
    assert Changes.drawn(Examples.Charts.BarChart, Themes.default()) == []
  end
end

# Every chart under every option, one test a chart and an option (spec/12 §6, #735), one
# module an option so the nine run side by side: the option measured on the chart, as the
# panel does. Where the panel says the chart draws none of what the option changes, the
# chart under the option is the chart under Default, document for document. (A test a
# chart would carry all nine options — Downsampling's renders take half a second — and be
# one test's minute; one module would be the suite's long pole.)
for entry <- Examples.Themes.list(), entry.key != "default" do
  defmodule Module.concat(Examples.Themes.ChangesTest, Macro.camelize(entry.key)) do
    @moduledoc "Every gallery chart under #{entry.name} (#795)."
    use ExUnit.Case, async: true

    alias Examples.Themes
    alias Examples.Themes.Changes

    @key entry.key

    for {module, slug} <- Examples.Gallery.charts() do
      @module module
      test "#{slug} under #{@key}" do
        default = Changes.svg(@module, nil)

        if Changes.drawn(@module, Themes.theme(@key), default) == [],
          do: assert(Changes.svg(@module, @key) == default)
      end
    end
  end
end
