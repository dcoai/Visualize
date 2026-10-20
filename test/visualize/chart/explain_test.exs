defmodule Visualize.Chart.ExplainTest do
  @moduledoc """
  Provenance over the layers of a stack (spec/14 §17.1, D-83): every leaf path of
  `Visualize.Chart.stack/1` with the layer that set it and the layers it overrode. The
  stack carries no tags — a tagged fragment would not be a fragment — so `explain/1`
  recomputes the cascade, and the properties here are what say the two agree.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Visualize.Chart

  @theme {:theme, %{version: 2, theme: :default, styles: %{series: %{stroke_width: 1}}}}
  @frame {:frame,
          %{
            frames: %{
              main: %{
                kind: :cartesian,
                margin: %{top: 800, bottom: 400},
                axes: [%{scale: :x, side: :bottom, ticks: 6}]
              }
            },
            marks: [%{id: :series, type: :line, data: :p, channels: %{x: :t, y: :v}}]
          }}
  @house {:house, %{theme: :dark, styles: %{series: %{stroke: :series_2, stroke_width: 2}}}}
  @panel {:panel,
          %{
            frames: %{main: %{margin: %{top: 600}}},
            marks: [%{id: :series, type: :area, data: :p, channels: %{x: :t, y: :v}}]
          }}

  @layers [@theme, @frame, @house, @panel]

  defp entry(entries, path), do: Enum.find(entries, &(&1.path == path))

  describe "explain/1 over a four-layer stack" do
    test "every leaf of the stack has exactly one entry, ordered by path" do
      entries = Chart.explain(@layers)
      paths = Enum.map(entries, & &1.path)

      assert paths == Enum.sort(paths)
      assert paths == Enum.uniq(paths)

      stacked = Chart.stack(@layers)
      for %{path: path, value: value} <- entries, do: assert(at(stacked, path) == value)
    end

    test "the winning layer and the layers it overrode are named" do
      entries = Chart.explain(@layers)

      assert entry(entries, [:theme]) == %{
               path: [:theme],
               value: :dark,
               layer: :house,
               overrode: [:theme]
             }

      assert entry(entries, [:frames, "main", :margin, :top]).layer == :panel
      assert entry(entries, [:frames, "main", :margin, :top]).overrode == [:frame]
      assert entry(entries, [:frames, "main", :margin, :bottom]).layer == :frame
      assert entry(entries, [:frames, "main", :margin, :bottom]).overrode == []
      assert entry(entries, [:version]).layer == :theme
    end

    test "an identity-replaced element reports the layer it overrode" do
      entries = Chart.explain(@layers)

      assert entry(entries, [:marks, 0, :type]) == %{
               path: [:marks, 0, :type],
               value: :area,
               layer: :panel,
               overrode: [:frame]
             }

      assert entry(entries, [:marks, 0, :channels, :x]).overrode == [:frame]
      assert Enum.count(entries, &(hd(&1.path) == :marks)) == 5
    end

    test "a union name declared twice reports the layer it overrode" do
      entries = Chart.explain(@layers)

      assert entry(entries, [:styles, "series", :stroke_width]) == %{
               path: [:styles, "series", :stroke_width],
               value: 2,
               layer: :house,
               overrode: [:theme]
             }

      assert entry(entries, [:styles, "series", :stroke]).overrode == []
    end

    test "a value a whole replacement discarded has no path and so no entry" do
      lower = %{frames: %{main: %{axes: [%{scale: :x, side: :bottom, ticks: 6}]}}}
      higher = %{frames: %{main: %{axes: [%{scale: :x, side: :bottom, grid: true}]}}}
      entries = Chart.explain([lower, higher])

      assert entry(entries, [:frames, "main", :axes, 0, :ticks]) == nil
      assert entry(entries, [:frames, "main", :axes, 0, :grid]).layer == 1
      assert entry(entries, [:frames, "main", :axes, 0, :scale]).overrode == [0]
    end
  end

  describe "explain/1, the layers it takes" do
    test "a layer without a name is its zero-based position" do
      assert Chart.explain([%{version: 2}, %{version: 2}]) == [
               %{path: [:version], value: 2, layer: 1, overrode: [0]}
             ]
    end

    test "named and unnamed layers mix" do
      entries = Chart.explain([%{theme: :default}, {:house, %{theme: :dark}}])
      assert entries == [%{path: [:theme], value: :dark, layer: :house, overrode: [0]}]
    end

    test "a chart struct is a layer, named or not" do
      chart = Chart.from_map!(%{version: 2, frames: %{main: %{kind: :cartesian}}})

      assert Chart.explain([chart]) == Chart.explain([{0, chart}])
      assert entry(Chart.explain([chart]), [:frames, "main", :kind]).value == :cartesian
    end

    test "no layers is no entries" do
      assert Chart.explain([]) == []
      assert Chart.explain([%{}]) == []
    end
  end

  # -- properties over generated layers ------------------------------------------------

  defp style, do: optional_map(%{stroke_width: integer(1..5), stroke: member_of([:a, :b])})
  defp scale, do: fixed_map(%{kind: member_of([:linear, :time]), nice: boolean()})

  defp names(pool, gen),
    do: map(list_of(tuple({member_of(pool), gen}), max_length: 2), &Map.new/1)

  defp mark do
    gen all(type <- member_of([:line, :area]), id <- member_of([nil, :a, :b])) do
      base = %{type: type, data: :p, channels: %{x: :t, y: :v}}
      if id, do: Map.put(base, :id, id), else: base
    end
  end

  defp frame do
    optional_map(%{
      kind: member_of([:cartesian, :polar]),
      margin: fixed_map(%{top: integer(0..90), bottom: integer(0..90)}),
      scales: names([:x, :y], scale()),
      axes:
        list_of(fixed_map(%{scale: member_of([:x, :y]), side: member_of([:top, :left])}),
          max_length: 2
        )
    })
  end

  defp fragment do
    optional_map(%{
      version: constant(1),
      theme: member_of([:default, :dark]),
      styles: names([:series, :muted], style()),
      vars: names([:unit, :n], fixed_map(%{default: integer()})),
      frames: fixed_map(%{main: frame()}),
      marks: list_of(mark(), max_length: 3)
    })
  end

  defp layers, do: list_of(fragment(), max_length: 4)

  property "the entries are exactly the leaves of the stack, each with its value" do
    check all(layers <- layers()) do
      stacked = Chart.stack(layers)
      entries = Chart.explain(layers)

      assert Enum.map(entries, & &1.path) == Enum.sort(positions(stacked, []))
      for %{path: path, value: value} <- entries, do: assert(at(stacked, path) == value)
    end
  end

  property "a layer is a position in the list, and it overrode only layers below it" do
    check all(layers <- layers()) do
      last = length(layers) - 1

      for %{layer: layer, overrode: overrode} <- Chart.explain(layers) do
        assert layer in 0..last//1
        assert overrode == Enum.sort(overrode)
        assert Enum.all?(overrode, &(&1 < layer))
      end
    end
  end

  property "naming the layers changes nothing but the names" do
    check all(layers <- layers()) do
      named = Enum.map(layers, &{{:layer, &1}, &1})
      entries = Chart.explain(layers)
      named_entries = Chart.explain(named)

      assert Enum.map(entries, & &1.path) == Enum.map(named_entries, & &1.path)
      assert Enum.map(entries, & &1.value) == Enum.map(named_entries, & &1.value)
    end
  end

  # The leaf positions of a term, walked structurally rather than by the schema: a map is
  # descended into, so is a list whose every element is a map, and nothing else is.
  defp positions(v, path) when is_map(v) and not is_struct(v) do
    Enum.flat_map(v, fn {k, e} -> positions(e, path ++ [k]) end)
  end

  defp positions([], _path), do: []

  defp positions(v, path) when is_list(v) do
    if Enum.all?(v, &(is_map(&1) and not is_struct(&1))) do
      v |> Enum.with_index() |> Enum.flat_map(fn {e, i} -> positions(e, path ++ [i]) end)
    else
      [path]
    end
  end

  defp positions(_v, path), do: [path]

  defp at(value, []), do: value
  defp at(value, [k | rest]) when is_list(value), do: at(Enum.at(value, k), rest)
  defp at(value, [k | rest]) when is_map(value), do: at(Map.fetch!(value, k), rest)
end
