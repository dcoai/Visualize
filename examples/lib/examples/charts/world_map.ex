defmodule Examples.Charts.WorldMap do
  @moduledoc """
  World map as a design (#129): a `:geo` frame whose projection is the Natural Earth, and
  four `:path` marks over the `:projection` step — the ocean, the graticule, the land and
  the rim.

  The projection is the frame's (spec/14 §4.6) and every mark's data pipeline ends in a
  `:projection` step over a geometry column (§5.4.4, #349): the ocean and the rim are the
  `Sphere`, the projection's own outline, filled under everything and stroked over it; the
  graticule is one `LineString` per meridian and parallel, the equator and the prime
  meridian heavier through style keys bound to the row; the land is one feature per land
  mass of Natural Earth's 1:110m land (#499), coloured by its id through the `color`
  scale. The hand-written version clipped the map to an ellipse it drew by hand — a
  pseudo-cylindrical projection ends at the antimeridian, so the design clips nothing.
  The animation turns the projection's `rotate` the way the Earth turns (#523): the land
  drifts east and the centre meridian moves west, as on the Globe. `rotate`'s `lambda` is
  the centre meridian (spec/07 §1.4, D-44), so it falls as the ticks rise.

  Its ocean is the theme's `:surface` (#422), the plane the data is laid on: not the page
  (`:background` would make it vanish), not a data colour (the land reads through the
  series), and distinct from the `:grid` that strokes the graticule over it — so the map
  follows the palette and the gallery names no absolute colour (#421).
  """

  import Visualize.Chart.Build

  alias Examples.Charts.{Design, WorldGeography}

  @zero_margin %{top: 0, right: 0, bottom: 0, left: 0}
  @doc "The size this chart is drawn at when the caller names none (spec/14 §4.2)."
  def size, do: {700, 400}

  def title, do: "World Map"
  def description, do: "Natural Earth projection with graticule; land from Natural Earth 1:110m"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    {width, _height} = Design.size(__MODULE__, opts)
    lon = if tick = opts[:animation_tick], do: -rem(tick * 2, 360), else: 0

    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        source(:globe, [:shape]),
        source(:graticule, [:kind, :degree, :shape, :weight, :opacity]),
        source(:land, [:name, :shape]),
        style(:ocean, fill: :surface, stroke: :none),
        style(:rim, fill: :none, stroke: :axis, stroke_width: 1.5),
        style(:graticule,
          fill: :none,
          stroke: :grid,
          stroke_width: {:field, :weight},
          stroke_opacity: {:field, :opacity}
        ),
        style(:land,
          fill: {:field, :name},
          fill_opacity: 0.8,
          stroke: :background,
          stroke_width: 0.5
        ),
        geo(
          margin: @zero_margin,
          projection: %{type: :natural_earth, scale: width / 5.5, rotate: [lon, 0, 0]}
        ),
        ordinal_scale(:color),
        # The sphere under everything, the lines, the land, and the sphere's rim over all.
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

  # Every thirty degrees; the equator and the prime meridian heavier.
  defp graticule do
    for line <- WorldGeography.graticule(30) do
      Map.merge(
        line,
        if(line.degree == 0, do: %{weight: 1, opacity: 0.8}, else: %{weight: 0.5, opacity: 0.5})
      )
    end
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "World Map"}),
        source(:globe, [:shape]),
        source(:graticule, [:kind, :degree, :shape, :weight, :opacity]),
        source(:land, [:name, :shape]),
        style(:ocean, fill: :surface, stroke: :none),
        style(:rim, fill: :none, stroke: :axis, stroke_width: 1.5),
        style(:graticule, fill: :none, stroke: :grid,
          stroke_width: {:field, :weight}, stroke_opacity: {:field, :opacity}),
        style(:land, fill: {:field, :name}, fill_opacity: 0.8, stroke: :background, stroke_width: 0.5),
        # The projection is the frame's (spec/14 §4.6).
        geo(margin: %{top: 0, right: 0, bottom: 0, left: 0},
          projection: %{type: :natural_earth, scale: 700 / 5.5}),
        ordinal_scale(:color),
        # Each mark ends in a :projection step over its rows' geometry (§5.4.4): the
        # Sphere is the projection's outline, a LineString a graticule line, a feature a
        # land mass.
        path(projection(from(:globe), nil, field: :shape), %{path: :path}, style: :ocean),
        path(projection(from(:graticule), nil, field: :shape), %{path: :path}, style: :graticule),
        path(projection(from(:land), nil, field: :shape), %{path: :path}, style: :land),
        path(projection(from(:globe), nil, field: :shape), %{path: :path}, style: :rim)
      ])

    # globe: [%{shape: %{"type" => "Sphere"}}]; graticule and land: rows with GeoJSON
    # under :shape (Examples.Charts.WorldGeography.graticule/1 and land/0). The land is
    # Natural Earth's 1:110m land (naturalearthdata.com, public domain), one row per land mass.
    {:ok, applied} = Visualize.Chart.apply(design, sources: %{globe: globe, graticule: graticule, land: land})
    Visualize.Chart.render(applied)
    """
  end
end
