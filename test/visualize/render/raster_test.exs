defmodule Visualize.Render.RasterTest do
  # `Visualize.Render.to_png/2` over the optional resvg package (spec/09 §9, D-118). The CI
  # image has no system fonts, so a call that draws text names the bundled font and leaves
  # the system's out (spec/12 §4); the gallery's pixels are held by the raster goldens.
  use ExUnit.Case, async: true

  alias Visualize.{Chart, Designs, Render}
  alias Visualize.IR.Element
  alias Visualize.PNGPixels
  alias Visualize.Render.Raster
  alias Visualize.Render.Raster.Families

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

  describe "to_png/2 with resvg" do
    test "every gallery design rasterises at the frame's size" do
      for name <- Designs.names() do
        applied = Designs.apply(name)
        assert {:ok, png, []} = Render.to_png(literal_design(name), @fonts)
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
      assert PNGPixels.size(from_string) == PNGPixels.size(from_ir)
    end

    test "the shapes are painted and the background fills the transparent pixels" do
      plain = Render.to_png!(swatch())
      assert PNGPixels.pixel(plain, 1, 1) == {255, 0, 0, 255}
      assert PNGPixels.pixel(plain, 8, 1) == {0, 0, 0, 0}

      backed = Render.to_png!(swatch(), background: "#0000ff")
      assert PNGPixels.pixel(backed, 1, 1) == {255, 0, 0, 255}
      assert PNGPixels.pixel(backed, 8, 1) == {0, 0, 255, 255}
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

  describe "fonts (spec/09 §9.6, §9.7)" do
    # A 60×20 document with one text in `family`, or in none when `family` is nil.
    defp text_doc(family) do
      attr = if family, do: ~s( font-family="#{family}"), else: ""

      ~s(<svg xmlns="http://www.w3.org/2000/svg" width="60" height="20">) <>
        ~s(<text x="0" y="16" font-size="16"#{attr}>Hi</text></svg>)
    end

    test "a family list no font resolves is listed in the warnings" do
      assert {:ok, png, [{:missing_family, "Inter, sans-serif", ["Inter", "Arial"]}]} =
               Render.to_png(
                 text_doc("Inter, sans-serif"),
                 Keyword.delete(@fonts, :generic_families)
               )

      assert <<@signature, _::binary>> = png

      assert {:ok, _, []} = Render.to_png(text_doc("Inter, sans-serif"), @fonts)
      assert {:ok, _, []} = Render.to_png(text_doc("Nope, 'DejaVu Sans'"), @fonts)
    end

    test "names and generic keywords match case-sensitively, as resvg does" do
      assert {:ok, _, [{:missing_family, "dejavu sans", ["dejavu sans"]}]} =
               Render.to_png(text_doc("dejavu sans"), @fonts)

      assert {:ok, _, [{:missing_family, "Sans-Serif", ["Sans-Serif"]}]} =
               Render.to_png(text_doc("Sans-Serif"), @fonts)
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
      bare = [system_fonts: false]
      {:ok, _png, warnings} = Render.to_png(literal_design(:bar), bare)
      assert warnings == [{:missing_family, "sans-serif", ["Arial"]}]
      assert Raster.fonts(bare).families == MapSet.new()
    end

    test "text that names no family is drawn in :font_family, written on the root" do
      assert {:ok, _, []} = Render.to_png(text_doc(nil), @fonts)

      assert {:ok, _, [{:missing_family, "Inter", ["Inter"]}]} =
               Render.to_png(text_doc(nil), [font_family: "Inter"] ++ @fonts)

      {:ok, from_default, []} = Render.to_png(text_doc(nil), @fonts)
      {:ok, named, []} = Render.to_png(text_doc("DejaVu Sans"), @fonts)
      assert from_default == named
    end

    test "a document with no text has no warnings, whatever it names" do
      svg = ~s(<svg xmlns="http://www.w3.org/2000/svg" width="4" height="4" font-family="Nope"/>)
      assert {:ok, _, []} = Render.to_png(svg, system_fonts: false)
    end

    test "the ! variant raises when a family is missing" do
      assert_raise RuntimeError, ~r/missing_family/, fn ->
        Render.to_png!(text_doc("Inter"), @fonts)
      end

      assert is_binary(Render.to_png!(text_doc("DejaVu Sans"), @fonts))
    end

    test "the same font configuration reuses one database" do
      fonts = Raster.fonts(@fonts)
      assert MapSet.member?(fonts.families, "DejaVu Sans")

      respelled = [
        generic_families: [sans_serif: "DejaVu Sans", serif: "Times New Roman"],
        font_dirs: ["test/support/fonts/../fonts", Path.expand("test/support/fonts")],
        system_fonts: false
      ]

      assert Raster.fonts(respelled).db === fonts.db
      refute Raster.fonts(Keyword.delete(@fonts, :generic_families)).db === fonts.db
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

  describe "family lists (Raster.Families)" do
    test "attribute and style lists are collected in document order, decoded and once" do
      svg =
        ~s(<svg><g font-family="&quot;Open Sans&quot;, serif"><text style="fill: red; font-family: Mono Pro">a</text>) <>
          ~s(<text font-family='Inter'>b</text><text font-family="&quot;Open Sans&quot;, serif">c</text></g></svg>)

      assert Families.lists(svg) == [~s("Open Sans", serif), "Mono Pro", "Inter"]
    end

    test "a list splits on commas outside quotes; only an exact unquoted keyword is generic" do
      assert Families.members(~s("A, B", 'C' ,  Helvetica   Neue , sans-serif, "serif", Serif)) ==
               [
                 {:name, "A, B"},
                 {:name, "C"},
                 {:name, "Helvetica Neue"},
                 {:generic, :sans_serif},
                 {:name, "serif"},
                 {:name, "Serif"}
               ]
    end

    test "a text is an orphan when neither it nor an ancestor names a family" do
      assert Families.orphan_text?(~s(<svg><g><text>x</text></g></svg>))
      refute Families.orphan_text?(~s(<svg><g font-family="A"><text>x</text></g></svg>))
      refute Families.orphan_text?(~s(<svg><g style="font-family: A"><text>x</text></g></svg>))
      refute Families.orphan_text?(~s(<svg><text font-family="A">x</text></svg>))
      assert Families.orphan_text?(~s(<svg><g font-family="A"/><g><text>x</text></g></svg>))
      assert Families.orphan_text?(~s(<svg><g font-family="A"></g><text a=">">x</text></svg>))
      refute Families.orphan_text?(~s(<svg><title>t</title></svg>))
    end

    test "the default family is written on the root only when it has none and a text is an orphan" do
      assert Families.with_default(~s(<svg a="1"><text>x</text></svg>), ~s("A B", serif)) ==
               ~s(<svg font-family="&quot;A B&quot;, serif" a="1"><text>x</text></svg>)

      named = ~s(<svg font-family="X"><text>x</text></svg>)
      assert Families.with_default(named, "Y") == named
      assert Families.with_default("<svg/>", "Y") == "<svg/>"
    end

    test "list_fonts lines give their family names; another form gives none" do
      lines = [
        "/f/DejaVuSans.ttf: 'DejaVu Sans (English, United States)', 0, Normal, 400, Normal",
        "/f/a: b.ttc: 'Noto Sans CJK JP (English, United States)', 'Noto Sans CJK JP (Japanese, Japan)', 2, Normal, 400, Normal",
        "/f/odd.ttf: 'People's Font (Chinese, People's Republic of China)', 0, Italic, 700, Condensed",
        "not a listing line"
      ]

      assert Families.from_listing(lines) ==
               MapSet.new(["DejaVu Sans", "Noto Sans CJK JP", "People's Font"])
    end
  end
end
