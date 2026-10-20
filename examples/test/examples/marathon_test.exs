defmodule Examples.MarathonTest do
  @moduledoc """
  *Grandma's Marathon* (#783, #819): the traced course is 26.2 miles, every runner's
  position is monotonic in race time and reaches the finish at its target, the view at
  rest is mid-race with the standings in order of distance, and the pack inset's fit
  follows the field from tick to tick.
  """
  use ExUnit.Case, async: true

  alias Examples.Charts.{Design, Marathon}
  alias Examples.Charts.Marathon.{Course, Field}

  @mile 1609.344

  # The haversine distance, written here rather than read from the module, so the length
  # is measured independently of how the course was densified.
  defp meters({lon0, lat0}, {lon1, lat1}) do
    rad = :math.pi() / 180
    dlat = (lat1 - lat0) * rad
    dlon = (lon1 - lon0) * rad

    a =
      :math.pow(:math.sin(dlat / 2), 2) +
        :math.cos(lat0 * rad) * :math.cos(lat1 * rad) * :math.pow(:math.sin(dlon / 2), 2)

    2 * 6_371_008.8 * :math.asin(:math.sqrt(a))
  end

  defp polyline_miles(rows) do
    points = Enum.map(rows, &{&1["lon"], &1["lat"]})

    points
    |> Enum.zip(tl(points))
    |> Enum.map(fn {a, b} -> meters(a, b) end)
    |> Enum.sum()
    |> Kernel./(@mile)
  end

  describe "the course" do
    test "is 26.2 miles within 1%, by the polyline's cumulative distance" do
      miles = polyline_miles(Course.rows())
      assert abs(miles - 26.2) / 26.2 < 0.01, "#{miles} miles"
    end

    test "is hand-placed waypoints densified to a fix about every ten meters" do
      assert length(Course.waypoints()) in 60..120
      rows = Course.rows()
      assert length(rows) in 4_000..4_500
      assert hd(rows) == %{"lon" => -91.7101, "lat" => 47.00719}
      assert List.last(rows) == %{"lon" => -92.0938, "lat" => 46.781}

      points = Enum.map(rows, &{&1["lon"], &1["lat"]})
      steps = points |> Enum.zip(tl(points)) |> Enum.map(fn {a, b} -> meters(a, b) end)
      assert Enum.max(steps) <= 10.5
    end

    test "runs from Two Harbors southwest to Canal Park, by the Aerial Lift Bridge" do
      {lon0, lat0} = hd(Course.waypoints())
      {lon1, lat1} = List.last(Course.waypoints())
      assert lon0 > lon1 and lat0 > lat1
      # The finish is within 250 m of the bridge (46.7790, -92.0929).
      assert meters({lon1, lat1}, {-92.0929, 46.7790}) < 250
    end

    test "has a marker at every mile, labeled every five and at the start and finish" do
      markers = Course.markers()
      assert length(markers) == 28
      assert Enum.map(markers, & &1["mile"]) == [0.0 | Enum.map(1..26, &(&1 * 1.0))] ++ [26.2]

      assert for(%{"label" => label} <- markers, label, do: label) ==
               ["Start", "5", "10", "15", "20", "25", "Finish"]

      # Each marker sits at its distance along the course.
      for %{"mile" => mile, "lon" => lon, "lat" => lat} <- markers, mile in [5.0, 13.0, 21.0] do
        {x, y} = Course.at(mile * @mile)
        assert_in_delta x, lon, 1.0e-6
        assert_in_delta y, lat, 1.0e-6
      end
    end
  end

  describe "the field" do
    test "is ten fictional runners, five in each division, finishing between 2:10 and 2:35" do
      runners = Field.runners()
      assert length(runners) == 10
      assert Enum.frequencies_by(runners, & &1.division) == %{"men" => 5, "women" => 5}
      assert Enum.all?(runners, &(&1.finish >= 7_800 and &1.finish <= 9_300))

      # Made-up names: this list is the whole field, so a change to it is a change here.
      assert Enum.map(runners, & &1.name) == [
               "Anders Velk",
               "Kofi Brannagh",
               "Mateo Strandquist",
               "Daniel Ostrowe",
               "Jonah Kettering",
               "Nadia Ferrow",
               "Lena Marsk",
               "Priya Calloway",
               "Ilse Varrow",
               "Ruth Halvard"
             ]

      # Some fade and some run a negative split.
      assert Enum.any?(runners, &(&1.split > 0)) and Enum.any?(runners, &(&1.split < 0))
    end

    test "each runner's distance is monotonic in race time, reaches the finish at the target and stays" do
      length = Course.length()

      for runner <- Field.runners() do
        distances = for clock <- 0..(runner.finish + 600)//7, do: Field.meters(runner, clock)
        assert distances == Enum.sort(distances), runner.bib
        assert Field.meters(runner, 0) == 0.0
        assert Field.meters(runner, runner.finish - 30) < length
        assert Field.meters(runner, runner.finish) == length
        assert Field.meters(runner, runner.finish + 3_600) == length
      end
    end

    test "every runner slows on Lemon Drop Hill" do
      {from, to} = Field.hill()

      for runner <- Field.runners() do
        on_hill = pace(runner, from * @mile, to * @mile)
        before = pace(runner, (from - 0.6) * @mile, from * @mile)
        assert on_hill > before, runner.bib
      end
    end

    test "the gap to the leader is time behind the leader at the same point" do
      [leader, second | _] = Field.standings(4_800)
      assert leader["gap"] == "leader"
      runner = Enum.find(Field.runners(), &(&1.bib == second["bib"]))
      lead = Enum.find(Field.runners(), &(&1.bib == leader["bib"]))
      behind = 4_800 - Field.clock_at(lead, Field.meters(runner, 4_800))
      assert second["gap"] == "+" <> Field.duration(behind)
    end
  end

  # Seconds a mile between two points of the course.
  defp pace(runner, from, to),
    do: (Field.clock_at(runner, to) - Field.clock_at(runner, from)) / ((to - from) / @mile)

  describe "the view" do
    test "at rest is a mid-race moment, the standings in order of distance" do
      assert Marathon.clock([]) == 4_800
      {_design, sources} = Marathon.design([])
      runners = sources["runners"]

      miles = Enum.map(runners, & &1["miles"])
      assert miles == Enum.sort(miles, :desc)
      assert Enum.map(runners, & &1["place"]) == Enum.to_list(1..10)
      # Nobody is still at the start, and nobody has finished.
      assert Enum.all?(miles, &(&1 > 5 and &1 < 26))
      refute Enum.any?(runners, & &1["finished"])

      # The standings' band reads them last place first, so the leader is on top.
      applied = Design.applied(Marathon, [])

      assert applied.frames["standings"].scales["y"].domain ==
               Enum.reverse(Enum.map(runners, & &1["runner"]))
    end

    test "a runner keeps its color whatever the order" do
      applied = Design.applied(Marathon, [])

      for frame <- ["course", "pack", "standings"] do
        assert applied.frames[frame].scales["color"].domain == Field.labels()
      end
    end

    test "the pack inset's fit follows the field, and its tiles with it; the course's does not move" do
      [a, b] = for tick <- [40, 41], do: Design.applied(Marathon, animation_tick: tick)

      refute projection(a, "pack") == projection(b, "pack")
      assert projection(a, "course") == projection(b, "course")

      [svg_a, svg_b] = for tick <- [40, 41], do: Marathon.render(animation_tick: tick)
      refute tiles(svg_a, "pack") == tiles(svg_b, "pack")
    end

    test "the inset fits the runners themselves, every one inside its padding (#828)" do
      for tick <- [0, 40, 120, 180] do
        {_design, sources} = Marathon.design(animation_tick: tick)
        assert Map.keys(sources) |> Enum.sort() == ["clock", "course", "markers", "runners"]
        pack = Design.applied(Marathon, animation_tick: tick).frames["pack"]
        %{width: w, height: h} = pack.plot

        points =
          for r <- sources["runners"],
              do: Visualize.Geo.Projection.project(pack.projection, r["lon"], r["lat"])

        # Inside the 32 px padding, and touching it on the tighter axis unless the span binds.
        assert Enum.all?(points, fn {x, y} ->
                 x >= 32 - 1.0e-6 and x <= w - 32 + 1.0e-6 and y >= 32 - 1.0e-6 and
                   y <= h - 32 + 1.0e-6
               end),
               "tick #{tick}"
      end
    end

    test "the inset keeps an extent of at least 500 m when everyone stands at the finish" do
      {_design, sources} = Marathon.design(animation_tick: 230)
      assert Enum.all?(sources["runners"], & &1["finished"])
      pack = Design.applied(Marathon, animation_tick: 230).frames["pack"]
      %{width: w, height: h} = pack.plot
      {_, top} = Visualize.Geo.Projection.invert(pack.projection, w / 2, 32)
      {_, bottom} = Visualize.Geo.Projection.invert(pack.projection, w / 2, h - 32)
      assert_in_delta meters({0, top}, {0, bottom}), 500, 2
    end

    test "the inset draws the whole course and every marker, clipped to its plot (D-212)" do
      svg = Marathon.render(animation_tick: 120)
      [_, pack] = String.split(svg, ~s(class="frame frame-pack"), parts: 2)
      [pack | _] = String.split(pack, ~s(class="frame frame-), parts: 2)

      for class <- ["mark mark-line", "mark mark-circle", "mark mark-symbol"] do
        assert pack =~ ~r{<g class="#{class}"[^>]* clip-path="url\(#vis-clip-}, class
      end

      # Every marker is drawn, the off-plot ones clipped, each with its inset label.
      assert length(Regex.scan(~r{>mile \d+<}, pack)) == 26
      # The course frame clips nothing but its tiles.
      [_, course] = String.split(svg, ~s(class="frame frame-course"), parts: 2)
      [course | _] = String.split(course, ~s(class="frame frame-), parts: 2)
      assert length(Regex.scan(~r{clip-path=}, course)) == 1
    end

    test "the animation runs the clock forward from five minutes in, round to 2:40:00" do
      assert Marathon.clock(animation_tick: 0) == 300
      assert Marathon.clock(animation_tick: 1) == 340
      assert Enum.max(for t <- 0..400, do: Marathon.clock(animation_tick: t)) < 9_600

      # Past the last finish, every runner stands at the finish.
      {_design, sources} = Marathon.design(animation_tick: 230)
      assert Enum.all?(sources["runners"], & &1["finished"])
      assert Enum.all?(sources["runners"], &(&1["miles"] == Float.round(Course.miles(), 2)))
    end
  end

  describe "the basemaps stay inside their frames (#826, D-209)" do
    test "each fitted frame's tiles are clipped to that frame's plot" do
      applied = Design.applied(Marathon, [])
      svg = Marathon.render([])

      for frame <- ["course", "pack"] do
        %{width: w, height: h} = applied.frames[frame].plot
        [_, group] = String.split(svg, ~s(class="frame frame-#{frame}"), parts: 2)

        [id] =
          Regex.run(~r{<g class="mark mark-tiles" clip-path="url\(#([^)]+)\)"}, group,
            capture: :all_but_first
          )

        [rect] = Regex.run(~r{<clipPath id="#{id}"><rect [^>]*>}, group)
        assert rect =~ ~s(width="#{w / 1}") or rect =~ ~s(width="#{trunc(w)}")
        assert rect =~ ~s(height="#{h / 1}") or rect =~ ~s(height="#{trunc(h)}")
      end
    end
  end

  defp projection(applied, frame) do
    projection = applied.frames[frame].projection
    {projection.scale, projection.translate}
  end

  # The first tile a frame draws: its URL and where it is placed.
  defp tiles(svg, frame) do
    [_, group] = String.split(svg, ~s(class="frame frame-#{frame}"), parts: 2)
    [image] = Regex.run(~r{<image [^>]*>}, group)
    image
  end
end
