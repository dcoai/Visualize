defmodule Examples.RingLabelsTest do
  @moduledoc """
  #489: the gallery's centred texts sit at the ring's centre, and no ring label leaves the
  plot.

  The Radial bar's and the Donut's centre texts are frame labels at `{:frame, :center}`,
  the polar origin whatever the `r` range (spec/14 §6.3). The Radial bar's and the Chord's
  names outside the ring are kept inside the plot by a ring sized from the plot and its
  longest label (`Examples.Charts.Design.ring_radius/4`, spec/14 §5.5) — held here by
  measurement: resvg's bounding box of every drawn ring label, in the suite's DejaVu Sans.
  """
  use ExUnit.Case, async: true

  alias Examples.Charts.{ChordDiagram, Design, DonutChart, RadialBarChart}

  doctest Examples.Charts.Design

  @fonts Path.expand("../../../test/support/fonts", __DIR__)

  # The polar group's translate — the ring's centre — and the frame labels' points, in the
  # frame's own coordinates, which both sit in.
  defp centre(svg) do
    [cx, cy] =
      Regex.run(~r/<g class="polar" transform="translate\(([-\d.]+),([-\d.]+)\)"/, svg,
        capture: :all_but_first
      )

    {number(cx), number(cy)}
  end

  defp label_points(svg) do
    ~r/<text class="label"[^>]*?\bx="([-\d.]+)"[^>]*?\by="([-\d.]+)"[^>]*>([^<]*)<\/text>/
    |> Regex.scan(svg, capture: :all_but_first)
    |> Enum.map(fn [x, y, text] -> {text, {number(x), number(y)}} end)
  end

  defp number(string) do
    case Float.parse(string) do
      {value, ""} -> value
    end
  end

  describe "the centre texts sit at the ring's centre (spec/14 §6.3)" do
    test "the Radial bar's average and its word, though r's range starts at 50" do
      svg = RadialBarChart.render()
      {cx, cy} = centre(svg)
      points = Map.new(label_points(svg))

      # The text's x is the centre's; its baseline the centre's, nudged by the label's dy.
      assert points["67.1"] == {cx, cy - 5}
      assert points["average"] == {cx, cy + 15}
      assert {cx, cy} == {200.0, 200.0}
    end

    test "the Donut's total and its caption, centred in the plot its legend leaves" do
      svg = DonutChart.render()
      {cx, cy} = centre(svg)
      points = Map.new(label_points(svg))

      assert points["$1000K"] == {cx, cy - 10}
      assert points["Total Revenue"] == {cx, cy + 15}
      # The plot is 280 wide: the 400 box less the 120 legend margin.
      assert {cx, cy} == {140.0, 200.0}
    end

    test "both centre texts are anchored at their middle" do
      for svg <- [RadialBarChart.render(), DonutChart.render()] do
        texts = Regex.scan(~r/<text class="label"[^>]*>/, svg) |> List.flatten()
        assert texts != []
        assert Enum.all?(texts, &(&1 =~ ~s(text-anchor="middle"))), inspect(texts)
      end
    end
  end

  describe "the ring leaves room for its labels (spec/14 §5.5)" do
    test "the Radial bar's ring is the plot's half less the longest day name's room" do
      {design, _sources} = RadialBarChart.design([])
      [_inner, outer] = get_in(design, [:frames, :main, :scales, :r, :range])

      # 200 − (4 + dr 11 + "Wednesday" at 0.6 × 11 a character + 4).
      assert_in_delta outer,
                      200 - (4 + 11 + Visualize.Chart.Text.width("Wednesday", 11) + 4),
                      1.0e-6
    end

    test "the Chord's ring is the plot's half less the longest region name's room" do
      {design, _sources} = ChordDiagram.design([])
      [_ribbons, %{options: %{outer_radius: outer}}] = design.marks

      assert_in_delta outer,
                      250 - (4 + 6 + Visualize.Chart.Text.width("Americas", 11) + 4),
                      1.0e-6
    end
  end

  describe "no ring label's drawn box leaves the plot (measured)" do
    @describetag :resvg

    for {module, size, names} <- [
          {RadialBarChart, {400, 400},
           ~w(Monday Tuesday Wednesday Thursday Friday Saturday Sunday)},
          {ChordDiagram, {500, 500}, ~w(Asia Europe Americas Africa Oceania)}
        ] do
      test "#{inspect(module)}" do
        {width, height} = unquote(Macro.escape(size))
        names = unquote(names)
        boxes = measured(unquote(module))

        # The chart has no margin, so its plot is the whole box.
        assert Enum.sort(Map.keys(Map.take(boxes, names))) == Enum.sort(names)

        for name <- names do
          {x, y, w, h} = Map.fetch!(boxes, name)

          assert x >= 0 and y >= 0 and x + w <= width and y + h <= height,
                 "#{name} at #{inspect({x, y, w, h})} leaves the #{width} x #{height} plot"
        end
      end
    end
  end

  # Every text's drawn bounding box by its content, `{x, y, w, h}` in the root's user
  # units: resvg's `--query-all` over the chart's literal SVG, each text given an id, the
  # SVG on stdin through the rasteriser's own port (spec/09 §9.5).
  defp measured(module) do
    svg =
      module
      |> Design.applied([])
      |> Visualize.Chart.render(root: true, resolve: :literal)

    margin = get_in(elem(module.design([]), 0), [:frames, :main, :margin])
    assert margin == %{top: 0, right: 0, bottom: 0, left: 0}

    {svg, contents} = with_text_ids(svg)

    flags = [
      "--query-all",
      "--skip-system-fonts",
      "--use-fonts-dir",
      @fonts,
      "--sans-serif-family",
      "DejaVu Sans"
    ]

    {:exit, 0, out} =
      Visualize.Render.Raster.run(Visualize.Render.Raster.binary(), flags, svg, 30_000)

    for line <- String.split(out, "\n", trim: true),
        [id, x, y, w, h] <- [String.split(line, ",")],
        Map.has_key?(contents, id),
        into: %{},
        do: {contents[id], {number(x), number(y), number(w), number(h)}}
  end

  defp with_text_ids(svg) do
    parts = String.split(svg, "<text ")

    {tagged, contents} =
      parts
      |> tl()
      |> Enum.with_index()
      |> Enum.map_reduce(%{}, fn {part, i}, acc ->
        [content | _] = String.split(String.replace(part, ~r/^[^>]*>/, "", global: false), "<")
        {"<text id=\"vis-t#{i}\" " <> part, Map.put(acc, "vis-t#{i}", content)}
      end)

    {Enum.join([hd(parts) | tagged]), contents}
  end
end
