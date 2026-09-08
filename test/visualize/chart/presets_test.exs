defmodule Visualize.Chart.PresetsTest do
  @moduledoc """
  The ten components as preset designs (spec/14 §15, D-64): every preset validates and
  survives `from_map(to_map(design))`, the assign mapping yields the rows of §15.2, the
  chart presets render through the layer on their own, a design is bindable to another
  source with the same columns, and a preset design re-framed as a facet renders panels.
  The byte identity of each component with its golden is `Visualize.ComponentsTest` and
  `Visualize.Components.TreeTest`.
  """
  use ExUnit.Case, async: true

  alias Visualize.Chart
  alias Visualize.Chart.{Frame, Presets}

  doctest Presets

  @t0 ~U[2024-01-01 00:00:00Z]
  @series for {v, h} <- Enum.with_index([4, 9, 2, 7]),
              do: %{at: DateTime.add(@t0, h * 6 * 3600, :second), value: v}
  @categories [%{name: "a", value: 30}, %{name: "b", value: 80}, %{name: "c", value: 45}]
  @points [%{x: 1, y: 10}, %{x: 4, y: 3}, %{x: 7, y: 12}, %{x: 9, y: 6}]
  @stacked [%{month: "Jan", apples: 10, pears: 20}, %{month: "Feb", apples: 15, pears: 5}]
  @hierarchy %{
    name: "root",
    children: [
      %{name: "a", children: [%{name: "a1", value: 10}, %{name: "a2", value: 20}]},
      %{name: "b", value: 30}
    ]
  }

  # The assigns of each preset on a small dataset and on the empty case.
  def assigns do
    %{
      line_chart: %{data: @series, x: & &1.at, y: & &1.value, show_points: true, x_label: "t"},
      bar_chart: %{data: @categories, x: & &1.name, y: & &1.value},
      horizontal_bar_chart: %{data: @categories, x: & &1.value, y: & &1.name},
      pie_chart: %{data: @categories, value: & &1.value, label: & &1.name, title: "Pie"},
      scatter_plot: %{data: @points, x: & &1.x, y: & &1.y, size: & &1.y},
      area_chart: %{data: @series, x: & &1.at, y: & &1.value, curve: :step},
      stacked_bar_chart: %{data: @stacked, x: & &1.month, keys: [:apples, :pears]},
      tree_diagram: %{data: @hierarchy},
      treemap_chart: %{data: @hierarchy, colors: ["#111", "#222"]},
      sunburst_chart: %{data: @hierarchy, description: "Rings"}
    }
  end

  def empty do
    %{
      line_chart: %{data: [], x: & &1.at, y: & &1.value},
      bar_chart: %{data: [], x: & &1.name, y: & &1.value},
      horizontal_bar_chart: %{data: [], x: & &1.value, y: & &1.name},
      pie_chart: %{data: [], value: & &1.value},
      scatter_plot: %{data: [], x: & &1.x, y: & &1.y},
      area_chart: %{data: [], x: & &1.at, y: & &1.value},
      stacked_bar_chart: %{data: [], x: & &1.month, keys: [:apples, :pears]},
      tree_diagram: %{data: %{name: "root"}},
      treemap_chart: %{data: %{name: "root", value: 1}},
      sunburst_chart: %{data: %{name: "root", value: 1}}
    }
  end

  test "names/0 lists the ten presets in spec/10 order" do
    assert Presets.names() == [
             :line_chart,
             :bar_chart,
             :horizontal_bar_chart,
             :pie_chart,
             :scatter_plot,
             :area_chart,
             :stacked_bar_chart,
             :tree_diagram,
             :treemap_chart,
             :sunburst_chart
           ]

    assert Map.keys(assigns()) |> Enum.sort() == Enum.sort(Presets.names())
  end

  test "every preset validates and survives from_map(to_map(design)), with and without data" do
    for name <- Presets.names(), source <- [assigns(), empty()] do
      design = Presets.design(name, Map.fetch!(source, name))
      assert {:ok, chart} = Chart.from_map(design), "#{name}: #{inspect(design)}"
      assert Chart.from_map(Chart.to_map(chart)) == {:ok, chart}, "#{name}"
      assert chart.sources == %{data: %{fields: hd(Map.values(design.sources)).fields}}
      refute has_function?(design), "#{name} carries a function"
    end
  end

  test "the assign mapping yields the rows of spec/14 §15.2" do
    assert Presets.sources(:bar_chart, assigns().bar_chart) ==
             %{data: [%{x: "a", y: 30}, %{x: "b", y: 80}, %{x: "c", y: 45}]}

    assert %{data: [%{x: 1, y: 10, r: 10} | _]} =
             Presets.sources(:scatter_plot, assigns().scatter_plot)

    assert %{data: [%{x: "Jan", apples: 10, pears: 20} | _]} =
             Presets.sources(:stacked_bar_chart, assigns().stacked_bar_chart)

    assert %{data: [%{value: 30, index: 0, label: "a"} | _]} =
             Presets.sources(:pie_chart, assigns().pie_chart)

    assert %{data: [%{value: 30, index: 0} = first | _]} =
             Presets.sources(:pie_chart, %{data: @categories, value: & &1.value})

    refute Map.has_key?(first, :label)

    assert %{data: rows} = Presets.sources(:treemap_chart, assigns().treemap_chart)

    assert Enum.map(rows, &{&1.id, &1.parent, &1.label, &1.value, &1.branch}) == [
             {"0", nil, "root", 0, nil},
             {"0.0", "0", "a", 0, 0},
             {"0.0.0", "0.0", "a1", 10, 0},
             {"0.0.1", "0.0", "a2", 20, 0},
             {"0.1", "0", "b", 30, 1}
           ]

    # An accessor is applied to every node, internal ones included.
    %{data: valued} =
      Presets.sources(:sunburst_chart, %{data: @hierarchy, value: fn d -> d[:value] || 1 end})

    assert Enum.map(valued, & &1.value) == [1, 1, 10, 20, 30]

    # `data` is read through `Visualize.Data.Table.rows/1` first (D-53).
    columns = %{name: ["a", "b"], value: [1, 2]}

    assert Presets.sources(:bar_chart, %{data: columns, x: & &1.name, y: & &1.value}).data ==
             [%{x: "a", y: 1}, %{x: "b", y: 2}]
  end

  test "an absent assign takes the component's default and an unknown preset raises" do
    assert Presets.defaults(:line_chart).margin == %{top: 20, right: 20, bottom: 30, left: 40}
    assert Presets.defaults(:horizontal_bar_chart).margin.left == 100
    assert Presets.defaults(:pie_chart).colors == :category10

    design = Presets.bar_chart(%{data: [], x: & &1.name, y: & &1.value})
    assert design.frame.size == %{width: 600, height: 400}
    assert design.frame.margin == %{top: 20, right: 20, bottom: 30, left: 40}
    assert design.frame.scales.x == %{kind: :band, padding: 0.1}

    for f <- [&Presets.defaults/1, &Presets.design(&1, %{}), &Presets.sources(&1, %{})] do
      assert_raise ArgumentError, ~r/not a preset/, fn -> f.(:no_such_chart) end
    end
  end

  test "the x scale of a series chart follows the first datum (spec/10 §2.2)" do
    line = fn data -> Presets.line_chart(%{data: data, x: & &1.x, y: & &1.y}).frame.scales.x end
    assert line.([%{x: @t0, y: 1}]) == %{kind: :time}
    assert line.([%{x: ~D[2024-01-01], y: 1}]) == %{kind: :time}
    assert line.([%{x: 3, y: 1}]) == %{kind: :linear}
    assert line.([%{x: "a", y: 1}]) == %{kind: :band, padding: 0.1}
    assert line.([]) == %{kind: :linear}
  end

  test "the assigns reach the design: colours, options, labels, meta and the transform" do
    design = Presets.line_chart(Map.put(assigns().line_chart, :stroke, "tomato"))
    assert design.styles.line == %{stroke: "tomato", stroke_width: 2, curve: :linear}
    assert design.styles.point == %{fill: "tomato"}
    assert [%{type: :line}, %{type: :circle, options: %{radius: 4}}] = design.marks
    assert design.labels == [%{anchor: {:axis, :x}, text: ["t"]}]

    pie = Presets.pie_chart(assigns().pie_chart)
    assert pie.meta == %{name: "Pie"}
    assert pie.frame.kind == :polar

    assert [%{options: %{outer_radius: 190.0, inner_radius: 0, pad_angle: 0.02}, label: label}] =
             pie.marks

    assert label.text == [{:field, :label}]

    refute Map.has_key?(
             hd(Presets.pie_chart(Map.put(assigns().pie_chart, :show_labels, false)).marks),
             :label
           )

    stacked = Presets.stacked_bar_chart(assigns().stacked_bar_chart)

    assert stacked.frame.scales.color == %{
             kind: :ordinal,
             domain: [:apples, :pears],
             range: :category10
           }

    assert [%{data: %{source: :data, transforms: [%{op: :stack, fields: [:apples, :pears]}]}}] =
             stacked.marks

    tree =
      Presets.tree_diagram(%{data: @hierarchy, orientation: :vertical, width: 400, height: 300})

    assert [%{type: :path, data: %{transforms: [links]}}, %{type: :circle, channels: channels}] =
             tree.marks

    assert links == %{
             op: :tree,
             id: :id,
             by: :parent,
             size: [160, 260],
             orientation: :vertical,
             output: :links
           }

    assert channels == %{x: :x, y: :y}
    assert Enum.at(tree.marks, 1).label == %{text: [{:field, :label}], anchor: :middle}

    horizontal = Presets.tree_diagram(%{data: @hierarchy})
    assert hd(horizontal.marks).data.transforms |> hd() |> Map.fetch!(:orientation) == :horizontal
    assert Enum.at(horizontal.marks, 1).channels == %{x: :y, y: :x}

    treemap = Presets.treemap_chart(assigns().treemap_chart)

    assert [%{data: %{transforms: [%{op: :treemap}, leaves]}}] = treemap.marks
    assert leaves == %{op: :filter, field: :height, test: :eq, value: 0}

    sunburst = Presets.sunburst_chart(assigns().sunburst_chart)
    assert sunburst.meta == %{description: ["Rings"]}
    assert sunburst.frame.scales.color.domain == [0, 1]

    assert [%{channels: arc_channels, label: arc_label, data: %{transforms: steps}}] =
             sunburst.marks

    assert [%{op: :partition, size: [angle, 300.0]}, below_root, positive] = steps
    assert_in_delta angle, 2 * :math.pi(), 1.0e-9
    assert below_root == %{op: :filter, field: :depth, test: :gt, value: 0}
    assert positive == %{op: :filter, field: :value, test: :gt, value: 0}
    assert arc_channels == %{start: :x0, end: :x1, inner: :y0, outer: :y1}
    assert arc_label == %{text: [{:field, :label}], anchor: :middle, style: :arc_label}
    assert sunburst.styles.arc_label == %{fill: :background, font_size: :label_size}
  end

  test "a chart preset renders through the layer on its own, and binds to another source" do
    for name <- Presets.names() -- [:tree_diagram, :treemap_chart, :sunburst_chart] do
      a = Map.fetch!(assigns(), name)
      chart = Chart.from_map!(Presets.design(name, a))
      sources = Presets.sources(name, a)
      svg = Frame.render(Frame.new(chart, sources: sources), sources: sources)
      assert svg =~ ~s(class="frame"), "#{name}"
      assert svg =~ ~r/class="mark mark-(line|rect|circle|area|arc)"/, "#{name}"
    end

    a = assigns().bar_chart
    chart = Chart.from_map!(Presets.bar_chart(a))
    other = %{data: %{x: ["p", "q"], y: [1, 2]}}
    svg = Frame.render(Frame.new(chart, sources: other), sources: other)
    assert svg =~ ">p</text>"
    assert length(Regex.scan(~r/<rect /, svg)) == 2
  end

  test "an empty colour list is an ArgumentError naming the scale" do
    a = Map.put(assigns().pie_chart, :colors, [])

    assert_raise ArgumentError, ~r/scale :color: an empty range/, fn ->
      Frame.new(Chart.from_map!(Presets.pie_chart(a)), sources: Presets.sources(:pie_chart, a))
    end
  end

  test "a preset design re-framed as a facet renders one panel per value (spec/14 §4.6)" do
    a = %{data: @categories, x: & &1.name, y: & &1.value}
    design = Presets.bar_chart(a)
    fields = design.sources.data.fields ++ [:region]
    facet = Map.merge(design.frame, %{kind: :facet, facet: %{by: :region, columns: 2}})
    design = %{design | frame: facet, sources: %{data: %{fields: fields}}}
    chart = Chart.from_map!(design)

    rows =
      for {row, i} <- Enum.with_index(Presets.sources(:bar_chart, a).data),
          do: Map.put(row, :region, if(rem(i, 2) == 0, do: "east", else: "west"))

    sources = %{data: rows}
    frame = Frame.new(chart, sources: sources)
    assert frame.panels == ["east", "west"]
    svg = Frame.render(frame, sources: sources)
    assert length(Regex.scan(~r/class="panel"/, svg)) == 2
    assert length(Regex.scan(~r/<rect /, svg)) == 3
  end

  describe "the hierarchy presets through the layer (spec/14 §15.4, D-70)" do
    import Phoenix.LiveViewTest, only: [render_component: 2]

    alias Visualize.Components.Tree

    @tree_hierarchy %{
      name: "root",
      children: [
        %{name: "a", children: [%{name: "a1", value: 10}, %{name: "a2", value: 20}]},
        %{name: "b", value: 30},
        %{name: "c", children: [%{name: "c1", value: 5}, %{name: "c2", value: 0}]}
      ]
    }
    @root_only %{name: "root", value: 1}

    # The design rendered by the layer alone, over the assign mapping's rows.
    defp layer(name, a) do
      chart = Chart.from_map!(Presets.design(name, a))
      sources = Presets.sources(name, a)
      Frame.render(Frame.new(chart, sources: sources), sources: sources)
    end

    # Every `<tag …>` of an SVG string as a map of its attributes, in document order.
    defp tags(svg, tag) do
      for [_, attrs] <- Regex.scan(~r/<#{tag}\b([^>]*)>/, svg) do
        Map.new(Regex.scan(~r/([\w-]+)="([^"]*)"/, attrs), fn [_, k, v] -> {k, v} end)
      end
    end

    defp texts(svg), do: for([_, t] <- Regex.scan(~r/<text[^>]*>([^<]*)<\/text>/, svg), do: t)

    # The layer prints an attribute as its number and the component through the
    # four-decimal formatter (spec/10 §1.2), so a layer value is formatted before comparing.
    defp num(string) do
      case Float.parse(string) do
        {number, ""} -> Visualize.IR.Path.format_number(number)
        _ -> string
      end
    end

    test "the tree's links, circles and labels are the component's, in count and geometry" do
      for a <- [
            %{data: @tree_hierarchy},
            %{data: @tree_hierarchy, orientation: :vertical, width: 400, height: 300},
            %{data: @root_only}
          ] do
        svg = layer(:tree_diagram, a)
        component = render_component(&Tree.tree_diagram/1, a)

        # Both print the row's path through `Visualize.IR.Path.to_string/1` (D-71).
        paths = Enum.map(tags(svg, "path"), & &1["d"])
        assert paths == Enum.map(tags(component, "path"), & &1["d"])
        assert length(paths) == length(Presets.sources(:tree_diagram, a).data) - 1

        centres = Enum.map(tags(svg, "circle"), &{num(&1["cx"]), num(&1["cy"])})

        assert centres ==
                 for(
                   [_, x, y] <- Regex.scan(~r/translate\(([^,]+), ([^)]+)\)/, component),
                   do: {x, y}
                 )
                 |> tl()

        assert texts(svg) == texts(component)
        assert length(centres) == length(Presets.sources(:tree_diagram, a).data)
      end
    end

    test "the treemap's cells are the component's leaves, in count and geometry" do
      for a <- [%{data: @tree_hierarchy}, %{data: @root_only}] do
        svg = layer(:treemap_chart, a)
        component = render_component(&Tree.treemap_chart/1, a)

        geometry = fn markup ->
          for r <- tags(markup, "rect"), do: Map.new(~w(x y width height), &{&1, num(r[&1])})
        end

        assert geometry.(svg) == geometry.(component)
        rows = Presets.sources(:treemap_chart, a).data
        parents = MapSet.new(rows, & &1.parent)
        assert length(geometry.(svg)) == Enum.count(rows, &(&1.id not in parents))
      end

      svg = layer(:treemap_chart, %{data: @tree_hierarchy, colors: ["#111", "#222"]})
      assert Enum.map(tags(svg, "rect"), & &1["fill"]) == ["#111", "#111", "#222", "#111", "#111"]
    end

    test "the sunburst's arcs and labels are the component's, in count and geometry" do
      for a <- [%{data: @tree_hierarchy}, %{data: @root_only}] do
        svg = layer(:sunburst_chart, a)
        component = render_component(&Tree.sunburst_chart/1, a)

        assert Enum.map(tags(svg, "path"), & &1["d"]) ==
                 Enum.map(tags(component, "path"), & &1["d"])

        assert Enum.map(tags(svg, "path"), & &1["fill"]) ==
                 Enum.map(tags(component, "path"), & &1["fill"])

        position = &Enum.map(tags(&1, "text"), fn t -> {num(t["x"]), num(t["y"])} end)
        assert position.(svg) == position.(component)
        assert texts(svg) == texts(component)
      end

      # Seven nodes below the root, one of them zero-valued and therefore undrawn.
      assert length(tags(layer(:sunburst_chart, %{data: @tree_hierarchy}), "path")) == 6
    end
  end

  defp has_function?(term) when is_function(term), do: true
  defp has_function?(%_{} = struct), do: struct |> Map.from_struct() |> has_function?()
  defp has_function?(map) when is_map(map), do: Enum.any?(map, &has_function?/1)
  defp has_function?(list) when is_list(list), do: Enum.any?(list, &has_function?/1)
  defp has_function?(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> has_function?()
  defp has_function?(_scalar), do: false
end
