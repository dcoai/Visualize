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
  alias Visualize.Backend.CanvasBinary.Decoder
  alias Visualize.Backend.CanvasBinary.Opcodes
  alias Visualize.IR.{Element, Path, Transform}
  alias Visualize.PathGen
  alias Visualize.SVG

  require Opcodes

  describe "the geometric types that are not paths (spec/09 §4.4, #269)" do
    @style %{stroke: "#123456", stroke_width: 2, fill: :none}

    defp bytes(element), do: CanvasBinary.encode_element!(element)

    test "a line is byte for byte its two-point path" do
      line = Element.line(1, 2, 30, 40, @style)
      path = Element.path(Path.new() |> Path.move_to(1, 2) |> Path.line_to(30, 40), @style)
      assert bytes(line) == bytes(path)
      assert byte_size(bytes(line)) > 0
    end

    test "a polyline is a move and its lines; a polygon the same, closed" do
      points = [{0, 0}, {10, 5}, {20, 0}]
      open = Path.new() |> Path.move_to(0, 0) |> Path.line_to(10, 5) |> Path.line_to(20, 0)
      assert bytes(Element.polyline(points, @style)) == bytes(Element.path(open, @style))

      assert bytes(Element.polygon(points, @style)) ==
               bytes(Element.path(Path.close(open), @style))

      refute bytes(Element.polyline(points, @style)) == bytes(Element.polygon(points, @style))
    end

    test "an ellipse is four cubic quarter-arcs, closed, with the control distance κ of each radius" do
      k = 0.5522847
      {cx, cy, rx, ry} = {50, 40, 20, 10}

      path =
        Path.new()
        |> Path.move_to(70, 40)
        |> Path.curve_to(70, 40 + ry * k, 50 + rx * k, 50, 50, 50)
        |> Path.curve_to(50 - rx * k, 50, 30, 40 + ry * k, 30, 40)
        |> Path.curve_to(30, 40 - ry * k, 50 - rx * k, 30, 50, 30)
        |> Path.curve_to(50 + rx * k, 30, 70, 40 - ry * k, 70, 40)
        |> Path.close()

      assert bytes(Element.ellipse(cx, cy, rx, ry, @style)) == bytes(Element.path(path, @style))
    end

    test "the transform and the style travel with the element, and text is still dropped" do
      moved = %{Element.line(0, 0, 1, 1, @style) | transform: Transform.translate(5, 6)}

      moved_path = %{
        Element.path(Path.new() |> Path.move_to(0, 0) |> Path.line_to(1, 1), @style)
        | transform: Transform.translate(5, 6)
      }

      assert bytes(moved) == bytes(moved_path)
      assert bytes(Element.text("hi", 1, 2)) == <<>>
    end

    test "an axis on the binary stream carries one record per tick line and the domain" do
      axis =
        Visualize.Axis.bottom(
          Visualize.Scale.linear()
          |> Visualize.Scale.domain([0, 10])
          |> Visualize.Scale.range([0, 100])
        )
        |> Visualize.Axis.ticks(5)

      element = Visualize.Axis.generate(axis, resolve: :literal)
      lines = element |> flatten() |> Enum.count(&(&1.type == :line))
      paths = element |> flatten() |> Enum.count(&(&1.type == :path))
      assert lines > 0
      records = bytes(element)
      # Every line and path draws: at least one path record per element of either type.
      assert length(Regex.scan(~r/[\x01\x02\x05\x06\x07]/, records)) >= lines + paths
    end

    defp flatten(%Element{children: children} = element),
      do: [element | Enum.flat_map(children, &flatten/1)]
  end

  describe "path form selection" do
    property "a polyline takes the point-list record and round-trips at either width" do
      check all(path <- PathGen.polyline()) do
        <<0x05, _::binary>> = binary = CanvasBinary.encode_path!(path)
        assert Decoder.decode_path(binary) == PathGen.round_f32(path)

        <<0x01, _::binary>> = f64 = CanvasBinary.encode_path!(path, precision: :f64)
        assert Decoder.decode_path(f64) == path
      end
    end

    test "anything the point-list record would lose is a full command stream" do
      for commands <- [
            [{:M, 0.0, 0.0}, {:L, 1.0, 1.0}, :Z],
            [{:M, 0.0, 0.0}, {:L, 1.0, 1.0}, {:M, 2.0, 2.0}, {:L, 3.0, 3.0}],
            [{:M, 0.0, 0.0}, {:H, 5.0}],
            [{:M, 0.0, 0.0}, {:l, 1.0, 1.0}],
            [{:L, 0.0, 0.0}],
            []
          ] do
        path = %Path{commands: commands}
        assert <<0x06, _::binary>> = binary = CanvasBinary.encode_path!(path)
        assert Decoder.decode_path(binary) == path

        assert <<0x02, _::binary>> = f64 = CanvasBinary.encode_path!(path, precision: :f64)
        assert Decoder.decode_path(f64) == path
      end
    end

    test "the precision option is :f32 or :f64" do
      path = %Path{commands: [{:M, 0.0, 0.0}]}

      assert_raise ArgumentError, ~r/precision: :f32 or :f64/, fn ->
        CanvasBinary.encode_path!(path, precision: :single)
      end

      assert_raise ArgumentError, fn ->
        CanvasBinary.encode_element!(Element.path(path), precision: 32)
      end
    end
  end

  describe "the cubic run (D-74)" do
    property "one M then Cs is a cubic_run and round-trips to the rounded path" do
      check all(path <- PathGen.cubic_run()) do
        <<0x07, count::little-32, _::binary>> = binary = CanvasBinary.encode_path!(path)
        assert count == length(path.commands) - 1
        assert byte_size(binary) == 13 + 24 * count
        assert Decoder.decode_path(binary) == PathGen.round_f32(path)

        <<0x02, _::binary>> = f64 = CanvasBinary.encode_path!(path, precision: :f64)
        assert Decoder.decode_path(f64) == path
      end
    end

    test "a run broken by any other command, or with no curve, is a command stream" do
      c = {:C, 1.0, 1.0, 2.0, 1.0, 3.0, 0.0}

      for commands <- [
            [{:M, 0.0, 0.0}],
            [{:M, 0.0, 0.0}, {:L, 1.0, 1.0}, c],
            [{:M, 0.0, 0.0}, c, {:L, 4.0, 0.0}],
            [{:M, 0.0, 0.0}, c, :Z],
            [{:M, 0.0, 0.0}, c, {:M, 5.0, 5.0}, c],
            [{:M, 0.0, 0.0}, {:c, 1.0, 1.0, 2.0, 1.0, 3.0, 0.0}],
            [c]
          ] do
        path = %Path{commands: commands}
        assert <<opcode, _::binary>> = CanvasBinary.encode_path!(path)
        assert opcode in [0x05, 0x06], inspect(commands)
      end
    end

    test "a smooth continuation counts as a run, and the curve generators emit runs" do
      smooth =
        Path.new()
        |> Path.move_to(0.0, 0.0)
        |> Path.curve_to(1.0, 1.0, 2.0, 1.0, 3.0, 0.0)
        |> Path.smooth_curve_to(5.0, -1.0, 6.0, 0.0)

      assert <<0x07, 2::little-32, _::binary>> = CanvasBinary.encode_path!(smooth)

      points = for i <- 0..9, do: {i * 10.0, :math.sin(i) * 20.0}

      for curve <- [:monotone_x, :monotone_y, :cardinal, :catmull_rom, :natural] do
        assert <<0x07, 9::little-32, _::binary>> =
                 CanvasBinary.encode_path!(Visualize.Shape.Curve.generate(curve, points)),
               "#{curve} is not a run"
      end

      assert <<0x06, _::binary>> =
               CanvasBinary.encode_path!(Visualize.Shape.Curve.generate(:basis, points))
    end
  end

  describe "the f32 records (D-73)" do
    property "an f32 holds a coordinate below 16,384 to within 2^-11" do
      check all(v <- float(min: -16_384.0, max: 16_384.0)) do
        <<rounded::float-32>> = <<v::float-32>>
        assert abs(v - rounded) <= :math.pow(2, -11)
      end
    end

    property "the f32 command stream is the f64 one with every argument rounded" do
      check all(path <- PathGen.path()) do
        f32 = CanvasBinary.encode_path!(path)
        f64 = CanvasBinary.encode_path!(path, precision: :f64)
        assert Decoder.decode_path(f32) == PathGen.round_f32(Decoder.decode_path(f64))
      end
    end

    test "an element stream is f32 by default and f64 on request, every path record alike" do
      curve = Path.new() |> Path.move_to(0.0, 0.0) |> Path.curve_to(1.0, 1.0, 2.0, 1.0, 3.0, 0.0)
      line = Path.new() |> Path.move_to(0.0, 0.0) |> Path.line_to(1.0, 1.0)
      group = Element.group([Element.path(curve), Element.path(line)])

      assert [:save, {:cubic_run, _, _}, {:path32, _}, :restore] =
               Decoder.decode(CanvasBinary.encode_element!(group))

      assert [:save, {:path_cubic, _}, {:path, _}, :restore] =
               Decoder.decode(CanvasBinary.encode_element!(group, precision: :f64))

      svg = SVG.Element.path(%{d: "M0,0L1,1", fill: "none", stroke: "red"})

      assert [{:style, _}, {:path_cubic32, _}, :stroke] =
               Decoder.decode(CanvasBinary.encode_element!(svg))

      assert [{:style, _}, {:path_cubic, _}, :stroke] =
               Decoder.decode(CanvasBinary.encode_element!(svg, precision: :f64))
    end
  end

  describe "the command stream" do
    property "decode(encode(path)) is the path with its smooth curves expanded" do
      check all(path <- PathGen.path()) do
        expected = Path.expand_smooth(path)

        binary = CanvasBinary.encode_path!(path)

        unless match?(<<0x05, _::binary>>, binary) do
          assert Decoder.decode_path(binary) == PathGen.round_f32(expected)
        end

        f64 = CanvasBinary.encode_path!(path, precision: :f64)

        unless match?(<<0x01, _::binary>>, f64) do
          assert Decoder.decode_path(f64) == expected
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

      <<0x06, count::little-32, _::binary>> = binary = CanvasBinary.encode_path!(path)
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
             path32: Opcodes.path32(),
             path_cubic32: Opcodes.path_cubic32(),
             cubic_run: Opcodes.cubic_run(),
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
             {:path_cubic32, [{:M, 0.0, 0.0}, {:L, 1.0, 1.0}, :Z]},
             :stroke,
             {:style, %{fill: {0, 0, 255, 255}, stroke: nil, stroke_width: nil, opacity: 0.5}},
             {:circles, [{1.0, 2.0, 3.0}]},
             :fill,
             :restore
           ]
  end
end
