defmodule Visualize.Backend.CanvasTest do
  @moduledoc """
  The Canvas backend's command stream is executable in every format (spec/09 §3; D-37):
  no path command is left as a comment, a group's style reaches its children, and a scene
  encodes to binary.
  """
  use ExUnit.Case, async: true

  alias Visualize.Backend.{Canvas, CanvasBinary, Hybrid}
  alias Visualize.IR.{Element, Path, Transform}
  alias Visualize.Render

  @every_command %Path{
    commands: [
      {:M, 0, 0},
      {:l, 10, 0},
      {:H, 20},
      {:v, 5},
      {:c, 1, 1, 2, 2, 3, 3},
      {:S, 30, 10, 40, 10},
      {:q, 1, 1, 2, 0},
      {:T, 50, 10},
      {:A, 5, 5, 0, 0, 1, 60, 10},
      {:a, 5, 5, 0, 0, 1, 10, 0},
      :Z,
      {:m, 1, 1},
      {:L, 2, 2}
    ]
  }

  test "every IR path command renders to an executable JavaScript statement" do
    js = Render.to_canvas_string(Element.path(@every_command, %{stroke: "red"}), format: :js)
    refute js =~ "//"
    assert js =~ "ctx.moveTo(0, 0);"
    assert js =~ "ctx.lineTo(10, 0);"
    assert js =~ "ctx.lineTo(20, 0);"
    assert js =~ "ctx.lineTo(20, 5);"
    assert js =~ "ctx.bezierCurveTo(21, 6, 22, 7, 23, 8);"
    assert js =~ "ctx.bezierCurveTo(24, 9, 30, 10, 40, 10);"
    assert js =~ "ctx.quadraticCurveTo(41, 11, 42, 10);"
    assert js =~ "ctx.quadraticCurveTo(43, 9, 50, 10);"
    assert js =~ "ctx.ellipse("
    assert js =~ "ctx.closePath();"
    assert js =~ "ctx.moveTo(1, 1);"
    assert js =~ "ctx.stroke();"
  end

  test "the command tuples are only Canvas calls, so :json and :commands execute too" do
    commands = Canvas.path_data(@every_command)
    names = commands |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

    assert names -- [:moveTo, :lineTo, :bezierCurveTo, :quadraticCurveTo, :ellipse, :closePath] ==
             []

    json = @every_command |> Element.path() |> Render.to_canvas_string(format: :json)
    assert json =~ ~s({"cmd":"ellipse","args":[)
    assert json =~ ",false]}"
    refute json =~ ~s("false")
  end

  describe "arcs" do
    test "a half circle becomes one ellipse call about its centre" do
      path = %Path{commands: [{:M, 0, 0}, {:A, 10, 10, 0, 0, 1, 20, 0}]}

      [_, {:ellipse, [cx, cy, rx, ry, rot, start, finish, anticlockwise]}] =
        Canvas.path_data(path)

      assert_in_delta cx, 10, 1.0e-9
      assert_in_delta cy, 0, 1.0e-9
      assert_in_delta rx, 10, 1.0e-9
      assert_in_delta ry, 10, 1.0e-9
      assert rot == 0.0
      assert_in_delta start, :math.pi(), 1.0e-9
      assert_in_delta finish, 2 * :math.pi(), 1.0e-9
      assert anticlockwise == false
    end

    test "the sweep flag picks the other side, the large flag the long way round" do
      path = %Path{commands: [{:M, 0, 0}, {:A, 10, 10, 0, 0, 0, 20, 0}]}
      [_, {:ellipse, [_, _, _, _, _, start, finish, true]}] = Canvas.path_data(path)
      assert_in_delta start, :math.pi(), 1.0e-9
      assert_in_delta finish, 0, 1.0e-9

      path = %Path{commands: [{:M, 0, 0}, {:A, 10, 10, 0, 1, 1, 10, 10}]}
      [_, {:ellipse, [cx, cy, _, _, _, start, finish, false]}] = Canvas.path_data(path)
      assert_in_delta cx, 10, 1.0e-9
      assert_in_delta cy, 0, 1.0e-9
      assert_in_delta finish - start, 3 * :math.pi() / 2, 1.0e-9
    end

    test "radii too small for the chord are scaled up; a zero radius is a line" do
      path = %Path{commands: [{:M, 0, 0}, {:A, 1, 1, 0, 0, 1, 20, 0}]}
      [_, {:ellipse, [_, _, rx, ry, _, _, _, _]}] = Canvas.path_data(path)
      assert_in_delta rx, 10, 1.0e-9
      assert_in_delta ry, 10, 1.0e-9

      assert Canvas.path_data(%Path{commands: [{:M, 0, 0}, {:A, 0, 5, 0, 0, 1, 20, 0}]}) ==
               [{:moveTo, [0, 0]}, {:lineTo, [20, 0]}]

      assert Canvas.path_data(%Path{commands: [{:M, 0, 0}, {:A, 5, 5, 0, 0, 1, 0, 0}]}) ==
               [{:moveTo, [0, 0]}]
    end
  end

  test "a group's style is set after its transform and reaches its children" do
    group =
      Element.group([Element.rect(0, 0, 1, 1)],
        style: %{stroke: "blue", stroke_width: 2},
        transform: Transform.translate(5, 5)
      )

    assert Canvas.render_element(group, format: :commands) == [
             {:save, []},
             {:translate, [5, 5]},
             {:set_strokeStyle, ["blue"]},
             {:set_lineWidth, [2]},
             {:beginPath, []},
             {:rect, [0, 0, 1, 1]},
             {:restore, []}
           ]
  end

  test "Hybrid keeps :dynamic_style for a list of dynamic elements" do
    path = Path.new() |> Path.move_to(0, 0) |> Path.line_to(1, 1)

    canvas =
      Hybrid.render_dynamic(
        dynamic: [Element.path(path)],
        dynamic_style: %{stroke: "#123456", stroke_width: 3},
        canvas_format: :js
      )

    assert canvas =~ "ctx.strokeStyle = '#123456';"
    assert canvas =~ "ctx.lineWidth = 3;"
  end

  test "drawImage is executable: the image loads and draws in onload" do
    js = Element.image("a.png", 1, 2, 3, 4) |> Render.to_canvas_string(format: :js)
    refute js =~ "//"
    assert js =~ "new Image()"
    assert js =~ "ctx.drawImage(img, 1, 2, 3, 4);"
    assert js =~ "img.src='a.png';"
  end

  test "render_scene/2 accepts the binary formats as the concatenated element streams" do
    elements = [
      Element.rect(0, 0, 1, 1, %{fill: "red"}),
      Element.circle(1, 1, 1, %{fill: "blue"})
    ]

    expected = Enum.map_join(elements, &CanvasBinary.encode_element!/1)
    assert Render.to_canvas(elements, format: :binary) == expected
    assert Render.to_canvas(elements, format: :binary_base64) == Base.encode64(expected)
  end

  test "a title and a desc draw nothing on a canvas (D-56)" do
    root = Element.root(10, 10, title: "t", description: "d", children: [Element.circle(1, 1, 1)])

    assert Canvas.render_element(root, format: :commands) ==
             Canvas.render_element(Element.root(10, 10, children: [Element.circle(1, 1, 1)]),
               format: :commands
             )
  end
end
