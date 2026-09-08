# metresis `line`: the default for a gauge — one series over time, deploys ruled. The
# series is a slot filled by the pool's `series` when nothing binds `primary`; the title
# and the unit are variables with defaults.
%{
  version: 1,
  meta: %{name: "line"},
  sources: %{primary: %{fields: [:t, :v], default: :series}, events: %{fields: [:at, :sha]}},
  vars: %{title: %{default: "Weight"}, unit: %{default: "kg"}},
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
    %{type: :line, data: :primary, channels: %{x: :t, y: :v}, style: :series},
    %{
      type: :rule,
      data: :events,
      channels: %{x: :at},
      label: %{text: ["deploy ", {:field, :sha}]},
      style: :muted
    }
  ],
  labels: [
    %{anchor: :title, text: [Visualize.Chart.var(:title)]},
    %{anchor: {:axis, :y}, text: [Visualize.Chart.var(:unit)]}
  ]
}
