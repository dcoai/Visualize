# metresis `heatmap`: value by time of day and day — a rect per cell through a sequential scale.
%{
  version: 1,
  meta: %{name: "heatmap"},
  sources: %{heat: %{fields: [:hour, :day, :v]}},
  frame: %{
    kind: :cartesian,
    margin: %{top: 20, right: 20, bottom: 30, left: 40},
    scales: %{
      x: %{kind: :band, padding: 0.05},
      y: %{kind: :band, padding: 0.05},
      color: %{kind: :sequential, domain: [0, :auto]}
    },
    axes: [%{scale: :x, side: :bottom}, %{scale: :y, side: :left}],
    legend: %{scale: :color, position: :top_right}
  },
  marks: [
    %{type: :rect, data: :heat, channels: %{x0: :hour, x1: :hour, y0: :day, y1: :day, value: :v}}
  ],
  labels: [%{anchor: :title, text: ["Heatmap"]}]
}
