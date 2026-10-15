defmodule Examples.Charts.CompositionChart do
  @moduledoc """
  Composition (spec/14 §3.5–§3.9, #705): a look built from parts rather than written out —
  the theme's palette names and its modifiers stacked, a style derived from another part
  by part, what every element inherits said once as defaults, and sizes in real units.

  - **Palette names and modifiers, stacked.** A service's bar takes the style its state
    names (`style: {:field, :state}`, §3.6): `:good` from the theme's palette, `:degraded`
    declared as the list `[:warning, :outline]` — the warning look with the fill taken away
    — and `:down` deriving from `:bad` with a heavier stroke (`extends: :bad`), the bad
    stroke's color and dash kept part by part (§3.5). The bar labels stack `[:label, :bold]`,
    the busiest service's line `[:style_3, :thick]`, and the latency budget
    `[:bad, :dashed]`.
  - **Defaults, three deep** (§3.8): the design gives every text `em(1.05)` and every rect a
    `pt(1)` outline in the background color, and every line `pt(1.5)` on a smooth curve; the
    trend frame's own defaults draw its lines thinner, `pt(1)`, and its text at `pct(90)`
    — the nearer container wins, kind entry over parts.
  - **Units** (§3.9): `pt` for widths, `mm` for a label's gap, `em` and `pct` for sizes.
  - **A stroke that does not scale** (§3.9): the budget line is `non_scaling: true`, so
    under the page's zoom it keeps its hairline while the trend lines grow with the zoom.
  """

  import Visualize.Chart.Build
  import Visualize.Color, only: [color: 1]
  import Visualize.Units, only: [pt: 1, mm: 1, em: 1, pct: 1]

  alias Examples.Charts.Design

  @services [
    %{service: "api", latency: 84, state: :good},
    %{service: "web", latency: 142, state: :degraded},
    %{service: "db", latency: 231, state: :down},
    %{service: "cache", latency: 12, state: :good},
    %{service: "queue", latency: 176, state: :degraded}
  ]

  # The latency budget, in milliseconds: the line drawn across the trend.
  @budget 200

  @doc "The size this chart is drawn at when the caller names none (spec/14 §4.2)."
  def size, do: {820, 400}

  def title, do: "Composition"

  def description,
    do:
      "Palette names and modifiers stacked, extends, defaults, units and a stroke that does not scale"

  @doc "The page's own panels (spec/14 §12.6): the chart under zoom."
  def panels, do: [:zoom]

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    design =
      Design.fold(
        List.flatten([
          chart(meta: %{name: title(), description: [description()]}),
          layout(columns: [2, 3], gap: 12),
          source(:services, [:service, :latency, :state]),
          source(:trend, [:minute, :ms, :service]),
          source(:budget, [:ms]),

          # What every element inherits: one place says it (spec/14 §3.8).
          defaults(%{
            font: %{size: em(1.05)},
            rect: %{stroke: %{color: color(:background), width: pt(1)}},
            line: %{stroke: %{width: pt(1.5), cap: :round}, curve: %{type: :monotone_x}}
          }),

          # A list is a style: the warning look, outlined — its fill taken away.
          %{styles: %{degraded: [:warning, :outline]}},
          # A style derived part by part: bad's stroke color and dash kept, made heavier.
          style(:down, extends: :bad, stroke: %{width: pt(3)}),
          style(:heading, extends: :title, font: %{size: em(1.1)}),
          in_frame(:status, [
            cartesian(cell: [0, 0], margin: %{top: 48, right: 10, bottom: 30, left: 44}),
            band_scale(:x, padding: 0.25),
            linear_scale(:y, domain: [0, :auto], nice: true),
            axis(:x, :bottom),
            axis(:y, :left, ticks: 5),
            rect(:services, %{x0: :service, x1: :service, y0: 0, y1: :latency},
              # The state names the style: a palette name, a list, a derived style.
              style: {:field, :state},
              label: %{
                text: [{:field, :latency}, " ms"],
                anchor: :y1,
                style: [:label, :bold, %{text: %{offset: [0, mm(1)]}}]
              }
            ),
            label(:subtitle, ["Latency by service, styled by state"], style: :heading)
          ]),
          in_frame(:trend, [
            cartesian(
              cell: [1, 0],
              margin: %{top: 34, right: 16, bottom: 30, left: 44},
              # The frame's own defaults, nearer than the design's: thinner lines here.
              defaults: %{font: %{size: pct(90)}, line: %{stroke: %{width: pt(1)}}}
            ),
            linear_scale(:x),
            linear_scale(:y, domain: [0, :auto], nice: true),
            axis(:x, :bottom, ticks: 6),
            axis(:y, :left, ticks: 5, grid: true),
            line(:trend, %{x: :minute, y: :ms, series: :service}),
            # The busiest service: the palette's third style, made thick by a modifier.
            line(filter(from(:trend), :service, test: :eq, value: "db"), %{x: :minute, y: :ms},
              style: [:style_3, :thick]
            ),
            # The budget: dashed bad, a hairline that keeps its width under a zoom.
            rule(:budget, %{y: :ms},
              style: [:bad, :dashed, %{stroke: %{width: pt(0.75), non_scaling: true}}]
            ),
            label({:axis, :x}, ["minute"]),
            label(:subtitle, ["The last hour, against the #{@budget} ms budget"], style: :heading)
          ])
        ])
      )

    {design,
     %{
       services: @services,
       trend: trend_rows(opts[:animation_tick] || 0),
       budget: [%{ms: @budget}]
     }}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  # A minute's latency per service: each its own level and swing; an animation tick moves
  # the hour on by a minute.
  defp trend_rows(tick) do
    for %{service: service, latency: level} <- @services, minute <- 0..60 do
      t = minute + tick
      swing = level * 0.25 * :math.sin(t / 7 + String.length(service))
      %{minute: minute, ms: Float.round(level + swing, 1), service: service}
    end
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build
    import Visualize.Color
    import Visualize.Units

    services = [
      %{service: "api", latency: 84, state: :good},
      %{service: "web", latency: 142, state: :degraded},
      %{service: "db", latency: 231, state: :down},
      %{service: "cache", latency: 12, state: :good},
      %{service: "queue", latency: 176, state: :degraded}
    ]

    {:ok, design} =
      Visualize.Chart.compose(
        List.flatten([
          chart(meta: %{name: "Composition"}),
          layout(columns: [2, 3], gap: 12),
          source(:services, [:service, :latency, :state]),
          source(:trend, [:minute, :ms, :service]),
          source(:budget, [:ms]),

          # What every element inherits, said once: every text, every rect, every line.
          defaults(%{
            font: %{size: em(1.05)},
            rect: %{stroke: %{color: color(:background), width: pt(1)}},
            line: %{stroke: %{width: pt(1.5), cap: :round}, curve: %{type: :monotone_x}}
          }),

          # A list is a style: the palette's warning look with the outline modifier.
          %{styles: %{degraded: [:warning, :outline]}},
          # Derived part by part: bad's stroke color and dash kept, the width heavier.
          style(:down, extends: :bad, stroke: %{width: pt(3)}),
          style(:heading, extends: :title, font: %{size: em(1.1)}),
          in_frame(:status, [
            cartesian(cell: [0, 0], margin: %{top: 48, right: 10, bottom: 30, left: 44}),
            band_scale(:x, padding: 0.25),
            linear_scale(:y, domain: [0, :auto], nice: true),
            axis(:x, :bottom),
            axis(:y, :left, ticks: 5),
            # Each bar's style is the one its state names: :good, :degraded or :down.
            rect(:services, %{x0: :service, x1: :service, y0: 0, y1: :latency},
              style: {:field, :state},
              label: %{
                text: [{:field, :latency}, " ms"],
                anchor: :y1,
                style: [:label, :bold, %{text: %{offset: [0, mm(1)]}}]
              }
            ),
            label(:subtitle, ["Latency by service, styled by state"], style: :heading)
          ]),
          in_frame(:trend, [
            # The frame's own defaults are nearer than the design's: thinner lines here.
            cartesian(
              cell: [1, 0],
              margin: %{top: 34, right: 16, bottom: 30, left: 44},
              defaults: %{font: %{size: pct(90)}, line: %{stroke: %{width: pt(1)}}}
            ),
            linear_scale(:x),
            linear_scale(:y, domain: [0, :auto], nice: true),
            axis(:x, :bottom, ticks: 6),
            axis(:y, :left, ticks: 5, grid: true),
            line(:trend, %{x: :minute, y: :ms, series: :service}),
            line(filter(from(:trend), :service, test: :eq, value: "db"), %{x: :minute, y: :ms},
              style: [:style_3, :thick]
            ),
            # A hairline that keeps its width under a zoom.
            rule(:budget, %{y: :ms},
              style: [:bad, :dashed, %{stroke: %{width: pt(0.75), non_scaling: true}}]
            ),
            label({:axis, :x}, ["minute"]),
            label(:subtitle, ["The last hour, against the 200 ms budget"], style: :heading)
          ])
        ])
      )

    {:ok, applied} =
      Visualize.Chart.apply(design,
        sources: %{services: services, trend: trend, budget: [%{ms: 200}]}
      )

    Visualize.Chart.render(applied)
    """
  end
end
