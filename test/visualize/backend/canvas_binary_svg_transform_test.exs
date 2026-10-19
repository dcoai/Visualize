defmodule Visualize.Backend.CanvasBinarySVGTransformTest do
  @moduledoc """
  The `transform` attribute on the binary canvas of SVG elements (spec/09 §4.7, #746,
  D-193): a drawing element's own transform is the first of its records inside its
  `save` … `restore`, and the attribute — a group's or a leaf's — is read as SVG reads
  it, the whole list, into the transform the IR encoder would write. The binary hook's
  drawing of a turned leaf is then held to resvg's raster of the SVG.
  """
  use ExUnit.Case, async: true

  import Visualize.JsHooks, only: [run: 1]

  alias Visualize.Backend.CanvasBinary
  alias Visualize.Backend.CanvasBinary.Decoder
  alias Visualize.IR.Transform
  alias Visualize.SVG.Element

  defp records(tree), do: Decoder.decode(CanvasBinary.encode_element!(tree))

  # The matrix of the one transform record a leaf with `transform` writes.
  defp matrix_of(transform) do
    case records(Element.rect(%{width: 4, height: 4, transform: transform})) do
      [:save, {:transform, :translate, {e, f}}, {:rects, _}, :restore] ->
        {1.0, 0.0, 0.0, 1.0, e, f}

      [:save, {:transform, :translate_scale, {e, f, a, d}}, {:rects, _}, :restore] ->
        {a, 0.0, 0.0, d, e, f}

      [:save, {:transform, :matrix, matrix}, {:rects, _}, :restore] ->
        matrix
    end
  end

  defp assert_matrix(got, want) do
    for {g, w} <- Enum.zip(Tuple.to_list(got), Tuple.to_list(want)),
        do: assert_in_delta(g, w, 1.0e-9)
  end

  describe "a leaf's own transform" do
    test "a root rect's translate is its first record, inside its save … restore (#746)" do
      rect = Element.rect(%{width: 4, height: 4, fill: "#ff0000", transform: "translate(50,50)"})

      assert [
               :save,
               {:transform, :translate, {50.0, 50.0}},
               {:style, %{fill: {255, 0, 0, 255}}},
               {:rects, [{+0.0, +0.0, 4.0, 4.0}]},
               :fill,
               :restore
             ] = records(rect)
    end

    test "a transform alone is scoped, and ends with the leaf: its sibling draws unmoved" do
      tree =
        %{
          Element.svg(%{width: 20, height: 20, fill: "#000000"})
          | children: [
              Element.circle(%{cx: 1, cy: 1, r: 1, transform: "rotate(30)"}),
              Element.line(%{x1: 0, y1: 0, x2: 1, y2: 0, stroke: "#000000"}),
              Element.path(%{d: "M0 0 L1 1", transform: "scale(2)"})
            ]
        }

      assert [
               :save,
               {:style, _},
               :save,
               {:transform, :matrix, _},
               {:circles, _},
               :fill,
               :restore,
               :save,
               {:style, _},
               {:path_cubic32, _},
               :stroke,
               :restore,
               :save,
               {:transform, :matrix, {2.0, +0.0, +0.0, 2.0, +0.0, +0.0}},
               {:path_cubic32, _},
               :fill,
               :restore,
               :restore
             ] = records(tree)
    end

    test "a leaf that sets nothing still writes no pair" do
      assert [{:rects, _}] = records(Element.rect(%{width: 1, height: 1}))
    end
  end

  describe "the attribute is read as SVG reads it" do
    test "every operation, and a list, is the matrix IR.Transform folds it to" do
      cases = [
        {"translate(5)", Transform.translate(5, 0)},
        {"translate(1e1 -.5)", Transform.translate(10, -0.5)},
        {"scale(2)", Transform.scale(2)},
        {"scale(2, 3)", Transform.scale(2, 3)},
        {"rotate(30)", Transform.rotate(30)},
        {"rotate(30 5,5)", Transform.new() |> Transform.rotate(30, 5, 5)},
        {"skewX(10)", Transform.new() |> Transform.skew_x(10)},
        {"skewY(-5)", Transform.new() |> Transform.skew_y(-5)},
        {"matrix(1 2 3 4 5 6)", Transform.new() |> Transform.matrix(1, 2, 3, 4, 5, 6)},
        {"translate(50,40) rotate(30)",
         Transform.new() |> Transform.translate(50, 40) |> Transform.rotate(30)},
        {" translate(1,2),scale(3) ",
         Transform.new() |> Transform.translate(1, 2) |> Transform.scale(3, 3)}
      ]

      for {string, transform} <- cases do
        assert_matrix(matrix_of(string), Transform.to_matrix(transform))
      end
    end

    test "what IR.Transform.to_string/1 writes reads back as the transform it wrote" do
      transform =
        Transform.new()
        |> Transform.translate(12.5, -3)
        |> Transform.rotate(-45, 2, 2)
        |> Transform.skew_x(7)
        |> Transform.scale(0.5, 2)

      assert_matrix(matrix_of(Transform.to_string(transform)), Transform.to_matrix(transform))
    end

    test "a list in error writes no transform, as SVG ignores it" do
      for string <- ["", "  ", "rotate(30) bogus", "translate(1,2,3)", "rotate(1,2)", "turn(1)"] do
        assert [{:rects, _}] = records(Element.rect(%{width: 4, height: 4, transform: string})),
               inspect(string)
      end
    end

    test "a group's compound transform is drawn whole, not its first operation alone" do
      tree = %{
        Element.g(%{transform: "translate(50,40) rotate(30)"})
        | children: [Element.rect(%{width: 4, height: 4})]
      }

      assert [:save, {:transform, :matrix, matrix}, {:rects, _}, :restore] = records(tree)

      assert_matrix(
        matrix,
        Transform.to_matrix(
          Transform.new()
          |> Transform.translate(50, 40)
          |> Transform.rotate(30)
        )
      )
    end
  end

  describe "a turned leaf on the binary canvas is the SVG's (#746)" do
    # Both node and resvg (test_helper, #652).
    @describetag :js_resvg

    # A square turned 45° about the middle of the page: a diamond resvg rasterizes, and the
    # binary hook draws as a rect under the matrix the stub records.
    defp diamond do
      %{
        Element.svg(%{width: 240, height: 120})
        | children: [
            Element.rect(%{
              x: -30,
              y: -30,
              width: 60,
              height: 60,
              fill: "#d62728",
              transform: "translate(120,60) rotate(45)"
            })
          ]
      }
    end

    defp hook_matrix do
      data = %{binary: CanvasBinary.to_base64(CanvasBinary.encode_element!(diamond()))}

      {:ok, %{"draws" => [%{"name" => "fill", "m" => m}]}} =
        run("""
        const el = Stub.element(#{Jason.encode!(Map.merge(data, %{width: "240", height: "120"}))}, 240, 120);
        Stub.mount(CanvasBinaryChart, el);
        Stub.done({});
        """)

      {m["a"], m["b"], m["c"], m["d"], m["e"], m["f"]}
    end

    test "the square is drawn turned where resvg's raster has it" do
      {:ok, png, _warnings} =
        Visualize.Render.to_png(to_string(diamond()), scale: 1, background: "#ffffff")

      image = Visualize.PNGPixels.decode(png)
      m = hook_matrix()
      red? = fn {x, y} -> match?({r, g, _b, _a} when r > 180 and g < 90, pixel(image, x, y)) end

      # Inside the square, inset from its edges: the hook's matrix puts every such point
      # where resvg painted red.
      for x <- -24..24//8, y <- -24..24//8 do
        point = Transform.apply_matrix(m, {x, y})
        assert red?.(point), "#{inspect({x, y})} drawn at #{inspect(point)}: not red in resvg"
      end

      # The unturned square's corners lie outside the diamond: white in resvg, so a hook that
      # drew it unturned would be told apart.
      for corner <- [{94, 34}, {146, 34}, {94, 86}, {146, 86}] do
        refute red?.(corner), "#{inspect(corner)} is red: the square was not turned"
      end
    end
  end

  defp pixel(image, x, y), do: Visualize.PNGPixels.pixel(image, round(x), round(y))
end
