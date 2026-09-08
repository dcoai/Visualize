# metresis `step`: the default for an ordinal — a held value, never interpolated.
%{
  version: 1,
  meta: %{name: "step"},
  sources: %{series: %{fields: [:t, :mood]}},
  styles: %{series: %{stroke_width: 1.5, curve: :step_after}},
  frame: %{
    kind: :cartesian,
    size: %{width: 400, height: 200},
    margin: %{top: 20, right: 20, bottom: 30, left: 50},
    scales: %{x: %{kind: :time}, y: %{kind: :band, domain: ["down", "base", "up"]}},
    axes: [
      %{scale: :x, side: :bottom, ticks: 4, format: "%H:%M"},
      %{scale: :y, side: :left, grid: true}
    ]
  },
  marks: [%{type: :line, data: :series, channels: %{x: :t, y: :mood}, style: :series}],
  labels: [%{anchor: :title, text: ["Mood"]}]
}
