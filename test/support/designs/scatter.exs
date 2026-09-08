# metresis `scatter`: two metrics against each other, one symbol per sample.
%{
  version: 1,
  meta: %{name: "scatter"},
  sources: %{samples: %{fields: [:w, :s]}},
  styles: %{dot: %{symbol: :circle, symbol_size: 40, fill_opacity: 0.7}},
  frame: %{
    kind: :cartesian,
    size: %{width: 400, height: 200},
    margin: %{top: 20, right: 20, bottom: 30, left: 40},
    scales: %{x: %{kind: :linear, nice: true}, y: %{kind: :linear, nice: true}},
    axes: [
      %{scale: :x, side: :bottom, ticks: 5, grid: true},
      %{scale: :y, side: :left, ticks: 4, grid: true}
    ]
  },
  marks: [%{type: :symbol, data: :samples, channels: %{x: :w, y: :s}, style: :dot}],
  labels: [
    %{anchor: :title, text: ["Weight against sleep"]},
    %{anchor: {:axis, :x}, text: ["kg"]},
    %{anchor: {:axis, :y}, text: ["h"]}
  ]
}
