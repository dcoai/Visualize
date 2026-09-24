# metresis `rose`: a cyclic quantity — a wind rose over eight bearings.
%{
  version: 2,
  meta: %{name: "rose"},
  sources: %{wind: %{fields: [:bearing, :count]}},
  styles: %{petal: %{fill: :series_1, stroke: :background}},
  frames: %{main: %{
    kind: :polar,
    margin: %{top: 30, right: 30, bottom: 30, left: 30},
    scales: %{angle: %{kind: :radial, domain: [0, 360]}, r: %{kind: :sqrt, domain: [0, :auto]}},
    axes: [
      %{scale: :angle, side: :bottom, ticks: 8, grid: true},
      %{scale: :r, side: :top, ticks: 3, grid: true}
    ]
  }},
  marks: [
    %{
      type: :rose,
      data: :wind,
      channels: %{angle: :bearing, value: :count},
      options: %{width: 45, pad_angle: 0.02},
      style: :petal
    }
  ],
  labels: [%{anchor: :title, text: ["Wind"]}]
}
