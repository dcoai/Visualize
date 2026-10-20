defmodule Examples.Charts.Marathon do
  @moduledoc """
  Grandma's Marathon (#783): an elite field on the point-to-point course from just outside
  Two Harbors, Minnesota, along Lake Superior's North Shore to Canal Park in Duluth, over
  OpenStreetMap's tiles. It replaces the single runner round Central Park (#476) with the
  case that one could not show: **several moving things on one route**, who is ahead, by
  how much, and how the gaps change.

  **The course is traced and the runners are fictional.** `Examples.Charts.Marathon.Course`
  is about a hundred waypoints placed by hand over the basemap from public descriptions of
  the course, densified to some 4,200 fixes. `Examples.Charts.Marathon.Field` is ten made-up
  runners, five men and five women in one field, each with a pace profile. No real
  athlete's name or result appears, and the page shows no race logo or branding.

  Four frames in a box, placed by layout weights (spec/14 §2.8, §4.2), all reading the same
  `runners` rows, so the map and the standings cannot disagree:

  - **`course`**: a `:geo` Mercator frame fitted to the whole course (§4.6), its tiles
    beneath (D-119). It draws the course line, the mile markers (labeled every five miles
    and at the start and finish), and one mark per runner. The color is the runner's,
    through an ordinal scale over every runner's key, so a runner keeps a color whatever
    the order. The division is the mark's shape: a dot for the men, a diamond for the
    women. The legend is keyed by bib and name, and the bib's letter is the division.
  - **`pack`**: the inset, a second `:geo` frame **fitted to the field**. At the whole
    course's zoom the leaders are within a pixel or a few of each other for much of the
    race. The inset's fit reads the stretch of course from the last runner to the leader,
    a little either side, so it follows the field and its projection and its tiles change
    every tick. It fits that stretch rather than the runners' points alone for two
    reasons. The runners all lie on the stretch, and a frame's marks are not clipped to
    its plot (§5.2), so the course line it draws must not reach past the inset. The
    stretch also keeps an extent when every runner stands at the finish.
  - **`clock`**: the race clock, a text over a one-row source.
  - **`standings`**: one bar per runner of the miles covered, in order, the leader on top,
    each labeled with its gap to the leader in time.

  **The race clock is the animation tick.** At rest the view is 1:20:00 into the race, a
  mid-race moment rather than the start line, where every dot would sit on one point.
  Running, each tick is forty seconds of race time from five minutes in, round to 2:40:00,
  after every runner has finished. A runner who has finished stays at the finish.

  The course is over the compile ceiling, so on the Canvas backend it is drawn on the
  canvas, and the basemap's images sit beneath it in the page's backdrop while the
  attribution stays readable over it (spec/14 §12.3, §12.4, D-120).

  **The provider is the host's choice** (spec/14 §5.2). This gallery uses
  OpenStreetMap's standard tiles with the attribution their usage policy requires. That
  policy allows light use such as a demonstration page, and a polling dashboard belongs
  on a provider whose terms allow it. The library emits the URLs and never fetches a tile.
  """

  import Visualize.Chart.Build

  alias Examples.Charts.Design
  alias Examples.Charts.Marathon.{Course, Field}

  @zero_margin %{top: 0, right: 0, bottom: 0, left: 0}

  @tiles %{
    url: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
    attribution: "© OpenStreetMap contributors",
    max_zoom: 19
  }

  # The race clock at rest, and the run's: a tick is forty seconds of race time, from
  # five minutes in round to 2:40:00.
  @at_rest 4_800
  @step 40
  @first 300
  @last 9_600

  # How far either side of the field the inset's stretch of course reaches, in meters.
  @reach 250

  @doc "The size this chart is drawn at when the caller names none (spec/14 §4.2)."
  def size, do: {960, 620}

  def title, do: "Grandma's Marathon"
  def description, do: "An elite field from Two Harbors to Canal Park, Duluth"

  @doc """
  The race clock of a render, in seconds: `#{@at_rest}` at rest, and from the animation
  tick `#{@step}` seconds a tick, from `#{@first}` round to `#{@last}`.
  """
  @spec clock(keyword()) :: integer()
  def clock(opts) do
    case opts[:animation_tick] do
      nil -> @at_rest
      tick -> @first + rem(tick * @step, @last - @first)
    end
  end

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    clock = clock(opts)
    runners = Field.standings(clock)

    design =
      Design.fold(
        List.flatten([
          chart(meta: %{name: title(), description: [description()]}),
          layout(columns: [3, 2], rows: [6, 1, 6], gap: 8),
          source("course", ["lon", "lat"]),
          source("markers", ["lon", "lat", "mile", "label"]),
          source("runners", [
            "bib",
            "runner",
            "division",
            "lon",
            "lat",
            "miles",
            "place",
            "gap"
          ]),
          source("field", ["lon", "lat"]),
          source("field_markers", ["lon", "lat", "mile", "label"]),
          source("clock", ["clock"]),
          style("route", fill: :none, stroke: %{width: 3, opacity: 0.85}, curve: :linear),
          style("marker", fill: :background, stroke: %{color: :text, width: 1}),
          style("tag", extends: :label, font: %{weight: :bold}),
          style("runner", fill: {:field, "runner"}, stroke: %{color: :background, width: 1.5}),
          style("clock", extends: :title),
          in_frame("course", List.flatten(course_frame())),
          in_frame("pack", List.flatten(pack_frame())),
          in_frame("clock", clock_frame()),
          in_frame("standings", standings_frame())
        ])
      )

    {design,
     %{
       "course" => Course.rows(),
       "markers" => Course.markers(),
       "runners" => runners,
       "field" => field(runners),
       "field_markers" => field_markers(runners),
       "clock" => [%{"clock" => Field.duration(clock)}]
     }}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  # The whole course, its markers and the field, fitted to the course.
  defp course_frame do
    [
      geo(
        cell: [0, 0],
        span: [1, 3],
        margin: @zero_margin,
        projection: %{
          type: :mercator,
          fit: %{data: "course", fields: ["lon", "lat"], padding: 24}
        }
      ),
      runner_colors(),
      legend("color", position: :right, title: ["Bib and runner"]),
      line(projection(from("course"), ["lon", "lat"]), %{x: :x, y: :y}, style: "route"),
      circle(projection(from("markers"), ["lon", "lat"]), %{x: :x, y: :y},
        options: %{radius: 2.5},
        style: "marker"
      ),
      circle(
        projection(filter(from("markers"), "label", test: :present), ["lon", "lat"]),
        %{x: :x, y: :y},
        options: %{radius: 3.5},
        style: "marker",
        label: %{text: [{:field, "label"}], anchor: :right, style: "tag"}
      ),
      runner_marks(),
      # The basemap is declared last and drawn first (D-119).
      tiles(nil, %{}, tiles: @tiles)
    ]
  end

  # The inset: the stretch of course the field is on, fitted afresh every tick.
  defp pack_frame do
    [
      geo(
        cell: [1, 0],
        margin: @zero_margin,
        projection: %{
          type: :mercator,
          fit: %{data: "field", fields: ["lon", "lat"], padding: 20}
        }
      ),
      runner_colors(),
      line(projection(from("field"), ["lon", "lat"]), %{x: :x, y: :y}, style: "route"),
      circle(projection(from("field_markers"), ["lon", "lat"]), %{x: :x, y: :y},
        options: %{radius: 3.5},
        style: "marker",
        label: %{text: [{:field, "label"}], anchor: :left, style: "tag"}
      ),
      runner_marks(label: %{text: [{:field, "bib"}], anchor: :right, style: "tag"}),
      tiles(nil, %{}, tiles: @tiles)
    ]
  end

  defp clock_frame do
    [
      cartesian(cell: [1, 1], margin: %{top: 0, right: 8, bottom: 0, left: 8}),
      linear_scale(:x, domain: [0, 1]),
      linear_scale(:y, domain: [0, 1]),
      text(from("clock"), %{x: 0, y: 0.5},
        label: %{text: ["Race clock ", {:field, "clock"}], anchor: :start, style: "clock"}
      )
    ]
  end

  # Miles covered, leader on top: a band `:auto` runs upward, so the rows go in last
  # place first.
  defp standings_frame do
    [
      cartesian(cell: [1, 2], margin: %{top: 8, right: 48, bottom: 28, left: 138}),
      linear_scale(:x, domain: [0, 26.2]),
      band_scale(:y, padding: 0.18),
      runner_colors(),
      axis(:x, :bottom, ticks: 6),
      axis(:y, :left),
      rect(
        sort(from("runners"), "place", order: :descending),
        %{x0: 0, x1: "miles", y0: "runner", y1: "runner"},
        style: "runner",
        options: %{corner_radius: 2},
        label: %{text: [{:field, "gap"}], anchor: :x1}
      )
    ]
  end

  # The runner's color, by key over the whole field, so it never follows the order.
  defp runner_colors, do: ordinal_scale("color", domain: Field.labels())

  # A dot for each man and a diamond for each woman, in the runner's color.
  defp runner_marks(opts \\ []) do
    [
      circle(
        projection(filter(from("runners"), "division", test: :eq, value: "men"), ["lon", "lat"]),
        %{x: :x, y: :y},
        [style: "runner", options: %{radius: 5}] ++ opts
      ),
      symbol(
        projection(filter(from("runners"), "division", test: :eq, value: "women"), [
          "lon",
          "lat"
        ]),
        %{x: :x, y: :y},
        [style: ["runner", %{marker: %{shape: :diamond, size: 90}}]] ++ opts
      )
    ]
  end

  # The stretch of course from the last runner to the leader, `@reach` either side.
  defp field(runners) do
    {lo, hi} = extent(runners)
    Course.stretch(lo - @reach, hi + @reach)
  end

  # The mile markers on that stretch.
  defp field_markers(runners) do
    {lo, hi} = extent(runners)
    mile = Course.mile()

    Course.markers()
    |> Enum.filter(fn %{"mile" => m} -> m * mile >= lo - @reach and m * mile <= hi + @reach end)
    |> Enum.map(&Map.put(&1, "label", inset_label(&1)))
  end

  # Every marker on the stretch is labeled there: the inset is zoomed in enough to read them.
  defp inset_label(%{"label" => label}) when label in ["Start", "Finish"], do: label
  defp inset_label(%{"mile" => mile}), do: "mile #{round(mile)}"

  defp extent(runners) do
    runners
    |> Enum.map(&(&1["miles"] * Course.mile()))
    |> Enum.min_max()
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    tiles = %{
      url: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
      attribution: "© OpenStreetMap contributors"
    }

    # One runner's mark: a dot in the runner's color, through a scale over every key.
    dots = projection(from("runners"), ["lon", "lat"])
    colors = ordinal_scale("color", domain: ["M1 Anders Velk", "W1 Nadia Ferrow"])

    {:ok, design} =
      Visualize.Chart.compose(
        List.flatten([
          chart(meta: %{name: "Grandma's Marathon"}),
          # Frames in a box: the course down the left, the inset and standings beside it.
          layout(columns: [3, 2], rows: [1, 1], gap: 8),
          source("course", ["lon", "lat"]),
          source("runners", ["runner", "lon", "lat", "miles", "place", "gap"]),
          source("field", ["lon", "lat"]),
          style("route", fill: :none, stroke: %{width: 3}),
          style("runner", fill: {:field, "runner"}, stroke: %{color: :background}),
          in_frame("course", [
            # A Mercator projection fitted to the course (spec/14 §4.6).
            geo(cell: [0, 0], span: [1, 2], margin: %{top: 0, right: 0, bottom: 0, left: 0},
              projection: %{type: :mercator, fit: %{data: "course", fields: ["lon", "lat"]}}),
            colors,
            legend("color", position: :bottom_right),
            line(projection(from("course"), ["lon", "lat"]), %{x: :x, y: :y}, style: "route"),
            circle(dots, %{x: :x, y: :y}, options: %{radius: 5}, style: "runner"),
            # Declared last, drawn beneath every other mark (D-119).
            tiles(nil, %{}, tiles: tiles)
          ]),
          in_frame("pack", [
            # The inset follows the field: its fit reads the stretch of course the runners
            # are on, which the host recomputes every tick, so its tiles move with it.
            geo(cell: [1, 0], margin: %{top: 0, right: 0, bottom: 0, left: 0},
              projection: %{type: :mercator, fit: %{data: "field", fields: ["lon", "lat"], padding: 20}}),
            colors,
            line(projection(from("field"), ["lon", "lat"]), %{x: :x, y: :y}, style: "route"),
            circle(dots, %{x: :x, y: :y}, options: %{radius: 5}, style: "runner"),
            tiles(nil, %{}, tiles: tiles)
          ]),
          in_frame("standings", [
            cartesian(cell: [1, 1], margin: %{top: 8, right: 48, bottom: 28, left: 138}),
            linear_scale(:x, domain: [0, 26.2]),
            band_scale(:y, padding: 0.18),
            colors,
            axis(:x, :bottom),
            axis(:y, :left),
            # The same rows as the map, last place first so the leader is on top.
            rect(sort(from("runners"), "place", order: :descending),
              %{x0: 0, x1: "miles", y0: "runner", y1: "runner"},
              style: "runner", label: %{text: [{:field, "gap"}], anchor: :x1})
          ])
        ])
      )

    # course: about 4,200 %{"lon", "lat"} fixes; runners: one row per runner at the race
    # clock, leader first; field: the stretch of course from the last runner to the leader.
    {:ok, applied} =
      Visualize.Chart.apply(design,
        sources: %{"course" => course, "runners" => runners, "field" => field}
      )

    Visualize.Chart.render(applied)
    """
  end
end
