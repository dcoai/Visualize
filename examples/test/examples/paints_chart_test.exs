defmodule Examples.PaintsChartTest do
  @moduledoc """
  The Paints chart's swatches and blend (#786, spec/14 §3.1): every hatch pattern, a
  stroke inside, outside and doubled, and incidents that multiply where they overlap.
  """
  use ExUnit.Case, async: true

  alias Examples.Charts.{Design, PaintsChart}
  alias Visualize.Chart

  setup_all do
    svg = Chart.render(Design.applied(PaintsChart, []), root: true, resolve: :literal)
    %{svg: svg}
  end

  test "the swatches fill with lines and dots, beside the window's crosshatch", %{svg: svg} do
    patterns = Regex.scan(~r/<pattern [^>]*>(.*?)<\/pattern>/s, svg, capture: :all_but_first)
    bodies = Enum.map(patterns, &hd/1)

    # A dots pattern holds a circle; lines one line; the crosshatch two.
    assert Enum.any?(bodies, &(&1 =~ "<circle"))
    assert Enum.any?(bodies, &(length(Regex.scan(~r/<line /, &1)) == 1))
    assert Enum.any?(bodies, &(length(Regex.scan(~r/<line /, &1)) == 2))
  end

  test "a stroke sits inside, outside or doubled on its edge", %{svg: svg} do
    # Inside: a doubled width clipped to the shape; double: a thinner line over the stroke.
    assert svg =~ ~r/<clipPath id="vis-clip-/
    assert svg =~ ~s(stroke-width="12")
    assert svg =~ ~s(stroke-width="3.0")
  end

  test "the incidents multiply where they overlap", %{svg: svg} do
    assert length(Regex.scan(~r/style="mix-blend-mode: multiply"/, svg)) == 4
  end

  # The gallery's canvas mode is the hybrid split, each plot a binary stream (spec/14 §12):
  # the incidents' plot multiplies them and the swatches' clips both edged strokes (#788).
  test "the gallery's canvas plots carry the clips and the blends" do
    records =
      for plot <- Design.hybrid(PaintsChart, []).plots, into: %{} do
        decoded = Visualize.Backend.CanvasBinary.Decoder.decode(Base.decode64!(plot.canvas))
        {plot.name, Enum.filter(decoded, &match?({kind, _} when kind in [:clip, :blend], &1))}
      end

    assert records["swatches"] == [clip: :inside, clip: :outside]
    assert Enum.count(records["main"], &(&1 == {:blend, "multiply"})) == 4
  end

  # The gallery's canvas is the binary one (#788, D-208): it clips the inside and outside
  # strokes and multiplies the incidents as the `:json` canvas does, draw for draw.
  @tag :js
  test "the binary canvas clips and multiplies as the :json canvas does" do
    applied = Design.applied(PaintsChart, [])
    json = IO.iodata_to_binary(Chart.render(applied, backend: :canvas, format: :json))
    binary = Chart.render(applied, backend: :canvas, format: :binary_base64)

    state = fn hook, data ->
      {:ok, %{"draws" => draws}} =
        Visualize.JsHooks.run("""
        Stub.mount(#{hook}, Stub.element(#{Jason.encode!(Map.merge(data, %{width: "760", height: "540"}))}, 760, 540));
        Stub.done({});
        """)

      for %{"name" => name} = d <- draws,
          name in ["fill", "stroke"],
          do:
            {name, d["clips"], d["globalCompositeOperation"],
             Float.round(d["lineWidth"] * 1.0, 2)}
    end

    on_json = state.("CanvasChart", %{commands: json})
    on_binary = state.("CanvasBinaryChart", %{binary: binary})

    assert on_binary == on_json
    # The inside swatch clips to its shape, the outside one away from it, at twice the width.
    assert {"stroke", ["nonzero"], "source-over", 12.0} in on_binary
    assert {"stroke", ["evenodd"], "source-over", 12.0} in on_binary
    assert Enum.count(on_binary, &match?({"fill", [], "multiply", _}, &1)) == 4
  end
end
