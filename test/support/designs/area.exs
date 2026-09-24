# metresis `area`: composition over time, one series.
%{
  version: 2,
  meta: %{name: "area"},
  sources: %{series: %{fields: [:t, :v]}},
  styles: %{series: %{fill_opacity: 0.4, stroke: :series_1}},
  frames: %{main: %{
    kind: :cartesian,
    margin: %{top: 20, right: 20, bottom: 30, left: 40},
    scales: %{x: %{kind: :time}, y: %{kind: :linear, domain: [0, :auto], nice: true}},
    axes: [
      %{scale: :x, side: :bottom, ticks: 4, format: "%H:%M"},
      %{scale: :y, side: :left, ticks: 4}
    ]
  }},
  marks: [%{type: :area, data: :series, channels: %{x: :t, y: :v}, style: :series}],
  labels: [%{anchor: :title, text: ["Area"]}]
}
