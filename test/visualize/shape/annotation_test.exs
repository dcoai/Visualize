defmodule Visualize.Shape.AnnotationTest do
  @moduledoc "The `Rule` and `XBand` annotation marks (spec/04 §12–13, D-27)."
  use ExUnit.Case, async: true

  alias Visualize.Backend.SVG
  alias Visualize.IR.Element
  alias Visualize.Scale
  alias Visualize.Shape
  alias Visualize.Shape.{Rule, XBand}

  @t0 ~U[2024-01-01 00:00:00Z]
  @t1 ~U[2024-01-02 00:00:00Z]
  @noon ~U[2024-01-01 12:00:00Z]
  @six ~U[2024-01-01 06:00:00Z]

  @label_style %{
    font_size: 10,
    font_family: "sans-serif",
    text_anchor: :start,
    fill: :current_color
  }

  defp time_scale, do: Scale.time() |> Scale.domain([@t0, @t1]) |> Scale.range([0, 240])
  defp linear, do: Scale.linear() |> Scale.domain([0, 10]) |> Scale.range([0, 100])

  describe "Rule.generate/2" do
    test "a bare value through a time scale, with a label at the top" do
      [group] =
        Rule.new()
        |> Rule.scale(time_scale())
        |> Rule.y0(150)
        |> Rule.y1(10)
        |> Rule.label("deploy")
        |> Rule.generate([@noon])

      assert %Element{type: :group, style: %{class: "rule"}, children: [line, text]} = group

      assert line == %Element{
               type: :line,
               attrs: %{x1: 120.0, y1: 150, x2: 120.0, y2: 10},
               style: %{stroke: :current_color, stroke_width: 1}
             }

      assert text == %Element{
               type: :text,
               attrs: %{x: 120.0, y: 10, dx: 3, dy: 10},
               style: @label_style,
               content: "deploy"
             }
    end

    test "map data with accessors through a linear scale" do
      events = [%{at: 2, name: "a"}, %{at: 7, name: nil}]

      [first, second] =
        Rule.new()
        |> Rule.x(:at)
        |> Rule.scale(linear())
        |> Rule.y1(:y)
        |> Rule.label(:name)
        |> Rule.generate(Enum.map(events, &Map.put(&1, :y, 50)))

      assert [%{attrs: %{x1: 20.0, y2: 50}}, %{content: "a"}] = first.children
      assert [%{attrs: %{x1: 70.0}}] = second.children
    end

    test "without a scale the value is a pixel coordinate; nil clears the label" do
      [group] = Rule.new() |> Rule.label("x") |> Rule.label(nil) |> Rule.generate([33])
      assert [%{type: :line, attrs: %{x1: 33, y1: 0, x2: 33, y2: 100}}] = group.children
    end

    test "renders as a group" do
      [group] = Rule.new() |> Rule.label("now") |> Rule.generate([33])
      svg = group |> SVG.render_element() |> IO.iodata_to_binary()
      assert svg =~ ~s(<g class="rule">)
      assert svg =~ ~s(stroke="currentColor")
      assert svg =~ ~r/<text [^>]*>now<\/text>/
    end

    test "an empty list yields []" do
      assert Rule.new() |> Rule.generate([]) == []
    end
  end

  describe "XBand.generate/2" do
    test "a tuple through a time scale, with the brush's fill and a label" do
      [group] =
        XBand.new()
        |> XBand.scale(time_scale())
        |> XBand.y1(80)
        |> XBand.label("incident")
        |> XBand.generate([{@noon, @six}])

      assert %Element{type: :group, style: %{class: "x-band"}, children: [rect, text]} = group

      assert rect == %Element{
               type: :rect,
               attrs: %{x: 60.0, y: 0, width: 60.0, height: 80},
               style: %{fill: "rgba(119, 119, 119, 0.2)"}
             }

      assert text.attrs == %{x: 60.0, y: 0, dx: 3, dy: 10}
      assert text.content == "incident"
    end

    test "fill and label accessors read the datum; a nil fill omits the key" do
      windows = [%{from: 1, to: 3, color: "pink", note: "w1"}, %{from: 5, to: 6}]

      [first, second] =
        XBand.new()
        |> XBand.x0(:from)
        |> XBand.x1(:to)
        |> XBand.scale(linear())
        |> XBand.fill(:color)
        |> XBand.label(:note)
        |> XBand.generate(windows)

      assert [%{attrs: %{x: 10.0, width: 20.0}, style: %{fill: "pink"}}, %{content: "w1"}] =
               first.children

      assert [%{attrs: %{x: 50.0, width: 10.0}, style: style}] = second.children
      assert style == %{}
    end

    test "the vertical extent is ordered whichever way it is given" do
      [group] = XBand.new() |> XBand.y0(90) |> XBand.y1(30) |> XBand.generate([{0, 5}])
      assert [%{attrs: %{y: 30, height: 60}}] = group.children
    end

    test "an empty list yields []" do
      assert XBand.new() |> XBand.generate([]) == []
    end
  end

  describe "through the facade" do
    test "rule setters dispatch" do
      [group] =
        Shape.rule()
        |> Shape.x(:at)
        |> Shape.scale(linear())
        |> Shape.y0(5)
        |> Shape.y1(15)
        |> Shape.label(:name)
        |> Shape.generate([%{at: 5, name: "mid"}])

      assert [%{attrs: %{x1: 50.0, y1: 5, y2: 15}}, %{content: "mid"}] = group.children
    end

    test "x_band setters dispatch" do
      [group] =
        Shape.x_band()
        |> Shape.x0(:from)
        |> Shape.x1(:to)
        |> Shape.scale(linear())
        |> Shape.y0(0)
        |> Shape.y1(20)
        |> Shape.fill("gold")
        |> Shape.label("w")
        |> Shape.generate([%{from: 0, to: 10}])

      assert [%{attrs: %{x: +0.0, width: 100.0, height: 20}, style: %{fill: "gold"}}, _] =
               group.children
    end

    test "generate_path/2 does not accept rules or x-bands" do
      assert_raise FunctionClauseError, fn -> Shape.generate_path(Shape.rule(), [1]) end
    end
  end
end
