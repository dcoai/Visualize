# metresis `stacked_bar`: the stack transform under one rect mark, coloured by key.
%{
  version: 2,
  meta: %{name: "stacked_bar"},
  sources: %{categories: %{fields: [:cat, :a, :b, :c]}},
  frames: %{main: %{
    kind: :cartesian,
    margin: %{top: 20, right: 20, bottom: 30, left: 40},
    scales: %{
      x: %{kind: :band, padding: 0.2},
      y: %{kind: :linear, domain: [0, :auto], nice: true},
      color: %{kind: :ordinal}
    },
    axes: [%{scale: :x, side: :bottom}, %{scale: :y, side: :left, ticks: 4, grid: true}],
    legend: %{scale: :color, position: :top_right}
  }},
  marks: [
    %{
      type: :rect,
      data: %{source: :categories, transforms: [%{op: :stack, fields: [:a, :b, :c]}]},
      channels: %{x0: :cat, x1: :cat, y0: :y0, y1: :y1, value: :key}
    }
  ],
  labels: [%{anchor: :title, text: ["Stacked bar"]}]
}
