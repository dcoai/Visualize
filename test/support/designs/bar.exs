# metresis `bar`: a tally over discrete buckets.
%{
  version: 1,
  meta: %{name: "bar"},
  sources: %{categories: %{fields: [:cat, :n]}},
  frame: %{
    kind: :cartesian,
    margin: %{top: 20, right: 20, bottom: 30, left: 40},
    scales: %{
      x: %{kind: :band, domain: :auto, padding: 0.2},
      y: %{kind: :linear, domain: [0, :auto], nice: true}
    },
    axes: [%{scale: :x, side: :bottom}, %{scale: :y, side: :left, ticks: 4, grid: true}]
  },
  marks: [
    %{
      type: :rect,
      data: :categories,
      channels: %{x0: :cat, x1: :cat, y0: 0, y1: :n},
      label: %{text: [{:field, :n}], anchor: :top}
    }
  ],
  labels: [%{anchor: :title, text: ["Bar"]}]
}
