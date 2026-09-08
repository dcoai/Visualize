defmodule Visualize.Chart.ComposeTest do
  @moduledoc """
  Composition of fragments by the schema's merge rules (spec/14 §1.5, §8, D-65):
  collections concatenate associatively, declarations unite with a conflict at a name
  declared differently, scalars are the later's, and a node both fragments give as a
  map merges key by key.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Visualize.Chart

  @label_set %{
    labels: [
      %{anchor: :caption, text: ["© house"]},
      %{anchor: {:frame, :top_right}, text: ["last 24 h"]}
    ]
  }
  @house %{
    version: 1,
    theme: :dark,
    styles: %{series: %{stroke_width: 2}, muted: %{opacity: 0.5}},
    frame: %{
      kind: :cartesian,
      size: %{width: 800, height: 400},
      margin: %{top: 10, right: 10, bottom: 30, left: 40},
      scales: %{x: %{kind: :time}},
      axes: [%{scale: :x, side: :bottom, ticks: 6}]
    }
  }
  @chart %{
    version: 1,
    sources: %{primary: %{fields: [:t, :v]}},
    styles: %{accent: %{stroke: :series_2}},
    frame: %{
      kind: :cartesian,
      size: %{width: 600, height: 300},
      scales: %{y: %{kind: :linear, domain: [0, :auto]}},
      axes: [%{scale: :y, side: :left, grid: true}]
    },
    marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v}, style: :accent}],
    labels: [%{anchor: :title, text: ["Uptime"]}]
  }

  describe "compose/2" do
    test "a label set, a house sheet and a chart compose into one design that validates" do
      {:ok, design} = Chart.compose([@label_set, @house, @chart])

      assert Enum.map(design.labels, & &1.anchor) == [:caption, {:frame, :top_right}, :title]
      assert Map.keys(design.styles) |> Enum.sort() == [:accent, :muted, :series]
      assert design.theme == :dark
      assert design.frame.size == %{width: 600, height: 300}
      assert design.frame.margin == @house.frame.margin
      assert Map.keys(design.frame.scales) |> Enum.sort() == [:x, :y]
      assert Enum.map(design.frame.axes, & &1.scale) == [:x, :y]
      assert design.marks == @chart.marks
      assert {:ok, _} = Chart.from_map(design)
    end

    test "a union name declared differently is a conflict at its path, every one reported" do
      a = %{styles: %{series: %{stroke_width: 2}}, frame: %{scales: %{x: %{kind: :time}}}}
      b = %{styles: %{series: %{stroke_width: 3}}, frame: %{scales: %{x: %{kind: :linear}}}}

      assert Chart.compose(a, b) ==
               {:error, [{[:frame, :scales, :x], :conflict}, {[:styles, :series], :conflict}]}

      assert Chart.compose([a, b]) == Chart.compose(a, b)
    end

    test "a union name declared equally in both is taken once" do
      a = %{styles: %{series: %{stroke_width: 2}}, vars: %{unit: %{default: "%"}}}
      assert Chart.compose(a, a) == {:ok, a}
    end

    test "a key one fragment alone carries is taken as it is" do
      assert Chart.compose(%{version: 1}, %{marks: []}) == {:ok, %{version: 1, marks: []}}
      assert Chart.compose(%{}, @chart) == {:ok, @chart}
      assert Chart.compose(@chart, %{}) == {:ok, @chart}
    end

    test "a node given as anything but a map by either side is the later's whole" do
      var = Chart.var(:frame)
      assert Chart.compose(%{frame: %{kind: :polar}}, %{frame: var}) == {:ok, %{frame: var}}

      assert Chart.compose(%{theme: :dark}, %{theme: %{name: :house}}) ==
               {:ok, %{theme: %{name: :house}}}

      assert Chart.compose(%{theme: %{name: :a, axis: "#000"}}, %{theme: %{name: :b}}) ==
               {:ok, %{theme: %{name: :b, axis: "#000"}}}
    end

    test "a key the schema does not know is the later's" do
      assert Chart.compose(%{extra: 1, marks: [1]}, %{extra: 2, marks: [2]}) ==
               {:ok, %{extra: 2, marks: [1, 2]}}
    end

    test "a chart struct is taken as its map" do
      chart = Chart.from_map!(@chart)

      assert Chart.compose(@label_set, chart) == Chart.compose(@label_set, Chart.to_map(chart))

      assert {:ok, design} = Chart.compose(@label_set, chart)
      assert length(design.labels) == 3
    end

    test "compose/1 folds left to right and is the empty map for no fragments" do
      assert Chart.compose([]) == {:ok, %{}}
      assert Chart.compose([@chart]) == {:ok, @chart}
      {:ok, ab} = Chart.compose(@label_set, @house)
      assert Chart.compose([@label_set, @house, @chart]) == Chart.compose(ab, @chart)
    end
  end

  # -- properties over generated fragments ------------------------------------------

  @style_names [:series, :muted, :accent, :axis, :label]
  @scale_names [:x, :y, :color, :angle]

  defp style, do: optional_map(%{stroke_width: integer(1..5), opacity: float(min: 0.0, max: 1.0)})
  defp scale, do: fixed_map(%{kind: member_of([:linear, :time, :band]), nice: boolean()})

  # Declarations over a small name pool: names collide often, so both the equal-once and
  # the conflict branches of `:union` are exercised.
  defp names(pool, gen),
    do: map(list_of(tuple({member_of(pool), gen}), max_length: 3), &Map.new/1)

  defp mark,
    do:
      fixed_map(%{
        type: member_of([:line, :area]),
        data: constant(:p),
        channels: constant(%{x: :t, y: :v})
      })

  defp label,
    do:
      fixed_map(%{
        anchor: member_of([:title, :caption]),
        text: list_of(string(:alphanumeric), max_length: 2)
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
      labels: list_of(label(), max_length: 3)
    })
  end

  property "collections concatenate and scalars are the later's" do
    check all(a <- fragment(), b <- fragment()) do
      case Chart.compose(a, b) do
        {:ok, merged} ->
          assert Map.get(merged, :marks) == concat(a, b, :marks)
          assert Map.get(merged, :labels) == concat(a, b, :labels)
          assert Map.get(merged, :theme) == later(a, b, :theme)
          assert Map.get(merged, :version) == later(a, b, :version)

          if is_map(a[:frame]) and is_map(b[:frame]) do
            assert Map.get(merged.frame, :size) == later(a.frame, b.frame, :size)
            assert Map.get(merged.frame, :kind) == later(a.frame, b.frame, :kind)
            assert Map.get(merged.frame, :axes) == concat(a.frame, b.frame, :axes)
          else
            assert Map.get(merged, :frame) == later(a, b, :frame)
          end

        {:error, errors} ->
          assert Enum.all?(errors, &match?({[_ | _], :conflict}, &1))
          assert Enum.any?(errors, fn {path, _} -> conflicting?(a, b, path) end)
      end
    end
  end

  property "composition over a list is associative" do
    check all(a <- fragment(), b <- fragment(), c <- fragment()) do
      left = with {:ok, ab} <- Chart.compose(a, b), do: Chart.compose(ab, c)
      right = with {:ok, bc} <- Chart.compose(b, c), do: Chart.compose(a, bc)

      case {left, right} do
        {{:ok, l}, {:ok, r}} -> assert l == r
        {{:error, _}, {:error, _}} -> :ok
        {{:ok, _}, {:error, _}} -> flunk("left fold composed, right fold conflicted")
        {{:error, _}, {:ok, _}} -> flunk("right fold composed, left fold conflicted")
      end

      assert Chart.compose([a, b, c]) == left
    end
  end

  property "union keys compose the same in either order when nothing conflicts" do
    check all(a <- fragment(), b <- fragment()) do
      with {:ok, ab} <- Chart.compose(a, b), {:ok, ba} <- Chart.compose(b, a) do
        assert Map.get(ab, :styles) == Map.get(ba, :styles)
        assert Map.get(ab, :vars) == Map.get(ba, :vars)
      end
    end
  end

  defp concat(a, b, key) do
    case {Map.fetch(a, key), Map.fetch(b, key)} do
      {{:ok, x}, {:ok, y}} -> x ++ y
      {{:ok, x}, :error} -> x
      {:error, {:ok, y}} -> y
      {:error, :error} -> nil
    end
  end

  defp later(a, b, key), do: Map.get(b, key, Map.get(a, key))

  defp conflicting?(a, b, path) do
    x = get_in(a, Enum.map(path, &Access.key(&1, nil)))
    y = get_in(b, Enum.map(path, &Access.key(&1, nil)))
    x != nil and y != nil and x != y
  end
end
