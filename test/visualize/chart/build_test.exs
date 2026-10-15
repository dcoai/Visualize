defmodule Visualize.Chart.BuildTest do
  @moduledoc """
  The builder of spec/14 §16: every function returns a fragment and the fold of the
  fragments is the design, key for key.

  The round trip is the acceptance — each of the thirteen stored designs of
  `test/support/designs/` is written here as a `Visualize.Chart.Build` pipeline, and
  `Visualize.Chart.compose/1` of it must be the identical map — so a builder function that
  writes a key the literal does not, or misses one it does, fails here rather than in a
  golden. The rest holds the schema's word on every option (D-78) and the correspondence
  between the schema and the generated mark, transform and scale functions (D-79).
  """
  use ExUnit.Case, async: true

  import Visualize.Chart.Build

  alias Visualize.Chart
  alias Visualize.Chart.Build
  alias Visualize.Chart.Build.Generate
  alias Visualize.Chart.Migration
  alias Visualize.Designs

  doctest Build

  @margin %{top: 20, right: 20, bottom: 30, left: 40}

  describe "the stored designs as pipelines" do
    for name <- Designs.names() do
      test "#{name}" do
        name = unquote(name)
        assert {:ok, built} = Chart.compose(pipeline(name))
        # The stored designs are version 2, in flat style keys: the 2 -> 3 step's rewrite
        # of the styles into their parts (D-172) is what a pipeline builds today.
        stored = name |> Designs.design() |> Map.put(:version, 3) |> Migration.parts(:design)
        assert built == stored
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

    test "a style may name the parent it extends" do
      assert style(:heavy, extends: :series, stroke: %{width: 3}) ==
               %{styles: %{heavy: %{extends: :series, stroke: %{width: 3}}}}
    end

    test "a style written in the flat keys of version 2 is built in its parts (D-172)" do
      assert style(:heavy, extends: :series, stroke_width: 3) ==
               %{styles: %{heavy: %{extends: :series, stroke: %{width: 3}}}}

      assert style(:soft, fill: :series_1, fill_opacity: 0.4, curve: :step) ==
               %{
                 styles: %{
                   soft: %{
                     fill: %{type: :solid, color: :series_1, opacity: 0.4},
                     curve: %{type: :step}
                   }
                 }
               }
    end

    test "the keys a node does know are kept as given" do
      assert axis(:x, :bottom, ticks: 6, format: "%H:%M", grid: true) == %{
               frames: %{
                 main: %{
                   axes: [%{scale: :x, side: :bottom, ticks: 6, format: "%H:%M", grid: true}]
                 }
               }
             }
    end
  end

  describe "a mark takes exactly its type's channels and options" do
    test "a channel the type does not read" do
      assert_raise ArgumentError, ~r/:angle is not a channel of a :line mark/, fn ->
        line(:series, %{x: :t, y: :v, angle: :a})
      end
    end

    test "an option the type does not read" do
      assert_raise ArgumentError, ~r/:height is not an option of a :line mark/, fn ->
        line(:series, %{x: :t, y: :v}, options: %{height: 10})
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
               band(:states, %{x0: :t0, x1: :t1}, options: Chart.var(:band))

      assert mark.options == Chart.var(:band)
      assert %{marks: [%{channels: %Chart.Var{}}]} = mark(:line, :series, Chart.var(:c))
    end
  end

  describe "the schema generates the mark, transform and scale functions" do
    test "one function per mark type, taking exactly its channels and options" do
      for type <- Chart.Schema.mark_types() do
        %{required: required, optional: optional} = Chart.Schema.channels(type)
        channels = Map.new(required ++ optional, &{&1, :f})
        options = Map.new(Chart.Schema.options(type), &{&1, 1})

        assert function_exported?(Build, type, 2)
        assert function_exported?(Build, type, 3)

        assert apply(Build, type, [:src, channels, [options: options, style: :s]]) ==
                 mark(type, :src, channels, options: options, style: :s)

        assert_raise ArgumentError, fn -> apply(Build, type, [:src, %{nope: :f}]) end
      end
    end

    # The keys an op's builder takes positionally: its required keys, and `fields` for the
    # projection, whose one required key is either of two (spec/14 §5.4.4, §16).
    defp positional(:projection), do: [:fields]
    defp positional(op), do: Chart.Schema.transform_keys(op).required

    test "one appender per transform op, its required keys as its arguments" do
      for op <- Chart.Schema.transform_ops() do
        %{optional: optional} = Chart.Schema.transform_keys(op)
        required = positional(op)
        optional = optional -- required
        args = Enum.map(required, fn _ -> :f end)

        assert function_exported?(Build, op, 1 + length(required))
        assert function_exported?(Build, op, 2 + length(required))

        node = apply(Build, op, [from(:src) | args] ++ [Enum.map(optional, &{&1, :v})])
        assert [step] = node.transforms
        assert step.op == op
        assert Map.take(step, required) == Map.new(required, &{&1, :f})
        assert Map.take(step, optional) == Map.new(optional, &{&1, :v})
        assert apply(Build, op, [:src | args]) == apply(Build, op, [from(:src) | args])
      end
    end

    test "a projection over a geometry column is projection/3 with nil fields (#349)" do
      assert projection(from(:land), nil, field: :shape) ==
               %{source: :land, transforms: [%{op: :projection, field: :shape}]}
    end

    test "one function per scale kind, suffixed because band is also a mark type" do
      assert :band in Chart.Schema.mark_types()
      assert :band in Chart.Schema.scale_kinds()

      for kind <- Chart.Schema.scale_kinds() do
        name = :"#{kind}_scale"
        assert function_exported?(Build, name, 1)
        assert function_exported?(Build, name, 2)
        assert apply(Build, name, [:s, [domain: :auto]]) == scale(:s, kind, domain: :auto)
      end
    end

    test "a generated function's documentation is the schema's" do
      assert {:docs_v1, _, _, _, _, _, docs} = Code.fetch_docs(Build)
      assert [%{"en" => text}] = for({{:function, :rose, 3}, _, _, doc, _} <- docs, do: doc)
      assert text =~ "A `:rose` mark"
      assert text =~ "Required channels: `angle`."
      assert text =~ "Optional channels: `value`, `series`."
      assert text =~ "Options: `width`, `inner_radius`, `outer_radius`, `pad_angle`."
    end

    test "every generated function is declared to the surface scanner" do
      injected = MapSet.new(Generate.injected())

      for type <- Chart.Schema.mark_types(), arity <- [2, 3] do
        assert {type, arity} in injected
      end

      for kind <- Chart.Schema.scale_kinds(), arity <- [1, 2] do
        assert {:"#{kind}_scale", arity} in injected
      end

      for op <- Chart.Schema.transform_ops() do
        n = length(positional(op))
        assert {op, 1 + n} in injected
        assert {op, 2 + n} in injected
      end

      kinds = Chart.Schema.mark_types() ++ Chart.Schema.scale_kinds()
      assert MapSet.size(injected) == 2 * length(kinds ++ Chart.Schema.transform_ops())
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
      fragments = [scale(:x, :time), axis(:x, :bottom), cartesian(), axis(:y, :left)]
      assert {:ok, %{frames: %{main: frame}}} = Chart.compose(fragments)
      assert frame.kind == :cartesian
      assert frame.scales == %{x: %{kind: :time}}
      assert frame.axes == [%{scale: :x, side: :bottom}, %{scale: :y, side: :left}]
    end

    test "a facet frame lifts by and columns into its facet node" do
      assert facet(by: :region, columns: 2) == %{
               frames: %{
                 main: %{
                   kind: :facet,
                   facet: %{by: :region, columns: 2}
                 }
               }
             }
    end

    test "the seed carries the current schema version" do
      assert chart() == %{version: Chart.Migration.current()}
    end

    test "in_frame/2 puts a group of fragments in one named frame (#383)" do
      fragments =
        [chart(), source(:load, [:t, :v])] ++
          in_frame(:history, [
            cartesian(box: [0, 0, 1, 1]),
            time_scale(:x),
            axis(:x, :bottom),
            line(:load, %{x: :t, y: :v}),
            label(:title, ["Load"])
          ]) ++
          in_frame(:now, [
            polar(box: [0.72, 0.04, 0.24, 0.24]),
            linear_scale(:angle, domain: [0, 4]),
            arc(:load, %{start: 0, end: :v})
          ])

      assert {:ok, design} = Chart.compose(fragments)
      assert design.frames |> Map.keys() |> Enum.sort() == [:history, :now]
      assert design.frames.history.box == [0, 0, 1, 1]
      assert design.frames.history.scales == %{x: %{kind: :time}}
      assert design.frames.now.scales == %{angle: %{kind: :linear, domain: [0, 4]}}
      # A mark and a label say the frame their group was put in.
      assert Enum.map(design.marks, & &1.frame) == [:history, :now]
      assert Enum.map(design.labels, & &1.frame) == [:history]
    end

    test "in_frame/2 keeps a frame a mark already says, and refuses a fragment of two frames" do
      [mark] = in_frame(:now, [line(:load, %{x: :t, y: :v}, frame: :history)])
      assert hd(mark.marks).frame == :history

      two = %{frames: %{a: %{kind: :cartesian}, b: %{kind: :polar}}}

      assert_raise ArgumentError, ~r/takes a fragment of one frame; this one has 2/, fn ->
        in_frame(:now, [two])
      end
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
      cartesian(margin: @margin),
      time_scale(:x),
      linear_scale(:y, domain: [0, :auto], nice: true),
      axis(:x, :bottom, ticks: 4, format: "%H:%M"),
      axis(:y, :left, ticks: 4, grid: true),
      line(:primary, %{x: :t, y: :v}, style: :series),
      rule(:events, %{x: :at},
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
      cartesian(margin: %{top: 20, right: 20, bottom: 30, left: 50}),
      time_scale(:x),
      band_scale(:y, domain: ["down", "base", "up"]),
      axis(:x, :bottom, ticks: 4, format: "%H:%M"),
      axis(:y, :left, grid: true),
      line(:series, %{x: :t, y: :mood}, style: :series),
      title(["Mood"])
    ]
  end

  defp pipeline(:area) do
    [
      chart(meta: %{name: "area"}),
      source(:series, [:t, :v]),
      style(:series, fill_opacity: 0.4, stroke: :series_1),
      cartesian(margin: @margin),
      time_scale(:x),
      linear_scale(:y, domain: [0, :auto], nice: true),
      axis(:x, :bottom, ticks: 4, format: "%H:%M"),
      axis(:y, :left, ticks: 4),
      area(:series, %{x: :t, y: :v}, style: :series),
      title(["Area"])
    ]
  end

  defp pipeline(:stacked_area) do
    [
      chart(meta: %{name: "stacked_area"}),
      source(:series, [:t, :a, :b, :c]),
      cartesian(margin: @margin),
      time_scale(:x),
      linear_scale(:y, domain: [0, :auto], nice: true),
      ordinal_scale(:color),
      axis(:x, :bottom, ticks: 4, format: "%H:%M"),
      axis(:y, :left, ticks: 4),
      legend(:color, position: :top_left),
      area(stack(from(:series), [:a, :b, :c]), %{x: :t, y: :y1, y0: :y0, series: :key}),
      title(["Stacked area"])
    ]
  end

  defp pipeline(:bar) do
    [
      chart(meta: %{name: "bar"}),
      source(:categories, [:cat, :n]),
      cartesian(margin: @margin),
      band_scale(:x, domain: :auto, padding: 0.2),
      linear_scale(:y, domain: [0, :auto], nice: true),
      axis(:x, :bottom),
      axis(:y, :left, ticks: 4, grid: true),
      rect(:categories, %{x0: :cat, x1: :cat, y0: 0, y1: :n},
        label: %{text: [{:field, :n}], anchor: :top}
      ),
      title(["Bar"])
    ]
  end

  defp pipeline(:stacked_bar) do
    [
      chart(meta: %{name: "stacked_bar"}),
      source(:categories, [:cat, :a, :b, :c]),
      cartesian(margin: @margin),
      band_scale(:x, padding: 0.2),
      linear_scale(:y, domain: [0, :auto], nice: true),
      ordinal_scale(:color),
      axis(:x, :bottom),
      axis(:y, :left, ticks: 4, grid: true),
      legend(:color, position: :top_right),
      rect(stack(from(:categories), [:a, :b, :c]), %{
        x0: :cat,
        x1: :cat,
        y0: :y0,
        y1: :y1,
        value: :key
      }),
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
      cartesian(margin: %{top: 20, right: 20, bottom: 30, left: 20}),
      time_scale(:x),
      ordinal_scale(:color, domain: ["ok", "degraded", "down"]),
      axis(:x, :bottom, ticks: 6, format: "%H:%M"),
      legend(:color, position: :top),
      band(:states, %{x0: :t0, x1: :t1},
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
      cartesian(margin: %{top: 10, right: 10, bottom: 30, left: 10}),
      time_scale(:x),
      ordinal_scale(:color, domain: ["pass", "fail"], range: ["#3f8a37", "#c8373b"]),
      axis(:x, :bottom, ticks: 6, format: "%H:%M"),
      band(:flags, %{x0: :t0, x1: :t1}, options: %{height: 20}, style: :flag)
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
      cartesian(margin: %{top: 40, right: 10, bottom: 10, left: 10}),
      time_scale(:x),
      linear_scale(:y, domain: [0, :auto]),
      line(:series, %{x: :t, y: :v}, style: :spark),
      label({:frame, :top_left}, [Chart.var(:value)], style: :big, dy: -30),
      label({:frame, :top_right}, [Chart.var(:delta)], dy: -30)
    ]
  end

  defp pipeline(:heatmap) do
    [
      chart(meta: %{name: "heatmap"}),
      source(:heat, [:hour, :day, :v]),
      cartesian(margin: @margin),
      band_scale(:x, padding: 0.05),
      band_scale(:y, padding: 0.05),
      sequential_scale(:color, domain: [0, :auto]),
      axis(:x, :bottom),
      axis(:y, :left),
      legend(:color, position: :top_right),
      rect(:heat, %{x0: :hour, x1: :hour, y0: :day, y1: :day, value: :v}),
      title(["Heatmap"])
    ]
  end

  defp pipeline(:histogram) do
    [
      chart(meta: %{name: "histogram"}),
      source(:samples, [:w]),
      var(:bins, 5),
      cartesian(margin: @margin),
      linear_scale(:x),
      linear_scale(:y, domain: [0, :auto]),
      axis(:x, :bottom, ticks: 5),
      axis(:y, :left, ticks: 4, grid: true),
      rect(bin(from(:samples), :w, thresholds: Chart.var(:bins)), %{
        x0: :x0,
        x1: :x1,
        y0: :y0,
        y1: :count
      }),
      title(["Histogram"]),
      label({:axis, :x}, ["kg"])
    ]
  end

  defp pipeline(:scatter) do
    [
      chart(meta: %{name: "scatter"}),
      source(:samples, [:w, :s]),
      style(:dot, symbol: :circle, symbol_size: 40, fill_opacity: 0.7),
      cartesian(margin: @margin),
      linear_scale(:x, nice: true),
      linear_scale(:y, nice: true),
      axis(:x, :bottom, ticks: 5, grid: true),
      axis(:y, :left, ticks: 4, grid: true),
      symbol(:samples, %{x: :w, y: :s}, style: :dot),
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
      polar(margin: %{top: 30, right: 30, bottom: 30, left: 30}),
      radial_scale(:angle, domain: [0, 360]),
      sqrt_scale(:r, domain: [0, :auto]),
      axis(:angle, :bottom, ticks: 8, grid: true),
      axis(:r, :top, ticks: 3, grid: true),
      rose(:wind, %{angle: :bearing, value: :count},
        options: %{width: 45, pad_angle: 0.02},
        style: :petal
      ),
      title(["Wind"])
    ]
  end
end
