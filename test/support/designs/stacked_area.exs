# metresis `stacked_area`: three series stacked by a transform, one area per series.
%{
  version: 2,
  meta: %{name: "stacked_area"},
  sources: %{series: %{fields: [:t, :a, :b, :c]}},
  frames: %{main: %{
    kind: :cartesian,
    margin: %{top: 20, right: 20, bottom: 30, left: 40},
    scales: %{
      x: %{kind: :time},
      y: %{kind: :linear, domain: [0, :auto], nice: true},
      color: %{kind: :ordinal}
    },
    axes: [
      %{scale: :x, side: :bottom, ticks: 4, format: "%H:%M"},
      %{scale: :y, side: :left, ticks: 4}
    ],
    legend: %{scale: :color, position: :top_left}
  }},
  marks: [
    %{
      type: :area,
      data: %{source: :series, transforms: [%{op: :stack, fields: [:a, :b, :c]}]},
      channels: %{x: :t, y: :y1, y0: :y0, series: :key}
    }
  ],
  labels: [%{anchor: :title, text: ["Stacked area"]}]
}
