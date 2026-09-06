defmodule Visualize.Backend.CanvasBinaryTest do
  @moduledoc """
  The binary encoder against its own contract (spec/09 §4; D-36): the compact record only
  for a polyline, an exact command count with smooth curves expanded, transforms folded in
  SVG order, colours through `Visualize.Color.parse/1` — with a decoder written from the
  specification as the round-trip witness.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Visualize.Backend.CanvasBinary
  alias Visualize.Backend.CanvasBinary.Opcodes
  alias Visualize.CanvasBinaryDecoder, as: Decoder
  alias Visualize.IR.{Element, Path, Transform}
  alias Visualize.PathGen
  alias Visualize.SVG

  require Opcodes

  describe "path form selection" do
    property "a polyline takes the compact record and round-trips" do
      check all(path <- PathGen.polyline()) do
        <<0x01, _::binary>> = binary = CanvasBinary.encode_path!(path)
        assert Decoder.decode_path(binary) == path
      end
    end

    test "anything the compact record would lose is a full command stream" do
      for commands <- [
            [{:M, 0.0, 0.0}, {:L, 1.0, 1.0}, :Z],
            [{:M, 0.0, 0.0}, {:L, 1.0, 1.0}, {:M, 2.0, 2.0}, {:L, 3.0, 3.0}],
            [{:M, 0.0, 0.0}, {:H, 5.0}],
            [{:M, 0.0, 0.0}, {:l, 1.0, 1.0}],
            [{:L, 0.0, 0.0}],
            []
          ] do
        path = %Path{commands: commands}
        assert <<0x02, _::binary>> = binary = CanvasBinary.encode_path!(path)
        assert Decoder.decode_path(binary) == path
      end
    end
  end

  describe "the command stream" do
    property "decode(encode(path)) is the path with its smooth curves expanded" do
      check all(path <- PathGen.path()) do
        binary = CanvasBinary.encode_path!(path)
        expected = Path.expand_smooth(path)

        unless match?(<<0x01, _::binary>>, binary) do
          assert Decoder.decode_path(binary) == expected
        end
      end
    end

    test "S and T reflect the previous control point and count as one command each" do
      path =
        Path.new()
        |> Path.move_to(0.0, 0.0)
        |> Path.curve_to(1.0, 1.0, 2.0, 1.0, 3.0, 0.0)
        |> Path.smooth_curve_to(5.0, -1.0, 6.0, 0.0)
        |> Path.quad_to(7.0, 1.0, 8.0, 0.0)
        |> Path.smooth_quad_to(10.0, 0.0)
        |> Path.smooth_curve_to_rel(1.0, 1.0, 2.0, 0.0)

      <<0x02, count::little-32, _::binary>> = binary = CanvasBinary.encode_path!(path)
      assert count == 6

      assert Decoder.decode_path(binary).commands == [
               {:M, 0.0, 0.0},
               {:C, 1.0, 1.0, 2.0, 1.0, 3.0, 0.0},
               {:C, 4.0, -1.0, 5.0, -1.0, 6.0, 0.0},
               {:Q, 7.0, 1.0, 8.0, 0.0},
               {:Q, 9.0, -1.0, 10.0, 0.0},
               # After a quadratic there is no cubic control point: the current point.
               {:c, 0.0, 0.0, 1.0, 1.0, 2.0, 0.0}
             ]
    end
  end

  describe "transforms" do
    defp matrix_of(transform) do
      element = Element.rect(0, 0, 1, 1) |> Element.set_transform(transform)
      [{:transform, kind, values} | _] = Decoder.decode(CanvasBinary.encode_element!(element))
      {kind, values}
    end

    defp assert_matrix({:matrix, actual}, expected) do
      Enum.zip(Tuple.to_list(actual), Tuple.to_list(expected))
      |> Enum.each(fn {a, e} -> assert_in_delta a, e, 1.0e-9 end)
    end

    test "the compact kinds cover exactly a translate and a translate-then-scale" do
      assert matrix_of(Transform.translate(1, 2)) == {:translate, {1.0, 2.0}}

      assert matrix_of(Transform.translate(1, 2) |> Transform.scale(3, 4)) ==
               {:translate_scale, {1.0, 2.0, 3.0, 4.0}}
    end

    test "rotate about a centre, skew and matrix fold into the full matrix" do
      assert_matrix(
        matrix_of(Transform.new() |> Transform.rotate(90, 10, 10)),
        {0, 1, -1, 0, 20, 0}
      )

      assert_matrix(matrix_of(Transform.new() |> Transform.skew_x(45)), {1, 0, 1, 1, 0, 0})
      assert_matrix(matrix_of(Transform.new() |> Transform.skew_y(45)), {1, 1, 0, 1, 0, 0})

      assert_matrix(
        matrix_of(Transform.new() |> Transform.matrix(1, 2, 3, 4, 5, 6)),
        {1, 2, 3, 4, 5, 6}
      )
    end

    test "operations compose in SVG order: the last applies to the point first" do
      assert_matrix(
        matrix_of(Transform.scale(2) |> Transform.translate(10, 0)),
        {2, 0, 0, 2, 20, 0}
      )

      assert_matrix(
        matrix_of(Transform.rotate(90) |> Transform.translate(10, 0)),
        {0, 1, -1, 0, 0, 10}
      )
    end
  end

  describe "colours" do
    defp fill_of(style) do
      [{:style, %{fill: fill}} | _] =
        Decoder.decode(CanvasBinary.encode_element!(Element.rect(0, 0, 1, 1, style)))

      fill
    end

    test "rgba with an integral alpha no longer raises, and names resolve" do
      assert fill_of(%{fill: "rgba(0,0,0,1)"}) == {0, 0, 0, 255}
      assert fill_of(%{fill: "rgba(10, 20, 30, 0.5)"}) == {10, 20, 30, 128}
      assert fill_of(%{fill: "steelblue"}) == {70, 130, 180, 255}
      assert fill_of(%{fill: "#4682b4"}) == {70, 130, 180, 255}
      assert fill_of(%{fill: "#fff"}) == {255, 255, 255, 255}
      assert fill_of(%{fill: "#ff000080"}) == {255, 0, 0, 128}
      assert fill_of(%{fill: "hsl(0, 100%, 50%)"}) == {255, 0, 0, 255}
      assert fill_of(%{fill: "not a colour"}) == {0, 0, 0, 255}
    end

    test "the SVG element encoder resolves names and honours the opacity attribute" do
      element =
        SVG.Element.rect(%{x: 0, y: 0, width: 1, height: 1, fill: "steelblue", opacity: 0.5})

      assert [{:style, %{fill: {70, 130, 180, 127}}} | _] =
               Decoder.decode(CanvasBinary.encode_element!(element))

      own_alpha =
        SVG.Element.rect(%{
          x: 0,
          y: 0,
          width: 1,
          height: 1,
          fill: "rgba(1,2,3,0.25)",
          opacity: 0.5
        })

      assert [{:style, %{fill: {1, 2, 3, 63}}} | _] =
               Decoder.decode(CanvasBinary.encode_element!(own_alpha))

      atom = SVG.Element.rect(%{x: 0, y: 0, width: 1, height: 1, fill: :red})

      assert [{:style, %{fill: {255, 0, 0, 255}}} | _] =
               Decoder.decode(CanvasBinary.encode_element!(atom))
    end
  end

  test "the moduledoc opcode table is the Opcodes module" do
    {:docs_v1, _, _, _, %{"en" => doc}, _, _} = Code.fetch_docs(CanvasBinary)

    documented =
      Regex.scan(~r/^\| `(\w+)` \| `(0x[0-9A-F]{2})` \|/m, doc)
      |> Enum.map(fn [_, name, byte] ->
        {String.to_atom(name), String.to_integer(String.slice(byte, 2..3), 16)}
      end)

    assert documented == [
             path: Opcodes.path(),
             path_cubic: Opcodes.path_cubic(),
             circles: Opcodes.circles(),
             rects: Opcodes.rects(),
             style: Opcodes.style(),
             transform: Opcodes.transform(),
             save: Opcodes.save(),
             restore: Opcodes.restore(),
             fill: Opcodes.fill(),
             stroke: Opcodes.stroke()
           ]
  end

  test "an element tree round-trips through the decoder" do
    path = Path.new() |> Path.move_to(0.0, 0.0) |> Path.line_to(1.0, 1.0) |> Path.close()

    group =
      Element.group(
        [
          Element.path(path, %{stroke: "red", stroke_width: 2, fill: :none}),
          Element.circle(1.0, 2.0, 3.0, %{fill: "blue", opacity: 0.5})
        ],
        transform: Transform.translate(5, 6)
      )

    assert Decoder.decode(CanvasBinary.encode_element!(group)) == [
             :save,
             {:transform, :translate, {5.0, 6.0}},
             {:style, %{fill: nil, stroke: {255, 0, 0, 255}, stroke_width: 2.0, opacity: nil}},
             {:path_cubic, [{:M, 0.0, 0.0}, {:L, 1.0, 1.0}, :Z]},
             :stroke,
             {:style, %{fill: {0, 0, 255, 255}, stroke: nil, stroke_width: nil, opacity: 0.5}},
             {:circles, [{1.0, 2.0, 3.0}]},
             :fill,
             :restore
           ]
  end
end
