defmodule Examples.Charts.ColorsChart do
  @moduledoc """
  Colors as values (spec/08 §1.9, spec/14 §3.2, #705): every color the chart draws is a
  **typed color** — a name of the theme's color table, `color(:blue)`, or a transform of
  one — resolved through the theme at render, so the palette switch above the chart
  recolors every swatch, the derived ones included.

  Two frames on one layout (spec/14 §2.8):

  - **Transforms.** One tile per row, filled through the frame's ordinal `color` scale,
    whose range lists one color value per row (spec/14 §4.3, D-185): a name,
    `intensity/2`, `lighten/2`, `darken/2`, `blend/1` of two names and of two weighted ones,
    a role, a ramp position and a CSS name. The tile's text is `contrast()` (§3.2), the ink
    chosen per tile against the color it sits on — dark on a pale tile, light on a dark one,
    in one style.
  - **Shades.** `shade(color(:red), n)` from 0 to 1000 (spec/08 §1.9), 500 being the name
    itself, the range of the frame's `color` scale, each step labeled in its own contrast
    ink.

  The design names no theme, so on SVG it is drawn in the implicit default theme and its
  root carries the automatic dark mode rule (spec/08 §7.3) — what the page's
  *Automatic dark mode* panel shows beside `color_scheme: false`.
  """

  import Visualize.Chart.Build

  import Visualize.Color,
    only: [
      color: 1,
      intensity: 2,
      lighten: 2,
      darken: 2,
      blend: 1,
      alpha: 2,
      contrast: 0,
      ramp: 2,
      shade: 2
    ]

  alias Examples.Charts.Design

  # The transform rows, top to bottom: the expression as a person writes it, and the
  # color value its tile is filled with, through the frame's color scale.
  @transforms [
    {"color(:blue)", color(:blue)},
    {"color(:blue) |> intensity(0.5)", color(:blue) |> intensity(0.5)},
    {"color(:blue) |> lighten(0.4)", color(:blue) |> lighten(0.4)},
    {"color(:blue) |> darken(0.4)", color(:blue) |> darken(0.4)},
    {"blend([color(:blue), color(:red)])", blend([color(:blue), color(:red)])},
    {"blend([…0.65, …0.3]) |> alpha(0.65)",
     blend([color(:blue) |> intensity(0.65), color(:red) |> intensity(0.3)]) |> alpha(0.65)},
    {"color(:bad)", color(:bad)},
    {"ramp(:thermal, 0.8)", ramp(:thermal, 0.8)},
    {"color(:steelblue)", color(:steelblue)}
  ]

  @steps Enum.map(0..10, &(&1 * 100))

  @doc "The size this chart is drawn at when the caller names none (spec/14 §4.2)."
  def size, do: {760, 520}

  def title, do: "Colors"

  @doc "The page's own panels (spec/14 §12.6): this design under the implicit theme."
  def panels, do: [:dark_mode]

  def description,
    do: "Typed colors, transform chains and shades, each resolved through the theme"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    design =
      Design.fold(
        List.flatten([
          chart(meta: %{name: title(), description: [description()]}),
          layout(rows: [3, 1], gap: 16),
          source(:transforms, [:expr]),
          source(:shades, [:step]),

          # A tile is filled by the row's category, through the frame's color scale.
          style(:tile, fill: {:field, :expr}),
          style(:step, fill: {:field, :step}),

          # The tile's text: the ink that reads on whatever tile it sits on.
          style(:ink, extends: :label, fill: contrast(), font: %{weight: :bold}),
          style(:heading, extends: :title, font: %{size: 13}),
          in_frame(:transforms, [
            cartesian(cell: [0, 0], margin: %{top: 28, right: 20, bottom: 8, left: 250}),
            # A band runs up the y axis, so the domain lists the rows bottom first.
            band_scale(:y,
              domain: Enum.reverse(Enum.map(@transforms, &elem(&1, 0))),
              padding: 0.12
            ),
            linear_scale(:x, domain: [0, 1]),
            # A color value per row: the range of a color scale is a color position.
            ordinal_scale(:color,
              domain: Enum.map(@transforms, &elem(&1, 0)),
              range: Enum.map(@transforms, &elem(&1, 1))
            ),
            axis(:y, :left),
            rect(:transforms, %{y0: :expr, y1: :expr, x0: 0, x1: 1},
              style: :tile,
              label: %{text: ["Aa · contrast()"], anchor: :middle, style: :ink}
            ),
            label(:subtitle, ["Transforms of the theme's names"], style: :heading)
          ]),
          in_frame(:shades, [
            cartesian(cell: [0, 1], margin: %{top: 28, right: 20, bottom: 8, left: 20}),
            band_scale(:x, padding: 0.06),
            linear_scale(:y, domain: [0, 1]),
            ordinal_scale(:color,
              domain: Enum.map(@steps, &Integer.to_string/1),
              range: Enum.map(@steps, &shade(color(:red), &1))
            ),
            rect(:shades, %{x0: :step, x1: :step, y0: 0, y1: 1},
              style: :step,
              label: %{text: [{:field, :step}], anchor: :middle, style: :ink}
            ),
            label(:subtitle, ["shade(color(:red), n), from 0 to 1000"], style: :heading)
          ])
        ])
      )

    {design, %{transforms: transform_rows(), shades: shade_rows(opts[:animation_tick] || 0)}}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  defp transform_rows, do: for({expr, _color} <- @transforms, do: %{expr: expr})

  # The strip's steps in order; an animation tick turns the strip by a step per tick, so a
  # run walks the scale through the band.
  defp shade_rows(tick) do
    for i <- 0..10 do
      %{step: Integer.to_string(rem(i + tick, 11) * 100)}
    end
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build
    import Visualize.Color

    # A color is a value: a name of the theme's table, or a transform of one, resolved
    # through the theme at render. A color scale's range is a color position, so each
    # row's tile takes its color value from the frame's `color` scale; its text is the
    # contrast ink, chosen per tile.
    transforms = [
      {"color(:blue)", color(:blue)},
      {"color(:blue) |> intensity(0.5)", color(:blue) |> intensity(0.5)},
      {"color(:blue) |> lighten(0.4)", color(:blue) |> lighten(0.4)},
      {"color(:blue) |> darken(0.4)", color(:blue) |> darken(0.4)},
      {"blend([color(:blue), color(:red)])", blend([color(:blue), color(:red)])},
      {"blend([…0.65, …0.3]) |> alpha(0.65)",
       blend([color(:blue) |> intensity(0.65), color(:red) |> intensity(0.3)]) |> alpha(0.65)},
      {"color(:bad)", color(:bad)},
      {"ramp(:thermal, 0.8)", ramp(:thermal, 0.8)},
      {"color(:steelblue)", color(:steelblue)}
    ]

    steps = Enum.map(0..1000//100, &Integer.to_string/1)

    {:ok, design} =
      Visualize.Chart.compose(
        List.flatten([
          chart(meta: %{name: "Colors"}),
          layout(rows: [3, 1], gap: 16),
          source(:transforms, [:expr]),
          source(:shades, [:step]),
          style(:tile, fill: {:field, :expr}),
          style(:step, fill: {:field, :step}),
          style(:ink, extends: :label, fill: contrast(), font: %{weight: :bold}),
          style(:heading, extends: :title, font: %{size: 13}),
          in_frame(:transforms, [
            cartesian(cell: [0, 0], margin: %{top: 28, right: 20, bottom: 8, left: 250}),
            # A band runs up the y axis, so the domain lists the rows bottom first.
            band_scale(:y, domain: Enum.reverse(Enum.map(transforms, &elem(&1, 0))), padding: 0.12),
            linear_scale(:x, domain: [0, 1]),
            ordinal_scale(:color,
              domain: Enum.map(transforms, &elem(&1, 0)),
              range: Enum.map(transforms, &elem(&1, 1))
            ),
            axis(:y, :left),
            rect(:transforms, %{y0: :expr, y1: :expr, x0: 0, x1: 1},
              style: :tile,
              label: %{text: ["Aa · contrast()"], anchor: :middle, style: :ink}
            ),
            label(:subtitle, ["Transforms of the theme's names"], style: :heading)
          ]),
          in_frame(:shades, [
            cartesian(cell: [0, 1], margin: %{top: 28, right: 20, bottom: 8, left: 20}),
            band_scale(:x, padding: 0.06),
            linear_scale(:y, domain: [0, 1]),
            ordinal_scale(:color,
              domain: steps,
              range: Enum.map(0..1000//100, &shade(color(:red), &1))
            ),
            rect(:shades, %{x0: :step, x1: :step, y0: 0, y1: 1},
              style: :step,
              label: %{text: [{:field, :step}], anchor: :middle, style: :ink}
            ),
            label(:subtitle, ["shade(color(:red), n), from 0 to 1000"], style: :heading)
          ])
        ])
      )

    rows = %{
      transforms: for({expr, _color} <- transforms, do: %{expr: expr}),
      shades: for(step <- steps, do: %{step: step})
    }

    {:ok, applied} = Visualize.Chart.apply(design, sources: rows)
    Visualize.Chart.render(applied)

    # No theme named: drawn as a document (`root: true`), the root carries a rule that
    # follows the viewer's dark mode; `color_scheme: false` leaves it out.
    Visualize.Chart.render(applied, root: true)
    """
  end
end
