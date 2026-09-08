defmodule Visualize.Chart.BuildTest do
  @moduledoc """
  The builder of spec/14 §16: every function returns a fragment and the fold of the
  fragments is the design, key for key.

  The round trip is the acceptance — each of the thirteen stored designs of
  `test/support/designs/` is written here as a `Visualize.Chart.Build` pipeline, and
  `Visualize.Chart.compose/1` of it must be the identical map — so a builder function that
  writes a key the literal does not, or misses one it does, fails here rather than in a
  golden. The rest holds the schema's word on every option (D-78).
  """
  use ExUnit.Case, async: true

  import Visualize.Chart.Build

  alias Visualize.Chart
  alias Visualize.Chart.Build
  alias Visualize.Designs

  doctest Build

  @margin %{top: 20, right: 20, bottom: 30, left: 40}

  describe "the stored designs as pipelines" do
    for name <- Designs.names() do
      test "#{name}" do
        name = unquote(name)
        assert {:ok, built} = Chart.compose(pipeline(name))
        assert built == Designs.design(name)
        assert {:ok, _chart} = Chart.from_map(built)
      end
    end
  end

  describe "an option is a key of the node the function builds" do
    test "a design key the schema does not know" do
      assert_raise ArgumentError, ~r/:themes is not a key of a :design node/, fn ->
        chart(themes: :default)
      end
    end

    test "a misspelt style key" do
      assert_raise ArgumentError, ~r/:stoke_width is not a key of a :style node/, fn ->
        style(:series, stoke_width: 2)
      end
    end

    test "a legend key that belongs to an axis" do
      assert_raise ArgumentError, ~r/:ticks is not a key of a :legend node/, fn ->
        legend(:color, ticks: 4)
      end
    end

    test "a transform key the schema does not know" do
      assert_raise ArgumentError, ~r/:threshold is not a key of a :transform node/, fn ->
        bin(from(:samples), :w, threshold: 5)
      end
    end

    test "the keys a node does know are kept as given" do
      assert axis(:x, :bottom, ticks: 6, format: "%H:%M", grid: true) == %{
               frame: %{
                 axes: [%{scale: :x, side: :bottom, ticks: 6, format: "%H:%M", grid: true}]
               }
             }
    end
  end

  describe "a mark takes exactly its type's channels and options" do
    test "a channel the type does not read" do
      assert_raise ArgumentError, ~r/:angle is not a channel of a :line mark/, fn ->
        mark(:line, :series, %{x: :t, y: :v, angle: :a})
      end
    end

    test "an option the type does not read" do
      assert_raise ArgumentError, ~r/:height is not an option of a :line mark/, fn ->
        mark(:line, :series, %{x: :t, y: :v}, options: %{height: 10})
      end
    end

    test "every channel of every type is accepted" do
      for type <- Chart.Schema.mark_types() do
        %{required: required, optional: optional} = Chart.Schema.channels(type)
        channels = Map.new(required ++ optional, &{&1, :f})
        options = Map.new(Chart.Schema.options(type), &{&1, 1})

        assert %{marks: [mark]} = mark(type, :src, channels, options: options)
        assert mark.channels == channels
        assert mark.options == options
      end
    end

    test "a type the schema does not know" do
      assert_raise ArgumentError, ~r/not a mark type: :spline/, fn ->
        mark(:spline, :series, %{x: :t})
      end
    end

    test "a variable standing for a whole node passes through" do
      assert %{marks: [mark]} =
               mark(:band, :states, %{x0: :t0, x1: :t1}, options: Chart.var(:band))

      assert mark.options == Chart.var(:band)
      assert %{marks: [%{channels: %Chart.Var{}}]} = mark(:line, :series, Chart.var(:c))
    end
  end

  describe "data nodes" do
    test "from/1 carries no transforms key" do
      assert from(:primary) == %{source: :primary}
    end

    test "an appender reads a source name as from/1 of it" do
      assert bin(:samples, :w, thresholds: 20) == bin(from(:samples), :w, thresholds: 20)
    end

    test "the steps run in the order they were appended" do
      node = from(:data) |> treemap(padding: 2) |> filter(:height, test: :eq, value: 0)

      assert node == %{
               source: :data,
               transforms: [
                 %{op: :treemap, padding: 2},
                 %{op: :filter, field: :height, test: :eq, value: 0}
               ]
             }
    end
  end

  describe "the fold" do
    test "two fragments that declare one name differently are a conflict at its path" do
      fragments = [style(:series, stroke_width: 1), style(:series, stroke_width: 2)]
      assert Chart.compose(fragments) == {:error, [{[:styles, :series], :conflict}]}
    end

    test "scales union and axes concatenate whatever the order of the fragments" do
      fragments = [scale(:x, :time), axis(:x, :bottom), cartesian(400, 200), axis(:y, :left)]
      assert {:ok, %{frame: frame}} = Chart.compose(fragments)
      assert frame.kind == :cartesian
      assert frame.scales == %{x: %{kind: :time}}
      assert frame.axes == [%{scale: :x, side: :bottom}, %{scale: :y, side: :left}]
    end

    test "a facet frame lifts by and columns into its facet node" do
      assert facet(600, 400, by: :region, columns: 2) == %{
               frame: %{
                 kind: :facet,
                 size: %{width: 600, height: 400},
                 facet: %{by: :region, columns: 2}
               }
             }
    end

    test "the seed carries the current schema version" do
      assert chart() == %{version: Chart.Migration.current()}
    end
  end

  # -- the thirteen stored designs (test/support/designs/) --------------------------------

  defp pipeline(:line) do
    [
      chart(meta: %{name: "line"}),
      source(:primary, [:t, :v], default: :series),
      source(:events, [:at, :sha]),
      var(:title, "Weight"),
      var(:unit, "kg"),
      style(:series, stroke_width: 1.5),
      style(:muted, stroke: :axis, opacity: 0.6),
      cartesian(400, 200, margin: @margin),
      scale(:x, :time),
      scale(:y, :linear, domain: [0, :auto], nice: true),
      axis(:x, :bottom, ticks: 4, format: "%H:%M"),
      axis(:y, :left, ticks: 4, grid: true),
      mark(:line, :primary, %{x: :t, y: :v}, style: :series),
      mark(:rule, :events, %{x: :at},
        label: %{text: ["deploy ", {:field, :sha}]},
        style: :muted
      ),
      title([Chart.var(:title)]),
      label({:axis, :y}, [Chart.var(:unit)])
    ]
  end

  defp pipeline(:step) do
    [
      chart(meta: %{name: "step"}),
      source(:series, [:t, :mood]),
      style(:series, stroke_width: 1.5, curve: :step_after),
      cartesian(400, 200, margin: %{top: 20, right: 20, bottom: 30, left: 50}),
      scale(:x, :time),
      scale(:y, :band, domain: ["down", "base", "up"]),
      axis(:x, :bottom, ticks: 4, format: "%H:%M"),
      axis(:y, :left, grid: true),
      mark(:line, :series, %{x: :t, y: :mood}, style: :series),
      title(["Mood"])
    ]
  end

  defp pipeline(:area) do
    [
      chart(meta: %{name: "area"}),
      source(:series, [:t, :v]),
      style(:series, fill_opacity: 0.4, stroke: :series_1),
      cartesian(400, 200, margin: @margin),
      scale(:x, :time),
      scale(:y, :linear, domain: [0, :auto], nice: true),
      axis(:x, :bottom, ticks: 4, format: "%H:%M"),
      axis(:y, :left, ticks: 4),
      mark(:area, :series, %{x: :t, y: :v}, style: :series),
      title(["Area"])
    ]
  end

  defp pipeline(:stacked_area) do
    [
      chart(meta: %{name: "stacked_area"}),
      source(:series, [:t, :a, :b, :c]),
      cartesian(400, 200, margin: @margin),
      scale(:x, :time),
      scale(:y, :linear, domain: [0, :auto], nice: true),
      scale(:color, :ordinal),
      axis(:x, :bottom, ticks: 4, format: "%H:%M"),
      axis(:y, :left, ticks: 4),
      legend(:color, position: :top_left),
      mark(:area, stack(from(:series), [:a, :b, :c]), %{x: :t, y: :y1, y0: :y0, series: :key}),
      title(["Stacked area"])
    ]
  end

  defp pipeline(:bar) do
    [
      chart(meta: %{name: "bar"}),
      source(:categories, [:cat, :n]),
      cartesian(400, 200, margin: @margin),
      scale(:x, :band, domain: :auto, padding: 0.2),
      scale(:y, :linear, domain: [0, :auto], nice: true),
      axis(:x, :bottom),
      axis(:y, :left, ticks: 4, grid: true),
      mark(:rect, :categories, %{x0: :cat, x1: :cat, y0: 0, y1: :n},
        label: %{text: [{:field, :n}], anchor: :top}
      ),
      title(["Bar"])
    ]
  end

  defp pipeline(:stacked_bar) do
    [
      chart(meta: %{name: "stacked_bar"}),
      source(:categories, [:cat, :a, :b, :c]),
      cartesian(400, 200, margin: @margin),
      scale(:x, :band, padding: 0.2),
      scale(:y, :linear, domain: [0, :auto], nice: true),
      scale(:color, :ordinal),
      axis(:x, :bottom),
      axis(:y, :left, ticks: 4, grid: true),
      legend(:color, position: :top_right),
      mark(
        :rect,
        stack(from(:categories), [:a, :b, :c]),
        %{x0: :cat, x1: :cat, y0: :y0, y1: :y1, value: :key}
      ),
      title(["Stacked bar"])
    ]
  end

  defp pipeline(:state_timeline) do
    [
      chart(meta: %{name: "state_timeline"}),
      source(:states, [:t0, :t1, :state]),
      var(:band, %{height: 50}),
      style(:by_state, fill: {:field, :state}, stroke: :background),
      style(:over, fill: :background, font_size: :font_size, font_family: :font_family),
      cartesian(400, 100, margin: %{top: 20, right: 20, bottom: 30, left: 20}),
      scale(:x, :time),
      scale(:color, :ordinal, domain: ["ok", "degraded", "down"]),
      axis(:x, :bottom, ticks: 6, format: "%H:%M"),
      legend(:color, position: :top),
      mark(:band, :states, %{x0: :t0, x1: :t1},
        options: Chart.var(:band),
        style: :by_state,
        label: %{text: [{:field, :state}], anchor: :middle, style: :over}
      ),
      title(["Build status"])
    ]
  end

  defp pipeline(:status_strip) do
    [
      chart(meta: %{name: "status_strip"}),
      source(:flags, [:t0, :t1, :ok]),
      style(:flag, fill: {:field, :ok}),
      cartesian(400, 60, margin: %{top: 10, right: 10, bottom: 30, left: 10}),
      scale(:x, :time),
      scale(:color, :ordinal, domain: ["pass", "fail"], range: ["#3f8a37", "#c8373b"]),
      axis(:x, :bottom, ticks: 6, format: "%H:%M"),
      mark(:band, :flags, %{x0: :t0, x1: :t1}, options: %{height: 20}, style: :flag)
    ]
  end

  defp pipeline(:single_stat) do
    [
      chart(meta: %{name: "single_stat"}),
      source(:series, [:t, :v]),
      var(:value, "8 kg"),
      var(:delta, "+1.5 vs last week"),
      style(:spark, stroke: :series_1, stroke_width: 1),
      style(:big, fill: :text, font_size: :title_size, font_weight: :bold),
      cartesian(200, 100, margin: %{top: 40, right: 10, bottom: 10, left: 10}),
      scale(:x, :time),
      scale(:y, :linear, domain: [0, :auto]),
      mark(:line, :series, %{x: :t, y: :v}, style: :spark),
      label({:frame, :top_left}, [Chart.var(:value)], style: :big, dy: -30),
      label({:frame, :top_right}, [Chart.var(:delta)], dy: -30)
    ]
  end

  defp pipeline(:heatmap) do
    [
      chart(meta: %{name: "heatmap"}),
      source(:heat, [:hour, :day, :v]),
      cartesian(400, 200, margin: @margin),
      scale(:x, :band, padding: 0.05),
      scale(:y, :band, padding: 0.05),
      scale(:color, :sequential, domain: [0, :auto]),
      axis(:x, :bottom),
      axis(:y, :left),
      legend(:color, position: :top_right),
      mark(:rect, :heat, %{x0: :hour, x1: :hour, y0: :day, y1: :day, value: :v}),
      title(["Heatmap"])
    ]
  end

  defp pipeline(:histogram) do
    [
      chart(meta: %{name: "histogram"}),
      source(:samples, [:w]),
      var(:bins, 5),
      cartesian(400, 200, margin: @margin),
      scale(:x, :linear),
      scale(:y, :linear, domain: [0, :auto]),
      axis(:x, :bottom, ticks: 5),
      axis(:y, :left, ticks: 4, grid: true),
      mark(
        :rect,
        bin(from(:samples), :w, thresholds: Chart.var(:bins)),
        %{x0: :x0, x1: :x1, y0: :y0, y1: :count}
      ),
      title(["Histogram"]),
      label({:axis, :x}, ["kg"])
    ]
  end

  defp pipeline(:scatter) do
    [
      chart(meta: %{name: "scatter"}),
      source(:samples, [:w, :s]),
      style(:dot, symbol: :circle, symbol_size: 40, fill_opacity: 0.7),
      cartesian(400, 200, margin: @margin),
      scale(:x, :linear, nice: true),
      scale(:y, :linear, nice: true),
      axis(:x, :bottom, ticks: 5, grid: true),
      axis(:y, :left, ticks: 4, grid: true),
      mark(:symbol, :samples, %{x: :w, y: :s}, style: :dot),
      title(["Weight against sleep"]),
      label({:axis, :x}, ["kg"]),
      label({:axis, :y}, ["h"])
    ]
  end

  defp pipeline(:rose) do
    [
      chart(meta: %{name: "rose"}),
      source(:wind, [:bearing, :count]),
      style(:petal, fill: :series_1, stroke: :background),
      polar(300, 300, margin: %{top: 30, right: 30, bottom: 30, left: 30}),
      scale(:angle, :radial, domain: [0, 360]),
      scale(:r, :sqrt, domain: [0, :auto]),
      axis(:angle, :bottom, ticks: 8, grid: true),
      axis(:r, :top, ticks: 3, grid: true),
      mark(:rose, :wind, %{angle: :bearing, value: :count},
        options: %{width: 45, pad_angle: 0.02},
        style: :petal
      ),
      title(["Wind"])
    ]
  end
end
