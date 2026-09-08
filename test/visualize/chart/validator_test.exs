defmodule Visualize.Chart.ValidatorTest do
  @moduledoc """
  Every key of every node kind reports a wrong type at its exact path, every required key
  its absence, and every reference kind a dangling name (spec/14 §10).
  """
  use ExUnit.Case, async: true

  import Visualize.Chart, only: [var: 1]

  alias Visualize.Chart.{Schema, Validator}

  # Every node kind present once, every reference resolving.
  @full %{
    version: 1,
    meta: %{name: "Full", description: ["all ", var(:unit)]},
    sources: %{primary: %{fields: [:t, :v, :sha], default: :main}, other: %{fields: [:w]}},
    vars: %{unit: %{default: "%"}, accent: %{}},
    theme: %{
      name: :house,
      series: ["#111111", "#222222"],
      axis: "#666666",
      grid: "#e0e0e0",
      text: "#333333",
      background: "#ffffff",
      font_family: "sans-serif",
      font_size: 10,
      label_size: 12,
      title_size: 16
    },
    styles: %{
      series: %{
        stroke: var(:accent),
        stroke_width: 2,
        curve: :catmull_rom,
        curve_opts: %{alpha: 0.5},
        fill: {:field, :sha}
      },
      muted: %{stroke: :axis, opacity: 0.6, font_family: :font_family, symbol: :star}
    },
    frame: %{
      kind: :cartesian,
      size: %{width: 600, height: 300},
      margin: %{top: 20, right: 20, bottom: 30, left: 40},
      scales: %{
        x: %{kind: :time, domain: :auto},
        y: %{kind: :linear, domain: [0, :auto], nice: true},
        color: %{kind: :ordinal, range: :category10}
      },
      axes: [
        %{scale: :x, side: :bottom, ticks: %{count: 6, size_inner: 4}, format: "%H:%M"},
        %{scale: :y, side: :left, ticks: 5, grid: true}
      ],
      legend: %{scale: :color, position: :top_right, title: ["colour"]},
      projection: %{type: :mercator, scale: 100, translate: [1, 2]},
      facet: %{by: :sha, columns: 2},
      viewport: %{scale: :x, span: 60}
    },
    marks: [
      %{type: :line, data: :primary, channels: %{x: :t, y: :v}, style: :series, render: :svg},
      %{
        type: :rule,
        data: :primary,
        channels: %{x: :t},
        label: %{text: ["deploy ", {:field, :sha}], anchor: :top, style: :muted, dx: 1, dy: 2}
      },
      %{
        type: :arc,
        data: %{
          source: :primary,
          transforms: [%{op: :bin, field: :v, thresholds: 20, as: :count}]
        },
        channels: %{value: :count},
        options: %{inner_radius: 10, outer_radius: 50}
      }
    ],
    labels: [
      %{anchor: :title, text: ["Full ", var(:unit)], style: :title, dx: 0, dy: -4},
      %{anchor: {:axis, :y}, text: ["unit"]}
    ]
  }

  # Where an instance of each node kind sits in @full.
  @paths %{
    design: [],
    meta: [:meta],
    source: [:sources, :primary],
    var: [:vars, :unit],
    theme: [:theme],
    style: [:styles, :series],
    curve_opts: [:styles, :series, :curve_opts],
    label: [:labels, 0],
    frame: [:frame],
    size: [:frame, :size],
    margin: [:frame, :margin],
    scale: [:frame, :scales, :y],
    axis: [:frame, :axes, 0],
    ticks: [:frame, :axes, 0, :ticks],
    legend: [:frame, :legend],
    projection: [:frame, :projection],
    facet: [:frame, :facet],
    viewport: [:frame, :viewport],
    mark: [:marks, 2],
    data: [:marks, 2, :data],
    transform: [:marks, 2, :data, :transforms, 0],
    channels: [:marks, 2, :channels],
    options: [:marks, 2, :options],
    mark_label: [:marks, 1, :label]
  }

  defp errors(design) do
    {:error, errors} = Validator.validate(design)
    errors
  end

  defp put_at(_map, [], value), do: value

  defp put_at(list, [i | rest], value) when is_integer(i) do
    List.update_at(list, i, &put_at(&1, rest, value))
  end

  defp put_at(map, [k | rest], value) do
    Map.put(map, k, put_at(Map.get(map, k, %{}), rest, value))
  end

  defp delete_at(map, [k]), do: Map.delete(map, k)

  defp delete_at(list, [i | rest]) when is_integer(i),
    do: List.update_at(list, i, &delete_at(&1, rest))

  defp delete_at(map, [k | rest]), do: Map.update!(map, k, &delete_at(&1, rest))

  # A mark of the type with its required channels, at index 0 of a minimal design.
  defp design_with_mark(type) do
    channels = Map.new(Schema.channels(type).required, &{&1, :t})
    mark = %{type: type, data: :primary, channels: channels}
    %{version: 1, sources: %{primary: %{fields: [:t]}}, frame: %{kind: :cartesian}, marks: [mark]}
  end

  test "the fixture covers every node kind and validates" do
    assert Enum.sort(Map.keys(@paths)) == Enum.sort(Schema.kinds())
    assert Validator.validate(@full) == :ok
  end

  # The full design, its transform on an op that reads `key` when the kind is a transform.
  defp reading(:transform, key) when key != :op do
    op =
      Enum.find(Schema.transform_ops(), fn op ->
        %{required: r, optional: o} = Schema.transform_keys(op)
        key in (r ++ o)
      end)

    put_at(@full, @paths[:transform], %{op: op})
  end

  defp reading(_kind, _key), do: @full

  describe "types" do
    test "every key of every node kind reports a wrong type at its path" do
      for kind <- Schema.kinds() -- [:channels, :options], spec <- Schema.describe(kind) do
        path = @paths[kind] ++ [spec.key]
        errors = errors(put_at(reading(kind, spec.key), path, {:bad}))

        assert Enum.any?(errors, fn
                 {^path, {:type, _}} -> true
                 {^path, {:enum, _}} -> true
                 _ -> false
               end),
               "#{inspect(path)} did not report the wrong type: #{inspect(errors)}"
      end
    end

    test "every channel and option reports a wrong type on the mark that reads it" do
      for kind <- [:channels, :options], spec <- Schema.describe(kind) do
        type =
          Enum.find(Schema.mark_types(), fn type ->
            spec.key in read_keys(kind, type)
          end)

        assert type, "no mark type reads #{kind}.#{spec.key}"
        path = [:marks, 0, kind, spec.key]
        design = put_at(design_with_mark(type), path, {:bad})
        assert {path, {:type, spec.type}} in errors(design)
      end
    end

    test "every required key reports its absence" do
      for kind <- Schema.kinds(), spec <- Schema.describe(kind), spec.required do
        path = @paths[kind] ++ [spec.key]
        assert {path, :required} in errors(delete_at(@full, path))
      end
    end

    test "a required channel of the mark type reports its absence" do
      design = design_with_mark(:percentile_band)
      design = put_at(design, [:marks, 0, :channels], %{x: :t})
      assert errors(design) == [{[:marks, 0, :channels, :median], :required}]
    end

    test "a key a transform op requires reports its absence, one it does not read is invalid" do
      path = @paths[:transform]
      missing = put_at(@full, path, %{op: :stack, order: :none})
      assert errors(missing) == [{path ++ [:fields], :required}]

      extra = put_at(@full, path ++ [:offset], :expand)
      assert errors(extra) == [{path ++ [:offset], {:invalid_for, :bin}}]
    end

    test "an unknown key reports at its path in every node kind" do
      for {kind, path} <- @paths do
        assert {path ++ [:bogus], :unknown_key} in errors(put_at(@full, path ++ [:bogus], 1)),
               "#{kind}"
      end
    end

    test "a channel or option the mark type does not read is invalid for it" do
      design = put_at(design_with_mark(:line), [:marks, 0, :channels, :value], :t)
      assert errors(design) == [{[:marks, 0, :channels, :value], {:invalid_for, :line}}]

      design = put_at(design_with_mark(:line), [:marks, 0, :options, :radius], 3)
      assert errors(design) == [{[:marks, 0, :options, :radius], {:invalid_for, :line}}]
    end

    test "a field reference in a frame label has no datum" do
      design = put_at(@full, [:labels, 0, :text], ["a", {:field, :sha}])
      assert errors(design) == [{[:labels, 0, :text, 1], {:invalid_for, :label}}]
    end

    test "an extent carries :auto only as one of two bounds" do
      assert Validator.validate(put_at(@full, [:frame, :scales, :y, :domain], [:auto, 5])) == :ok

      assert errors(put_at(@full, [:frame, :scales, :y, :domain], [1, :auto, 5])) ==
               [{[:frame, :scales, :y, :domain], {:type, :extent}}]
    end

    test "a one_of reports the chosen alternative's errors" do
      design = put_at(@full, [:marks, 2, :data, :transforms, 0, :op], :nope)

      assert errors(design) ==
               [{[:marks, 2, :data, :transforms, 0, :op], {:enum, Schema.transform_ops()}}]
    end

    test "a string where a name belongs is a type error" do
      assert errors(put_at(@full, [:marks, 0, :channels, :x], "t")) ==
               [{[:marks, 0, :channels, :x], {:type, :channel}}]
    end

    test "the version must be the current one" do
      assert errors(Map.put(@full, :version, 2)) == [{[:version], {:unsupported_version, 2}}]
    end

    test "an empty theme series is reported" do
      assert errors(put_at(@full, [:theme, :series], [])) == [{[:theme, :series], :required}]
    end

    test "slots resolve against the default theme when none is named" do
      design = %{version: 1, frame: %{kind: :cartesian}, styles: %{s: %{opacity: :none}}}
      assert errors(design) == [{[:styles, :s, :opacity], {:undeclared, :slot, :none}}]
    end

    test "something other than a map is not a design" do
      assert Validator.validate(:nope) == {:error, [{[], {:type, {:node, :design}}}]}
    end
  end

  describe "references" do
    test "scales" do
      for path <- [
            [:frame, :axes, 0, :scale],
            [:frame, :legend, :scale],
            [:frame, :viewport, :scale]
          ] do
        assert errors(put_at(@full, path, :nope)) == [{path, {:undeclared, :scale, :nope}}]
      end

      assert errors(put_at(@full, [:labels, 1, :anchor], {:axis, :nope})) ==
               [{[:labels, 1, :anchor], {:undeclared, :scale, :nope}}]
    end

    test "styles, including the built-in names" do
      for path <- [
            [:marks, 0, :style],
            [:marks, 1, :label, :style],
            [:frame, :axes, 0, :style],
            [:frame, :legend, :style],
            [:labels, 0, :style]
          ] do
        assert errors(put_at(@full, path, :nope)) == [{path, {:undeclared, :style, :nope}}]
        assert Validator.validate(put_at(@full, path, :grid)) == :ok
      end
    end

    test "sources" do
      assert errors(put_at(@full, [:marks, 0, :data], :nope)) ==
               [{[:marks, 0, :data], {:undeclared, :source, :nope}}]

      assert errors(put_at(@full, [:marks, 2, :data, :source], :nope)) ==
               [{[:marks, 2, :data, :source], {:undeclared, :source, :nope}}]
    end

    test "variables, wherever they appear" do
      for path <- [
            [:meta, :description, 1],
            [:styles, :series, :stroke],
            [:labels, 0, :text, 1],
            [:marks, 1, :label, :text, 0],
            [:marks, 2, :options],
            [:frame, :size]
          ] do
        assert errors(put_at(@full, path, var(:nope))) == [{path, {:undeclared, :var, :nope}}]
      end
    end

    test "fields, against the mark's source" do
      assert errors(put_at(@full, [:marks, 0, :channels, :x], :nope)) ==
               [{[:marks, 0, :channels, :x], {:undeclared, :field, :nope}}]

      assert errors(put_at(@full, [:marks, 0, :channels, :x], {:field, :nope})) ==
               [{[:marks, 0, :channels, :x], {:undeclared, :field, :nope}}]

      assert errors(put_at(@full, [:marks, 1, :label, :text, 1], {:field, :nope})) ==
               [{[:marks, 1, :label, :text, 1], {:undeclared, :field, :nope}}]

      # After a transform the columns are the transform's: unchecked until application.
      assert Validator.validate(put_at(@full, [:marks, 2, :channels, :value], :anything)) == :ok

      # A source read through a data node without transforms is checked.
      design = put_at(@full, [:marks, 0, :data], %{source: :primary, transforms: []})

      assert errors(put_at(design, [:marks, 0, :channels, :y], :nope)) ==
               [{[:marks, 0, :channels, :y], {:undeclared, :field, :nope}}]
    end

    test "theme slots, against the built-in or inline theme" do
      assert errors(put_at(@full, [:styles, :muted, :stroke], :nope)) ==
               [{[:styles, :muted, :stroke], {:undeclared, :slot, :nope}}]

      assert errors(put_at(@full, [:styles, :muted, :stroke], :series_3)) ==
               [{[:styles, :muted, :stroke], {:undeclared, :slot, :series_3}}]

      assert Validator.validate(put_at(@full, [:styles, :muted, :stroke], {:series, 99})) == :ok
      assert Validator.validate(put_at(@full, [:styles, :muted, :stroke], :series_2)) == :ok

      dark = put_at(@full, [:theme], :dark)
      assert Validator.validate(put_at(dark, [:styles, :muted, :stroke], :series_10)) == :ok

      assert errors(put_at(dark, [:styles, :muted, :font_size], :series_11)) ==
               [{[:styles, :muted, :font_size], {:undeclared, :slot, :series_11}}]

      # A theme the validator does not know leaves slots to application.
      house = put_at(@full, [:theme], :house)
      assert Validator.validate(put_at(house, [:styles, :muted, :stroke], :anything)) == :ok
    end
  end

  describe "errors" do
    test "are ordered by path" do
      design =
        @full
        |> put_at([:marks, 0, :type], 3)
        |> put_at([:frame, :kind], 3)
        |> Map.delete(:version)

      assert Enum.map(errors(design), &elem(&1, 0)) == [
               [:frame, :kind],
               [:marks, 0, :type],
               [:version]
             ]
    end

    test "format/1 renders a path and a reason in words" do
      assert Validator.format({[:marks, 1, :channels, :y], {:undeclared, :field, :temp}}) ==
               "marks[1].channels.y: field :temp is not declared by the mark's source"

      assert Validator.format({[], {:type, {:node, :design}}}) == "design: must be a design node"

      assert Validator.format({[:frame, :kind], {:enum, [:cartesian, :polar]}}) ==
               "frame.kind: must be one of :cartesian, :polar"

      assert Validator.format({[:version], {:unsupported_version, 2}}) ==
               "version: version 2 is not supported; the current version is 1"

      assert Validator.format({[:marks, 0, :options, :radius], {:invalid_for, :line}}) ==
               "marks[0].options.radius: is not read by :line"

      assert Validator.format({[:styles, :s, :fill], {:type, :colour}}) ==
               "styles.s.fill: must be a colour string, :none or a theme slot"
    end
  end

  defp read_keys(:channels, type) do
    %{required: required, optional: optional} = Schema.channels(type)
    required ++ optional
  end

  defp read_keys(:options, type), do: Schema.options(type)
end
