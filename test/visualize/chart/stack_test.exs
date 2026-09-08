defmodule Visualize.Chart.StackTest do
  @moduledoc """
  The cascade over fragments (spec/14 §8.2, D-81): for every key the higher layer wins,
  a `:union` name both layers declare is the higher layer's entry whole, a node both
  give as a map cascades key by key, and the result is a fragment like the layers.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Visualize.Chart

  @theme %{version: 1, theme: :default, styles: %{series: %{stroke_width: 1}}}
  @frame %{
    version: 1,
    frame: %{
      kind: :cartesian,
      size: %{width: 800, height: 400},
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
      size: %{width: 600, height: 300},
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
      assert design.frame.size == %{width: 600, height: 300}
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
      chart = Chart.from_map!(Chart.stack([@frame, @panel, %{version: 1}]))

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
      assert Chart.stack(%{frame: %{kind: :polar, size: %{width: 10, height: 20}}}, %{
               frame: %{size: %{width: 30}}
             }) == %{frame: %{kind: :polar, size: %{width: 30, height: 20}}}
    end

    test "a node either layer gives as anything else is the higher layer's whole" do
      var = Chart.var(:frame)

      assert Chart.stack(%{frame: %{kind: :polar}}, %{frame: var}) == %{frame: var}
      assert Chart.stack(%{frame: var}, %{frame: %{kind: :polar}}) == %{frame: %{kind: :polar}}
      assert Chart.stack(%{styles: var}, %{styles: %{a: %{}}}) == %{styles: %{a: %{}}}
      assert Chart.stack(%{styles: %{a: %{}}}, %{styles: var}) == %{styles: var}
      assert Chart.stack(%{theme: :dark}, %{theme: %{name: :house}}) == %{theme: %{name: :house}}
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

  # -- properties over generated fragments ------------------------------------------

  @style_names [:series, :muted, :accent]
  @scale_names [:x, :y, :color]

  defp style, do: optional_map(%{stroke_width: integer(1..5), opacity: float(min: 0.0, max: 1.0)})
  defp scale, do: fixed_map(%{kind: member_of([:linear, :time, :band]), nice: boolean()})

  defp names(pool, gen),
    do: map(list_of(tuple({member_of(pool), gen}), max_length: 3), &Map.new/1)

  defp mark,
    do:
      fixed_map(%{
        type: member_of([:line, :area]),
        data: constant(:p),
        channels: constant(%{x: :t, y: :v})
      })

  defp frame do
    optional_map(%{
      kind: member_of([:cartesian, :polar]),
      size: fixed_map(%{width: integer(100..900), height: integer(100..900)}),
      scales: names(@scale_names, scale()),
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
      styles: names(@style_names, style()),
      vars: names([:unit, :n], fixed_map(%{default: integer()})),
      frame: frame(),
      marks: list_of(mark(), max_length: 3),
      labels: list_of(fixed_map(%{anchor: member_of([:title, :caption])}), max_length: 3)
    })
  end

  property "the cascade is associative over a list" do
    check all(a <- fragment(), b <- fragment(), c <- fragment()) do
      assert Chart.stack(Chart.stack(a, b), c) == Chart.stack(a, Chart.stack(b, c))
      assert Chart.stack([a, b, c]) == Chart.stack(Chart.stack(a, b), c)
    end
  end

  property "one layer is itself and the empty fragment is the identity" do
    check all(a <- fragment()) do
      assert Chart.stack([a]) == a
      assert Chart.stack(%{}, a) == a
      assert Chart.stack(a, %{}) == a
    end
  end

  property "collections append and scalars are the higher layer's" do
    check all(a <- fragment(), b <- fragment()) do
      stacked = Chart.stack(a, b)

      assert Map.get(stacked, :marks) == concat(a, b, :marks)
      assert Map.get(stacked, :labels) == concat(a, b, :labels)
      assert Map.get(stacked, :theme) == higher(a, b, :theme)

      for key <- [:styles, :vars], Map.has_key?(a, key) or Map.has_key?(b, key) do
        assert Map.get(stacked, key) ==
                 Map.merge(Map.get(a, key, %{}), Map.get(b, key, %{}))
      end
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
    Enum.all?([:styles, :vars, :theme, :version, :frame], fn key ->
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
