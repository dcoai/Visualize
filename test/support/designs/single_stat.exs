# metresis `single_stat`: one number and a sparkline — no axes, the frame's labels carry
# the text, which is two variables: the stat and its comparison.
%{
  version: 1,
  meta: %{name: "single_stat"},
  sources: %{series: %{fields: [:t, :v]}},
  vars: %{value: %{default: "8 kg"}, delta: %{default: "+1.5 vs last week"}},
  styles: %{
    spark: %{stroke: :series_1, stroke_width: 1},
    big: %{fill: :text, font_size: :title_size, font_weight: :bold}
  },
  frame: %{
    kind: :cartesian,
    size: %{width: 200, height: 100},
    margin: %{top: 40, right: 10, bottom: 10, left: 10},
    scales: %{x: %{kind: :time}, y: %{kind: :linear, domain: [0, :auto]}}
  },
  marks: [%{type: :line, data: :series, channels: %{x: :t, y: :v}, style: :spark}],
  labels: [
    %{anchor: {:frame, :top_left}, text: [Visualize.Chart.var(:value)], style: :big, dy: -30},
    %{anchor: {:frame, :top_right}, text: [Visualize.Chart.var(:delta)], dy: -30}
  ]
}
