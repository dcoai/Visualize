defmodule Visualize.SVG.BridgeTest do
  @moduledoc """
  The two SVG serialisers agree (spec/02 §5, spec/09 §2; D-11, D-12, D-34): the IR backend
  and the HEEx bridge (`from_ir/1` then `Visualize.SVG.Renderer`) emit one markup for one
  scene, and every `d` string comes from `Visualize.IR.Path.to_string/1`.
  """
  use ExUnit.Case, async: true

  alias Visualize.Backend
  alias Visualize.IR.{Element, Path, Transform}
  alias Visualize.Render
  alias Visualize.SVG

  doctest Visualize.SVG
  doctest Visualize.SVG.Element
  doctest Visualize.SVG.Path
  doctest Visualize.SVG.Renderer

  defp scene do
    curve =
      Path.new()
      |> Path.move_to(0, 0.5)
      |> Path.curve_to(10, 20.25, 30.125, -0.00001, 40, 1.0e-5)
      |> Path.smooth_curve_to(50, 60, 70, 80)
      |> Path.arc_to(20, 10, 0.0, 0, 1, 90, 90)
      |> Path.line_to_rel(1, 2)
      |> Path.horizontal_to(100)
      |> Path.vertical_to_rel(-3)
      |> Path.close()

    gradient =
      Element.linear_gradient("fade",
        x1: 0,
        y1: 0,
        x2: 1,
        y2: 0,
        stops: [Element.stop("0%", "#fff"), Element.stop("100%", "#000", opacity: 0.5)]
      )

    group =
      Element.group(
        [
          Element.path(curve, %{
            stroke: "steelblue",
            fill: :none,
            stroke_width: 1.5,
            stroke_linecap: :round
          }),
          Element.rect(1, 2, 3, 4, %{fill: "url(#fade)", fill_opacity: 0.5, class: "bar"}),
          Element.circle(5, 6, 7, %{fill: :current_color}),
          Element.line(0, 0, 10, 10, %{stroke: "#000", stroke_dasharray: "2,2"}),
          Element.text("a < b & \"c\"", 1, 2, %{
            font_size: 12,
            text_anchor: :middle,
            dominant_baseline: :hanging
          }),
          Element.polyline([{0, 0}, {1.5, 2}, {3, -0.0}], %{stroke: "red"}),
          Element.polygon([{0, 0}, {10, 0}, {5, 8}], %{fill: "green"}),
          Element.image("x.png", 0, 0, 10, 10)
        ],
        transform: Transform.translate(40, 20) |> Transform.rotate(15) |> Transform.scale(2),
        style: %{opacity: 0.9},
        attrs: %{class: "plot"}
      )

    Element.root(800, 600, view_box: "0 0 400 300", children: [Element.defs([gradient]), group])
  end

  test "the IR backend and the HEEx bridge emit identical markup for one scene" do
    element = scene()
    assert Render.to_svg_string(element) == element |> SVG.Element.from_ir() |> SVG.to_string()
  end

  test "a root renders xmlns and viewBox on both paths, never view-box" do
    root = Element.root(10, 20, view_box: "0 0 5 10")
    backend = Render.to_svg_string(root)
    bridge = root |> SVG.Element.from_ir() |> SVG.to_string()

    for markup <- [backend, bridge] do
      assert markup =~ ~s( xmlns="http://www.w3.org/2000/svg")
      assert markup =~ ~s( viewBox="0 0 5 10")
      refute markup =~ "view-box"
    end
  end

  test "a responsive root scales by CSS on both paths; a plain root emits neither attribute" do
    plain = Element.root(10, 20)
    responsive = Element.root(10, 20, responsive: true)
    ratio = Element.root(10, 20, preserve_aspect_ratio: "none")

    for render <- [&Render.to_svg_string/1, &(&1 |> SVG.Element.from_ir() |> SVG.to_string())] do
      refute render.(plain) =~ "preserveAspectRatio"
      refute render.(plain) =~ "style="
      assert render.(responsive) =~ ~s( preserveAspectRatio="xMidYMid meet")
      assert render.(responsive) =~ ~s( style="width:100%;height:auto")
      assert render.(responsive) =~ ~s( width="10")
      assert render.(ratio) =~ ~s( preserveAspectRatio="none")
      refute render.(ratio) =~ "style="
    end

    assert Element.root(1, 1, responsive: true, preserve_aspect_ratio: "xMinYMin slice").attrs ==
             %{
               width: 1,
               height: 1,
               view_box: "0 0 1 1",
               role: "img",
               preserve_aspect_ratio: "xMinYMin slice",
               style: "width:100%;height:auto"
             }
  end

  test "a named root has a title, a desc and aria-labelledby on both paths (D-56)" do
    named = Element.root(10, 20, title: "Sales", description: "Monthly sales, 2024 & 2025")
    plain = Element.root(10, 20)
    only_title = Element.root(10, 20, title: "Sales", id: "chart")

    for render <- [&Render.to_svg_string/1, &(&1 |> SVG.Element.from_ir() |> SVG.to_string())] do
      svg = render.(named)
      [_, id] = Regex.run(~r/ id="([^"]+)"/, svg)
      assert String.starts_with?(id, "vis-")
      assert svg =~ ~s( role="img")
      assert svg =~ ~s( aria-labelledby="#{id}-title #{id}-desc")

      assert svg =~
               ~s(><title id="#{id}-title">Sales</title><desc id="#{id}-desc">Monthly sales, 2024 &amp; 2025</desc>)

      assert render.(plain) =~ ~s( role="img")
      refute render.(plain) =~ "aria-labelledby"
      refute render.(plain) =~ "<title"
      refute render.(plain) =~ ~s( id=")

      assert render.(only_title) =~ ~s( id="chart" role="img")
      assert render.(only_title) =~ ~s( aria-labelledby="chart-title")
      assert render.(only_title) =~ ~s(<title id="chart-title">Sales</title>)
      refute render.(only_title) =~ "<desc"
    end

    assert Element.root(1, 1, title: "a").attrs.id == Element.root(2, 2, title: "a").attrs.id
    refute Element.root(1, 1, title: "a").attrs.id == Element.root(1, 1, title: "b").attrs.id

    assert [%Element{type: :title}, %Element{type: :desc}, %Element{type: :group}] =
             Element.root(1, 1, title: "t", description: "d", children: [Element.group()]).children
  end

  test "camel-cased SVG attributes are not hyphenated; presentation attributes are" do
    assert SVG.Renderer.attribute_name(:view_box) == "viewBox"
    assert SVG.Renderer.attribute_name(:preserve_aspect_ratio) == "preserveAspectRatio"
    assert SVG.Renderer.attribute_name(:clip_path_units) == "clipPathUnits"
    assert SVG.Renderer.attribute_name(:clip_path) == "clip-path"
    assert SVG.Renderer.attribute_name(:stroke_width) == "stroke-width"
    assert SVG.Renderer.attribute_name(:viewBox) == "viewBox"
  end

  test "nil attributes are omitted and stop is self-closing in the bridge renderer" do
    element = SVG.Element.new(:stop, %{offset: "0%", stop_color: nil})
    assert SVG.to_string(element) == ~s(<stop offset="0%"/>)
  end

  describe "one d serialiser (D-12)" do
    @extreme %Path{
      commands: [{:M, 1.0e20, 1.0e-5}, {:L, 0.33333333, -0.00004}, {:A, 1.5, 2, 0.0, 0, 1, 3, 4}]
    }

    test "path_data/1, SVG.Path.to_string/1 and String.Chars equal IR.Path.to_string/1" do
      d = Path.to_string(@extreme)
      assert d == "M100000000000000000000,0L0.3333,0A1.5,2,0,0,1,3,4"
      assert Backend.SVG.path_data(@extreme) == d
      assert SVG.Path.to_string(@extreme) == d
      assert to_string(@extreme) == d
    end

    test "Render.path_data/2 with the SVG backend is the same string" do
      assert Render.path_data(@extreme, backend: :svg) == Path.to_string(@extreme)
    end
  end

  test "the backend serialises a transform as IR.Transform.to_string/1 does" do
    t = Transform.translate(1, 2) |> Transform.scale(2) |> Transform.rotate(-0.0)
    element = Element.rect(0, 0, 1, 1) |> Element.set_transform(t)
    assert Render.to_svg_string(element) =~ ~s|transform="translate(1,2) scale(2) rotate(0)"|
  end
end
