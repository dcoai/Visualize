defmodule Visualize.ComponentsTest do
  @moduledoc """
  Render goldens for the seven chart components of `Visualize.Components` (spec/10 §2).

  Each component is rendered through `Phoenix.LiveViewTest.render_component/2` on a small
  fixed dataset and on empty data, and compared byte for byte with
  `test/support/components/<name>.svg` and `<name>_empty.svg`. The goldens are the
  recurrence guard for the component layer having never rendered (D-45), and since D-64 they
  hold every component byte for byte to what the hand-built component drew — except the
  pie's labels. Those were retired from the equivalence by #494 (D-123): the old labels were
  inked `:background`, white at 2.0:1 on `:category10`'s olive, and that output was the
  defect, so the golden records the labels the preset now fits (`:hide`) and inks
  `:contrast`, after the slices. The axes left it with D-134 (#532): an axis without a
  format or a count derives them, so a time axis reads `03:00` where the old component
  printed `2024-01-01 03:00:00Z`, and a 540 px x axis carries six ticks, not eleven. Every
  other byte — the shell, every path, the donut — is still the old component's, and a test
  below holds that the pie's golden, labels aside, is the label-less component's.
  Regenerate only when a component's output changes on purpose:

      mix run -e 'Visualize.ComponentsTest.write!()'
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Visualize.{Components, Theme}

  @dir "test/support/components"

  @t0 ~U[2024-01-01 00:00:00Z]

  @series for {v, h} <- Enum.with_index([4, 9, 2, 7]),
              do: %{at: DateTime.add(@t0, h * 6 * 3600, :second), value: v}
  @categories [%{name: "a", value: 30}, %{name: "b", value: 80}, %{name: "c", value: 45}]
  @points [%{x: 1, y: 10}, %{x: 4, y: 3}, %{x: 7, y: 12}, %{x: 9, y: 6}]
  @stacked [
    %{month: "Jan", apples: 10, pears: 20},
    %{month: "Feb", apples: 15, pears: 5},
    %{month: "Mar", apples: 0, pears: 25}
  ]

  @case_names ~w(line_chart line_chart_points bar_chart bar_chart_responsive
                 horizontal_bar_chart pie_chart donut_chart scatter_plot scatter_plot_sized
                 area_chart stacked_bar_chart)a
  @empty_names ~w(line_chart bar_chart horizontal_bar_chart pie_chart scatter_plot area_chart
                  stacked_bar_chart)a

  # Accessors are anonymous functions, which a module attribute cannot hold.
  def cases do
    [
      line_chart: {&Components.line_chart/1, %{data: @series, x: & &1.at, y: & &1.value}},
      line_chart_points:
        {&Components.line_chart/1,
         %{
           data: @points,
           x: & &1.x,
           y: & &1.y,
           show_points: true,
           curve: :monotone_x,
           x_label: "x",
           y_label: "y",
           animate: true,
           class: "chart",
           title: "Points",
           description: "Four points on a monotone curve"
         }},
      bar_chart: {&Components.bar_chart/1, %{data: @categories, x: & &1.name, y: & &1.value}},
      bar_chart_responsive:
        {&Components.bar_chart/1,
         %{data: @categories, x: & &1.name, y: & &1.value, responsive: true, class: "chart"}},
      horizontal_bar_chart:
        {&Components.horizontal_bar_chart/1, %{data: @categories, x: & &1.value, y: & &1.name}},
      pie_chart:
        {&Components.pie_chart/1, %{data: @categories, value: & &1.value, label: & &1.name}},
      donut_chart:
        {&Components.pie_chart/1,
         %{data: @categories, value: & &1.value, inner_radius: 60, colors: ["#111", "#222"]}},
      scatter_plot: {&Components.scatter_plot/1, %{data: @points, x: & &1.x, y: & &1.y}},
      scatter_plot_sized:
        {&Components.scatter_plot/1, %{data: @points, x: & &1.x, y: & &1.y, size: & &1.y}},
      area_chart:
        {&Components.area_chart/1, %{data: @series, x: & &1.at, y: & &1.value, curve: :step}},
      stacked_bar_chart:
        {&Components.stacked_bar_chart/1,
         %{data: @stacked, x: & &1.month, keys: [:apples, :pears], colors: :set2}}
    ]
  end

  def empty do
    [
      line_chart: {&Components.line_chart/1, %{data: [], x: & &1.at, y: & &1.value}},
      bar_chart: {&Components.bar_chart/1, %{data: [], x: & &1.name, y: & &1.value}},
      horizontal_bar_chart:
        {&Components.horizontal_bar_chart/1, %{data: [], x: & &1.value, y: & &1.name}},
      pie_chart: {&Components.pie_chart/1, %{data: [], value: & &1.value, label: & &1.name}},
      scatter_plot: {&Components.scatter_plot/1, %{data: [], x: & &1.x, y: & &1.y}},
      area_chart: {&Components.area_chart/1, %{data: [], x: & &1.at, y: & &1.value}},
      stacked_bar_chart:
        {&Components.stacked_bar_chart/1, %{data: [], x: & &1.month, keys: [:apples, :pears]}}
    ]
  end

  def render_case({component, assigns}), do: render_component(component, assigns)

  def goldens do
    Enum.map(cases(), fn {name, c} -> {"#{name}.svg", render_case(c)} end) ++
      Enum.map(empty(), fn {name, c} -> {"#{name}_empty.svg", render_case(c)} end)
  end

  def write! do
    File.mkdir_p!(@dir)
    Enum.each(goldens(), fn {file, svg} -> File.write!(Path.join(@dir, file), svg) end)
  end

  for name <- @case_names do
    test "#{name} renders as recorded" do
      c = Keyword.fetch!(cases(), unquote(name))
      assert File.read!(Path.join(@dir, "#{unquote(name)}.svg")) == render_case(c)
    end
  end

  for name <- @empty_names do
    test "#{name} renders the frame alone with no data" do
      svg = render_case(Keyword.fetch!(empty(), unquote(name)))
      assert File.read!(Path.join(@dir, "#{unquote(name)}_empty.svg")) == svg
      # The axes are paths too; a mark is a rect, a circle, or a path in the mark colour.
      assert svg =~ "<svg"
      refute svg =~ "<rect"
      refute svg =~ "<circle"
      refute svg =~ "steelblue"
      refute svg =~ ~r/<path d="[^"]*" fill="#/
    end
  end

  # The lines of an SVG that are neither blank nor a label.
  defp unlabelled(svg) do
    svg
    |> String.split("\n")
    |> Enum.reject(&(String.trim(&1) == "" or String.starts_with?(String.trim(&1), "<text")))
  end

  test "the pie's golden, labels aside, is the label-less component's byte for byte (#494)" do
    {component, assigns} = Keyword.fetch!(cases(), :pie_chart)
    golden = File.read!(Path.join(@dir, "pie_chart.svg"))
    assert golden =~ "<text"

    assert unlabelled(golden) ==
             unlabelled(render_component(component, Map.put(assigns, :show_labels, false)))
  end

  test "every chart component has a golden and an empty-data golden" do
    names = ~w(line_chart bar_chart horizontal_bar_chart pie_chart scatter_plot area_chart
               stacked_bar_chart)

    for name <- names do
      assert File.exists?(Path.join(@dir, "#{name}.svg"))
      assert File.exists?(Path.join(@dir, "#{name}_empty.svg"))
    end
  end

  test "responsive puts the CSS-scaling attributes on the <svg> and nothing else (D-54)" do
    plain = render_case(Keyword.fetch!(cases(), :bar_chart))
    responsive = render_case(Keyword.fetch!(cases(), :bar_chart_responsive))
    refute plain =~ "preserveAspectRatio"
    assert responsive =~ ~s(<svg width="600" height="400" class="chart" )
    assert responsive =~ ~s(preserveAspectRatio="xMidYMid meet" style="width:100%;height:auto")

    assert String.replace(responsive, ~r/<svg[^>]*>/, "") ==
             String.replace(plain, ~r/<svg[^>]*>/, "")
  end

  describe "accessibility (spec/10 §1.2, D-56)" do
    test "every <svg> is role=img; a titled one names itself first" do
      plain = render_case(Keyword.fetch!(cases(), :bar_chart))
      assert plain =~ ~s| role="img" |
      refute plain =~ "aria-labelledby"
      refute plain =~ "<title"

      titled = render_case(Keyword.fetch!(cases(), :line_chart_points))
      [_, id] = Regex.run(~r/aria-labelledby="([^"]+)-title/, titled)
      assert titled =~ ~s|role="img" aria-labelledby="#{id}-title" aria-describedby="#{id}-desc"|
      assert titled =~ ~s|<title id="#{id}-title">Points</title>|
      assert titled =~ ~s|<desc id="#{id}-desc">Four points on a monotone curve</desc>|
      assert titled =~ ~s|<g class="x-axis" transform="translate(0, 350)"><g aria-hidden="true"|

      only_desc =
        render_component(&Components.pie_chart/1, %{
          data: @categories,
          value: & &1.value,
          description: "Three slices"
        })

      assert only_desc =~ ~r/aria-labelledby="vis-[a-z0-9]+-desc"/
      refute only_desc =~ "aria-describedby"
      refute only_desc =~ "<title"
      assert only_desc =~ ~r/<desc id="vis-[a-z0-9]+-desc">Three slices<\/desc>/
    end
  end

  describe "theme (spec/10 §1.2, D-55)" do
    test "the default theme's slots render as var() references with their fallbacks" do
      svg = render_case(Keyword.fetch!(cases(), :bar_chart))

      assert svg =~
               ~s|<svg width="600" height="400" font-family="var(--vis-font-family, sans-serif)" |

      assert svg =~ ~s|fill="var(--vis-series-1, #3b6fa8)"|
      assert svg =~ ~s|stroke="var(--vis-axis, #666666)"|
      assert svg =~ ~s|fill="var(--vis-text, #333333)"|
      refute svg =~ "currentColor"
    end

    test "the dark theme changes every fallback and nothing else" do
      light = render_case(Keyword.fetch!(cases(), :bar_chart))

      dark =
        render_component(&Components.bar_chart/1, %{
          data: @categories,
          x: & &1.name,
          y: & &1.value,
          theme: Theme.dark()
        })

      assert dark =~ ~s|fill="var(--vis-series-1, #7fb3e6)"|
      assert dark =~ ~s|stroke="var(--vis-axis, #a0a4ab)"|
      assert dark =~ ~s|fill="var(--vis-text, #e6e6e6)"|

      relit =
        dark
        |> String.replace("#7fb3e6", "#3b6fa8")
        |> String.replace("#a0a4ab", "#666666")
        |> String.replace("#e6e6e6", "#333333")

      assert relit == light
    end

    test "an explicit colour assign is used as given; a label on a slice is inked by contrast" do
      svg = render_case(Keyword.fetch!(cases(), :line_chart_points))
      pie = render_case(Keyword.fetch!(cases(), :pie_chart))

      custom =
        render_component(&Components.bar_chart/1, %{
          data: @categories,
          x: & &1.name,
          y: & &1.value,
          fill: "tomato"
        })

      assert custom =~ ~s|fill="tomato"|
      refute custom =~ "--vis-series"

      assert svg =~
               ~s|font-size="var(--vis-label-size, 12px)" fill="var(--vis-text, #333333)" class="axis-label"|

      assert pie =~ ~s|stroke="var(--vis-background, #ffffff)" stroke-width="2"|

      # The theme's background on the blue slice, its text on the orange, and black on the
      # green, where neither slot reaches 4.5:1 (D-123, #494).
      assert pie =~ ~s|font-size="var(--vis-label-size, 12px)" fill="#ffffff">a</text>|
      assert pie =~ ~s|font-size="var(--vis-label-size, 12px)" fill="#333333">b</text>|
      assert pie =~ ~s|font-size="var(--vis-label-size, 12px)" fill="#000000">c</text>|
    end
  end

  describe "colors" do
    test "a colour list is used as given and cycled" do
      svg =
        render_component(&Components.pie_chart/1, %{
          data: @categories,
          value: & &1.value,
          colors: ["#111", "#222"]
        })

      fills = Regex.scan(~r/fill="(#[0-9a-f]+)"/, svg) |> Enum.map(&Enum.at(&1, 1))
      assert fills == ["#111", "#222", "#111"]
    end

    test "a scheme atom is taken by index" do
      svg =
        render_component(&Components.stacked_bar_chart/1, %{
          data: @stacked,
          x: & &1.month,
          keys: [:apples, :pears],
          colors: :category10
        })

      [first, second | _] = Visualize.Scale.Color.scheme(:category10)
      assert svg =~ ~s(fill="#{first}")
      assert svg =~ ~s(fill="#{second}")
    end

    test "an unknown scheme is an ArgumentError naming schemes/0" do
      assert_raise ArgumentError, ~r/schemes\/0/, fn ->
        render_component(&Components.pie_chart/1, %{
          data: @categories,
          value: & &1.value,
          colors: :no_such_scheme
        })
      end
    end

    test "an empty colour list is an ArgumentError" do
      assert_raise ArgumentError, fn ->
        render_component(&Components.pie_chart/1, %{
          data: @categories,
          value: & &1.value,
          colors: []
        })
      end
    end
  end

  describe "degenerate data" do
    test "a single datum renders mid-axis: the collapsed domain stays [v, v] (D-49, D-60)" do
      svg =
        render_component(&Components.line_chart/1, %{
          data: [hd(@series)],
          x: & &1.at,
          y: & &1.value
        })

      assert svg =~ "<path"

      svg =
        render_component(&Components.scatter_plot/1, %{
          data: [%{x: 3, y: 3}],
          x: & &1.x,
          y: & &1.y
        })

      assert svg =~ ~s(<circle cx="270" cy="175")
      assert length(Regex.scan(~r/class="tick"/, svg)) == 2
    end

    test "all-zero bars render with zero height" do
      svg =
        render_component(&Components.bar_chart/1, %{
          data: [%{name: "a", value: 0}],
          x: & &1.name,
          y: & &1.value
        })

      assert svg =~ ~s(height="0")
    end

    test "a Date x axis is a time scale" do
      data = [%{d: ~D[2024-01-01], v: 1}, %{d: ~D[2024-01-31], v: 2}]
      svg = render_component(&Components.line_chart/1, %{data: data, x: & &1.d, y: & &1.v})
      assert svg =~ "<path"
    end
  end

  describe "assigns" do
    test "a partial margin overrides one side" do
      svg =
        render_component(&Components.bar_chart/1, %{
          data: @categories,
          x: & &1.name,
          y: & &1.value,
          margin: %{left: 60}
        })

      assert svg =~ ~s|transform="translate(60, 20)"|
    end

    test "animate puts the transition on every mark and class lands on the svg" do
      svg =
        render_component(&Components.scatter_plot/1, %{
          data: @points,
          x: & &1.x,
          y: & &1.y,
          animate: true,
          class: "c"
        })

      assert svg =~ ~s(<svg width="600" height="400" class="c vis-animated")
      assert length(Regex.scan(~r/transition: all 0.3s ease-in-out;/, svg)) == length(@points)

      # A reader who asks for less motion gets none (spec/14 §21.6): the rule beats the
      # inline transition, and a chart that does not animate carries no rule.
      assert svg =~
               "<style>@media (prefers-reduced-motion: reduce) { svg.vis-animated * { transition: none !important; } }</style>"

      still = render_component(&Components.scatter_plot/1, %{data: @points, x: & &1.x, y: & &1.y})
      refute still =~ "<style" or still =~ "vis-animated"
    end

    test "pie labels are drawn only with show_labels and a label accessor" do
      name = fn d -> d.name end
      base = %{data: @categories, value: fn d -> d.value end}
      labelled = Map.put(base, :label, name)
      hidden = Map.put(labelled, :show_labels, false)

      refute render_component(&Components.pie_chart/1, base) =~ "<text"
      refute render_component(&Components.pie_chart/1, hidden) =~ "<text"
      assert render_component(&Components.pie_chart/1, labelled) =~ ">a</text>"
    end
  end
end
