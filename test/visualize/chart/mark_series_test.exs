defmodule Visualize.Chart.MarkSeriesTest do
  @moduledoc """
  The `series` channel on every mark that draws rows (spec/14 §5.2, §5.6, D-126, #508):
  each element and each label a series draws carries its `data-series` and is painted in
  the series' colour, anything more specific wins the paint, and a mark without the
  channel — or a row whose reading is `nil` — names no series.
  """
  use ExUnit.Case, async: true

  alias Visualize.Chart
  alias Visualize.Chart.{Frame, Mark}
  alias Visualize.IR.Element

  @rows for {v, i} <- Enum.with_index([4, 9, 2, 7]),
            do: %{t: i, v: v, k: "k#{rem(i, 2)}", c: "#ff0000"}
  @sources %{primary: @rows}

  @scales %{
    x: %{kind: :linear, domain: [0, 3]},
    y: %{kind: :linear, domain: [0, 10]},
    color: %{kind: :ordinal}
  }

  defp chart(marks, extra \\ %{}) do
    Chart.from_map!(
      Map.merge(
        %{
          version: 3,
          sources: %{primary: %{fields: [:t, :v, :k, :c]}},
          frames: %{
            main: %{
              kind: :cartesian,
              margin: %{top: 0, right: 0, bottom: 0, left: 0},
              scales: @scales
            }
          },
          marks: Enum.map(marks, &Map.merge(%{data: :primary}, &1))
        },
        extra
      )
    )
  end

  defp generate(mark, extra \\ %{}, sources \\ @sources) do
    chart = chart([mark], extra)
    frame = Frame.new(chart, sources: sources, size: {300, 200})
    Mark.generate(frame, hd(chart.marks), sources: sources)
  end

  defp series(%Element{attrs: attrs}), do: Map.get(attrs, "data-series")

  # The series colour of the frame's ordinal colour scale, as the legend paints it.
  defp slot(1), do: "var(--vis-series-1, #3b6fa8)"
  defp slot(2), do: "var(--vis-series-2, #d9730d)"

  @per_datum [
    {:circle, %{x: :t, y: :v}},
    {:symbol, %{x: :t, y: :v}},
    {:rect, %{x0: :t, x1: :t, y0: 0, y1: :v}},
    {:band, %{x0: :t, x1: :t}},
    {:text, %{x: :t, y: :v}},
    {:arc, %{value: :v}},
    {:rule, %{x: :t}},
    {:x_band, %{x0: :t, x1: :t}}
  ]

  describe "data-series on every element a series draws" do
    test "every per-datum type stamps each element with its own datum's series" do
      for {type, channels} <- @per_datum do
        group = generate(%{type: type, channels: Map.put(channels, :series, :k)})

        assert Enum.map(group.children, &series/1) == ~w(k0 k1 k0 k1),
               "#{type}: #{inspect(Enum.map(group.children, &series/1))}"
      end
    end

    test "a mark without the channel names no series, and a nil reading names none" do
      for {type, channels} <- @per_datum do
        assert Enum.all?(
                 generate(%{type: type, channels: channels}).children,
                 &(series(&1) == nil)
               )
      end

      rows = List.update_at(@rows, 1, &Map.put(&1, :k, nil))

      group =
        generate(%{type: :circle, channels: %{x: :t, y: :v, series: :k}}, %{}, %{primary: rows})

      assert Enum.map(group.children, &series/1) == ["k0", nil, "k0", "k1"]
    end

    test "a line's path carries it; a fill on a line draws no area (#659)" do
      group =
        generate(
          %{type: :line, channels: %{x: :t, y: :v, series: :k}, style: :filled},
          %{styles: %{filled: %{fill: "#eeeeee"}}}
        )

      assert [%{style: %{stroke: stroke0}} = line0, line1] = group.children
      assert Enum.map([line0, line1], &series/1) == ~w(k0 k1)
      assert stroke0 == slot(1)
    end

    test "every label a series draws carries it, a rule's lifted label included" do
      group =
        generate(%{
          type: :circle,
          channels: %{x: :t, y: :v, series: :k},
          label: %{text: [{:field, :v}]}
        })

      [_elements, %Element{children: labels}] = group.children
      assert Enum.map(labels, &series/1) == ~w(k0 k1 k0 k1)

      rule =
        generate(%{type: :rule, channels: %{x: :t, series: :k}, label: %{text: [{:field, :v}]}})

      [%Element{children: rules}, %Element{children: lifted}] = rule.children
      assert Enum.map(rules, &series/1) == ~w(k0 k1 k0 k1)
      assert Enum.map(lifted, & &1.type) == List.duplicate(:text, 4)
      assert Enum.map(lifted, &series/1) == ~w(k0 k1 k0 k1)
    end

    test "the second element of a double stroke copies the first's" do
      group =
        generate(
          %{type: :circle, channels: %{x: :t, y: :v, series: :k}, style: :double},
          %{styles: %{double: %{stroke_style: :double, stroke: "#000000"}}}
        )

      assert Enum.map(group.children, &series/1) == ~w(k0 k0 k1 k1 k0 k0 k1 k1)
    end
  end

  describe "the series' paint" do
    test "a series' points take its line's colour" do
      line = generate(%{type: :line, channels: %{x: :t, y: :v, series: :k}})
      circle = generate(%{type: :circle, channels: %{x: :t, y: :v, series: :k}})

      strokes = Map.new(line.children, &{series(&1), &1.style.stroke})
      assert strokes == %{"k0" => slot(1), "k1" => slot(2)}

      assert Enum.map(circle.children, &{series(&1), &1.style.fill}) ==
               Enum.map(~w(k0 k1 k0 k1), &{&1, strokes[&1]})
    end

    test "without a colour scale the series' position among the mark's series is its slot" do
      group =
        generate(%{type: :symbol, channels: %{x: :t, y: :v, series: :k}}, %{
          frames: %{
            main: %{
              kind: :cartesian,
              margin: %{top: 0, right: 0, bottom: 0, left: 0},
              scales: Map.delete(@scales, :color)
            }
          }
        })

      assert Enum.map(group.children, & &1.style.fill) == [slot(1), slot(2), slot(1), slot(2)]
    end

    test "anything more specific wins: a binding, a rect's value, a text's label fill" do
      bound =
        generate(
          %{type: :circle, channels: %{x: :t, y: :v, series: :k}, style: :red},
          %{styles: %{red: %{fill: {:field, :c}}}}
        )

      # The binding reads one value, the colour scale's third member, for every point.
      assert Enum.map(bound.children, & &1.style.fill) ==
               List.duplicate("var(--vis-series-3, #c8373b)", 4)

      rect =
        generate(%{
          type: :rect,
          channels: %{x0: :t, x1: :t, y0: 0, y1: :v, value: :c, series: :k}
        })

      # The value's one colour on every rectangle, not the series' two in turn.
      assert [fill] = rect.children |> Enum.map(& &1.style.fill) |> Enum.uniq()
      assert is_binary(fill)

      text = generate(%{type: :text, channels: %{x: :t, y: :v, series: :k}})
      assert Enum.all?(text.children, &(&1.style.fill == "var(--vis-text, #333333)"))
    end

    test "a rule's line and an x-band's rectangle take the series' colour inside the group" do
      rule = generate(%{type: :rule, channels: %{x: :t, series: :k}})

      assert Enum.map(rule.children, fn %Element{children: [line | _]} -> line.style.stroke end) ==
               [slot(1), slot(2), slot(1), slot(2)]

      assert Enum.all?(rule.children, &(not Map.has_key?(&1.style, :stroke)))

      band = generate(%{type: :x_band, channels: %{x0: :t, x1: :t, series: :k}})

      assert Enum.map(band.children, fn %Element{children: [rect | _]} -> rect.style.fill end) ==
               [slot(1), slot(2), slot(1), slot(2)]
    end
  end

  test "the rendered chart: every path, point and label of the marks names a series (#508)" do
    chart =
      chart([
        %{type: :line, channels: %{x: :t, y: :v, series: :k}, label: %{text: [{:field, :k}]}},
        %{type: :circle, channels: %{x: :t, y: :v, series: :k}}
      ])

    {:ok, applied} = Chart.apply(chart, sources: @sources)
    svg = Chart.render(applied, root: true)

    for tag <- ~w(path circle) do
      elements = Regex.scan(~r/<#{tag}\b[^>]*>/, svg) |> List.flatten()
      assert elements != []
      assert Enum.all?(elements, &(&1 =~ ~r/data-series="k[01]"/)), "a #{tag} names no series"
    end

    assert length(Regex.scan(~r/<circle\b[^>]*data-series="k0"/, svg)) == 2
    assert length(Regex.scan(~r/<text class="mark-label" data-series="k[01]"/, svg)) == 2
  end
end
