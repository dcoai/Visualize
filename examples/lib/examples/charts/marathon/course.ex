defmodule Examples.Charts.Marathon.Course do
  @moduledoc """
  The course of `Examples.Charts.Marathon` (#783): Grandma's Marathon, point to point from
  just outside Two Harbors, Minnesota, along Lake Superior's North Shore to Canal Park in
  Duluth.

  **The course is traced, not imported.** The waypoints below were placed by hand over
  OpenStreetMap's rendered tiles, read against public descriptions of the course: the
  start on Scenic 61 just outside Two Harbors, Knife River near mile 5, the Lester River
  near mile 19, London Road through Lakeside with Lemon Drop Hill near mile 22, Superior
  Street downtown, the Depot near mile 25.1, the aquarium and the *Irvin* on Harbor Drive,
  and the finish in Canal Park by the Aerial Lift Bridge. Each section was drawn over the
  tiles at a zoom where the road is a band several pixels wide and checked there, so the
  line sits on the road at the zoom where the whole course is shown. No way geometry was
  copied: OpenStreetMap's data is under the ODbL, whose share-alike terms an extract would
  bring into this MIT repository. Like the Central Park run it replaces, the course
  carries no one's location.

  The waypoints are densified to a fix about every ten meters, some 4,200 fixes. The start
  is the point 26.2 miles back along them from the finish, and it falls where public
  descriptions put the start line, so the traced landmarks land within a few tenths of a
  mile of the miles those descriptions give them.
  """

  @waypoints [
    # Scenic 61 (Scenic Drive, then North Shore Drive and Congdon Boulevard) from just
    # outside Two Harbors, through Knife River and French River to the Lester River.
    {-91.71010, 47.00719},
    {-91.72854, 46.99382},
    {-91.74013, 46.98382},
    {-91.74378, 46.98088},
    {-91.74807, 46.97735},
    {-91.75322, 46.97441},
    {-91.75751, 46.97176},
    {-91.75965, 46.96912},
    {-91.76137, 46.96559},
    {-91.76352, 46.96265},
    {-91.76693, 46.96029},
    {-91.77208, 46.95676},
    {-91.77637, 46.95382},
    {-91.77981, 46.95088},
    {-91.78281, 46.94824},
    {-91.78582, 46.94618},
    {-91.78925, 46.94382},
    {-91.79268, 46.94206},
    {-91.79869, 46.93853},
    {-91.80470, 46.93441},
    {-91.80985, 46.93088},
    {-91.81214, 46.93029},
    {-91.81815, 46.92924},
    {-91.82845, 46.92924},
    {-91.83532, 46.92882},
    {-91.84133, 46.92735},
    {-91.84820, 46.92559},
    {-91.85163, 46.92324},
    {-91.85249, 46.91912},
    {-91.85506, 46.91500},
    {-91.86021, 46.91118},
    {-91.86622, 46.90941},
    {-91.87395, 46.90853},
    {-91.88253, 46.90588},
    {-91.88940, 46.90235},
    {-91.89712, 46.89559},
    {-91.90485, 46.89176},
    {-91.90987, 46.88799},
    {-91.91416, 46.88446},
    {-91.91931, 46.88093},
    {-91.92361, 46.88046},
    {-91.93133, 46.87681},
    {-91.93734, 46.87387},
    {-91.94335, 46.87093},
    {-91.94850, 46.86916},
    {-91.95365, 46.86622},
    {-91.95880, 46.86299},
    {-91.96481, 46.85975},
    {-91.96910, 46.85740},
    {-91.97682, 46.85446},
    {-91.98283, 46.85093},
    {-91.98970, 46.84681},
    {-91.99657, 46.84269},
    {-92.00064, 46.83954},
    # London Road through Lakeside and Congdon, past Glensheen and over Lemon Drop Hill.
    {-92.00515, 46.83734},
    {-92.00773, 46.83661},
    {-92.01202, 46.83573},
    {-92.01674, 46.83485},
    {-92.02060, 46.83309},
    {-92.02489, 46.83016},
    {-92.02790, 46.82884},
    {-92.03090, 46.82605},
    {-92.03391, 46.82371},
    {-92.03820, 46.82210},
    {-92.04292, 46.82224},
    {-92.04549, 46.82165},
    {-92.04783, 46.81932},
    {-92.05128, 46.81710},
    {-92.05472, 46.81458},
    {-92.05817, 46.81191},
    {-92.06033, 46.80999},
    {-92.06205, 46.80836},
    {-92.06464, 46.80687},
    {-92.06852, 46.80480},
    {-92.07240, 46.80323},
    {-92.07627, 46.80139},
    # Superior Street through the East Hillside and downtown, to Fifth Avenue West.
    {-92.0807, 46.7985},
    {-92.0833, 46.7974},
    {-92.0862, 46.7962},
    {-92.0890, 46.7944},
    {-92.0924, 46.7916},
    {-92.0958, 46.7886},
    {-92.0988, 46.7862},
    {-92.1020, 46.7838},
    # Past the Depot, along Harbor Drive by the aquarium and the Irvin, then Railroad
    # Street and Canal Park Drive to the finish by the Aerial Lift Bridge.
    {-92.10458, 46.78198},
    {-92.10380, 46.78165},
    {-92.10239, 46.78096},
    {-92.10114, 46.78020},
    {-92.09995, 46.77980},
    {-92.09853, 46.77944},
    {-92.09742, 46.78020},
    {-92.0980, 46.7806},
    {-92.0983, 46.7822},
    {-92.0986, 46.7833},
    {-92.0970, 46.7841},
    {-92.09528, 46.78491},
    {-92.09485, 46.78354},
    {-92.0942, 46.7820},
    {-92.0938, 46.7810}
  ]

  # Meters in a mile, and the Earth's mean radius for the haversine distance.
  @mile 1609.344
  @radius 6_371_008.8
  # About one fix every ten meters.
  @spacing 10.0

  @meters fn {lon0, lat0}, {lon1, lat1} ->
    rad = :math.pi() / 180
    dlat = (lat1 - lat0) * rad
    dlon = (lon1 - lon0) * rad

    a =
      :math.pow(:math.sin(dlat / 2), 2) +
        :math.cos(lat0 * rad) * :math.cos(lat1 * rad) * :math.pow(:math.sin(dlon / 2), 2)

    2 * @radius * :math.asin(:math.sqrt(a))
  end

  # `{meters from the start, lon, lat}` for every fix, the last the finish.
  @fixes (fn ->
            legs = Enum.zip(@waypoints, tl(@waypoints))

            {fixes, total} =
              Enum.flat_map_reduce(legs, 0.0, fn {{lon0, lat0} = a, {lon1, lat1} = b}, start ->
                length = @meters.(a, b)
                n = max(1, ceil(length / @spacing))

                fixes =
                  for k <- 0..(n - 1) do
                    f = k / n
                    {start + length * f, lon0 + (lon1 - lon0) * f, lat0 + (lat1 - lat0) * f}
                  end

                {fixes, start + length}
              end)

            {lon, lat} = List.last(@waypoints)

            (fixes ++ [{total, lon, lat}])
            |> Enum.map(fn {m, lon, lat} ->
              {Float.round(m, 2), Float.round(lon, 6), Float.round(lat, 6)}
            end)
            |> List.to_tuple()
          end).()

  @length elem(elem(@fixes, tuple_size(@fixes) - 1), 0)

  @rows for i <- 0..(tuple_size(@fixes) - 1),
            {_m, lon, lat} = elem(@fixes, i),
            do: %{"lon" => lon, "lat" => lat}

  @doc "The hand-placed waypoints, `{lon, lat}` in race order."
  @spec waypoints() :: [{float(), float()}]
  def waypoints, do: @waypoints

  @doc "Meters in a mile."
  @spec mile() :: float()
  def mile, do: @mile

  @doc "The course's length along its fixes, in meters."
  @spec length() :: float()
  def length, do: @length

  @doc "The course's length in miles."
  @spec miles() :: float()
  def miles, do: @length / @mile

  @doc "The course's fixes as the rows the design binds, `%{\"lon\", \"lat\"}` in race order."
  @spec rows() :: [map()]
  def rows, do: @rows

  @doc """
  The point `meters` along the course, `{lon, lat}`, interpolated between the fixes either
  side of it. Before the start is the start and past the finish is the finish.
  """
  @spec at(number()) :: {float(), float()}
  def at(meters) when meters <= 0, do: point(0)
  def at(meters) when meters >= @length, do: point(tuple_size(@fixes) - 1)

  def at(meters) do
    i = index(meters)
    {m0, lon0, lat0} = elem(@fixes, i)
    {m1, lon1, lat1} = elem(@fixes, i + 1)
    f = (meters - m0) / (m1 - m0)
    {lon0 + (lon1 - lon0) * f, lat0 + (lat1 - lat0) * f}
  end

  @doc """
  The stretch of the course from `from` to `to` meters, as rows: the point at each end and
  every fix between. The pack inset fits and draws this stretch.
  """
  @spec stretch(number(), number()) :: [map()]
  def stretch(from, to) do
    from = max(from, 0.0)
    to = min(to, @length)

    inner =
      for i <- (index(from) + 1)..index(to)//1,
          {m, lon, lat} = elem(@fixes, i),
          m > from and m < to,
          do: {lon, lat}

    Enum.map([at(from) | inner] ++ [at(to)], fn {lon, lat} ->
      %{"lon" => Float.round(lon, 6), "lat" => Float.round(lat, 6)}
    end)
  end

  @doc """
  The mile markers as rows: the start, miles 1 to 26 and the finish, each at its distance
  along the course, with `mile` and a `label` every five miles and at the start and finish
  (`nil` on the others).
  """
  @spec markers() :: [map()]
  def markers do
    stops =
      [{0.0, "Start"}] ++
        for(n <- 1..26, do: {n * @mile, if(rem(n, 5) == 0, do: "#{n}")}) ++
        [{@length, "Finish"}]

    for {meters, label} <- stops do
      {lon, lat} = at(meters)

      %{
        "lon" => Float.round(lon, 6),
        "lat" => Float.round(lat, 6),
        "mile" => Float.round(meters / @mile, 1),
        "label" => label
      }
    end
  end

  defp point(i) do
    {_m, lon, lat} = elem(@fixes, i)
    {lon, lat}
  end

  # The index of the last fix at or before `meters`, by bisection over the tuple.
  defp index(meters), do: bisect(meters, 0, tuple_size(@fixes) - 1)

  defp bisect(_meters, lo, hi) when hi - lo <= 1, do: lo

  defp bisect(meters, lo, hi) do
    mid = div(lo + hi, 2)

    if elem(elem(@fixes, mid), 0) <= meters,
      do: bisect(meters, mid, hi),
      else: bisect(meters, lo, mid)
  end
end
