defmodule Examples.Charts.ColorsChart do
  @moduledoc """
  Colors as values (spec/08 §1.9, spec/14 §3.2, #705): every color the chart draws is a
  **typed color** — a name of the theme's color table, `color(:blue)`, or a transform of
  one — resolved through the theme at render, so the palette switch above the chart
  recolors every swatch, the derived ones included.

  Two frames on one layout (spec/14 §2.8):

  - **Transforms.** One tile per row, its style named by the row (`style: {:field, :look}`,
    §3.6), each style a fill of one color value: a name, `intensity/2`, `lighten/2`,
    `darken/2`, `blend/1` of two names and of two weighted ones, a role, a ramp position and
    a CSS name. The tile's text is `contrast()` (§3.2), the ink chosen per tile against the
    color it sits on — dark on a pale tile, light on a dark one, in one style.
  - **Shades.** `shade(color(:red), n)` from 0 to 1000 (spec/08 §1.9), 500 being the name
    itself, each step labeled in its own contrast ink.

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
  # style that fills its tile with that color.
  @transforms [
    {"color(:blue)", :plain},
    {"color(:blue) |> intensity(0.5)", :faint},
    {"color(:blue) |> lighten(0.4)", :light},
    {"color(:blue) |> darken(0.4)", :dark},
    {"blend([color(:blue), color(:red)])", :mixed},
    {"blend([…0.65, …0.3]) |> alpha(0.65)", :weighted},
    {"color(:bad)", :role},
    {"ramp(:thermal, 0.8)", :thermal},
    {"color(:steelblue)", :css}
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
          source(:transforms, [:expr, :look]),
          source(:shades, [:step, :look]),

          # One style per color value: a fill, and nothing else.
          style(:plain, fill: color(:blue)),
          style(:faint, fill: color(:blue) |> intensity(0.5)),
          style(:light, fill: color(:blue) |> lighten(0.4)),
          style(:dark, fill: color(:blue) |> darken(0.4)),
          style(:mixed, fill: blend([color(:blue), color(:red)])),
          style(:weighted,
            fill:
              blend([color(:blue) |> intensity(0.65), color(:red) |> intensity(0.3)])
              |> alpha(0.65)
          ),
          style(:role, fill: color(:bad)),
          style(:thermal, fill: ramp(:thermal, 0.8)),
          style(:css, fill: color(:steelblue)),
          # A style per step of the red scale, `shade_0` … `shade_1000`.
          Enum.map(@steps, &style(:"shade_#{&1}", fill: shade(color(:red), &1))),

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
            axis(:y, :left),
            rect(:transforms, %{y0: :expr, y1: :expr, x0: 0, x1: 1},
              style: {:field, :look},
              label: %{text: ["Aa · contrast()"], anchor: :middle, style: :ink}
            ),
            label(:subtitle, ["Transforms of the theme's names"], style: :heading)
          ]),
          in_frame(:shades, [
            cartesian(cell: [0, 1], margin: %{top: 28, right: 20, bottom: 8, left: 20}),
            band_scale(:x, padding: 0.06),
            linear_scale(:y, domain: [0, 1]),
            rect(:shades, %{x0: :step, x1: :step, y0: 0, y1: 1},
              style: {:field, :look},
              label: %{text: [{:field, :step}], anchor: :middle, style: :ink}
            ),
            label(:subtitle, ["shade(color(:red), n), from 0 to 1000"], style: :heading)
          ])
        ])
      )

    {design, %{transforms: transform_rows(), shades: shade_rows(opts[:animation_tick] || 0)}}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  defp transform_rows, do: for({expr, look} <- @transforms, do: %{expr: expr, look: look})

  # The strip's steps in order; an animation tick turns the strip by a step per tick, so a
  # run walks the scale through the band.
  defp shade_rows(tick) do
    for i <- 0..10 do
      n = rem(i + tick, 11) * 100
      %{step: Integer.to_string(n), look: :"shade_#{n}"}
    end
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build
    import Visualize.Color

    # A color is a value: a name of the theme's table, or a transform of one, resolved
    # through the theme at render. Each row's tile is filled by the style its `look`
    # names, and its text is the contrast ink, chosen per tile.
    transforms = [
      %{expr: "color(:blue)", look: :plain},
      %{expr: "color(:blue) |> intensity(0.5)", look: :faint},
      %{expr: "color(:blue) |> lighten(0.4)", look: :light},
      %{expr: "color(:blue) |> darken(0.4)", look: :dark},
      %{expr: "blend([color(:blue), color(:red)])", look: :mixed},
      %{expr: "blend([…0.65, …0.3]) |> alpha(0.65)", look: :weighted},
      %{expr: "color(:bad)", look: :role},
      %{expr: "ramp(:thermal, 0.8)", look: :thermal},
      %{expr: "color(:steelblue)", look: :css}
    ]

    steps = Enum.to_list(0..1000//100)
    shades = for n <- steps, do: %{step: "#{n}", look: :"shade_#{n}"}

    {:ok, design} =
      Visualize.Chart.compose(
        List.flatten([
          chart(meta: %{name: "Colors"}),
          layout(rows: [3, 1], gap: 16),
          source(:transforms, [:expr, :look]),
          source(:shades, [:step, :look]),
          style(:plain, fill: color(:blue)),
          style(:faint, fill: color(:blue) |> intensity(0.5)),
          style(:light, fill: color(:blue) |> lighten(0.4)),
          style(:dark, fill: color(:blue) |> darken(0.4)),
          style(:mixed, fill: blend([color(:blue), color(:red)])),
          style(:weighted,
            fill:
              blend([color(:blue) |> intensity(0.65), color(:red) |> intensity(0.3)])
              |> alpha(0.65)
          ),
          style(:role, fill: color(:bad)),
          style(:thermal, fill: ramp(:thermal, 0.8)),
          style(:css, fill: color(:steelblue)),
          Enum.map(steps, &style(:"shade_#{&1}", fill: shade(color(:red), &1))),
          style(:ink, extends: :label, fill: contrast(), font: %{weight: :bold}),
          style(:heading, extends: :title, font: %{size: 13}),
          in_frame(:transforms, [
            cartesian(cell: [0, 0], margin: %{top: 28, right: 20, bottom: 8, left: 250}),
            # A band runs up the y axis, so the domain lists the rows bottom first.
            band_scale(:y, domain: Enum.reverse(Enum.map(transforms, & &1.expr)), padding: 0.12),
            linear_scale(:x, domain: [0, 1]),
            axis(:y, :left),
            rect(:transforms, %{y0: :expr, y1: :expr, x0: 0, x1: 1},
              style: {:field, :look},
              label: %{text: ["Aa · contrast()"], anchor: :middle, style: :ink}
            ),
            label(:subtitle, ["Transforms of the theme's names"], style: :heading)
          ]),
          in_frame(:shades, [
            cartesian(cell: [0, 1], margin: %{top: 28, right: 20, bottom: 8, left: 20}),
            band_scale(:x, padding: 0.06),
            linear_scale(:y, domain: [0, 1]),
            rect(:shades, %{x0: :step, x1: :step, y0: 0, y1: 1},
              style: {:field, :look},
              label: %{text: [{:field, :step}], anchor: :middle, style: :ink}
            ),
            label(:subtitle, ["shade(color(:red), n), from 0 to 1000"], style: :heading)
          ])
        ])
      )

    {:ok, applied} = Visualize.Chart.apply(design, sources: %{transforms: transforms, shades: shades})
    Visualize.Chart.render(applied)

    # No theme named: drawn as a document (`root: true`), the root carries a rule that
    # follows the viewer's dark mode; `color_scheme: false` leaves it out.
    Visualize.Chart.render(applied, root: true)
    """
  end
end
