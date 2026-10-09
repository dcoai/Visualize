defmodule Visualize.Render.RasterTest do
  # `Visualize.Render.to_png/2` through the resvg command-line tool over a port (spec/09 §9,
  # D-121). The tests that run the binary are tagged `:resvg`, excluded when there is none
  # (spec/12 §4). The CI image has no system fonts, so a call that draws text names the
  # bundled font and leaves the system's out; the gallery's pixels are held by the raster
  # goldens, and the port's process and global-state tests are in RasterPortTest.
  use ExUnit.Case, async: true

  alias Visualize.{Chart, Designs, Render}
  alias Visualize.IR.Element
  alias Visualize.PNGPixels
  alias Visualize.Render.Raster

  @signature <<137, 80, 78, 71, 13, 10, 26, 10>>

  # The bundled font and no system fonts: the same pictures on every host (spec/12 §6).
  @fonts [
    font_dirs: ["test/support/fonts"],
    system_fonts: false,
    generic_families: [sans_serif: "DejaVu Sans"]
  ]

  # A 10×6 document: a red square on the left half, nothing on the right.
  defp swatch do
    Element.root(10, 6, children: [Element.rect(0, 0, 5, 6, %{fill: "#ff0000", stroke: :none})])
  end

  defp literal_design(name) do
    Chart.generate(Designs.apply(name), root: true, resolve: :literal)
  end

  # A 60×20 document with one text in `family`, or in none when `family` is nil.
  defp text_doc(family) do
    attr = if family, do: ~s( font-family="#{family}"), else: ""

    ~s(<svg xmlns="http://www.w3.org/2000/svg" width="60" height="20">) <>
      ~s(<text x="0" y="16" font-size="16"#{attr}>Hi</text></svg>)
  end

  describe "to_png/2 through resvg" do
    @describetag :resvg

    test "every gallery design rasterises at the frame's size, without warnings" do
      for name <- Designs.names() do
        applied = Designs.apply(name)
        assert {:ok, png, []} = Render.to_png(literal_design(name), @fonts), "#{name}"
        assert <<@signature, _::binary>> = png

        assert PNGPixels.size(png) == {applied.frame.size.width, applied.frame.size.height},
               "#{name}"
      end
    end

    test "scale: 2 doubles the dimensions exactly" do
      {:ok, one, []} = Render.to_png(literal_design(:line), @fonts)
      {:ok, two, []} = Render.to_png(literal_design(:line), [scale: 2] ++ @fonts)
      {w, h} = PNGPixels.size(one)
      assert PNGPixels.size(two) == {2 * w, 2 * h}
      assert PNGPixels.size(Render.to_png!(swatch(), scale: 1.5)) == {15, 9}
    end

    test "an SVG string rasterises as the root it was rendered from" do
      svg = Chart.render(Designs.apply(:bar), root: true, resolve: :literal)
      assert {:ok, from_string, []} = Render.to_png(svg, @fonts)
      assert {:ok, from_ir, []} = Render.to_png(literal_design(:bar), @fonts)
      assert from_string == from_ir
    end

    test "the shapes are painted and the background fills the transparent pixels" do
      plain = Render.to_png!(swatch())
      assert PNGPixels.pixel(plain, 1, 1) == {255, 0, 0, 255}
      assert PNGPixels.pixel(plain, 8, 1) == {0, 0, 0, 0}

      backed = Render.to_png!(swatch(), background: "#0000ff")
      assert PNGPixels.pixel(backed, 1, 1) == {255, 0, 0, 255}
      assert PNGPixels.pixel(backed, 8, 1) == {0, 0, 255, 255}
    end

    test "what resvg refuses comes back as its message" do
      assert {:error, {:rasterizer, "Error: failed to parse 'nonsense'" <> _}} =
               Render.to_png(swatch(), background: "nonsense")

      assert {:error, {:rasterizer, "Error: " <> _}} = Render.to_png("<not svg")
      assert {:error, {:rasterizer, "Error: " <> _}} = Render.to_png("")
      assert_raise RuntimeError, ~r/rasterizer/, fn -> Render.to_png!("<not svg") end
    end

    test "the binary is at least the supported minimum" do
      assert Raster.check_version(Raster.binary()) == :ok
      assert Raster.minimum() == "0.45.0"
    end
  end

  describe "before the binary" do
    test "a theme reference is an error, not a picture in the wrong colours" do
      css = Chart.generate(Designs.apply(:line), root: true, resolve: :css)
      assert Raster.to_png(css, [], true) == {:error, :css_references}
      assert_raise RuntimeError, ~r/css_references/, fn -> Raster.to_png!(css, [], true) end
    end

    test "a bad option or input is a programmer error, binary or none" do
      for available <- [true, false] do
        assert_raise ArgumentError, fn -> Raster.to_png(swatch(), [scale: 0], available) end

        assert_raise ArgumentError, fn ->
          Raster.to_png(swatch(), [background: :red], available)
        end

        assert_raise ArgumentError, fn -> Raster.to_png(swatch(), [timeout: 0], available) end
        assert_raise ArgumentError, fn -> Raster.to_png(swatch(), [timeout: 1.5], available) end
        assert_raise ArgumentError, fn -> Raster.to_png("<svg/>", [backend: :svg], available) end

        assert_raise FunctionClauseError, fn ->
          Raster.to_png(Element.group([]), [], available)
        end
      end
    end

    test "a bad font option is a programmer error" do
      assert_raise ArgumentError, fn -> Render.to_png(swatch(), font_dirs: "test/support") end
      assert_raise ArgumentError, fn -> Render.to_png(swatch(), font_dirs: ["no/such/dir"]) end
      assert_raise ArgumentError, fn -> Render.to_png(swatch(), system_fonts: :no) end
      assert_raise ArgumentError, fn -> Render.to_png(swatch(), generic_families: [sans: "X"]) end
      assert_raise ArgumentError, fn -> Render.to_png(swatch(), generic_families: [serif: 1]) end
      assert_raise ArgumentError, fn -> Render.to_png(swatch(), font_family: :serif) end
    end
  end

  describe "without resvg (the availability argument, spec/09 §9.4)" do
    test "the result is {:error, :no_rasterizer}" do
      assert Raster.to_png(swatch(), [], false) == {:error, :no_rasterizer}
      assert Raster.to_png("<svg/>", [scale: 2], false) == {:error, :no_rasterizer}
    end

    test "the ! variant raises" do
      assert_raise RuntimeError, ~r/no_rasterizer/, fn -> Raster.to_png!(swatch(), [], false) end
    end
  end

  describe "missing families, as resvg reports them (spec/09 §9.7)" do
    @describetag :resvg

    test "a family list no font resolves is a warning, the list without resvg's quotes" do
      assert {:ok, png, [{:missing_family, "Inter, sans-serif"}]} =
               Render.to_png(
                 text_doc("Inter, sans-serif"),
                 Keyword.delete(@fonts, :generic_families)
               )

      assert <<@signature, _::binary>> = png

      assert {:ok, _, [{:missing_family, "Other, Gone, Helvetica Neue, sans-serif"}]} =
               Render.to_png(
                 text_doc("Other, 'Gone', Helvetica   Neue, sans-serif"),
                 Keyword.delete(@fonts, :generic_families)
               )

      assert {:ok, _, []} = Render.to_png(text_doc("Inter, sans-serif"), @fonts)
      assert {:ok, _, []} = Render.to_png(text_doc("Nope, 'DejaVu Sans'"), @fonts)
    end

    test "names and generic keywords match case-sensitively" do
      assert {:ok, _, [{:missing_family, "dejavu sans"}]} =
               Render.to_png(text_doc("dejavu sans"), @fonts)

      assert {:ok, _, [{:missing_family, "Sans-Serif"}]} =
               Render.to_png(text_doc("Sans-Serif"), @fonts)
    end

    test "a list several texts name is one warning" do
      svg =
        ~s(<svg xmlns="http://www.w3.org/2000/svg" width="60" height="20">) <>
          ~s(<text font-family="Inter">a</text><text font-family="Inter">b</text></svg>)

      assert {:ok, _, [{:missing_family, "Inter"}]} = Render.to_png(svg, @fonts)
    end

    test "a missing family is text resvg left out, so the warning is the only trace of it" do
      {:ok, drawn, []} = Render.to_png(text_doc("DejaVu Sans"), @fonts)
      {:ok, dropped, [_]} = Render.to_png(text_doc("Inter"), @fonts)

      {:ok, empty, []} =
        Render.to_png(String.replace(text_doc(nil), ~r/<text.*<\/text>/, ""), @fonts)

      assert dropped == empty
      refute drawn == empty
    end

    test "without system fonts or font directories every text family is missing" do
      assert {:ok, _png, [{:missing_family, "sans-serif"}]} =
               Render.to_png(literal_design(:bar), system_fonts: false)
    end

    test "text that names no family is drawn in :font_family, written on the root" do
      assert {:ok, _, []} = Render.to_png(text_doc(nil), @fonts)

      assert {:ok, _, [{:missing_family, "Inter"}]} =
               Render.to_png(text_doc(nil), [font_family: "Inter"] ++ @fonts)

      {:ok, from_default, []} = Render.to_png(text_doc(nil), @fonts)
      {:ok, named, []} = Render.to_png(text_doc("DejaVu Sans"), @fonts)
      assert from_default == named
    end

    test "a family no text reads is never reported, the root default included" do
      svg = ~s(<svg xmlns="http://www.w3.org/2000/svg" width="4" height="4" font-family="Nope"/>)
      assert {:ok, _, []} = Render.to_png(svg, system_fonts: false)

      shapes = ~s(<svg xmlns="http://www.w3.org/2000/svg" width="4" height="4"/>)
      assert {:ok, _, []} = Render.to_png(shapes, font_family: "Nope", system_fonts: false)
    end

    test "the ! variant raises when a family is missing" do
      assert_raise RuntimeError, ~r/missing_family/, fn ->
        Render.to_png!(text_doc("Inter"), @fonts)
      end

      assert is_binary(Render.to_png!(text_doc("DejaVu Sans"), @fonts))
    end
  end

  describe "Raster.warnings/1 (resvg's text, spec/09 §9.7)" do
    test "a no-match line is a missing family, its list without the quotes" do
      text =
        ~S|Warning (in usvg::text:143): No match for '"Other", "Gone", sans-serif' font-family.|

      assert Raster.warnings(text) == [{:missing_family, "Other, Gone, sans-serif"}]
    end

    test "a comma inside a quoted name stays in its member" do
      text = ~S|Warning (in usvg::text:129): No match for '"A, B", serif' font-family.|
      assert Raster.warnings(text) == [{:missing_family, "A, B, serif"}]
    end

    test "every other line is kept, repeats once, blank lines dropped, in order" do
      text = """
      Warning (in usvg::text:143): No match for '"Inter"' font-family.

      Warning (in usvg::parser:1): something else.\r
      Warning (in usvg::text:143): No match for '"Inter"' font-family.
      """

      assert Raster.warnings(text) == [
               {:missing_family, "Inter"},
               {:rasterizer, "Warning (in usvg::parser:1): something else."}
             ]

      assert Raster.warnings("") == []
    end
  end
end
