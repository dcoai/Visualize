defmodule Visualize.Components.TreeTest do
  @moduledoc """
  Render goldens for the three hierarchy components of `Visualize.Components.Tree`
  (spec/10 §3), in the manner of `Visualize.ComponentsTest`: a small fixed hierarchy and
  a root-only one, each rendered through `Phoenix.LiveViewTest.render_component/2` and
  compared byte for byte with `test/support/components/<name>.svg` (D-46).

  The sunburst's labels were retired from the goldens' equivalence with the hand-built
  component by #494 (D-123): they were inked `:background` and kept by the component's own
  thresholds, and that output was the defect — white on a pale arc — so the goldens record
  the labels the preset now fits (`:truncate`) and inks `:contrast`, after the arcs. Every
  other byte, every arc and the shell, is still the old component's, and a test below holds
  that each sunburst golden, labels aside, is the component drawn with every label empty.

  The treemap's labels were retired from that equivalence by #497 on the same ground: the
  component drew them itself, `:background` with a CSS text shadow at the cell's top-left
  corner, white on a pale cell. The goldens record the labels its preset now carries,
  fitted (`:truncate`, the cell's width and height) and inked `:contrast` at the cell's
  centre, after the cells, with no shadow. Every cell and the shell are still the old
  component's, which the same test holds for each treemap golden, the root-only one too.

      mix run -e 'Visualize.Components.TreeTest.write!()'
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Visualize.Components.Tree

  @dir "test/support/components"

  @hierarchy %{
    name: "root",
    children: [
      %{name: "a", children: [%{name: "a1", value: 10}, %{name: "a2", value: 20}]},
      %{name: "b", value: 30},
      %{name: "c", children: [%{name: "c1", value: 5}, %{name: "c2", value: 0}]}
    ]
  }
  @root_only %{name: "root", value: 1}
  @strings %{
    "name" => "root",
    "children" => [%{"name" => "x", "value" => 2}, %{"name" => "y", "value" => 1}]
  }

  @case_names ~w(tree_diagram tree_diagram_vertical treemap_chart treemap_chart_slice
                 sunburst_chart sunburst_chart_colors)a
  @empty_names ~w(tree_diagram treemap_chart sunburst_chart)a

  def cases do
    [
      tree_diagram: {&Tree.tree_diagram/1, %{data: @hierarchy}},
      tree_diagram_vertical:
        {&Tree.tree_diagram/1,
         %{
           data: @hierarchy,
           orientation: :vertical,
           width: 400,
           height: 300,
           margin: %{left: 40, right: 40},
           node_radius: 4,
           label: &String.upcase(&1.name),
           animate: true,
           class: "tree",
           title: "Org",
           description: "A vertical tree"
         }},
      treemap_chart: {&Tree.treemap_chart/1, %{data: @hierarchy}},
      treemap_chart_slice:
        {&Tree.treemap_chart/1,
         %{data: @strings, tile: :slice, padding: 0, colors: ["#111", "#222"]}},
      sunburst_chart: {&Tree.sunburst_chart/1, %{data: @hierarchy}},
      sunburst_chart_colors:
        {&Tree.sunburst_chart/1,
         %{
           data: @hierarchy,
           width: 300,
           height: 400,
           colors: :set2,
           value: fn d -> d[:value] || 1 end,
           label: & &1.name
         }}
    ]
  end

  def empty do
    [
      tree_diagram: {&Tree.tree_diagram/1, %{data: @root_only}},
      treemap_chart: {&Tree.treemap_chart/1, %{data: @root_only}},
      sunburst_chart: {&Tree.sunburst_chart/1, %{data: @root_only}}
    ]
  end

  def render_case({component, assigns}), do: render_component(component, assigns)

  # The lines of an SVG that are neither blank nor a label.
  defp unlabelled(svg) do
    svg
    |> String.split("\n")
    |> Enum.reject(&(String.trim(&1) == "" or String.starts_with?(String.trim(&1), "<text")))
  end

  test "each sunburst and treemap golden, labels aside, is the component's with every label empty (#494, #497)" do
    labelled =
      Enum.map(~w(sunburst_chart sunburst_chart_colors treemap_chart treemap_chart_slice)a, fn
        name -> {"#{name}.svg", Keyword.fetch!(cases(), name)}
      end) ++ [{"treemap_chart_empty.svg", Keyword.fetch!(empty(), :treemap_chart)}]

    for {file, {component, assigns}} <- labelled do
      golden = File.read!(Path.join(@dir, file))
      assert golden =~ "<text"
      blank = render_component(component, Map.put(assigns, :label, fn _node -> "" end))
      assert unlabelled(golden) == unlabelled(blank), file
    end
  end

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
    test "#{name} renders a root-only hierarchy as recorded" do
      svg = render_case(Keyword.fetch!(empty(), unquote(name)))
      assert File.read!(Path.join(@dir, "#{unquote(name)}_empty.svg")) == svg
      assert svg =~ "<svg"
    end
  end

  # Every component prints its paths through `Visualize.IR.Path.to_string/1`, the one `d`
  # serialiser (spec/02 §2.2, D-34), whose coordinates are comma-separated; a space inside a
  # `d` is a hand format of the component's own (D-71). Every golden of the chart and the
  # hierarchy components is held, so the guard is one place for all ten.
  test "no component golden's d contains a space" do
    goldens = Path.wildcard(Path.join(@dir, "*.svg"))
    assert length(goldens) == 27

    for file <- goldens, [_, d] <- Regex.scan(~r/ d="([^"]*)"/, File.read!(file)) do
      refute d =~ " ", "#{Path.basename(file)}: #{d}"
    end
  end

  describe "tree_diagram/1" do
    test "one node per hierarchy node, one link per edge" do
      svg = render_component(&Tree.tree_diagram/1, %{data: @hierarchy})
      assert length(Regex.scan(~r/<circle/, svg)) == 8
      assert length(Regex.scan(~r/<path d="M/, svg)) == 7

      assert svg =~
               ~s|text-anchor="end" font-size="var(--vis-label-size, 12px)" fill="var(--vis-text, #333333)">root</text>|

      assert svg =~
               ~s|text-anchor="start" font-size="var(--vis-label-size, 12px)" fill="var(--vis-text, #333333)">a1</text>|
    end

    test "a root-only hierarchy is one node and no link" do
      svg = render_component(&Tree.tree_diagram/1, %{data: @root_only})
      assert length(Regex.scan(~r/<circle/, svg)) == 1
      refute svg =~ "<path"
      assert svg =~ ~s{fill="var(--vis-background, #ffffff)"}
    end
  end

  describe "treemap_chart/1" do
    test "one cell per leaf, coloured by the child of the root above it" do
      svg = render_component(&Tree.treemap_chart/1, %{data: @hierarchy})
      [c0, c1, c2 | _] = Visualize.Scale.Color.scheme(:category10)
      fills = Regex.scan(~r/<rect[^>]* fill="([^"]+)"/, svg) |> Enum.map(&Enum.at(&1, 1))
      assert fills == [c0, c0, c1, c2, c2]
    end

    test "a colour list is used as given and cycled" do
      svg = render_component(&Tree.treemap_chart/1, %{data: @hierarchy, colors: ["#111", "#222"]})
      fills = Regex.scan(~r/<rect[^>]* fill="([^"]+)"/, svg) |> Enum.map(&Enum.at(&1, 1))
      assert fills == ["#111", "#111", "#222", "#111", "#111"]
    end

    test "an unknown scheme is an ArgumentError" do
      assert_raise ArgumentError, ~r/schemes\/0/, fn ->
        render_component(&Tree.treemap_chart/1, %{data: @hierarchy, colors: :nope})
      end
    end

    test "a zero-valued leaf is a zero-area cell without a label" do
      svg = render_component(&Tree.treemap_chart/1, %{data: @hierarchy})
      assert svg =~ ~r/(width|height)="0"/
      refute svg =~ ">c2</text>"
      assert svg =~ ">a2</text>"
    end
  end

  describe "sunburst_chart/1" do
    test "one arc per node below the root with a positive value, labels rendered" do
      svg = render_component(&Tree.sunburst_chart/1, %{data: @hierarchy})
      # Seven non-root nodes, one of them (c2) zero-valued and therefore undrawn.
      assert length(Regex.scan(~r/<path d="M/, svg)) == 6
      assert svg =~ ">a</text>"
      assert svg =~ ">b</text>"
      refute svg =~ ">c2</text>"
    end

    test "a label accessor is honoured" do
      svg =
        render_component(&Tree.sunburst_chart/1, %{
          data: @hierarchy,
          label: &String.upcase(&1.name)
        })

      assert svg =~ ">A</text>"
      refute svg =~ ">a</text>"
    end

    test "colours follow the child of the root" do
      svg =
        render_component(&Tree.sunburst_chart/1, %{
          data: @hierarchy,
          colors: ["#111", "#222", "#333"]
        })

      fills = Regex.scan(~r/<path[^>]* fill="([^"]+)"/, svg) |> Enum.map(&Enum.at(&1, 1))
      assert fills == ["#111", "#111", "#111", "#222", "#333", "#333"]
    end

    test "a root-only hierarchy draws no arc" do
      svg = render_component(&Tree.sunburst_chart/1, %{data: @root_only})
      refute svg =~ "<path"
    end
  end
end
