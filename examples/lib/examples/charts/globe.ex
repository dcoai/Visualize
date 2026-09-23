defmodule Examples.Charts.Globe do
  @moduledoc """
  Globe as a design (#129): a `:geo` frame whose projection is the orthographic, and four
  `:path` marks over the `:projection` step — the ocean, the graticule, the land and the
  rim — as the world map's, with the globe's own projection.

  The orthographic clips the far hemisphere itself (spec/07 §1.5), so the `Sphere` is the
  visible disc and the land and the graticule end at its edge with no `clipPath` (§5.4.4,
  #349). The animation turns the projection's `rotate` — the globe spinning east with a
  slow nod — where the hand-written version rebuilt the projection each frame. Its dark
  page background and the highlight it painted on the glass are not the chart's.

  Its ocean is the one absolute colour left in the gallery (#421): a map's ocean is a
  backdrop the theme has no slot for — `:grid` is the graticule's own stroke and
  `:background` would make it vanish — so it keeps `#a8d5e5` until #422 gives a theme
  the word for a surface.
  """

  import Visualize.Chart.Build

  alias Examples.Charts.{Design, WorldGeography}

  @zero_margin %{top: 0, right: 0, bottom: 0, left: 0}
  @ocean "#a8d5e5"

  def title, do: "Globe"
  def description, do: "Rotating orthographic projection"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    width = opts[:width] || 500
    height = opts[:height] || 450
    radius = min(width, height) / 2 - 20

    {lon, lat} =
      case opts[:animation_tick] do
        nil -> {0, -20}
        tick -> {-rem(tick * 2, 360), -15 * :math.sin(tick * 0.03)}
      end

    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        source(:globe, [:shape]),
        source(:graticule, [:kind, :degree, :shape, :weight, :opacity]),
        source(:land, [:name, :shape]),
        style(:ocean, fill: @ocean, stroke: :none),
        style(:rim, fill: :none, stroke: :axis, stroke_width: 1.5),
        style(:graticule,
          fill: :none,
          stroke: :background,
          stroke_width: {:field, :weight},
          stroke_opacity: {:field, :opacity}
        ),
        style(:land,
          fill: {:field, :name},
          fill_opacity: 0.9,
          stroke: :background,
          stroke_width: 0.5
        ),
        geo(width, height,
          margin: @zero_margin,
          projection: %{type: :orthographic, scale: radius, rotate: [lon, lat, 0]}
        ),
        ordinal_scale(:color),
        # The visible disc under everything, the lines, the land, and its rim over all.
        path(projection(from(:globe), nil, field: :shape), %{path: :path}, style: :ocean),
        path(projection(from(:graticule), nil, field: :shape), %{path: :path}, style: :graticule),
        path(projection(from(:land), nil, field: :shape), %{path: :path}, style: :land),
        path(projection(from(:globe), nil, field: :shape), %{path: :path}, style: :rim)
      ])

    {design,
     %{
       globe: [%{shape: %{"type" => "Sphere"}}],
       graticule: graticule(),
       land: WorldGeography.land()
     }}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  # Every thirty degrees, faint on the water; the equator and the prime meridian heavier.
  defp graticule do
    for line <- WorldGeography.graticule(30) do
      Map.merge(
        line,
        if(line.degree == 0, do: %{weight: 0.8, opacity: 0.6}, else: %{weight: 0.3, opacity: 0.4})
      )
    end
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Globe"}),
        source(:globe, [:shape]),
        source(:graticule, [:kind, :degree, :shape, :weight, :opacity]),
        source(:land, [:name, :shape]),
        style(:ocean, fill: "#a8d5e5", stroke: :none),
        style(:rim, fill: :none, stroke: :axis, stroke_width: 1.5),
        style(:graticule, fill: :none, stroke: :background,
          stroke_width: {:field, :weight}, stroke_opacity: {:field, :opacity}),
        style(:land, fill: {:field, :name}, fill_opacity: 0.9, stroke: :background, stroke_width: 0.5),
        # The orthographic clips the far hemisphere itself; rotate turns the globe.
        geo(500, 450, margin: %{top: 0, right: 0, bottom: 0, left: 0},
          projection: %{type: :orthographic, scale: 205, rotate: [0, -20, 0]}),
        ordinal_scale(:color),
        # The Sphere is the visible disc; each other mark ends in a :projection step over
        # its rows' geometry (spec/14 §5.4.4).
        path(projection(from(:globe), nil, field: :shape), %{path: :path}, style: :ocean),
        path(projection(from(:graticule), nil, field: :shape), %{path: :path}, style: :graticule),
        path(projection(from(:land), nil, field: :shape), %{path: :path}, style: :land),
        path(projection(from(:globe), nil, field: :shape), %{path: :path}, style: :rim)
      ])

    {:ok, applied} = Visualize.Chart.apply(design, sources: %{globe: globe, graticule: graticule, land: land})
    Visualize.Chart.render(applied)
    """
  end
end
