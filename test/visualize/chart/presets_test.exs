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
  alias Visualize.Chart.{Frame, Presets, Style}

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
      assert chart.sources == %{"data" => %{fields: hd(Map.values(design.sources)).fields}}
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
    assert design.frames["main"].margin == %{top: 20, right: 20, bottom: 30, left: 40}
    assert design.frames["main"].scales["x"] == %{kind: :band, padding: 0.1}

    for f <- [&Presets.defaults/1, &Presets.design(&1, %{}), &Presets.sources(&1, %{})] do
      assert_raise ArgumentError, ~r/not a preset/, fn -> f.(:no_such_chart) end
    end
  end

  test "the x scale of a series chart follows the first datum (spec/10 §2.2)" do
    line = fn data ->
      Presets.line_chart(%{data: data, x: & &1.x, y: & &1.y}).frames["main"].scales["x"]
    end

    assert line.([%{x: @t0, y: 1}]) == %{kind: :time}
    assert line.([%{x: ~D[2024-01-01], y: 1}]) == %{kind: :time}
    assert line.([%{x: 3, y: 1}]) == %{kind: :linear}
    assert line.([%{x: "a", y: 1}]) == %{kind: :band, padding: 0.1}
    assert line.([]) == %{kind: :linear}
  end

  test "the assigns reach the design: colors, options, labels, meta and the transform" do
    design = Presets.line_chart(Map.put(assigns().line_chart, :stroke, "tomato"))

    assert Style.project(design.styles["line"]) == %{
             stroke: "tomato",
             stroke_width: 2,
             curve: :linear
           }

    assert Style.project(design.styles["point"]) == %{fill: "tomato"}
    assert [%{type: :line}, %{type: :circle, options: %{radius: 4}}] = design.marks
    assert design.labels == [%{anchor: {:axis, "x"}, text: ["t"]}]

    pie = Presets.pie_chart(assigns().pie_chart)
    assert pie.meta == %{name: "Pie"}
    assert pie.frames["main"].kind == :polar

    assert [%{options: %{outer_radius: 190.0, inner_radius: 0, pad_angle: 0.02}, label: label}] =
             pie.marks

    assert label.text == [{:field, "label"}]
    # A label on a fill reads on it and fits it, as the gallery's pie's (D-123, #494).
    assert label.fit == :hide
    assert Style.project(pie.styles["slice_label"]) == %{fill: :contrast, font_size: :label_size}

    refute Map.has_key?(
             hd(Presets.pie_chart(Map.put(assigns().pie_chart, :show_labels, false)).marks),
             :label
           )

    stacked = Presets.stacked_bar_chart(assigns().stacked_bar_chart)

    assert stacked.frames["main"].scales["color"] == %{
             kind: :ordinal,
             domain: ["apples", "pears"],
             range: :category10
           }

    assert [%{data: %{source: "data", transforms: [%{op: :stack, fields: ["apples", "pears"]}]}}] =
             stacked.marks

    tree =
      Presets.tree_diagram(%{data: @hierarchy, orientation: :vertical, width: 400, height: 300})

    assert [%{type: :path, data: %{transforms: [links]}}, %{type: :circle, channels: channels}] =
             tree.marks

    assert links == %{
             op: :tree,
             id: "id",
             by: "parent",
             size: [160, 260],
             orientation: :vertical,
             output: :links
           }

    assert channels == %{x: "x", y: "y"}
    assert Enum.at(tree.marks, 1).label == %{text: [{:field, "label"}], anchor: :middle}

    horizontal = Presets.tree_diagram(%{data: @hierarchy})
    assert hd(horizontal.marks).data.transforms |> hd() |> Map.fetch!(:orientation) == :horizontal
    assert Enum.at(horizontal.marks, 1).channels == %{x: "y", y: "x"}

    # The links are open cubics: stroked, never filled and closed by their chord (#345).
    assert Style.project(tree.styles["link"]).fill == :none

    {:ok, applied} =
      Chart.apply(tree, sources: Presets.sources(:tree_diagram, %{data: @hierarchy}))

    [link_group] = Regex.run(~r/<g class="mark mark-path"[^>]*>/, Chart.render(applied))
    assert link_group =~ ~s(fill="none")

    treemap = Presets.treemap_chart(assigns().treemap_chart)

    assert [%{data: %{transforms: [%{op: :treemap}, leaves]}, label: cell_label}] =
             treemap.marks

    assert leaves == %{op: :filter, field: "height", test: :eq, value: 0}
    # A cell's label is its mark's, read and fitted as the gallery's treemap's (#497).
    assert cell_label == %{
             text: [{:field, "label"}],
             anchor: :middle,
             fit: :truncate,
             style: "cell_label"
           }

    assert Style.project(treemap.styles["cell_label"]) == %{
             fill: :contrast,
             font_size: :label_size
           }

    sunburst = Presets.sunburst_chart(assigns().sunburst_chart)
    assert sunburst.meta == %{description: ["Rings"]}
    assert sunburst.frames["main"].scales["color"].domain == [0, 1]

    assert [%{channels: arc_channels, label: arc_label, data: %{transforms: steps}}] =
             sunburst.marks

    assert [%{op: :partition, size: [angle, 300.0]}, below_root, positive] = steps
    assert_in_delta angle, 2 * :math.pi(), 1.0e-9
    assert below_root == %{op: :filter, field: "depth", test: :gt, value: 0}
    assert positive == %{op: :filter, field: "value", test: :gt, value: 0}
    assert arc_channels == %{start: "x0", end: "x1", inner: "y0", outer: "y1"}

    assert arc_label == %{
             text: [{:field, "label"}],
             anchor: :middle,
             fit: :truncate,
             style: "arc_label"
           }

    assert Style.project(sunburst.styles["arc_label"]) == %{
             fill: :contrast,
             font_size: :label_size
           }
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

  test "every preset draws its marks on both canvas formats (spec/09 §3.3, §4.4, #231)" do
    for name <- Presets.names() do
      a = Map.fetch!(assigns(), name)
      chart = Chart.from_map!(Presets.design(name, a))
      sources = Presets.sources(name, a)

      applied = %Visualize.Chart.Applied{
        chart: chart,
        sources: sources,
        frame: Frame.new(chart, sources: sources)
      }

      marks = length(chart.marks)

      # The JS commands: a fill or a stroke per mark element, decided by the effective
      # style — the mark group's paint reaches its children (D-111).
      commands =
        Visualize.Chart.generate(applied, resolve: :literal)
        |> Visualize.Backend.Canvas.render_element(format: :commands)

      draws = Enum.count(commands, &(&1 in [{:fill, []}, {:stroke, []}]))
      assert draws >= marks, "#{name}: #{draws} draw calls for #{marks} marks"

      # The binary stream the same: a draw record per mark at least.
      binary = Chart.render(applied, backend: :canvas, format: :binary)
      records = Visualize.Backend.CanvasBinary.Decoder.decode(binary)
      assert Enum.count(records, &(&1 in [:fill, :stroke])) >= marks, "#{name}"
    end
  end

  test "an empty color list is an ArgumentError naming the scale" do
    a = Map.put(assigns().pie_chart, :colors, [])

    assert_raise ArgumentError, ~r/scale "color": an empty range/, fn ->
      Frame.new(Chart.from_map!(Presets.pie_chart(a)), sources: Presets.sources(:pie_chart, a))
    end
  end

  test "a preset design re-framed as a facet renders one panel per value (spec/14 §4.6)" do
    a = %{data: @categories, x: & &1.name, y: & &1.value}
    design = Presets.bar_chart(a)
    fields = design.sources["data"].fields ++ [:region]
    facet = Map.merge(design.frames["main"], %{kind: :facet, facet: %{by: :region, columns: 2}})
    design = %{design | frames: %{main: facet}, sources: %{data: %{fields: fields}}}
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
      defaults = Presets.defaults(name)
      size = {Map.get(a, :width, defaults.width), Map.get(a, :height, defaults.height)}
      Frame.render(Frame.new(chart, sources: sources, size: size), sources: sources)
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

        centers = Enum.map(tags(svg, "circle"), &{num(&1["cx"]), num(&1["cy"])})

        assert centers ==
                 for(
                   [_, x, y] <- Regex.scan(~r/translate\(([^,]+), ([^)]+)\)/, component),
                   do: {x, y}
                 )
                 |> tl()

        assert texts(svg) == texts(component)
        assert length(centers) == length(Presets.sources(:tree_diagram, a).data)
      end
    end

    test "the treemap's cells and labels are the component's, in count and geometry" do
      for a <- [%{data: @tree_hierarchy}, %{data: @root_only}] do
        svg = layer(:treemap_chart, a)
        component = render_component(&Tree.treemap_chart/1, a)

        geometry = fn markup ->
          for r <- tags(markup, "rect"), do: Map.new(~w(x y width height), &{&1, num(r[&1])})
        end

        assert geometry.(svg) == geometry.(component)
        # Each label where the layer put it, in the ink it chose for its cell (#497).
        label = &Enum.map(tags(&1, "text"), fn t -> {num(t["x"]), num(t["y"]), t["fill"]} end)
        assert label.(svg) == label.(component)
        assert texts(svg) == texts(component)
        assert texts(component) != []
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
        # Each label in the ink the layer chose for its arc (#494).
        ink = &Enum.map(tags(&1, "text"), fn t -> t["fill"] end)
        assert ink.(svg) == ink.(component)
        assert texts(svg) == texts(component)
      end

      # Seven nodes below the root, one of them zero-valued and therefore undrawn.
      assert length(tags(layer(:sunburst_chart, %{data: @tree_hierarchy}), "path")) == 6
    end
  end

  describe "the pie's, the sunburst's and the treemap's labels read on their fills (#494, #497, D-123)" do
    import Phoenix.LiveViewTest, only: [render_component: 2]

    alias Visualize.{Color, Theme}
    alias Visualize.Components.Tree
    alias Visualize.IR.Element

    @aa 4.5

    # Ten slices and ten branches, so every color of `:category10` is under a label.
    @slices for i <- 0..9, do: %{name: "slice #{i}", value: 10 + i}
    @branches %{
      name: "root",
      children:
        for i <- 0..9 do
          %{name: "b#{i}", children: [%{name: "b#{i}.0", value: 6}, %{name: "b#{i}.1", value: 4}]}
        end
    }

    defp ink_cases do
      [
        pie_chart: %{data: @slices, value: & &1.value, label: & &1.name},
        sunburst_chart: %{data: @branches},
        treemap_chart: %{data: @branches}
      ]
    end

    # The preset drawn by the layer on `theme` in `mode`, its label's `fit` replaced.
    defp drawn(name, assigns, theme, mode, fit) do
      design =
        name
        |> Presets.design(assigns)
        |> Map.update!(:marks, fn [mark] -> [put_in(mark, [:label, :fit], fit)] end)

      sources = Presets.sources(name, assigns)
      defaults = Presets.defaults(name)
      chart = Chart.from_map!(design)

      frame =
        Frame.new(chart, sources: sources, theme: theme, size: {defaults.width, defaults.height})

      Frame.generate(frame, sources: sources, resolve: mode)
    end

    # Every labeled mark's {element, its group's style, its label}, in drawing order.
    defp labeled(%Element{
           children: [
             %Element{style: %{class: "mark-elements"} = group, children: elements},
             %Element{style: %{class: "mark-labels"}, children: labels}
           ]
         }) do
      texts = Enum.filter(labels, &(&1.type == :text))
      assert length(elements) == length(texts)
      Enum.zip_with(elements, texts, &{&1, group, &2})
    end

    defp labeled(%Element{children: children}), do: Enum.flat_map(children, &labeled/1)

    # The literal a fill is drawn in: a CSS reference by its fallback.
    defp literal("var(" <> rest) do
      [_name, fallback] = String.split(rest, ",", parts: 2)
      fallback |> String.trim() |> String.replace_suffix(")", "")
    end

    defp literal(color) when is_binary(color), do: color

    test "the presets ink their labels by contrast and fit them as the gallery does" do
      assert Presets.pie_chart(Keyword.fetch!(ink_cases(), :pie_chart)).marks
             |> hd()
             |> get_in([:label, :fit]) == :hide

      assert Presets.sunburst_chart(%{data: @branches}).marks |> hd() |> get_in([:label, :fit]) ==
               :truncate

      assert Presets.treemap_chart(%{data: @branches}).marks |> hd() |> get_in([:label, :fit]) ==
               :truncate
    end

    test "a root-only treemap's label holds 4.5:1 against the :grid its cell is filled with" do
      # Its cell's fill in the layer is `:none` (D-122), so the label is inked against the
      # background; the component fills the cell `:grid` (spec/10 §3.3, #497).
      for theme <- [Theme.default(), Theme.dark()] do
        svg = render_component(&Tree.treemap_chart/1, %{data: @root_only, theme: theme})
        [_, fill] = Regex.run(~r/<text[^>]* fill="([^"]*)"[^>]*>root<\/text>/, svg)
        ratio = Color.contrast(Color.parse(fill), Color.parse(theme.grid))
        assert ratio >= @aa, "#{theme.background}: #{fill} on #{theme.grid} is #{ratio}:1"
      end
    end

    test "every label holds 4.5:1 against its element's fill on both built-in themes" do
      for {name, assigns} <- ink_cases(),
          theme <- [Theme.default(), Theme.dark()],
          mode <- [:css, :literal] do
        # Every element labeled — `fit: :none` — so no label is excused by being hidden.
        all = labeled(drawn(name, assigns, theme, mode, :none))
        assert length(all) >= 10, "#{name}: #{length(all)} labels"

        fills = MapSet.new(all, fn {element, _group, _text} -> literal(element.style.fill) end)
        assert MapSet.size(fills) == 10, "#{name}: every :category10 color under a label"

        for {element, _group, text} <- all do
          under = element.style.fill |> literal() |> Color.parse()
          ratio = Color.contrast(Color.parse(text.style.fill), under)

          assert ratio >= @aa,
                 "#{name} #{theme.background} #{mode}: #{text.content} in #{text.style.fill} " <>
                   "on #{Color.to_hex(under)} is #{Float.round(ratio, 2)}:1"
        end
      end
    end

    test "the component prints the labels the layer fitted, each in the layer's ink" do
      for {name, assigns} <- ink_cases(), theme <- [nil, Theme.dark()] do
        assigns = Map.put(assigns, :theme, theme)

        component =
          case name do
            :pie_chart -> render_component(&Visualize.Components.pie_chart/1, assigns)
            :sunburst_chart -> render_component(&Tree.sunburst_chart/1, assigns)
            :treemap_chart -> render_component(&Tree.treemap_chart/1, assigns)
          end

        fit = Presets.design(name, assigns).marks |> hd() |> get_in([:label, :fit])
        layer = drawn(name, assigns, theme || Theme.default(), :css, fit)
        texts = for t <- fitted(layer), do: {t.content, t.style.fill}

        printed =
          for [_, fill, content] <-
                Regex.scan(~r/<text[^>]*fill="([^"]*)"[^>]*>([^<]*)<\/text>/, component),
              do: {content, fill}

        assert printed == texts
        assert printed != []
        # The ink is a literal, chosen per element, never the background slot's reference.
        refute Enum.any?(printed, fn {_content, fill} -> String.starts_with?(fill, "var(") end)
      end
    end

    # The texts of every mark's labels' group: what the fit kept.
    defp fitted(%Element{style: %{class: "mark-labels"}, children: labels}),
      do: Enum.filter(labels, &(&1.type == :text))

    defp fitted(%Element{children: children}), do: Enum.flat_map(children, &fitted/1)
  end

  defp has_function?(term) when is_function(term), do: true
  defp has_function?(%_{} = struct), do: struct |> Map.from_struct() |> has_function?()
  defp has_function?(map) when is_map(map), do: Enum.any?(map, &has_function?/1)
  defp has_function?(list) when is_list(list), do: Enum.any?(list, &has_function?/1)
  defp has_function?(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> has_function?()
  defp has_function?(_scalar), do: false
end
