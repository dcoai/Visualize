defmodule Examples.Charts.PaintsChart do
  @moduledoc """
  Paints (spec/14 §3.1, §3.2, #705): what an area is filled with and a line drawn with,
  written in place in a style's parts — no `defs` entry, no gradient declared by name —
  and drawn alike by SVG and both canvases (D-175, D-179, D-180), which is what the
  backend switch above the chart is for.

  - **A linear gradient** under the request rate, `%{type: :linear, color: [a, b]}`: the
    series color fading to nothing, its stops evenly spaced, at `angle: 180`, top to bottom.
  - **A hatch** over the maintenance window, `%{type: :hatch, pattern: :crosshatch}`: the
    band reads as "not like the rest" without a hue of its own, in sizes written in points
    (`pt/1`, spec/14 §3.9).
  - **A shadow** under the line, `effect: %{type: :shadow, …}`, its offset in points and its
    color a translucent `color(:text)`.
  - **A radial gradient** on each incident, off center so the circle reads as lit from the
    top left, its outline a translucent stroke.
  - **Translucent fills**: the two incident series overlap, and where they do both show.
  """

  import Visualize.Chart.Build
  import Visualize.Color, only: [color: 1, alpha: 2, lighten: 2, darken: 2]
  import Visualize.Units, only: [pt: 1]

  alias Examples.Charts.Design

  @margin %{top: 30, right: 24, bottom: 34, left: 44}

  @doc "The size this chart is drawn at when the caller names none (spec/14 §4.2)."
  def size, do: {760, 420}

  def title, do: "Paints"

  def description,
    do: "Gradients, a hatch, a shadow and translucent paints, written in place"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        source(:requests, [:hour, :rate]),
        source(:maintenance, [:from, :to]),
        source(:incidents, [:hour, :rate, :team, :look]),

        # The rate's area: the series color fading out, top to bottom, in place.
        style(:fade,
          fill: %{
            type: :linear,
            color: [color(:series_1) |> alpha(0.55), color(:series_1) |> alpha(0)],
            angle: 180
          },
          stroke: :none
        ),

        # The rate's line, lifted off the area by a soft shadow.
        style(:trace,
          stroke: %{color: color(:series_1), width: 2.5},
          curve: :monotone_x,
          effect: %{
            type: :shadow,
            radius: 3,
            offset: [pt(2), pt(3)],
            color: color(:text) |> alpha(0.45)
          }
        ),

        # The maintenance window: crosshatched, so it reads without a hue of its own.
        style(:maintenance,
          fill: %{
            type: :hatch,
            pattern: :crosshatch,
            color: color(:warning) |> alpha(0.7),
            angle: 45,
            spacing: pt(6),
            width: pt(0.75)
          },
          stroke: %{color: color(:warning), width: 1, dash: [4, 3]}
        ),

        # Each incident lit from the top left, translucent so overlaps show: one look per
        # team, each written whole by `lit/1` rather than one extending the other, since a
        # gradient written in place and merged through `extends` does not draw yet.
        style(:incident, lit(color(:bad))),
        style(:incident_info, lit(color(:info))),
        cartesian(margin: @margin),
        linear_scale(:x, domain: [0, 24]),
        linear_scale(:y, domain: [0, :auto], nice: true),
        axis(:x, :bottom, ticks: 12),
        axis(:y, :left, ticks: 5, grid: true),
        x_band(:maintenance, %{x0: :from, x1: :to}, style: :maintenance),
        area(:requests, %{x: :hour, y: :rate, y0: {:scale, :min}}, style: :fade),
        line(:requests, %{x: :hour, y: :rate}, style: :trace),
        circle(:incidents, %{x: :hour, y: :rate, series: :team},
          style: {:field, :look},
          options: %{radius: 16}
        ),
        label({:axis, :x}, ["hour of the day"]),
        label(:subtitle, ["Requests per second, the maintenance window, and incidents"])
      ])

    {design,
     %{
       requests: request_rows(opts[:animation_tick] || 0),
       maintenance: [%{from: 2, to: 5}],
       incidents: incident_rows()
     }}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  # An incident's look in one hue: a radial gradient from a lighter step of it to a darker,
  # its center up and left, the whole paint at 0.7, and a translucent outline.
  defp lit(hue) do
    [
      fill: %{
        type: :radial,
        color: [hue |> lighten(0.5), hue, hue |> darken(0.3)],
        center: [0.35, 0.3],
        radius: 0.7,
        opacity: 0.7
      },
      stroke: %{color: hue |> alpha(0.5), width: 2}
    ]
  end

  # The day's requests; an animation tick moves the busy hours a quarter of an hour on, so
  # a run shows every paint redrawn over moving data.
  defp request_rows(tick) do
    for hour <- 0..24 do
      phase = (hour - 8 - tick * 0.25) * :math.pi() / 12
      rate = 120 + 90 * :math.sin(phase) + 15 * :math.cos(hour * 1.3)
      %{hour: hour, rate: Float.round(rate, 1)}
    end
  end

  defp incident_rows do
    [
      %{hour: 10.5, rate: 205, team: "web", look: :incident},
      %{hour: 10.9, rate: 196, team: "db", look: :incident_info},
      %{hour: 17.0, rate: 150, team: "web", look: :incident},
      %{hour: 19.4, rate: 96, team: "db", look: :incident_info}
    ]
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build
    import Visualize.Color
    import Visualize.Units

    # An incident's look in one hue: a radial gradient written in place, lit from the top
    # left, the whole paint translucent, with a translucent outline.
    lit = fn hue ->
      [
        fill: %{
          type: :radial,
          color: [hue |> lighten(0.5), hue, hue |> darken(0.3)],
          center: [0.35, 0.3],
          radius: 0.7,
          opacity: 0.7
        },
        stroke: %{color: hue |> alpha(0.5), width: 2}
      ]
    end

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Paints"}),
        source(:requests, [:hour, :rate]),
        source(:maintenance, [:from, :to]),
        source(:incidents, [:hour, :rate, :team, :look]),

        # A linear gradient in place: the series color fading out, top to bottom.
        style(:fade,
          fill: %{
            type: :linear,
            color: [color(:series_1) |> alpha(0.55), color(:series_1) |> alpha(0)],
            angle: 180
          },
          stroke: :none
        ),

        # A shadow, its offset in points and its color a translucent text color.
        style(:trace,
          stroke: %{color: color(:series_1), width: 2.5},
          curve: :monotone_x,
          effect: %{type: :shadow, radius: 3, offset: [pt(2), pt(3)], color: color(:text) |> alpha(0.45)}
        ),

        # A hatch: the window reads as different without a hue of its own.
        style(:maintenance,
          fill: %{
            type: :hatch,
            pattern: :crosshatch,
            color: color(:warning) |> alpha(0.7),
            angle: 45,
            spacing: pt(6),
            width: pt(0.75)
          },
          stroke: %{color: color(:warning), width: 1, dash: [4, 3]}
        ),
        style(:incident, lit.(color(:bad))),
        style(:incident_info, lit.(color(:info))),
        cartesian(margin: %{top: 30, right: 24, bottom: 34, left: 44}),
        linear_scale(:x, domain: [0, 24]),
        linear_scale(:y, domain: [0, :auto], nice: true),
        axis(:x, :bottom, ticks: 12),
        axis(:y, :left, ticks: 5, grid: true),
        x_band(:maintenance, %{x0: :from, x1: :to}, style: :maintenance),
        area(:requests, %{x: :hour, y: :rate, y0: {:scale, :min}}, style: :fade),
        line(:requests, %{x: :hour, y: :rate}, style: :trace),
        # Each incident's look is named by its row (`look: :incident`).
        circle(:incidents, %{x: :hour, y: :rate, series: :team},
          style: {:field, :look},
          options: %{radius: 16}
        ),
        label({:axis, :x}, ["hour of the day"])
      ])

    {:ok, applied} =
      Visualize.Chart.apply(design,
        sources: %{requests: requests, maintenance: [%{from: 2, to: 5}], incidents: incidents}
      )

    Visualize.Chart.render(applied)
    """
  end
end
