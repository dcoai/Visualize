defmodule Examples.Charts.GpsTrack do
  @moduledoc """
  A GPS track over a basemap (#476): a run once round Central Park, New York, drawn over
  OpenStreetMap's tiles through a `:geo` frame's Mercator projection fitted to the track.

  Three marks: the track as a `:line`, a runner's dot as a `:circle`, and the `:tiles`
  basemap, declared last and drawn first all the same, since tiles go beneath every other
  mark by type (spec/14 §5.2, D-119). The projection's `fit` reads the track (§4.6), so
  the view and the tiles follow the data and the basemap is a dynamic region.

  The track is about 2,400 fixes, one a second at a runner's pace. That is far over the
  compile ceiling, so on the Canvas backend it is drawn on the canvas, and the basemap's
  images sit beneath it in the page's backdrop while the attribution stays readable over
  it (spec/14 §12.3, §12.4, D-120).

  **The track is generated, not recorded.** It follows the four streets that bound the
  park, from Columbus Circle east along Central Park South, north up Fifth Avenue, west
  along Central Park North and south down Central Park West. The streets are straight on
  the Manhattan grid, so a corner-to-corner line with a few meters of deterministic
  jitter for GPS noise sits on them, carries no one's location and needs no license.

  **The provider is the host's choice** (spec/14 §5.2). This gallery uses
  OpenStreetMap's standard tiles with the attribution their usage policy requires. That
  policy allows light use such as a demonstration page, and a polling dashboard belongs
  on a provider whose terms allow it. The library emits the URLs and never fetches a tile.
  """

  import Visualize.Chart.Build

  alias Examples.Charts.Design

  @zero_margin %{top: 0, right: 0, bottom: 0, left: 0}

  @tiles %{
    url: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
    attribution: "© OpenStreetMap contributors",
    max_zoom: 19
  }

  # The park's bounding streets meet at these corners, `{lon, lat}`: Columbus Circle,
  # Fifth Avenue at 59th Street, Fifth Avenue at 110th Street (Duke Ellington Circle) and
  # Central Park West at 110th Street (Frederick Douglass Circle).
  @corners [
    {-73.98189, 40.76808},
    {-73.97300, 40.76437},
    {-73.94930, 40.79686},
    {-73.95818, 40.80045}
  ]

  # One fix a second at about 4 m/s round a loop of about 9.9 km.
  @fixes 2_400

  # Meters per degree of latitude, and of longitude at the park's latitude.
  @m_per_lat 111_320.0
  @m_per_lon 111_320.0 * :math.cos(40.78 * :math.pi() / 180)

  @track (fn ->
            corners = @corners
            legs = Enum.zip(corners, tl(corners) ++ [hd(corners)])

            meters = fn {{lon0, lat0}, {lon1, lat1}} ->
              :math.sqrt(
                :math.pow((lon1 - lon0) * @m_per_lon, 2) +
                  :math.pow((lat1 - lat0) * @m_per_lat, 2)
              )
            end

            lengths = Enum.map(legs, meters)
            total = Enum.sum(lengths)
            starts = Enum.scan([0.0 | lengths], &(&1 + &2)) |> Enum.drop(-1)

            for i <- 0..(@fixes - 1) do
              along = total * i / @fixes

              {{{lon0, lat0}, {lon1, lat1}}, start, length} =
                Enum.zip([legs, starts, lengths])
                |> Enum.filter(fn {_leg, s, _l} -> s <= along end)
                |> List.last()

              f = (along - start) / length
              # A few meters of GPS noise, the same on every compilation.
              east = 2.2 * :math.sin(i * 0.37) + 1.1 * :math.sin(i * 0.113 + 1.0)
              north = 2.0 * :math.sin(i * 0.29 + 2.0) + 1.0 * :math.sin(i * 0.071)

              %{
                lon: Float.round(lon0 + (lon1 - lon0) * f + east / @m_per_lon, 6),
                lat: Float.round(lat0 + (lat1 - lat0) * f + north / @m_per_lat, 6)
              }
            end
          end).()

  @doc "The size this chart is drawn at when the caller names none (spec/14 §4.2)."
  def size, do: {700, 500}

  def title, do: "GPS Track"
  def description, do: "A run round Central Park over OpenStreetMap tiles"

  @doc "The track's fixes, `%{lon, lat}` in order: the loop the design binds."
  def track, do: @track

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        source(:track, [:lon, :lat]),
        source(:runner, [:lon, :lat]),
        style(:route, fill: :none, stroke_width: 3, stroke_opacity: 0.9, curve: :linear),
        style(:runner, stroke: :background, stroke_width: 2),
        geo(
          margin: @zero_margin,
          projection: %{
            type: :mercator,
            fit: %{data: :track, fields: [:lon, :lat], padding: 24}
          }
        ),
        # The basemap is declared last and drawn first (D-119).
        line(projection(from(:track), [:lon, :lat]), %{x: :x, y: :y}, style: :route),
        circle(projection(from(:runner), [:lon, :lat]), %{x: :x, y: :y, value: 6},
          style: :runner
        ),
        tiles(nil, %{}, tiles: @tiles)
      ])

    {design, %{track: @track, runner: [runner(opts[:animation_tick])]}}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  # The runner's fix: the start at rest, forty seconds on per animation tick.
  defp runner(nil), do: hd(@track)
  defp runner(tick), do: Enum.at(@track, rem(tick * 40, @fixes))

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "GPS Track"}),
        source(:track, [:lon, :lat]),
        source(:runner, [:lon, :lat]),
        style(:route, fill: :none, stroke_width: 3, stroke_opacity: 0.9, curve: :linear),
        style(:runner, stroke: :background, stroke_width: 2),
        # A Mercator projection fitted to the track (spec/14 §4.6): the view and the
        # tiles follow the data.
        geo(margin: %{top: 0, right: 0, bottom: 0, left: 0},
          projection: %{type: :mercator, fit: %{data: :track, fields: [:lon, :lat], padding: 24}}),
        line(projection(from(:track), [:lon, :lat]), %{x: :x, y: :y}, style: :route),
        circle(projection(from(:runner), [:lon, :lat]), %{x: :x, y: :y, value: 6}, style: :runner),
        # The basemap: declared last, drawn beneath every other mark (D-119). The
        # provider and its terms are the host's; the library never fetches a tile.
        tiles(nil, %{},
          tiles: %{
            url: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
            attribution: "© OpenStreetMap contributors"
          }
        )
      ])

    # track: about 2,400 %{lon, lat} fixes; runner: the one fix the dot is at.
    {:ok, applied} = Visualize.Chart.apply(design, sources: %{track: track, runner: [runner]})
    Visualize.Chart.render(applied)
    """
  end
end
