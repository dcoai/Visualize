defmodule Visualize.Chart.SchemaTest do
  @moduledoc "The schema as data agrees with spec/14 and with the modules it names."
  use ExUnit.Case, async: true

  alias Visualize.Chart
  alias Visualize.Chart.Schema
  alias Visualize.Shape.{Curve, Symbol}
  alias Visualize.Theme

  doctest Schema

  @facets [:binding, :channel, :geometry, :style, :content]
  @merges [:concat, :union, :deep, :override]

  test "every key of every kind carries a facet and a merge rule" do
    for kind <- Schema.kinds(), spec <- Schema.describe(kind) do
      assert spec.facet in @facets, "#{kind}.#{spec.key}"
      assert spec.merge in @merges, "#{kind}.#{spec.key}"
      assert is_boolean(spec.required)

      refute spec.required and spec.default != nil,
             "#{kind}.#{spec.key} is required with a default"
    end

    for facet <- @facets, do: assert(Schema.keys(facet) != [], "#{facet}")
  end

  test "kinds/0 starts with the design and has no duplicates" do
    assert hd(Schema.kinds()) == :design
    assert Enum.uniq(Schema.kinds()) == Schema.kinds()
    assert length(Schema.kinds()) == 47
  end

  test "keys/1 and keys/2 are how style is known" do
    style_keys = Schema.keys(:style)
    assert {:design, :theme} in style_keys
    assert {:design, :styles} in style_keys
    assert {:mark, :style} in style_keys
    assert {:axis, :style} in style_keys
    assert {:style, :fill} in style_keys
    assert length(Schema.keys(:style, :style)) == 15
    assert length(Schema.keys(:flat_style, :style)) == 29
    assert {:style, :extends} in style_keys
    assert Schema.keys(:axis, :content) == [:format, :prefix, :unit, :measure]
    assert Schema.keys(:measure, :content) == [:unit, :quantity]
    assert Schema.keys(:label, :geometry) == [:dx, :dy, :rotate]
  end

  test "key/2 and default/2" do
    assert Schema.key(:mark, :render).default == :auto
    assert Schema.key(:mark, :nope) == nil
    assert Schema.default(:design, :version) == nil
    assert Schema.default(:axis, :style) == :axis
    assert Schema.default(:ticks, :size_inner) == 6

    assert_raise ArgumentError, fn -> Schema.describe(:nope) end
  end

  test "the struct's defaults are the schema's" do
    for {key, value} <- Map.from_struct(%Chart{}), key != :version do
      assert value == Schema.default(:design, key), "#{key}"
    end
  end

  test "mark types, channels and options follow spec/14 §5.2-5.3" do
    assert Schema.mark_types() == [
             :line,
             :area,
             :band,
             :rule,
             :x_band,
             :percentile_band,
             :rose,
             :symbol,
             :needle,
             :arc,
             :path,
             :rect,
             :circle,
             :text,
             :tiles,
             :choose
           ]

    assert Schema.channels(:area) ==
             %{required: [:x, :y], optional: [:x0, :x1, :y0, :y1, :series]}

    assert Schema.channels(:percentile_band) ==
             %{required: [:x, :median], optional: [:inner_lo, :inner_hi, :outer_lo, :outer_hi]}

    assert Schema.channels(:path) == %{required: [:path], optional: [:series]}

    assert Schema.channels(:arc) == %{
             required: [:value],
             optional: [:start, :end, :inner, :outer, :series]
           }

    # `series` names what a row belongs to on every type that draws rows: not on a band
    # of all the rows, nor on a basemap (#508, D-126).
    for type <- Schema.mark_types() -- [:percentile_band, :tiles] do
      assert :series in Schema.channels(type).optional, inspect(type) <> " takes no series"
    end

    refute :series in Schema.channels(:percentile_band).optional
    assert Schema.channels(:tiles) == %{required: [], optional: []}

    assert Schema.transform_keys(:bin) == %{required: [:field], optional: [:thresholds, :as]}
    assert Schema.transform_keys(:projection) == %{required: [], optional: [:fields, :field]}
    assert Schema.transform_keys(:filter) == %{required: [:field], optional: [:test, :value]}
    assert Schema.default(:transform, :test) == :present
    assert :projection in Schema.transform_ops() and :filter in Schema.transform_ops()
    assert_raise ArgumentError, fn -> Schema.transform_keys(:nope) end

    assert Schema.options(:arc) == [
             :inner_radius,
             :outer_radius,
             :corner_radius,
             :pad_angle,
             :start_angle,
             :end_angle
           ]

    assert Schema.options(:line) == [:closed]
    assert_raise ArgumentError, fn -> Schema.channels(:nope) end

    channel_keys = Enum.map(Schema.describe(:channels), & &1.key)
    option_keys = Enum.map(Schema.describe(:options), & &1.key)

    for type <- Schema.mark_types() do
      %{required: required, optional: optional} = Schema.channels(type)
      assert Enum.all?(required ++ optional, &(&1 in channel_keys)), "#{type}"
      assert Enum.all?(Schema.options(type), &(&1 in option_keys)), "#{type}"
    end
  end

  test "the enumerations name what the library implements" do
    assert Schema.symbol_types() == Symbol.types()

    for curve <- Schema.curve_types() do
      assert %{} = Curve.generate(curve, [{0, 0}, {1, 1}, {2, 0}], [])
    end

    assert length(Schema.scale_kinds()) == 14
    assert :bin in Schema.transform_ops() and :treemap in Schema.transform_ops()
    assert Schema.builtin_styles() == [:axis, :grid, :label, :title]

    theme = Theme.default()

    for spec <- Schema.describe(:theme) do
      assert spec.default == Map.fetch!(theme, spec.key), "theme.#{spec.key}"
    end
  end
end
