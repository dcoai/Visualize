# metresis `histogram`: the distribution within the window — a bin transform under a rect;
# the bin count is a variable.
%{
  version: 1,
  meta: %{name: "histogram"},
  sources: %{samples: %{fields: [:w]}},
  vars: %{bins: %{default: 5}},
  frame: %{
    kind: :cartesian,
    margin: %{top: 20, right: 20, bottom: 30, left: 40},
    scales: %{x: %{kind: :linear}, y: %{kind: :linear, domain: [0, :auto]}},
    axes: [%{scale: :x, side: :bottom, ticks: 5}, %{scale: :y, side: :left, ticks: 4, grid: true}]
  },
  marks: [
    %{
      type: :rect,
      data: %{
        source: :samples,
        transforms: [%{op: :bin, field: :w, thresholds: Visualize.Chart.var(:bins)}]
      },
      channels: %{x0: :x0, x1: :x1, y0: :y0, y1: :count}
    }
  ],
  labels: [%{anchor: :title, text: ["Histogram"]}, %{anchor: {:axis, :x}, text: ["kg"]}]
}
