defmodule Visualize.Chart.MergedPaintsTest do
  @moduledoc """
  #711, D-186: a gradient written in place is hoisted from the paint its style resolved to.
  A style that extends, stacks or defaults a gradient and changes its stops, its geometry
  or its type draws on SVG — every `url(#id)` it writes declared under the frame's `defs` —
  and on both canvases, in the stops it resolved to (spec/14 §2.7, §3.2). A compiled chart
  whose later tick first draws a merged paint declares it in that tick (#721, D-190).
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Visualize.Color, only: [color: 1, darken: 2]

  alias Visualize.Backend.CanvasBinary.Decoder
  alias Visualize.Chart

  # The base gradients a style may write in place, by the part that may hold each.
  @bases [
    fill: %{type: :radial, color: ["#ffeeee", "#aa0000"], center: [0.35, 0.3], radius: 0.7},
    fill: %{type: :linear, color: ["#eeeeff", "#0000aa"], angle: 90},
    fill: %{type: :hatch, pattern: :crosshatch, color: "#00aa00", spacing: 6},
    stroke: %{type: :linear, color: ["#eeeeff", "#0000aa"], width: 3}
  ]

  # What the second style says over the base's part; `stops` names the color the merged
  # paint's first stop must draw in, where the change sets one.
  defp changes(%{type: :hatch}) do
    [
      {%{type: :hatch, color: "#123456"}, "#123456"},
      {%{pattern: :dots}, nil},
      {%{type: :hatch, pattern: :lines, angle: 30}, nil},
      {%{type: :linear, color: ["#123456", "#000000"]}, "#123456"}
    ]
  end

  defp changes(%{type: type}) do
    [
      {%{color: ["#123456", "#654321"]}, "#123456"},
      {%{type: type, color: [color(:blue), color(:blue) |> darken(0.3)]}, "#3b6fa8"},
      {%{opacity: 0.5}, nil},
      {%{angle: 45, center: [0.5, 0.5]}, nil},
      {%{type: other(type), color: ["#123456", "#000000"]}, "#123456"}
    ]
  end

  defp other(:linear), do: :radial
  defp other(:radial), do: :linear

  # How the change reaches the second mark: through `extends`, a stack of names, a stack
  # with an inline node, a named style that is a list, a field entry naming the derived
  # style, or the design's defaults under the site.
  @ways [:extends, :stack, :inline_stack, :list_style, :field, :defaults]

  defp design(key, base, change, way) do
    {styles, site, defaults} =
      case way do
        :extends -> {%{a: %{key => base}, b: %{key => change, extends: :a}}, :b, nil}
        :stack -> {%{a: %{key => base}, b: %{key => change}}, [:a, :b], nil}
        :inline_stack -> {%{a: %{key => base}}, [:a, %{key => change}], nil}
        :list_style -> {%{a: %{key => base}, b: [:a, %{key => change}]}, :b, nil}
        :field -> {%{a: %{key => base}, b: %{key => change, extends: :a}}, {:field, :look}, nil}
        :defaults -> {%{b: %{key => change}}, :b, %{key => base}}
      end

    %{
      version: 3,
      sources: %{cells: %{fields: [:look]}},
      styles: styles,
      frames: %{
        main: %{
          kind: :cartesian,
          scales: %{x: %{kind: :linear, domain: [0, 1]}, y: %{kind: :linear, domain: [0, 1]}}
        }
      },
      marks: [
        %{type: :rect, data: :cells, channels: %{x0: 0.1, x1: 0.9, y0: 0.1, y1: 0.9}, style: site}
      ]
    }
    |> then(fn d -> if defaults, do: Map.put(d, :defaults, defaults), else: d end)
  end

  defp case_gen do
    gen all(
          {key, base} <- member_of(@bases),
          {change, first} <- member_of(changes(base)),
          way <- member_of(@ways)
        ) do
      {key, base, change, first, way}
    end
  end

  # The ids the SVG references and the ids its defs declare.
  defp referenced(svg),
    do: ~r/url\(#([^)]+)\)/ |> Regex.scan(svg, capture: :all_but_first) |> List.flatten()

  defp declared(svg),
    do:
      ~r/<(?:linearGradient|radialGradient|pattern)[^>]*\bid="([^"]+)"/
      |> Regex.scan(svg, capture: :all_but_first)
      |> List.flatten()

  property "a merged gradient draws on SVG and both canvases, in the stops it resolved to" do
    check all({key, base, change, first, way} <- case_gen(), max_runs: 200) do
      design = design(key, base, change, way)
      {:ok, applied} = Chart.apply(Chart.from_map!(design), sources: %{cells: [%{look: :b}]})
      label = inspect({key, base.type, change, way})

      svg = Chart.render(applied, resolve: :literal)
      refs = referenced(svg)
      assert refs != [], label
      assert refs -- declared(svg) == [], label

      commands = Chart.render(applied, backend: :canvas, format: :json)
      assert commands =~ ~r/"(linearGradient|radialGradient|hatchPattern)"/, label

      records = Decoder.decode(Chart.render(applied, backend: :canvas, format: :binary))
      assert Enum.any?(records, &match?({:paint, _, _}, &1)), label

      if first do
        assert String.downcase(svg) =~ first, label
        [r, g, b] = for i <- [1, 3, 5], do: String.to_integer(String.slice(first, i, 2), 16)
        assert commands =~ "rgba(#{r},#{g},#{b},", label
      end
    end
  end

  test "a gradient extended and changed is a definition of its own beside the base's" do
    styles = %{
      a: %{fill: %{type: :radial, color: ["#ffeeee", "#aa0000"], center: [0.35, 0.3]}},
      b: %{extends: :a, fill: %{type: :radial, color: ["#eeeeff", "#0000aa"]}}
    }

    design =
      design(:fill, styles.a.fill, styles.b.fill, :extends)
      |> Map.update!(:marks, fn [mark] ->
        [%{mark | style: :a}, %{mark | style: :b, channels: %{mark.channels | x0: 0.5}}]
      end)

    {:ok, applied} = Chart.apply(Chart.from_map!(design), sources: %{cells: [%{look: :b}]})
    svg = Chart.render(applied, resolve: :literal)

    assert [_, _] = declared(svg)
    # The derived look keeps its parent's center and draws its own stops.
    assert svg =~
             ~r/<radialGradient cx="0.35" cy="0.3"[^>]*>(<stop[^>]*>)*<stop offset="0%" stop-color="#eeeeff"/
  end

  # -- a compiled chart's later tick (#721, D-190) -----------------------------------------

  # The base's style under a field entry, which the first rows point at a style that leaves
  # the base's paint alone and a later row at the change: the merged paint is in no table.
  defp stacked(key, base, change) do
    design(key, base, change, :stack)
    |> Map.put(:styles, %{a: %{key => base}, b: %{key => change}, c: %{opacity: 0.9}})
    |> Map.put(:sources, %{cells: %{fields: [:x, :look]}})
    |> Map.update!(:marks, fn [mark] ->
      [%{mark | style: [:a, {:field, :look}], channels: %{mark.channels | x0: :x}}]
    end)
  end

  @first %{cells: [%{x: 0.1, look: :c}]}
  @later %{cells: [%{x: 0.1, look: :c}, %{x: 0.3, look: :b}]}

  defp compiled(design, sources) do
    {:ok, %{main: compiled}} = Chart.compile(design, sources: sources)
    compiled
  end

  defp undeclared(svg), do: Enum.uniq(referenced(svg)) -- declared(svg)

  property "a paint a later tick first draws is declared in every SVG output of that tick" do
    check all(
            {key, base} <- member_of(@bases),
            {change, _first} <- member_of(changes(base)),
            max_runs: 60
          ) do
      design = stacked(key, base, change)
      compiled = compiled(design, @first)
      label = inspect({key, base.type, change})

      {group, _} = Chart.Compiled.step(compiled, @later, at: 0)
      assert undeclared(Visualize.Render.to_string(group)) == [], label
      assert undeclared(Chart.Compiled.svg(compiled, @later)) == [], label

      # The static layer and the tick's SVG are two documents of one page.
      {payload, _} = Chart.Compiled.tick(compiled, @later, at: 0)
      assert undeclared(Chart.Compiled.static(compiled) <> payload.svg) == [], label
    end
  end

  test "a later tick's merged paint was the one the static defs lacked, and the canvas draws it" do
    base = %{type: :radial, color: ["#ffeeee", "#aa0000"]}
    design = stacked(:fill, base, %{color: ["#123456", "#654321"]})
    compiled = compiled(design, @first)

    {group, _} = Chart.Compiled.step(compiled, @later, at: 0)
    svg = Visualize.Render.to_string(group)
    [new] = Enum.uniq(referenced(svg)) -- declared(Chart.Compiled.static(compiled))
    assert new in declared(svg)
    assert String.downcase(svg) =~ "#123456"

    # The tick's own defs follow the compiled ones: two `defs`, the new paint in the second.
    assert [_compiled, %{type: :defs, children: [paint]} | _] = group.children
    assert paint.attrs.id == new

    # `render/2`'s SVG layer carries it too; the canvas reads the paint from the element.
    map = Chart.Compiled.render(compiled, @later)
    assert [%{type: :defs} | _] = map.dynamic_svg

    {:ok, applied} = Chart.apply(Chart.from_map!(design), sources: @later)
    commands = Chart.render(applied, backend: :canvas, format: :json)

    assert commands =~ "rgba(18,52,86,"
  end

  test "a tick that draws only declared paints is the output it was: one defs, first" do
    base = %{type: :radial, color: ["#ffeeee", "#aa0000"]}
    compiled = compiled(stacked(:fill, base, %{color: ["#123456", "#654321"]}), @first)

    {group, _} = Chart.Compiled.step(compiled, @first, at: 0)
    assert [%{type: :defs}] = Enum.filter(group.children, &(&1.type == :defs))
    assert hd(group.children) == hd(compiled.defs)

    {payload, _} = Chart.Compiled.tick(compiled, @first, at: 0)
    refute payload.svg =~ "<defs"
  end

  test "a style that is only part of a paint compiles, and draws once a stack completes it" do
    # `:b` alone is a hatch with no color: whole only over `:a`. Compiling built every
    # style's in-place paint alone and raised on it (D-190).
    base = %{type: :hatch, pattern: :crosshatch, color: "#00aa00", spacing: 6}
    compiled = compiled(stacked(:fill, base, %{type: :hatch, pattern: :lines, angle: 30}), @first)

    {group, _} = Chart.Compiled.step(compiled, @later, at: 0)
    svg = Visualize.Render.to_string(group)
    assert [_, _] = declared(svg)
    assert undeclared(svg) == []
  end
end
