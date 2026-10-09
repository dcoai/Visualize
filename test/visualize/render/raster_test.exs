defmodule Visualize.Render.RasterTest do
  # `Visualize.Render.to_png/2` over the optional resvg package (spec/09 §9, D-118). The CI
  # image has no system fonts, so nothing here asserts on text: dimensions, the PNG
  # signature and the pixels of filled shapes only (spec/12 §4).
  use ExUnit.Case, async: true

  alias Visualize.{Chart, Designs, Render}
  alias Visualize.IR.Element
  alias Visualize.Render.Raster

  @signature <<137, 80, 78, 71, 13, 10, 26, 10>>

  # A 10×6 document: a red square on the left half, nothing on the right.
  defp swatch do
    Element.root(10, 6, children: [Element.rect(0, 0, 5, 6, %{fill: "#ff0000", stroke: :none})])
  end

  defp literal_design(name) do
    Chart.generate(Designs.apply(name), root: true, resolve: :literal)
  end

  describe "to_png/2 with resvg" do
    test "every gallery design rasterises at the frame's size" do
      for name <- Designs.names() do
        applied = Designs.apply(name)
        assert {:ok, png} = Render.to_png(literal_design(name))
        assert <<@signature, _::binary>> = png
        assert size(png) == {applied.frame.size.width, applied.frame.size.height}, "#{name}"
      end
    end

    test "scale: 2 doubles the dimensions exactly" do
      {:ok, one} = Render.to_png(literal_design(:line))
      {:ok, two} = Render.to_png(literal_design(:line), scale: 2)
      {w, h} = size(one)
      assert size(two) == {2 * w, 2 * h}
      assert size(Render.to_png!(swatch(), scale: 1.5)) == {15, 9}
    end

    test "an SVG string rasterises as the root it was rendered from" do
      svg = Chart.render(Designs.apply(:bar), root: true, resolve: :literal)
      assert {:ok, from_string} = Render.to_png(svg)
      assert {:ok, from_ir} = Render.to_png(literal_design(:bar))
      assert size(from_string) == size(from_ir)
    end

    test "the shapes are painted and the background fills the transparent pixels" do
      plain = Render.to_png!(swatch())
      assert pixel(plain, 1, 1) == {255, 0, 0, 255}
      assert pixel(plain, 8, 1) == {0, 0, 0, 0}

      backed = Render.to_png!(swatch(), background: "#0000ff")
      assert pixel(backed, 1, 1) == {255, 0, 0, 255}
      assert pixel(backed, 8, 1) == {0, 0, 255, 255}
    end

    test "a theme reference is an error, not a picture in the wrong colours" do
      css = Chart.generate(Designs.apply(:line), root: true, resolve: :css)
      assert Render.to_png(css) == {:error, :css_references}
      assert_raise RuntimeError, ~r/css_references/, fn -> Render.to_png!(css) end
    end

    test "what resvg refuses comes back as its message" do
      assert {:error, {:rasterizer, message}} = Render.to_png(swatch(), background: "nonsense")
      assert is_binary(message)
      assert {:error, {:rasterizer, _}} = Render.to_png("<not svg")
    end

    test "a bad option or input is a programmer error" do
      assert_raise ArgumentError, fn -> Render.to_png(swatch(), scale: 0) end
      assert_raise ArgumentError, fn -> Render.to_png(swatch(), background: :red) end
      assert_raise ArgumentError, fn -> Render.to_png("<svg/>", backend: :svg) end
      assert_raise FunctionClauseError, fn -> Render.to_png(Element.group([])) end
    end
  end

  describe "without resvg (the availability argument, spec/09 §9.4)" do
    test "the result is {:error, :no_rasterizer}" do
      assert Raster.available?()
      assert Raster.to_png(swatch(), [], false) == {:error, :no_rasterizer}
      assert Raster.to_png("<svg/>", [scale: 2], false) == {:error, :no_rasterizer}
    end

    test "the ! variant raises" do
      assert_raise RuntimeError, ~r/no_rasterizer/, fn -> Raster.to_png!(swatch(), [], false) end
    end
  end

  # The IHDR chunk follows the signature directly.
  defp size(<<@signature, _len::32, "IHDR", w::32, h::32, _::binary>>), do: {w, h}

  # One RGBA pixel of an 8-bit RGBA, non-interlaced PNG: the IDAT data inflated and its
  # scanlines unfiltered (PNG §9), rows above `y` included since each row reads the last.
  defp pixel(<<@signature, rest::binary>> = png, x, y) do
    {w, _h} = size(png)
    <<_::32, "IHDR", _::64, 8, 6, 0, 0, 0, _::binary>> = rest
    idat = for {"IDAT", data} <- chunks(rest), into: "", do: data
    stride = w * 4

    row =
      idat
      |> :zlib.uncompress()
      |> rows(stride + 1)
      |> Enum.take(y + 1)
      |> Enum.reduce(:binary.copy(<<0>>, stride), fn <<filter, line::binary>>, prior ->
        unfilter(filter, line, prior)
      end)

    <<r, g, b, a>> = binary_part(row, x * 4, 4)
    {r, g, b, a}
  end

  defp chunks(<<>>), do: []

  defp chunks(<<len::32, type::binary-4, data::binary-size(len), _crc::32, rest::binary>>),
    do: [{type, data} | chunks(rest)]

  defp rows(<<>>, _size), do: []

  defp rows(data, size),
    do: [binary_part(data, 0, size) | rows(binary_part(data, size, byte_size(data) - size), size)]

  defp unfilter(filter, line, prior) do
    up = :binary.bin_to_list(prior)

    line
    |> :binary.bin_to_list()
    |> Enum.with_index()
    |> Enum.reduce([], fn {byte, i}, acc ->
      a = if i >= 4, do: Enum.at(acc, 3), else: 0
      b = Enum.at(up, i)
      c = if i >= 4, do: Enum.at(up, i - 4), else: 0
      [rem(byte + predict(filter, a, b, c), 256) | acc]
    end)
    |> Enum.reverse()
    |> :binary.list_to_bin()
  end

  defp predict(0, _a, _b, _c), do: 0
  defp predict(1, a, _b, _c), do: a
  defp predict(2, _a, b, _c), do: b
  defp predict(3, a, b, _c), do: div(a + b, 2)

  defp predict(4, a, b, c) do
    p = a + b - c
    {pa, pb, pc} = {abs(p - a), abs(p - b), abs(p - c)}

    cond do
      pa <= pb and pa <= pc -> a
      pb <= pc -> b
      true -> c
    end
  end
end
