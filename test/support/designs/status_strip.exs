# metresis `status_strip`: pass or fail at a glance — a flag per interval, two fixed colours.
%{
  version: 1,
  meta: %{name: "status_strip"},
  sources: %{flags: %{fields: [:t0, :t1, :ok]}},
  styles: %{flag: %{fill: {:field, :ok}}},
  frame: %{
    kind: :cartesian,
    margin: %{top: 10, right: 10, bottom: 30, left: 10},
    scales: %{
      x: %{kind: :time},
      color: %{kind: :ordinal, domain: ["pass", "fail"], range: ["#3f8a37", "#c8373b"]}
    },
    axes: [%{scale: :x, side: :bottom, ticks: 6, format: "%H:%M"}]
  },
  marks: [
    %{
      type: :band,
      data: :flags,
      channels: %{x0: :t0, x1: :t1},
      options: %{height: 20},
      style: :flag
    }
  ]
}
