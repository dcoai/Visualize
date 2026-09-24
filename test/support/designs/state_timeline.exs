# metresis `state_timeline`: which state, for how long — a band per interval, filled by
# state; the band's options are one variable standing for the whole node.
%{
  version: 1,
  meta: %{name: "state_timeline"},
  sources: %{states: %{fields: [:t0, :t1, :state]}},
  vars: %{band: %{default: %{height: 50}}},
  styles: %{
    by_state: %{fill: {:field, :state}, stroke: :background},
    over: %{fill: :background, font_size: :font_size, font_family: :font_family}
  },
  frame: %{
    kind: :cartesian,
    margin: %{top: 20, right: 20, bottom: 30, left: 20},
    scales: %{
      x: %{kind: :time},
      color: %{kind: :ordinal, domain: ["ok", "degraded", "down"]}
    },
    axes: [%{scale: :x, side: :bottom, ticks: 6, format: "%H:%M"}],
    legend: %{scale: :color, position: :top}
  },
  marks: [
    %{
      type: :band,
      data: :states,
      channels: %{x0: :t0, x1: :t1},
      options: Visualize.Chart.var(:band),
      style: :by_state,
      label: %{text: [{:field, :state}], anchor: :middle, style: :over}
    }
  ],
  labels: [%{anchor: :title, text: ["Build status"]}]
}
