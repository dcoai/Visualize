defmodule Visualize.Chart.StackTest do
  @moduledoc """
  The cascade over fragments (spec/14 §8.2, D-81): for every key the higher layer wins,
  a `:union` name both layers declare is the higher layer's entry whole, a node both
  give as a map cascades key by key, and the result is a fragment like the layers.

  A struct is a leaf of the walk (§1.4, D-92): a mergeable key either layer gives as a
  whole-node variable is the higher layer's value whole, where `compose/2` reports a
  conflict. That is a *replacement*, so the cascade is associative only where every layer
  gives its mergeable keys as maps — `stack/1` is the left fold and computes it either way.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Visualize.Chart

  @theme %{version: 1, theme: :default, styles: %{series: %{stroke_width: 1}}}
  @frame %{
    version: 1,
    frame: %{
      kind: :cartesian,
      margin: %{top: 10, right: 10, bottom: 30, left: 40},
      scales: %{x: %{kind: :time}, y: %{kind: :linear}},
      axes: [%{scale: :x, side: :bottom, ticks: 6}]
    }
  }
  @house %{
    theme: :dark,
    styles: %{series: %{stroke: :series_2, stroke_width: 2}, muted: %{opacity: 0.5}}
  }
  @panel %{
    sources: %{primary: %{fields: [:t, :v]}},
    frame: %{
      scales: %{y: %{kind: :linear, domain: [0, :auto]}},
      axes: [%{scale: :y, side: :left, grid: true}]
    },
    marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v}, style: :series}],
    labels: [%{anchor: :title, text: ["Uptime"]}]
  }

  describe "stack/1" do
    test "four layers stack into one design that validates and renders" do
      design = Chart.stack([@theme, @frame, @house, @panel])

      assert design.theme == :dark
      assert design.styles.series == %{stroke: :series_2, stroke_width: 2}
      assert design.styles.muted == %{opacity: 0.5}
      assert design.frame.kind == :cartesian
      assert design.frame.margin == @frame.frame.margin
      assert Map.keys(design.frame.scales) |> Enum.sort() == [:x, :y]
      assert design.frame.scales.y == %{kind: :linear, domain: [0, :auto]}
      assert Enum.map(design.frame.axes, & &1.scale) == [:x, :y]
      assert design.marks == @panel.marks

      rows = %{t: [~U[2026-01-01 00:00:00Z], ~U[2026-01-02 00:00:00Z]], v: [3, 9]}
      assert {:ok, applied} = Chart.apply(design, sources: %{primary: rows})
      svg = Chart.render(applied)
      assert svg =~ "mark mark-line"
      assert svg =~ "--vis-series-2"
    end

    test "swapping the house sheet changes every panel built on it" do
      other = %{@house | styles: %{series: %{stroke: :series_3, stroke_width: 4}}}

      a = Chart.stack([@theme, @frame, @house, @panel])
      b = Chart.stack([@theme, @frame, other, @panel])

      assert a.styles.series == %{stroke: :series_2, stroke_width: 2}
      assert b.styles.series == %{stroke: :series_3, stroke_width: 4}
      assert Map.delete(a, :styles) == Map.delete(b, :styles)
    end

    test "the empty stack is the empty fragment and one layer is itself" do
      assert Chart.stack([]) == %{}
      assert Chart.stack([@panel]) == @panel
      assert Chart.stack([@theme, @frame]) == Chart.stack(@theme, @frame)
    end

    test "a chart struct is taken as its map" do
      # The house declares the style the panel's mark reads; without it the design is not
      # one (D-113), and from_map!/1 says so.
      chart = Chart.from_map!(Chart.stack([@frame, @house, @panel, %{version: 1}]))

      assert Chart.stack([@house, chart]) == Chart.stack(@house, Chart.to_map(chart))
    end

    test "the result is a fragment: a stack is a layer of another stack" do
      lower = Chart.stack([@theme, @frame])
      assert Chart.stack([lower, @house, @panel]) == Chart.stack([@theme, @frame, @house, @panel])
    end
  end

  describe "stack/2, key by key" do
    test "a scalar is the higher layer's" do
      assert Chart.stack(%{version: 1, theme: :default}, %{theme: :dark}) ==
               %{version: 1, theme: :dark}
    end

    test "a union name both layers declare is the higher layer's entry, taken whole" do
      lower = %{styles: %{series: %{stroke: :series_1, stroke_width: 2}}}
      higher = %{styles: %{series: %{stroke_width: 3}}}

      assert Chart.stack(lower, higher) == %{styles: %{series: %{stroke_width: 3}}}
      assert Chart.compose(lower, higher) == {:error, [{[:styles, :series], :conflict}]}
    end

    test "union entries only one layer declares are kept" do
      lower = %{vars: %{unit: %{default: "%"}}, sources: %{a: %{fields: [:t]}}}
      higher = %{vars: %{n: %{default: 3}}}

      assert Chart.stack(lower, higher) == %{
               vars: %{unit: %{default: "%"}, n: %{default: 3}},
               sources: %{a: %{fields: [:t]}}
             }
    end

    test "collections append" do
      lower = %{marks: [%{type: :line, data: :p, channels: %{}}], labels: [%{anchor: :caption}]}
      higher = %{marks: [%{type: :rule, data: :p, channels: %{}}]}

      assert Chart.stack(lower, higher).marks == lower.marks ++ higher.marks
      assert Chart.stack(lower, higher).labels == lower.labels
    end

    test "a node both layers give as a map cascades key by key" do
      assert Chart.stack(%{frame: %{kind: :polar, margin: %{top: 10}}}, %{
               frame: %{margin: %{top: 30}}
             }) == %{frame: %{kind: :polar, margin: %{top: 30}}}
    end

    test "a node either layer gives as anything else is the higher layer's whole" do
      var = Chart.var(:frame)

      assert Chart.stack(%{frame: %{kind: :polar}}, %{frame: var}) == %{frame: var}
      assert Chart.stack(%{frame: var}, %{frame: %{kind: :polar}}) == %{frame: %{kind: :polar}}
      assert Chart.stack(%{styles: var}, %{styles: %{a: %{}}}) == %{styles: %{a: %{}}}
      assert Chart.stack(%{styles: %{a: %{}}}, %{styles: var}) == %{styles: var}
      assert Chart.stack(%{theme: :dark}, %{theme: %{name: :house}}) == %{theme: %{name: :house}}
    end

    test "every union key given as a whole-node variable is the higher layer's, where compose conflicts" do
      v = Chart.var(:v)

      for {declared, variable, path} <- [
            {%{sources: %{p: %{fields: [:t]}}}, %{sources: v}, [:sources]},
            {%{vars: %{unit: %{default: "%"}}}, %{vars: v}, [:vars]},
            {%{styles: %{series: %{stroke_width: 2}}}, %{styles: v}, [:styles]},
            {%{frame: %{scales: %{x: %{kind: :time}}}}, %{frame: %{scales: v}}, [:frame, :scales]}
          ] do
        assert Chart.stack(declared, variable) == variable
        assert Chart.stack(variable, declared) == declared
        assert Chart.stack(variable, variable) == variable

        assert Chart.compose(declared, variable) == {:error, [{path, :conflict}]}
        assert Chart.compose(variable, declared) == {:error, [{path, :conflict}]}
      end
    end

    test "a layer replacing a mergeable key whole is an erasure, so regrouping may differ" do
      # spec/14 §8.2, D-92: `stack/1` is the LEFT fold and computes this; the middle
      # layer's whole-node variable erases what the lowest declared, and that erasure
      # cannot survive being regrouped, because the intermediate would not be a fragment.
      a = %{vars: %{n: %{default: 0}}}
      b = %{vars: Chart.var(:sheet)}
      c = %{vars: %{}}

      assert Chart.stack([a, b, c]) == %{vars: %{}}
      assert Chart.stack(Chart.stack(a, b), c) == %{vars: %{}}
      assert Chart.stack(a, Chart.stack(b, c)) == %{vars: %{n: %{default: 0}}}

      # The same holds for a node key, where the rule is to recurse rather than unite.
      f = %{frame: %{kind: :polar}}
      g = %{frame: Chart.var(:f)}
      h = %{frame: %{margin: %{top: 1}}}

      assert Chart.stack([f, g, h]) == %{frame: %{margin: %{top: 1}}}
      assert Chart.stack(f, Chart.stack(g, h)) == %{frame: %{kind: :polar, margin: %{top: 1}}}
    end

    test "a key the schema does not know is the higher layer's" do
      assert Chart.stack(%{extra: 1, marks: [1]}, %{extra: 2, marks: [2]}) ==
               %{extra: 2, marks: [1, 2]}
    end

    test "a key one layer alone carries is taken as it is" do
      assert Chart.stack(%{}, @panel) == @panel
      assert Chart.stack(@panel, %{}) == @panel
    end
  end

  describe "element identity" do
    test "a higher mark with the same id replaces in place, keeping the lower's position" do
      lower = %{
        marks: [
          %{id: :series, type: :line, data: :p, channels: %{x: :t, y: :v}},
          %{type: :rule, data: :d, channels: %{x: :at}}
        ]
      }

      higher = %{marks: [%{id: :series, type: :area, data: :p, channels: %{x: :t, y: :v}}]}

      assert Chart.stack(lower, higher).marks == [
               %{id: :series, type: :area, data: :p, channels: %{x: :t, y: :v}},
               %{type: :rule, data: :d, channels: %{x: :at}}
             ]
    end

    test "a mark with no identity appends" do
      lower = %{marks: [%{type: :line, data: :p, channels: %{}}]}
      higher = %{marks: [%{type: :area, data: :p, channels: %{}}]}

      assert Chart.stack(lower, higher).marks == lower.marks ++ higher.marks
    end

    test "an id one layer alone uses appends rather than replacing anything" do
      lower = %{marks: [%{id: :a, type: :line, data: :p, channels: %{}}]}
      higher = %{marks: [%{id: :b, type: :area, data: :p, channels: %{}}]}

      assert Chart.stack(lower, higher).marks == lower.marks ++ higher.marks
    end

    test "a label with the same id replaces; compose keeps both" do
      lower = %{labels: [%{id: :title, anchor: :title, text: ["House"]}]}
      higher = %{labels: [%{id: :title, anchor: :title, text: ["Panel"]}]}

      assert Chart.stack(lower, higher).labels == higher.labels
      assert {:ok, composed} = Chart.compose(lower, higher)
      assert composed.labels == lower.labels ++ higher.labels
    end

    test "two axes for the same scale and side collapse to the higher layer's" do
      lower = %{
        frame: %{axes: [%{scale: :x, side: :bottom, ticks: 6}, %{scale: :y, side: :left}]}
      }

      higher = %{frame: %{axes: [%{scale: :x, side: :bottom, grid: true, style: :heavy}]}}

      assert Chart.stack(lower, higher).frame.axes == [
               %{scale: :x, side: :bottom, grid: true, style: :heavy},
               %{scale: :y, side: :left}
             ]
    end

    test "an axis on another side is another axis" do
      lower = %{frame: %{axes: [%{scale: :x, side: :bottom}]}}
      higher = %{frame: %{axes: [%{scale: :x, side: :top}]}}

      assert length(Chart.stack(lower, higher).frame.axes) == 2
    end

    test "identity matches within one key: a mark and a label may share an id" do
      lower = %{marks: [%{id: :a, type: :line, data: :p, channels: %{}}]}
      higher = %{labels: [%{id: :a, anchor: :title, text: ["T"]}]}

      stacked = Chart.stack(lower, higher)
      assert stacked.marks == lower.marks
      assert stacked.labels == higher.labels
    end

    test "transforms have no identity: a data pipeline is a sequence" do
      step = %{op: :filter, field: :v, test: :gt, value: 0}
      lower = %{marks: [%{type: :rect, data: %{source: :p, transforms: [step]}, channels: %{}}]}

      assert Chart.stack(lower, lower).marks == lower.marks ++ lower.marks
    end

    test "merging two lists collapses a duplicate identity in either of them" do
      dup = %{
        marks: [
          %{id: :a, type: :line, data: :p, channels: %{}},
          %{id: :a, type: :area, data: :p, channels: %{}}
        ]
      }

      assert Chart.stack(dup, %{marks: []}).marks == [
               %{id: :a, type: :area, data: :p, channels: %{}}
             ]

      assert Chart.stack(%{marks: []}, dup).marks == [
               %{id: :a, type: :area, data: :p, channels: %{}}
             ]
    end

    test "a key only one layer carries is passed through untouched" do
      dup = %{
        marks: [
          %{id: :a, type: :line, data: :p, channels: %{}},
          %{id: :a, type: :area, data: :p, channels: %{}}
        ]
      }

      assert Chart.stack(%{}, dup) == dup
      assert Chart.stack([dup]) == dup
    end

    test "a design carrying id round-trips through the map and the JSON forms" do
      design = %{
        version: 1,
        sources: %{p: %{fields: [:t, :v]}},
        frame: %{kind: :cartesian, scales: %{x: %{kind: :linear}, y: %{kind: :linear}}},
        marks: [%{id: :series, type: :line, data: :p, channels: %{x: :t, y: :v}}],
        labels: [%{id: :head, anchor: :title, text: ["Uptime"]}]
      }

      assert {:ok, chart} = Chart.from_map(design)

      assert Chart.to_map(chart) |> Map.take([:marks, :labels]) ==
               design |> Visualize.Chart.Migration.canonical() |> Map.take([:marks, :labels])

      assert {:ok, json} = Chart.to_json(chart)
      assert {:ok, ^chart} = Chart.from_json(json)
    end

    test "the builder takes id: on a mark and a label" do
      import Visualize.Chart.Build

      assert line(:p, %{x: :t, y: :v}, id: :series) ==
               %{marks: [%{id: :series, type: :line, data: :p, channels: %{x: :t, y: :v}}]}

      assert title(["T"], id: :head) == %{labels: [%{id: :head, anchor: :title, text: ["T"]}]}

      assert_raise ArgumentError, fn -> axis(:x, :bottom, id: :x_axis) end
    end

    test "a higher layer restyles the shared frame's x-axis rather than drawing a second" do
      frame = %{
        version: 1,
        sources: %{p: %{fields: [:t, :v]}},
        frame: %{
          kind: :cartesian,
          scales: %{x: %{kind: :linear}, y: %{kind: :linear}},
          axes: [%{scale: :x, side: :bottom, ticks: 3}, %{scale: :y, side: :left}]
        },
        marks: [%{id: :series, type: :line, data: :p, channels: %{x: :t, y: :v}}]
      }

      panel = %{
        styles: %{heavy: %{stroke_width: 3}},
        frame: %{axes: [%{scale: :x, side: :bottom, ticks: 3, grid: true, style: :heavy}]},
        marks: [%{id: :series, type: :area, data: :p, channels: %{x: :t, y: :v}}]
      }

      design = Chart.stack([frame, panel])
      assert length(design.frame.axes) == 2
      assert Enum.map(design.marks, & &1.type) == [:area]

      assert {:ok, applied} = Chart.apply(design, sources: %{p: %{t: [1, 2], v: [3, 9]}})
      svg = Chart.render(applied)
      assert svg =~ "mark mark-area"
      refute svg =~ "mark mark-line"
      assert length(String.split(svg, "axis-bottom")) == 2
    end
  end

  # -- properties over generated fragments ------------------------------------------

  @style_names [:series, :muted, :accent]
  @scale_names [:x, :y, :color]

  defp style, do: optional_map(%{stroke_width: integer(1..5), opacity: float(min: 0.0, max: 1.0)})
  defp scale, do: fixed_map(%{kind: member_of([:linear, :time, :band]), nice: boolean()})

  defp names(pool, gen),
    do: map(list_of(tuple({member_of(pool), gen}), max_length: 3), &Map.new/1)

  # A `:union` key may be given as a whole-node variable instead of a name map (spec/14
  # §1.4, §8.2, D-92): the cascade takes the higher layer's value whole, where `compose/2`
  # reports a conflict. One in five, so the name-map branches stay the common case.
  defp declaration(pool, gen),
    do: frequency([{4, names(pool, gen)}, {1, map(member_of([:sheet, :other]), &Chart.var/1)}])

  defp label do
    gen all(anchor <- member_of([:title, :caption]), id <- member_of([nil, :head, :foot])) do
      base = %{anchor: anchor, text: ["t"]}
      if id, do: Map.put(base, :id, id), else: base
    end
  end

  defp mark do
    gen all(type <- member_of([:line, :area]), id <- member_of([nil, :a, :b])) do
      base = %{type: type, data: :p, channels: %{x: :t, y: :v}}
      if id, do: Map.put(base, :id, id), else: base
    end
  end

  defp frame do
    optional_map(%{
      kind: member_of([:cartesian, :polar]),
      size: fixed_map(%{width: integer(100..900), height: integer(100..900)}),
      scales: declaration(@scale_names, scale()),
      axes:
        list_of(fixed_map(%{scale: member_of(@scale_names), side: member_of([:top, :left])}),
          max_length: 2
        )
    })
  end

  defp fragment do
    optional_map(%{
      version: constant(1),
      theme: member_of([:default, :dark]),
      sources: declaration([:primary, :other], fixed_map(%{fields: constant([:t, :v])})),
      styles: declaration(@style_names, style()),
      vars: declaration([:unit, :n], fixed_map(%{default: integer()})),
      frame: frame(),
      marks: list_of(mark(), max_length: 3),
      labels: list_of(label(), max_length: 3)
    })
  end

  property "the cascade is the left fold, and is associative where no layer replaces a union key whole" do
    check all(a <- fragment(), b <- fragment(), c <- fragment()) do
      assert Chart.stack([a, b, c]) == Chart.stack(Chart.stack(a, b), c)

      if Enum.all?([a, b, c], &unions_are_maps?/1) do
        assert Chart.stack(Chart.stack(a, b), c) == Chart.stack(a, Chart.stack(b, c))
      end
    end
  end

  # A layer that gives a `:union` key as a whole-node variable *replaces* the declaration
  # rather than merging into it, and an erasure in the middle of a fold does not survive
  # regrouping (spec/14 §8.2, D-92). The generator produces them, so the associativity
  # property asks for the layers where every mergeable key is a map.
  defp unions_are_maps?(fragment) do
    scales = fragment |> Map.get(:frame, %{}) |> Map.get(:scales, %{})

    Enum.all?([:sources, :styles, :vars], &(not is_struct(Map.get(fragment, &1, %{})))) and
      not is_struct(scales)
  end

  property "one layer is itself and the empty fragment is the identity" do
    check all(a <- fragment()) do
      assert Chart.stack([a]) == a
      assert Chart.stack(%{}, a) == a
      assert Chart.stack(a, %{}) == a
    end
  end

  property "collections append where no identity is declared by both layers" do
    check all(a <- fragment(), b <- fragment()) do
      stacked = Chart.stack(a, b)

      for key <- [:marks, :labels],
          shared_ids(a, b, key) == [],
          unique_ids?(a, key),
          unique_ids?(b, key) do
        assert Map.get(stacked, key) == concat(a, b, key)
      end

      assert Map.get(stacked, :theme) == higher(a, b, :theme)

      for key <- [:sources, :styles, :vars], Map.has_key?(a, key) or Map.has_key?(b, key) do
        assert Map.get(stacked, key) == united(a, b, key)
      end
    end
  end

  # A `:union` key both layers give as a name map unites, the higher layer's entry winning
  # each name; either layer giving it as a struct makes it one value, and the higher
  # layer's whole (spec/14 §8.2, D-92).
  defp united(a, b, key) do
    case {Map.get(a, key), Map.get(b, key)} do
      {x, nil} -> x
      {nil, y} -> y
      {x, y} when is_struct(x) or is_struct(y) -> y
      {x, y} -> Map.merge(x, y)
    end
  end

  property "an identity both layers declare carries the higher layer's element, once" do
    check all(a <- fragment(), b <- fragment()) do
      stacked = Chart.stack(a, b)

      for key <- [:marks, :labels], unique_ids?(a, key), unique_ids?(b, key) do
        elements = Map.get(stacked, key, [])
        assert ids(elements) == Enum.uniq(ids(elements))

        for id <- shared_ids(a, b, key) do
          assert Enum.find(elements, &(&1[:id] == id)) ==
                   Enum.find(Map.fetch!(b, key), &(&1[:id] == id))

          assert Enum.find_index(elements, &(&1[:id] == id)) ==
                   Enum.find_index(Map.fetch!(a, key), &(&1[:id] == id))
        end
      end
    end
  end

  defp ids(elements), do: for(e <- elements, id = e[:id], do: id)

  defp unique_ids?(fragment, key) do
    declared = ids(Map.get(fragment, key, []))
    declared == Enum.uniq(declared)
  end

  defp shared_ids(a, b, key) do
    if Map.has_key?(a, key) and Map.has_key?(b, key) do
      a |> Map.fetch!(key) |> ids() |> Enum.filter(&(&1 in ids(Map.fetch!(b, key))))
    else
      []
    end
  end

  property "over disjoint fragments the cascade is the union" do
    check all(a <- fragment(), b <- fragment()) do
      case Chart.compose(a, b) do
        {:ok, composed} -> if disjoint?(a, b), do: assert(Chart.stack(a, b) == composed)
        {:error, _} -> assert Chart.stack(a, b) != nil
      end
    end
  end

  defp disjoint?(a, b) do
    Enum.all?(
      [:marks, :labels],
      &(shared_ids(a, b, &1) == [] and unique_ids?(a, &1) and unique_ids?(b, &1))
    ) and
      Enum.all?([:sources, :styles, :vars, :theme, :version, :frame], fn key ->
        not (Map.has_key?(a, key) and Map.has_key?(b, key))
      end)
  end

  defp concat(a, b, key) do
    case {Map.fetch(a, key), Map.fetch(b, key)} do
      {{:ok, x}, {:ok, y}} -> x ++ y
      {{:ok, x}, :error} -> x
      {:error, {:ok, y}} -> y
      {:error, :error} -> nil
    end
  end

  defp higher(a, b, key), do: Map.get(b, key, Map.get(a, key))
end
