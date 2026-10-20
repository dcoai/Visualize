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
    top left, its outline a translucent stroke; the second team's look `extends` the first
    and sets only its own colors, keeping the gradient's geometry (spec/14 §3.5, D-186).
  - **Translucent fills, multiplied**: the two incident series overlap, and where they do both
    show, their colors multiplied (`blend: :multiply`).
  - **Swatches** beneath (#786): the `:lines` and `:dots` hatch patterns, and a stroke's
    `placement` on its edge — `:inside`, `:outside`, `:double`. The binary canvas clips the
    edged strokes and multiplies the incidents as SVG does, with its version 4 `clip` and
    `blend` records (spec/09 §4.3.18, §4.3.19, #788).
  """

  import Visualize.Chart.Build
  import Visualize.Color, only: [color: 1, alpha: 2, lighten: 2, darken: 2]
  import Visualize.Units, only: [pt: 1]

  alias Examples.Charts.Design

  @margin %{top: 30, right: 24, bottom: 34, left: 44}

  @doc "The size this chart is drawn at when the caller names none (spec/14 §4.2)."
  def size, do: {760, 540}

  def title, do: "Paints"

  def description,
    do: "Gradients, hatches, a shadow, stroke placement and blend, written in place"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    design =
      Design.fold(
        List.flatten([
          chart(meta: %{name: title(), description: [description()]}),
          layout(rows: [3, 1], gap: 8),
          source("swatches", ["look"]),
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
          # team, the second extending the first — its radial gradient's center, radius and
          # opacity, its outline's width — in its own colors.
          style(:incident,
            fill: %{
              type: :radial,
              color: shades(color(:bad)),
              center: [0.35, 0.3],
              radius: 0.7,
              opacity: 0.7
            },
            stroke: %{color: color(:bad) |> alpha(0.5), width: 2},
            # Where two incidents overlap, their colors multiply.
            blend: :multiply
          ),
          style(:incident_info,
            extends: :incident,
            fill: %{color: shades(color(:info))},
            stroke: %{color: color(:info) |> alpha(0.5)}
          ),
          in_frame("main", [
            cartesian(cell: [0, 0], margin: @margin),
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
          ]),
          # The swatches: the other hatch patterns, and a stroke's placement on its edge — inside
          # the shape, outside it, or doubled (spec/14 §3.1).
          style("lines",
            fill: %{
              type: :hatch,
              pattern: :lines,
              color: color(:series_1),
              spacing: pt(5),
              width: pt(1)
            },
            stroke: %{color: color(:series_1), width: 1}
          ),
          style("dots",
            fill: %{
              type: :hatch,
              pattern: :dots,
              color: color(:series_4),
              spacing: pt(5),
              width: pt(2)
            },
            stroke: %{color: color(:series_4), width: 1}
          ),
          style("inside",
            fill: color(:series_2) |> alpha(0.25),
            stroke: %{color: color(:series_2), width: 6, placement: :inside}
          ),
          style("outside",
            fill: color(:series_2) |> alpha(0.25),
            stroke: %{color: color(:series_2), width: 6, placement: :outside}
          ),
          style("double",
            fill: color(:series_2) |> alpha(0.25),
            stroke: %{color: color(:series_2), width: 9, placement: :double}
          ),
          in_frame("swatches", [
            cartesian(cell: [0, 1], margin: %{top: 24, right: 24, bottom: 24, left: 44}),
            band_scale(:x, padding: 0.3),
            linear_scale(:y, domain: [0, 1]),
            axis(:x, :bottom),
            rect("swatches", %{x0: "look", x1: "look", y0: 0, y1: 1}, style: {:field, "look"}),
            label(:subtitle, ["Hatch patterns, and a stroke inside, outside and doubled"])
          ])
        ])
      )

    {design,
     %{
       requests: request_rows(opts[:animation_tick] || 0),
       maintenance: [%{from: 2, to: 5}],
       incidents: incident_rows(),
       swatches: for(look <- ~w(lines dots inside outside double), do: %{"look" => look})
     }}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  # An incident's gradient in one hue: a lighter step of it, the hue, a darker step.
  defp shades(hue), do: [hue |> lighten(0.5), hue, hue |> darken(0.3)]

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

    # An incident's gradient in one hue: a lighter step of it, the hue, a darker step.
    shades = fn hue -> [hue |> lighten(0.5), hue, hue |> darken(0.3)] end

    {:ok, design} =
      Visualize.Chart.compose(
        List.flatten([
        chart(meta: %{name: "Paints"}),
        layout(rows: [3, 1], gap: 8),
        source("swatches", ["look"]),
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
        # A radial gradient in place, lit from the top left, the whole paint translucent,
        # with a translucent outline; the second look extends it in its own colors.
        style(:incident,
          fill: %{
            type: :radial,
            color: shades.(color(:bad)),
            center: [0.35, 0.3],
            radius: 0.7,
            opacity: 0.7
          },
          stroke: %{color: color(:bad) |> alpha(0.5), width: 2},
          # Where two incidents overlap, their colors multiply.
          blend: :multiply
        ),
        style(:incident_info,
          extends: :incident,
          fill: %{color: shades.(color(:info))},
          stroke: %{color: color(:info) |> alpha(0.5)}
        ),
        in_frame("main", [
        cartesian(cell: [0, 0], margin: %{top: 30, right: 24, bottom: 34, left: 44}),
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
        ]),
        # The swatches: the other hatch patterns, and a stroke's placement on its edge — inside
        # the shape, outside it, or doubled (spec/14 §3.1).
        style("lines",
          fill: %{type: :hatch, pattern: :lines, color: color(:series_1), spacing: pt(5), width: pt(1)},
          stroke: %{color: color(:series_1), width: 1}
        ),
        style("dots",
          fill: %{type: :hatch, pattern: :dots, color: color(:series_4), spacing: pt(5), width: pt(2)},
          stroke: %{color: color(:series_4), width: 1}
        ),
        style("inside",
          fill: color(:series_2) |> alpha(0.25),
          stroke: %{color: color(:series_2), width: 6, placement: :inside}
        ),
        style("outside",
          fill: color(:series_2) |> alpha(0.25),
          stroke: %{color: color(:series_2), width: 6, placement: :outside}
        ),
        style("double",
          fill: color(:series_2) |> alpha(0.25),
          stroke: %{color: color(:series_2), width: 9, placement: :double}
        ),
        in_frame("swatches", [
          cartesian(cell: [0, 1], margin: %{top: 24, right: 24, bottom: 24, left: 44}),
          band_scale(:x, padding: 0.3),
          linear_scale(:y, domain: [0, 1]),
          axis(:x, :bottom),
          rect("swatches", %{x0: "look", x1: "look", y0: 0, y1: 1}, style: {:field, "look"}),
          label(:subtitle, ["Hatch patterns, and a stroke inside, outside and doubled"])
        ])

        ])
      )

    {:ok, applied} =
      Visualize.Chart.apply(design,
        sources: %{
          requests: requests,
          maintenance: [%{from: 2, to: 5}],
          incidents: incidents,
          swatches: for(look <- ~w(lines dots inside outside double), do: %{"look" => look})
        }
      )

    Visualize.Chart.render(applied)
    """
  end
end
