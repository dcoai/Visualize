defmodule Visualize.Chart.ExplainStyleTest do
  @moduledoc """
  `Visualize.Chart.explain/2` (spec/14 §17.3, #661, D-172): for one element of an applied
  chart, each part of its style with the layer, the style name, the names it was reached
  through and the field reading that set it, lowest first, and whether the kind draws it.
  """
  use ExUnit.Case, async: true

  alias Visualize.Chart

  @rows [%{x: 0, y: 1, health: "warning"}, %{x: 1, y: 2, health: :good}]

  defp applied(marks, styles \\ %{}, labels \\ []) do
    design = %{
      version: 3,
      sources: %{s: %{fields: [:x, :y, :health]}},
      styles: styles,
      frames: %{
        main: %{
          kind: :cartesian,
          scales: %{x: %{kind: :linear}, y: %{kind: :linear}},
          axes: [%{scale: :x, side: :bottom}]
        }
      },
      marks: marks,
      labels: labels
    }

    {:ok, applied} = Chart.apply(design, sources: %{s: @rows})
    applied
  end

  defp chain(parts, part), do: Enum.map(parts[part].chain, &{&1.layer, &1.style})

  test "every layer of a stack, in order, each with what it set" do
    styles = %{heavy: %{extends: :bad, stroke: %{width: 4}}}
    stack = [:style_2, :heavy, {:field, :health}, %{stroke: %{width: 1}}]
    marks = [%{type: :rect, data: :s, channels: %{x0: :x, x1: :x, y0: 0, y1: :y}, style: stack}]

    %{parts: parts, kind: :rect, state: :selected} =
      Chart.explain(applied(marks, styles),
        at: [:marks, 0],
        datum: hd(@rows),
        state: :selected
      )

    # The palette's series style, the declared style through its `extends`, the style the
    # datum's `health` names, the view state, then the local edit (spec/14 §3.7).
    assert chain(parts, :stroke) == [
             {:theme, nil},
             {:palette, :style_2},
             {:style, :heavy},
             {:field, :warning},
             {:state, :selected},
             {:local, nil}
           ]

    [_root, _palette, heavy, field, state, local] = parts.stroke.chain
    assert heavy.via == [:bad]
    assert heavy.set.width == 4
    assert field.field == {:field, :health} and field.value == "warning"
    assert state.set == %{width: 2}
    assert local.set == %{width: 1}

    # The value is the merge of the chain: the local width over the warning stroke.
    assert parts.stroke.value.width == 1
    assert parts.stroke.value.color == {:color, :warning}

    # A marker the rect does not draw is still explained, as not drawn.
    assert parts.marker.drawn == false
    assert parts.fill.drawn == true
  end

  test "without a datum a field entry lays nothing; without a style the mark's own paint" do
    marks = [%{type: :line, data: :s, channels: %{x: :x, y: :y}, style: [{:field, :health}]}]
    %{parts: parts} = Chart.explain(applied(marks), at: [:marks, 0])

    assert [
             %{layer: :theme, container: :theme},
             %{layer: :mark, set: %{type: :solid, color: {:series, 1}}}
           ] =
             parts.stroke.chain
  end

  test "labels, a mark's inline label and an axis explain their own stacks" do
    marks = [
      %{
        type: :rule,
        data: :s,
        channels: %{x: :x},
        label: %{text: "r", anchor: :top, style: [:label, :bold]}
      }
    ]

    labels = [%{anchor: :title, text: "T"}]
    applied = applied(marks, %{}, labels)

    %{kind: :text, parts: parts} = Chart.explain(applied, at: [:marks, 0, :label])
    assert chain(parts, :font) == [{:theme, nil}, {:palette, :label}, {:palette, :bold}]
    assert parts.font.value.weight == :bold

    %{kind: :text, parts: title} = Chart.explain(applied, at: [:labels, 0])
    assert chain(title, :font) == [{:theme, nil}, {:palette, :title}]

    %{kind: :axis, parts: axis} = Chart.explain(applied, at: [:frames, :main, :axes, 0])
    assert chain(axis, :stroke) == [{:theme, nil}, {:palette, :axis}]
    assert axis.stroke.drawn
  end
end
