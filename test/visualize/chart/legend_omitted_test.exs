defmodule Visualize.Chart.LegendOmittedTest do
  # A legend that cannot be laid out in its room is omitted, not raised: not drawn, no
  # margin taken, so the plot keeps the height it has with no legend, and the frame
  # reports why with its entry count (spec/14 §4.5, #876, #914, D-231; metresis#540).
  use ExUnit.Case, async: true

  alias Visualize.Chart
  alias Visualize.Chart.Frame

  # A metresis panel's box: a dashboard grid cell.
  @size {600, 240}
  @margin %{top: 20, right: 20, bottom: 30, left: 40}

  # Series by host and mount over an inferred color scale, as metresis#540's bar chart of
  # disk use: how many there are, and how long their names, is the data's.
  defp design(legend) do
    %{
      version: 3,
      sources: %{primary: %{fields: [:n, :v, :k]}},
      frames: %{
        main: %{
          kind: :cartesian,
          margin: @margin,
          scales: %{
            x: %{kind: :linear, domain: [0, 10]},
            y: %{kind: :linear, domain: [0, 50]},
            color: %{kind: :ordinal}
          },
          axes: [%{scale: :x, side: :bottom}, %{scale: :y, side: :left}],
          legend: legend && Map.merge(%{scale: :color}, legend)
        }
      },
      marks: [%{type: :line, data: :primary, channels: %{x: :n, y: :v, series: :k}}]
    }
  end

  defp host_mount(i), do: "host-#{div(i, 4)}:/mount/data-#{rem(i, 4)}"

  defp rows(names),
    do: %{
      primary: for({name, s} <- Enum.with_index(names), i <- 0..1, do: %{n: i * 5, v: s, k: name})
    }

  defp apply!(legend, names) do
    design = legend |> design() |> drop_nil_legend()
    {:ok, applied} = Chart.apply(design, sources: rows(names), size: @size)
    applied
  end

  defp drop_nil_legend(%{frames: %{main: %{legend: nil}}} = design),
    do: update_in(design, [:frames, :main], &Map.delete(&1, :legend))

  defp drop_nil_legend(design), do: design

  defp forty, do: Enum.map(1..40, &host_mount/1)

  for {name, legend, names, reason} <- [
        {"a top margin grown past the box", quote(do: %{position: :top, inside: false}),
         quote(do: forty()), :height},
        {"a side margin narrower than the labels", quote(do: %{position: :right, inside: false}),
         quote(do: Enum.map(1..3, &host_mount/1)), :width},
        {"a row wider than the plot with wrap: false",
         quote(do: %{position: :top, inside: false, wrap: false}), quote(do: forty()), :row},
        {"a single cell wider than the plot", quote(do: %{position: :top, inside: false}),
         quote(do: ["a", String.duplicate("very-long-mount-name/", 4)]), :cell}
      ] do
    test "#{name} omits the legend: no raise, no legend group, the plot's own height, reported" do
      names = unquote(names)
      applied = apply!(unquote(legend), names)
      bare = apply!(nil, names)
      frame = applied.frames["main"]

      refute Chart.render(applied) =~ ~s(class="legend")
      assert frame.margin == @margin
      assert frame.plot == bare.frame.plot
      assert frame.plot.height == 240 - 20 - 30
      assert Frame.legend_extent(frame) == %{width: 0, height: 0}

      assert Frame.legend_fit(frame) ==
               %{status: :omitted, reason: unquote(reason), entries: length(names)}

      # A compiled chart reads the same, and draws it the same.
      {:ok, %{"main" => compiled}} = Chart.compile(applied)
      assert Chart.Compiled.legend_fit(compiled) == Frame.legend_fit(frame)
      assert compiled.plot == bare.frame.plot
      refute Chart.Compiled.svg(compiled, rows(names)) =~ ~s(class="legend")
    end
  end

  test "a legend with room is drawn and reported so; a frame with none reports nil" do
    names = Enum.map(1..3, &host_mount/1)
    applied = apply!(%{position: :top, inside: false}, names)

    assert Chart.render(applied) =~ ~s(class="legend")
    assert Frame.legend_fit(applied.frames["main"]) == %{status: :drawn, entries: 3}
    assert Frame.legend_fit(apply!(nil, names).frames["main"]) == nil
  end

  test "the minimum is checked before the room" do
    applied = apply!(%{position: :top, inside: false, min_entries: 50}, forty())

    assert Frame.legend_fit(applied.frames["main"]) ==
             %{status: :omitted, reason: :min_entries, entries: 40}
  end

  test "what does not depend on the data still raises" do
    assert_raise ArgumentError, ~r/max_label is a count of characters of at least 1/, fn ->
      %{position: :top, max_label: 0}
      |> design()
      |> Chart.from_map!()
      |> Frame.new(sources: rows(["a"]), size: @size)
    end
  end
end
