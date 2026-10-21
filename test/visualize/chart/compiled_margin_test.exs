defmodule Visualize.Chart.CompiledMarginTest do
  # A compiled chart's margin is the latest tick's (spec/14 §12.5, #860, D-222): a top
  # legend in its margin grows it to the tick's rows, and the static regions follow. A
  # grown margin that leaves the plot no height raises (§4.5).
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Visualize.Chart
  alias Visualize.Chart.{Compiled, Frame}

  @size {300, 200}

  # A top legend in the margin over an inferred color scale, with fixed position scales,
  # so both axes are static regions and the legend is the only furniture that moves.
  @design %{
    version: 2,
    sources: %{primary: %{fields: [:n, :v, :k]}},
    frames: %{
      main: %{
        kind: :cartesian,
        margin: %{top: 20, right: 20, bottom: 30, left: 40},
        scales: %{
          x: %{kind: :linear, domain: [0, 10]},
          y: %{kind: :linear, domain: [0, 10]},
          color: %{kind: :ordinal}
        },
        axes: [%{scale: :x, side: :bottom}, %{scale: :y, side: :left}],
        legend: %{scale: :color, position: :top, inside: false}
      }
    },
    marks: [%{type: :line, data: :primary, channels: %{x: :n, y: :v, series: :k}}]
  }

  # `count` series of two rows each; "series-12" and its kin wrap to five rows at 240 wide.
  defp rows(count, name \\ &"series-#{&1}") do
    %{primary: for(s <- 1..count, i <- 0..1, do: %{n: i * 5, v: s, k: name.(s)})}
  end

  defp compile!(sources, opts \\ []) do
    {:ok, %{"main" => compiled}} = Chart.compile(@design, [sources: sources, size: @size] ++ opts)
    compiled
  end

  # The static x axis's translate: the plot's height below the plot's top.
  defp axis_transform(%Compiled{regions: regions}) do
    %{status: :static, static: [axis]} = Enum.find(regions, &(&1.region == {:axis, 0}))
    axis.transform
  end

  # The frame a tick over these sources realizes, as the compiled chart realizes it.
  defp tick_frame(%Compiled{chart: chart}, sources),
    do: Frame.new(chart, sources: sources, size: @size)

  describe "a tick's margin carries into the compiled chart (D-222)" do
    test "stepped from one series to twelve, the static axes are where a fresh compile puts them" do
      one = compile!(rows(1))
      twelve = compile!(rows(12))
      assert one.margin.top == 20
      assert twelve.margin.top > 20

      {_group, stepped} = Compiled.step(one, rows(12))

      assert stepped.margin == twelve.margin
      assert stepped.plot == twelve.plot
      assert stepped.box == twelve.box
      assert axis_transform(stepped) == axis_transform(twelve)
      assert Compiled.static(stepped) == Compiled.static(twelve)
    end

    test "the stepped group is the fresh chart's, translated by the grown margin" do
      {group, _stepped} = Compiled.step(compile!(rows(1)), rows(12))
      {fresh, _twelve} = Compiled.step(compile!(rows(12)), rows(12))
      assert group == fresh

      assert Compiled.svg(compile!(rows(1)), rows(12)) ==
               Compiled.svg(compile!(rows(12)), rows(12))
    end

    test "stepped back to one series, the chart is the one it was compiled as" do
      one = compile!(rows(1))
      {_group, stepped} = Compiled.step(one, rows(12))
      {_group, back} = Compiled.step(stepped, rows(1))

      assert back.margin == one.margin
      assert back.plot == one.plot
      assert axis_transform(back) == axis_transform(one)
      assert Compiled.static(back) == Compiled.static(one)
    end

    test "on the canvas backend the tick's static document and canvas match a fresh compile" do
      one = compile!(rows(1), ceiling: 1)
      twelve = compile!(rows(12), ceiling: 1)
      assert [{target, _points}] = Compiled.targets(one)
      assert target in [:canvas, :binary]

      {payload, ticked} = Compiled.tick(one, rows(12))
      {fresh, _twelve} = Compiled.tick(twelve, rows(12))

      assert ticked.margin == twelve.margin
      assert axis_transform(ticked) == axis_transform(twelve)
      assert Compiled.static(ticked) == Compiled.static(twelve)
      assert payload == fresh

      {_payload, back} = Compiled.tick(ticked, rows(1))
      assert Compiled.static(back) == Compiled.static(one)
    end

    test "the hybrid chart map is drawn on the tick's margin" do
      map = Compiled.render(compile!(rows(1), ceiling: 1), rows(12))
      assert map == Compiled.render(compile!(rows(12), ceiling: 1), rows(12))
    end

    test "a viewport's incremental canvas is redrawn whole on a new plot, then scrolls again" do
      # The canvas mark reads no moving scale but the window's, so the layer scrolls (§12.5);
      # the legend's categories come from an SVG mark beside it.
      design =
        @design
        |> put_in([:frames, :main, :scales, :x], %{kind: :linear})
        |> put_in([:frames, :main, :viewport], %{scale: :x, span: 4})
        |> put_in([:marks], [
          %{type: :line, data: :primary, channels: %{x: :n, y: :v}, render: :binary},
          Map.put(hd(@design.marks), :render, :svg)
        ])

      {:ok, %{"main" => compiled}} = Chart.compile(design, sources: rows(1), size: @size)
      {first, compiled} = Compiled.tick(compiled, rows(1), now: 5)
      assert first.incremental.mode == "full"
      {second, compiled} = Compiled.tick(compiled, rows(1), now: 6)
      assert second.incremental.mode == "scroll_x"

      # Twelve series grow the top margin: the canvas is another size, so its old pixels
      # are not scrolled but repainted (spec/14 §12.5, #456).
      {grown, compiled} = Compiled.tick(compiled, rows(12), now: 7)
      assert compiled.plot.height < 150
      assert %{mode: "full", dx: 0, dy: 0} = grown.incremental
      {next, _compiled} = Compiled.tick(compiled, rows(12), now: 8)
      assert next.incremental.mode == "scroll_x"
    end

    test "a tick on the compiled plot leaves the chart as it was" do
      one = compile!(rows(1))
      {_group, stepped} = Compiled.step(one, rows(1))
      assert Compiled.static(stepped) == Compiled.static(one)
      assert stepped.regions == one.regions
    end
  end

  describe "a grown margin stays inside the box (D-222)" do
    test "a top legend whose rows leave the plot no height raises, naming the side, the need and the box" do
      long = rows(12, &"a-very-long-series-name-#{&1}")

      assert_raise ArgumentError,
                   ~r/legend at :top outside the plot needs 196 in the top margin, .*box 200 high/,
                   fn -> compile!(long) end
    end

    test "a tick whose rows grow the margin past the box raises" do
      one = compile!(rows(1))
      long = rows(12, &"a-very-long-series-name-#{&1}")

      assert_raise ArgumentError, ~r/top margin/, fn -> Compiled.step(one, long) end
      assert_raise ArgumentError, ~r/top margin/, fn -> Compiled.tick(one, long) end
    end

    test "a margin the author gave is not judged" do
      design = put_in(@design, [:frames, :main, :margin, :top], 180)
      assert {:ok, %{"main" => compiled}} = Chart.compile(design, sources: rows(1), size: @size)
      assert compiled.plot.height == -10
    end
  end

  describe "recurrence guard (D-222)" do
    property "the static regions stand on the tick frame's plot on every tick" do
      check all(counts <- list_of(integer(1..12), min_length: 1, max_length: 8)) do
        Enum.reduce(counts, compile!(rows(1)), fn count, compiled ->
          {_group, compiled} = Compiled.step(compiled, rows(count))
          frame = tick_frame(compiled, rows(count))

          assert compiled.margin == frame.margin
          assert compiled.plot == frame.plot
          assert axis_transform(compiled).operations == [{:translate, 0, frame.plot.height}]
          compiled
        end)
      end
    end
  end
end
