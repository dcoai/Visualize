defmodule Visualize.Chart.LegendWrapTest do
  # A top or bottom legend wraps to the plot's width, grows its margin to hold its rows,
  # and can cut its labels (spec/14 §4.5, #630, D-169).
  use ExUnit.Case, async: true

  alias Visualize.Chart
  alias Visualize.Chart.Frame
  alias Visualize.Chart.Frame.Legend

  @rows for {v, i} <- Enum.with_index([4, 9, 2, 7]), do: %{n: i, v: v, k: "c#{rem(i, 2)}"}

  # Ten characters each: 16 + 0.6 × 12 × 10 = 88 wide, so two (88 + 8 + 88 = 184) fit the
  # 200-wide plot and three do not.
  @five for i <- 1..5, do: "alpha-000#{i}"

  # 400 × 300 with margins of 100: a 200 × 100 plot.
  defp legend_frame(legend, opts \\ []) do
    domain = Keyword.get(opts, :domain, @five)
    margin = Keyword.get(opts, :margin, %{top: 100, right: 100, bottom: 100, left: 100})

    Chart.from_map!(%{
      version: 2,
      sources: %{primary: %{fields: [:n, :v, :k]}},
      frames: %{
        main: %{
          kind: :cartesian,
          margin: margin,
          scales: %{
            x: %{kind: :linear},
            y: %{kind: :linear},
            color: %{kind: :ordinal, domain: domain}
          },
          legend: Map.merge(%{scale: :color}, legend)
        }
      },
      marks: [%{type: :line, data: :primary, channels: %{x: :n, y: :v}}]
    })
    |> Frame.new(sources: %{primary: @rows}, size: {400, 300})
  end

  defp legend(frame) do
    [group] = Legend.generate(frame, :literal)
    [{:translate, x, y}] = group.transform.operations
    {{x, y}, group}
  end

  defp items(group), do: Enum.filter(group.children, &(&1.style[:class] == "legend-item"))

  defp at(item) do
    [{:translate, x, y}] = item.transform.operations
    {x, y}
  end

  describe "wrapping (D-169)" do
    test "entries flow onto rows 16 apart, each row centered on the widest" do
      {{x, y}, group} = legend(legend_frame(%{position: :top}))
      # Rows of two, two and one: the last, 88 wide, sits (184 − 88) / 2 in.
      assert Enum.map(items(group), &at/1) ==
               [{0, 0}, {96.0, 0}, {0, 16}, {96.0, 16}, {48.0, 32}]

      # The group is centered on the widest row: 100 − 184 / 2.
      assert {x, y} == {8.0, 8}
    end

    test "a bottom legend inside grows up from the plot's bottom edge" do
      {{_x, y}, _group} = legend(legend_frame(%{position: :bottom}))
      # 100 − 8 − 12 − 2 × 16
      assert y == 48
    end

    test "a legend that fits one row is laid out as the single row always was" do
      {{x, y}, group} = legend(legend_frame(%{position: :top}, domain: ["a", "b"]))
      # Entries 16 + 7.2 wide, 8 apart: the second at 31.2, the row 54.4 wide.
      assert [{0, 0}, {second, 0}] = Enum.map(items(group), &at/1)
      assert_in_delta second, 31.2, 1.0e-9
      assert_in_delta x, 100 - 54.4 / 2, 1.0e-9
      assert y == 8
    end

    test "the title is the first cell of the first row" do
      {_at, group} = legend(legend_frame(%{position: :top, title: "Series"}))
      [title | _] = group.children
      assert title.type == :text and title.content == "Series"
      # "Series" is 43.2 wide: it and one entry (43.2 + 8 + 88) fit, a second does not.
      assert [{x0, 0}, {_x1, 16} | _] = Enum.map(items(group), &at/1)
      assert_in_delta x0, 51.2 + (184 - 139.2) / 2, 1.0e-9
    end

    test "every entry keeps its group and data-series, so LegendHook reads it as a row" do
      {_at, group} = legend(legend_frame(%{position: :bottom, inside: false}))

      assert Enum.map(items(group), & &1.attrs["data-series"]) == @five

      assert Enum.all?(
               items(group),
               &(Enum.map(&1.children, fn c -> c.type end) == [:rect, :text])
             )
    end

    test "wrap: false keeps one row and raises when it is wider than the plot" do
      assert_raise ArgumentError,
                   ~r/:top with wrap: false needs 472.0 across the top, and the plot is 200 wide/,
                   fn -> legend_frame(%{position: :top, wrap: false}) end

      {_at, group} = legend(legend_frame(%{position: :top, wrap: false}, domain: ["a", "b"]))
      assert Enum.map(items(group), &elem(at(&1), 1)) == [0, 0]
    end

    test "a single entry wider than the plot raises, naming the side and the width" do
      long = String.duplicate("x", 30)

      assert_raise ArgumentError,
                   ~r/single entry of the legend at :bottom needs 232.0 across the bottom on its own, and the plot is 200 wide/,
                   fn -> legend_frame(%{position: :bottom}, domain: ["a", long]) end

      # The title is a cell too, and max_label does not cut it.
      assert_raise ArgumentError,
                   ~r/a title of the legend at :top needs 216.0 across the top/,
                   fn ->
                     legend_frame(%{position: :top, title: long, max_label: 5})
                   end
    end

    test "a side legend does not wrap" do
      {_at, group} = legend(legend_frame(%{position: :left, wrap: true}))
      assert Enum.map(items(group), &at/1) == Enum.map(0..4, &{0, &1 * 16})
    end
  end

  describe "a top or bottom margin grows to its rows (D-169)" do
    test "the margin takes (rows − 1) × 16 + 12 + 8 and the plot shrinks by it" do
      margin = %{top: 20, right: 100, bottom: 100, left: 100}
      frame = legend_frame(%{position: :top, inside: false}, margin: margin)

      assert frame.margin == %{margin | top: 52}
      assert frame.plot == %{width: 200, height: 300 - 52 - 100}
      # The scales follow the smaller plot.
      assert Frame.scale(frame, :y).range == [148, 0]

      {{_x, y}, _group} = legend(frame)
      # The last row's swatches 8 above the plot.
      assert y == -8 - 12 - 32
    end

    test "a bottom margin grows likewise, the first row 8 below the plot" do
      margin = %{top: 100, right: 100, bottom: 30, left: 100}
      frame = legend_frame(%{position: :bottom, inside: false}, margin: margin)

      assert frame.margin.bottom == 52
      {{_x, y}, _group} = legend(frame)
      assert y == frame.plot.height + 8
    end

    test "a margin that already holds the legend is left as it was" do
      margin = %{top: 60, right: 100, bottom: 100, left: 100}
      assert legend_frame(%{position: :top, inside: false}, margin: margin).margin == margin

      inside = legend_frame(%{position: :top}, margin: %{margin | top: 0})
      assert inside.margin.top == 0
    end
  end

  describe "Frame.legend_extent/1 (D-169)" do
    test "a wrapped legend's widest row and its rows" do
      assert Frame.legend_extent(legend_frame(%{position: :top})) == %{width: 184.0, height: 44}

      assert Frame.legend_extent(legend_frame(%{position: :bottom}, domain: ["a"])) ==
               %{width: 23.2, height: 12}
    end

    test "a stacked legend's estimated width and its rows, the title counted" do
      extent = Frame.legend_extent(legend_frame(%{position: :right, title: "T"}))
      assert_in_delta extent.width, 16 + 72, 1.0e-9
      assert extent.height == 5 * 16 + 12
    end

    test "no legend is no extent" do
      frame =
        Chart.from_map!(%{
          version: 2,
          frames: %{main: %{kind: :cartesian, scales: %{x: %{kind: :linear}}}}
        })
        |> Frame.new(size: {400, 300})

      assert Frame.legend_extent(frame) == %{width: 0, height: 0}
    end
  end

  describe "max_label (D-169)" do
    @long ["a-very-long-series-name-one", "a-very-long-series-name-two"]

    test "a longer label is cut with …, the full text in a title and aria-label" do
      {_at, group} = legend(legend_frame(%{position: :bottom, max_label: 10}, domain: @long))
      [first, _second] = items(group)

      assert [%{type: :title, content: "a-very-long-series-name-one"}, _rect, label] =
               first.children

      assert label.content == "a-very-lo…"
      assert String.length(label.content) == 10
      assert first.attrs["aria-label"] == "a-very-long-series-name-one"
      assert first.attrs["data-series"] == "a-very-long-series-name-one"
    end

    test "the cut label is what the layout measures" do
      # 16 + 7.2 × 10 = 88 each: two fit one row.
      {_at, group} = legend(legend_frame(%{position: :bottom, max_label: 10}, domain: @long))
      assert Enum.map(items(group), &elem(at(&1), 1)) == [0, 0]
    end

    test "a label within max_label is drawn as it was, with no title" do
      plain = legend_frame(%{position: :top}, domain: ["a", "b"])
      capped = legend_frame(%{position: :top, max_label: 5}, domain: ["a", "b"])
      assert Legend.generate(plain, :literal) == Legend.generate(capped, :literal)
    end

    test "it applies at a side, narrowing the width the margin must hold" do
      margin = %{top: 20, right: 100, bottom: 20, left: 20}

      assert_raise ArgumentError, ~r/needs .* in the right margin, which is 100/, fn ->
        legend_frame(%{position: :right, inside: false}, domain: @long, margin: margin)
      end

      frame =
        legend_frame(%{position: :right, inside: false, max_label: 8},
          domain: @long,
          margin: margin
        )

      {_at, group} = legend(frame)
      assert Enum.map(items(group), &List.last(&1.children).content) == ["a-very-…", "a-very-…"]
    end

    test "the SVG carries the full label as the entry's title" do
      svg =
        legend_frame(%{position: :bottom, max_label: 10}, domain: @long)
        |> Frame.render()

      assert svg =~ "<title>a-very-long-series-name-one</title>"
      assert svg =~ ~s(aria-label="a-very-long-series-name-one")
    end

    test "a max_label below 1 is a fault" do
      assert_raise ArgumentError,
                   ~r/max_label is a count of characters of at least 1, not 0/,
                   fn ->
                     legend_frame(%{position: :top, max_label: 0})
                   end
    end
  end
end
