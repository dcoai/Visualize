# metresis `line`: the default for a gauge — one series over time, deploys ruled.
%{
  version: 1,
  meta: %{name: "line"},
  sources: %{series: %{fields: [:t, :v]}, events: %{fields: [:at, :sha]}},
  styles: %{series: %{stroke_width: 1.5}, muted: %{stroke: :axis, opacity: 0.6}},
  frame: %{
    kind: :cartesian,
    size: %{width: 400, height: 200},
    margin: %{top: 20, right: 20, bottom: 30, left: 40},
    scales: %{x: %{kind: :time}, y: %{kind: :linear, domain: [0, :auto], nice: true}},
    axes: [
      %{scale: :x, side: :bottom, ticks: 4, format: "%H:%M"},
      %{scale: :y, side: :left, ticks: 4, grid: true}
    ]
  },
  marks: [
    %{type: :line, data: :series, channels: %{x: :t, y: :v}, style: :series},
    %{
      type: :rule,
      data: :events,
      channels: %{x: :at},
      label: %{text: ["deploy ", {:field, :sha}]},
      style: :muted
    }
  ],
  labels: [%{anchor: :title, text: ["Weight"]}, %{anchor: {:axis, :y}, text: ["kg"]}]
}
