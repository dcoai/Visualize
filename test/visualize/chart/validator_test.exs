defmodule Visualize.Chart.ValidatorTest do
  @moduledoc """
  Every key of every node kind reports a wrong type at its exact path, every required key
  its absence, and every reference kind a dangling name (spec/14 §10).
  """
  use ExUnit.Case, async: true

  import Visualize.Chart, only: [var: 1]

  alias Visualize.Chart.{Schema, Validator}

  doctest Validator

  # Every node kind present once, every reference resolving.
  @full %{
    version: 3,
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
        stroke: %{type: :solid, color: var(:accent), width: 2, dash: [4, 2]},
        curve: %{type: :catmull_rom, alpha: 0.5},
        fill: %{type: :solid, color: {:field, :sha}}
      },
      muted: %{
        stroke: %{type: :solid, color: :axis},
        opacity: 0.6,
        font: %{family: :font_family, size: :label_size},
        marker: %{shape: :star, size: 64},
        text: %{anchor: :middle, offset: [2, 0]},
        effect: %{type: :shadow, radius: 3},
        transition: %{duration: 200, easing: :cubic_out, fill: %{duration: 400}},
        animation: %{name: :pulse, duration: 1200, iterations: :infinite, delay: 0},
        enter: %{name: :grow, duration: 300, easing: :cubic_out},
        exit: %{name: :explode, duration: 700}
      },
      wash: %{fill: %{type: :paint, name: :fade}}
    },
    defs: %{
      fade: %{
        type: :linear,
        stops: [%{at: 0, color: :series_1, opacity: 0.8}, %{at: 1, color: "#fff"}],
        angle: 180
      }
    },
    defaults: %{stroke: %{width: 2, cap: :round}, line: %{stroke: %{width: 1.5}}},
    layout: %{columns: [1], rows: [1], gap: 4},
    interaction: %{sync: "dash", frame: :main},
    frames: %{
      main: %{
        kind: :cartesian,
        margin: %{top: 20, right: 20, bottom: 30, left: 40},
        scales: %{
          x: %{kind: :time, domain: :auto},
          y: %{
            kind: :linear,
            domain: [0, :auto],
            nice: true,
            transition: %{duration: 300, easing: :cubic_in_out, shrink_after: 0}
          },
          color: %{kind: :ordinal, range: :category10}
        },
        axes: [
          %{scale: :x, side: :bottom, ticks: %{count: 6, size_inner: 4}, format: "%H:%M"},
          %{
            scale: :y,
            side: :left,
            ticks: 5,
            grid: true,
            measure: %{unit: "ms", quantity: :duration}
          }
        ],
        legend: %{scale: :color, position: :top_right, title: ["color"]},
        projection: %{
          type: :mercator,
          scale: 100,
          translate: [1, 2],
          fit: %{data: :primary, fields: [:t, :v], padding: 8}
        },
        facet: %{by: :sha, columns: 2},
        viewport: %{scale: :x, span: 60}
      },
      # A basemap's frame (#475): a mark that draws tiles needs a Mercator projection.
      map: %{kind: :geo, projection: %{type: :mercator}}
    },
    marks: [
      %{
        type: :line,
        data: :primary,
        channels: %{x: :t, y: :v},
        style: :series,
        render: :svg,
        frame: :main
      },
      %{
        type: :rule,
        data: :primary,
        frame: :main,
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
        scales: %{color: :color},
        offset: %{x: :v},
        options: %{inner_radius: 10, outer_radius: 50},
        frame: :main
      },
      %{
        type: :tiles,
        frame: :map,
        tiles: %{
          url: "https://{s}.tile.example/{z}/{x}/{y}.png",
          attribution: "© OpenStreetMap contributors",
          subdomains: ["a", "b"],
          max_zoom: 18
        }
      }
    ],
    labels: [
      %{anchor: :title, text: ["Full ", var(:unit)], style: :title, dx: 0, dy: -4, frame: :main},
      %{anchor: {:axis, :y}, text: ["unit"], frame: :main}
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
    paint: [:defs, :fade],
    defaults: [:defaults],
    kind_defaults: [:defaults, :line],
    stroke: [:styles, :series, :stroke],
    curve: [:styles, :series, :curve],
    font: [:styles, :muted, :font],
    marker: [:styles, :muted, :marker],
    text_layout: [:styles, :muted, :text],
    effect: [:styles, :muted, :effect],
    style_transition: [:styles, :muted, :transition],
    part_transition: [:styles, :muted, :transition, :fill],
    style_animation: [:styles, :muted, :animation],
    style_enter: [:styles, :muted, :enter],
    style_exit: [:styles, :muted, :exit],
    stop: [:defs, :fade, :stops, 0],
    label: [:labels, 0],
    layout: [:layout],
    interaction: [:interaction],
    frame: [:frames, :main],
    margin: [:frames, :main, :margin],
    scale: [:frames, :main, :scales, :y],
    axis: [:frames, :main, :axes, 0],
    ticks: [:frames, :main, :axes, 0, :ticks],
    measure: [:frames, :main, :axes, 1, :measure],
    legend: [:frames, :main, :legend],
    projection: [:frames, :main, :projection],
    facet: [:frames, :main, :facet],
    viewport: [:frames, :main, :viewport],
    transition: [:frames, :main, :scales, :y, :transition],
    mark: [:marks, 2],
    data: [:marks, 2, :data],
    transform: [:marks, 2, :data, :transforms, 0],
    channels: [:marks, 2, :channels],
    mark_scales: [:marks, 2, :scales],
    mark_offset: [:marks, 2, :offset],
    options: [:marks, 2, :options],
    mark_label: [:marks, 1, :label],
    tooltip: [:marks, 2, :tooltip],
    tiles: [:marks, 3, :tiles],
    fit: [:frames, :main, :projection, :fit]
  }

  @stack_orders [:none, :ascending, :descending, :inside_out, :reverse, :appearance]

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

    %{
      version: 3,
      sources: %{primary: %{fields: [:t]}},
      frames: %{main: %{kind: :cartesian}},
      marks: [mark]
    }
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

  # A fit reads `field` or `fields`, not both (spec/14 §4.6).
  defp reading(:fit, :field), do: put_at(@full, @paths[:fit], %{data: :primary, field: :sha})

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

        # A needle's cap is the one enum among the options (#392): a wrong value is
        # reported as one.
        case spec.type do
          {:enum, values} -> assert {path, {:enum, values}} in errors(design)
          type -> assert {path, {:type, type}} in errors(design)
        end
      end
    end

    test "a channel may name its scale's own end, and only its two ends (#420)" do
      design = design_with_mark(:area)

      for which <- [:min, :max] do
        assert Validator.validate(put_at(design, [:marks, 0, :channels, :y0], {:scale, which})) ==
                 :ok
      end

      path = [:marks, 0, :channels, :y0]
      assert {path, {:type, :channel}} in errors(put_at(design, path, {:scale, :middle}))
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

      filter = %{op: :filter, field: :v, test: :gt, value: 0}
      assert Validator.validate(put_at(@full, path, filter)) == :ok
      assert errors(put_at(@full, path, %{op: :filter})) == [{path ++ [:field], :required}]

      assert errors(put_at(@full, path, Map.put(filter, :as, :n))) ==
               [{path ++ [:as], {:invalid_for, :filter}}]

      assert errors(put_at(@full, path, %{filter | test: :like})) ==
               [{path ++ [:test], {:enum, [:eq, :ne, :lt, :lte, :gt, :gte, :present, :absent]}}]
    end

    test "a projection reads points through fields or a geometry through field, never both (#349)" do
      path = @paths[:transform]
      assert Validator.validate(put_at(@full, path, %{op: :projection, fields: [:t, :v]})) == :ok
      assert Validator.validate(put_at(@full, path, %{op: :projection, field: :v})) == :ok
      assert errors(put_at(@full, path, %{op: :projection})) == [{path ++ [:fields], :required}]

      assert errors(put_at(@full, path, %{op: :projection, fields: [:t, :v], field: :v})) ==
               [{path ++ [:field], {:invalid_for, :projection}}]
    end

    test "a stack's order may be fixed by its keys; a sort's may not (spec/14 §5.4, #492)" do
      path = @paths[:transform]
      step = %{op: :stack, fields: [:t, :v], order: {:keys, [:v, :t]}}
      assert Validator.validate(put_at(@full, path, step)) == :ok

      # A listed key the stack lacks is ignored at run time, so it is no fault here.
      assert Validator.validate(put_at(@full, path, %{step | order: {:keys, [:nope]}})) == :ok

      assert errors(put_at(@full, path, %{step | order: {:keys, ["v"]}})) ==
               [{path ++ [:order], {:type, :key_order}}]

      assert errors(put_at(@full, path, %{step | order: {:keys, :v}})) ==
               [{path ++ [:order], {:type, {:one_of, [{:enum, @stack_orders}, :key_order]}}}]

      sort = %{op: :sort, field: :v, order: {:keys, [:v]}}
      assert errors(put_at(@full, path, sort)) == [{path ++ [:order], {:enum, @stack_orders}}]
    end

    test "a graph's node source must be a declared source (#346)" do
      path = @paths[:transform]
      step = %{op: :force, fields: [:t, :v], nodes: :nobody}

      assert errors(put_at(@full, path, step)) == [
               {path ++ [:nodes], {:undeclared, :source, :nobody}}
             ]

      assert Validator.validate(put_at(@full, path, %{step | nodes: :primary})) == :ok
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

    test "the angle scale's sweep is a turn at most and never nothing; an axis's radius is positive (#390)" do
      base = design_with_mark(:line)

      scale = fn node ->
        put_at(base, [:frames, :main, :scales, :angle], Map.merge(%{kind: :linear}, node))
      end

      assert errors(scale.(%{sweep: 0})) == [{[:frames, :main, :scales, :angle, :sweep], :sweep}]

      assert errors(scale.(%{sweep: 400})) == [
               {[:frames, :main, :scales, :angle, :sweep], :sweep}
             ]

      assert Validator.validate(scale.(%{start: -120, sweep: 240})) == :ok
      assert Validator.validate(scale.(%{sweep: -360})) == :ok

      axis = fn node ->
        put_at(scale.(%{}), [:frames, :main, :axes], [
          Map.merge(%{scale: :angle, side: :bottom}, node)
        ])
      end

      assert errors(axis.(%{radius: 0})) == [{[:frames, :main, :axes, 0, :radius], :radius}]
      assert Validator.validate(axis.(%{radius: 0.8, at: 45})) == :ok

      assert Validator.format({[:frames, :main, :scales, :angle, :sweep], :sweep}) ==
               "frames.main.scales.angle.sweep: must be within a turn, and not zero"
    end

    test "a needle is a polar frame's mark; elsewhere its type is invalid for it (#392)" do
      design = design_with_mark(:needle)
      assert errors(design) == [{[:marks, 0, :type], {:invalid_for, :needle}}]
      assert Validator.validate(put_in(design, [:frames, :main, :kind], :polar)) == :ok
      # A fragment of one mark has no frame to ask: allowed.
      assert Validator.validate(%{mark: hd(design.marks)}, :mark) == :ok

      capped =
        put_in(design, [:frames, :main, :kind], :polar)
        |> put_at([:marks, 0, :options, :cap], :square)

      assert errors(capped) == [{[:marks, 0, :options, :cap], {:enum, [:point, :round, :flat]}}]
    end

    test "an arc needs value, or both start and end (D-69)" do
      arc = fn channels -> put_at(design_with_mark(:arc), [:marks, 0, :channels], channels) end
      assert Validator.validate(arc.(%{start: :t, end: :t})) == :ok
      assert Validator.validate(arc.(%{value: :t, start: :t, end: :t, inner: :t})) == :ok
      assert errors(arc.(%{start: :t})) == [{[:marks, 0, :channels, :end], :required}]
      assert errors(arc.(%{end: :t, inner: :t})) == [{[:marks, 0, :channels, :start], :required}]
      assert errors(arc.(%{inner: :t})) == [{[:marks, 0, :channels, :value], :required}]
    end

    test "a field reference in a frame label has no datum" do
      design = put_at(@full, [:labels, 0, :text], ["a", {:field, :sha}])
      assert errors(design) == [{[:labels, 0, :text, 1], {:invalid_for, :label}}]
    end

    test "an extent carries :auto only as one of two bounds" do
      assert Validator.validate(put_at(@full, [:frames, :main, :scales, :y, :domain], [:auto, 5])) ==
               :ok

      assert errors(put_at(@full, [:frames, :main, :scales, :y, :domain], [1, :auto, 5])) ==
               [{[:frames, :main, :scales, :y, :domain], {:type, :extent}}]
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
      assert errors(Map.put(@full, :version, 4)) == [{[:version], {:newer_schema, 4, 3}}]
    end

    test "an empty theme series is reported" do
      assert errors(put_at(@full, [:theme, :series], [])) == [{[:theme, :series], :required}]
    end

    test "slots resolve against the default theme when none is named" do
      design = %{
        version: 3,
        frames: %{main: %{kind: :cartesian}},
        styles: %{s: %{opacity: :none}}
      }

      assert errors(design) == [{[:styles, :s, :opacity], {:undeclared, :slot, :none}}]
    end

    test "something other than a map is not a design" do
      assert Validator.validate(:nope) == {:error, [{[], {:type, {:node, :design}}}]}
    end
  end

  describe "references" do
    # A declaring map the design never wrote is the empty set (D-113, #368): the reference
    # is undeclared, not unchecked — and a design that validates draws.
    test "into a declaring map the design does not have" do
      design = %{
        version: 3,
        frames: %{main: %{kind: :cartesian, axes: [%{scale: :x, side: :bottom}]}},
        sources: %{s: %{fields: [:t, :value]}},
        marks: [%{type: :line, data: :s, channels: %{x: :t, y: :value}}]
      }

      assert errors(design) == [{[:frames, :main, :axes, 0, :scale], {:undeclared, :scale, :x}}]

      no_sources = %{
        version: 3,
        frames: %{main: %{kind: :cartesian}},
        marks: [%{type: :line, data: :s}]
      }

      assert errors(no_sources) == [{[:marks, 0, :data], {:undeclared, :source, :s}}]

      no_styles = %{
        version: 3,
        frames: %{main: %{kind: :cartesian}},
        sources: %{s: %{fields: [:t]}},
        marks: [%{type: :line, data: :s, style: :series}]
      }

      assert errors(no_styles) == [{[:marks, 0, :style], {:undeclared, :style, :series}}]

      no_defs = %{
        version: 3,
        frames: %{main: %{kind: :cartesian}},
        styles: %{w: %{fill: {:paint, :g}}}
      }

      assert errors(no_defs) == [{[:styles, :w, :fill, :name], {:undeclared, :paint, :g}}]

      no_vars = %{
        version: 3,
        frames: %{main: %{kind: :cartesian, margin: Visualize.Chart.var(:size)}}
      }

      assert errors(no_vars) == [{[:frames, :main, :margin], {:undeclared, :var, :size}}]

      # A fragment checked alone as its kind still has nothing to look a reference up in.
      assert Validator.validate(%{axis: %{scale: :x, side: :bottom}}, :axis) == :ok
    end

    # A source's types name only its fields (§2.3, #369).
    test "a typed column the source does not list" do
      typed = put_at(@full, [:sources, :primary, :types], %{t: :time, nope: :number})

      assert errors(typed) == [
               {[:sources, :primary, :types, :nope], {:undeclared, :field, :nope}}
             ]

      assert Validator.validate(put_at(@full, [:sources, :primary, :types], %{t: :time})) == :ok

      assert errors(put_at(@full, [:sources, :primary, :types], %{t: :date})) ==
               [{[:sources, :primary, :types, :t], {:enum, Schema.column_types()}}]
    end

    test "scales" do
      for path <- [
            [:frames, :main, :axes, 0, :scale],
            [:frames, :main, :legend, :scale],
            [:frames, :main, :viewport, :scale],
            [:marks, 2, :scales, :color]
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
            [:frames, :main, :axes, 0, :style],
            [:frames, :main, :legend, :style],
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
            [:styles, :series, :stroke, :color],
            [:labels, 0, :text, 1],
            [:marks, 1, :label, :text, 0],
            [:marks, 2, :options],
            [:frames, :main, :margin]
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
      assert errors(put_at(@full, [:styles, :muted, :stroke, :color], :nope)) ==
               [{[:styles, :muted, :stroke, :color], {:undeclared, :color, :nope}}]

      assert errors(put_at(@full, [:styles, :muted, :stroke, :color], :series_3)) ==
               [{[:styles, :muted, :stroke, :color], {:undeclared, :color, :series_3}}]

      assert Validator.validate(put_at(@full, [:styles, :muted, :stroke, :color], {:series, 99})) ==
               :ok

      assert Validator.validate(put_at(@full, [:styles, :muted, :stroke, :color], :series_2)) ==
               :ok

      dark = put_at(@full, [:theme], :dark)

      assert Validator.validate(put_at(dark, [:styles, :muted, :stroke, :color], :series_10)) ==
               :ok

      assert errors(put_at(dark, [:styles, :muted, :font, :size], :series_11)) ==
               [{[:styles, :muted, :font, :size], {:undeclared, :slot, :series_11}}]

      # A theme the validator does not know leaves slots to application.
      house = put_at(@full, [:theme], :house)

      assert Validator.validate(put_at(house, [:styles, :muted, :stroke, :color], :anything)) ==
               :ok
    end
  end

  describe "errors" do
    test "are ordered by path" do
      design =
        @full
        |> put_at([:marks, 0, :type], 3)
        |> put_at([:frames, :main, :kind], 3)
        |> Map.delete(:version)

      assert Enum.map(errors(design), &elem(&1, 0)) == [
               [:frames, :main, :kind],
               [:marks, 0, :type],
               [:version]
             ]
    end

    test "format/1 renders a path and a reason in words" do
      assert Validator.format({[:marks, 1, :channels, :y], {:undeclared, :field, :temp}}) ==
               "marks[1].channels.y: field :temp is not declared by the mark's source"

      assert Validator.format({[], {:type, {:node, :design}}}) == "design: must be a design node"

      assert Validator.format({[:frames, :main, :kind], {:enum, [:cartesian, :polar]}}) ==
               "frames.main.kind: must be one of :cartesian, :polar"

      assert Validator.format({[:version], {:unsupported_version, 2}}) ==
               "version: version 2 is not supported; the current version is 3"

      assert Validator.format({[:marks, 0, :options, :radius], {:invalid_for, :line}}) ==
               "marks[0].options.radius: is not read by :line"

      assert Validator.format({[:styles, :s, :fill], {:type, :color}}) ==
               "styles.s.fill: must be a color string, :none, a typed color — color(name), " <>
                 "ramp(name, t) with t in 0..1, contrast() — a transform of colors with every " <>
                 "number in 0..1, or a paint"

      assert Validator.format({[:styles, :s, :fill], {:undeclared, :color, :brand}}) ==
               "styles.s.fill: color :brand is not a name of the theme's color table"
    end
  end

  defp read_keys(:channels, type) do
    %{required: required, optional: optional} = Schema.channels(type)
    required ++ optional
  end

  defp read_keys(:options, type), do: Schema.options(type)

  describe "extends (spec/14 §3.5)" do
    defp with_styles(styles) do
      %{version: 3, styles: styles, frames: %{main: %{kind: :cartesian}}}
    end

    test "a chain of three validates and a built-in parent resolves" do
      styles = %{
        a: %{stroke: "#001"},
        b: %{extends: :a, opacity: 0.5},
        c: %{extends: :b, stroke_width: 2},
        d: %{extends: :axis}
      }

      assert Validator.validate(with_styles(styles)) == :ok
    end

    test "a parent nothing declares is undeclared at the key's path" do
      assert Validator.validate(with_styles(%{a: %{extends: :nope}})) ==
               {:error, [{[:styles, :a, :extends], {:undeclared, :style, :nope}}]}
    end

    test "a style that extends itself is :cycle at the style's path" do
      assert Validator.validate(with_styles(%{a: %{extends: :a}})) ==
               {:error, [{[:styles, :a], :cycle}]}
    end

    test "every style on a cycle is reported, and one merely reaching it is not" do
      styles = %{a: %{extends: :b}, b: %{extends: :c}, c: %{extends: :a}, d: %{extends: :a}}

      assert Validator.validate(with_styles(styles)) ==
               {:error,
                [{[:styles, :a], :cycle}, {[:styles, :b], :cycle}, {[:styles, :c], :cycle}]}
    end

    test "the reason reads as a line" do
      assert Validator.format({[:styles, :series], :cycle}) ==
               "styles.series: extends itself, directly or through a chain of `extends`"
    end
  end

  describe "a sync group (spec/14 §2.9, #466)" do
    defp synced(x, extra \\ %{}) do
      Map.merge(
        %{
          version: 3,
          interaction: %{sync: "dash"},
          frames: %{main: %{kind: :cartesian, scales: x}}
        },
        extra
      )
    end

    test "a linear or a time x joins a group" do
      assert Validator.validate(synced(%{x: %{kind: :linear}})) == :ok
      assert Validator.validate(synced(%{x: %{kind: :time}})) == :ok
    end

    test "a band or an ordinal x is refused, saying why" do
      for kind <- [:band, :ordinal, :log] do
        assert errors(synced(%{x: %{kind: kind}})) ==
                 [{[:interaction, :sync], {:sync, :x_scale, kind}}]
      end

      assert Validator.format({[:interaction, :sync], {:sync, :x_scale, :band}}) =~
               "interaction.sync: joins a sync group over a :band x scale; only a linear or time x syncs"
    end

    test "a frame with no x, or not cartesian, is refused" do
      assert errors(synced(%{y: %{kind: :linear}})) ==
               [{[:interaction, :sync], {:sync, :x_scale, nil}}]

      polar = put_at(synced(%{x: %{kind: :linear}}), [:frames, :main, :kind], :polar)
      assert errors(polar) == [{[:interaction, :sync], {:sync, :frame_kind, :polar}}]
    end

    test "the frame named, else the first by name, is the one read; an adopted x reads its owner" do
      frames = %{
        a: %{kind: :cartesian, scales: %{x: %{kind: :band}}},
        b: %{kind: :cartesian, scales: %{x: {:frame, :c, :x}}},
        c: %{kind: :cartesian, scales: %{x: %{kind: :time}}}
      }

      design = %{version: 3, interaction: %{sync: "dash"}, frames: frames}
      assert errors(design) == [{[:interaction, :sync], {:sync, :x_scale, :band}}]
      assert Validator.validate(put_at(design, [:interaction, :frame], :b)) == :ok

      assert {[:interaction, :frame], {:undeclared, :frame, :nope}} in errors(
               put_at(design, [:interaction, :frame], :nope)
             )
    end

    test "no sync, no check" do
      assert Validator.validate(%{version: 3, frames: %{main: %{kind: :polar}}}) == :ok
    end
  end
end
