defmodule Visualize.Geo.Clip do
  @moduledoc false
  # d3-geo's src/clip/index.js (v3.1.1): lines and polygons clipped on the sphere, before
  # the planar projection (spec/07 §2.2, D-127). The clip is generic over a *clipper* — a
  # struct whose module implements this behaviour — as d3's is over its four arguments
  # (`pointVisible`, `clipLine`, `interpolate`, `start`): `Clip.Antimeridian` cuts at ±180°
  # for every projection without a `clip_angle`, and `Clip.Circle` (#510) by the small
  # circle of a `clip_angle`.
  #
  # Coordinates are `{lon, lat}` in degrees in the clipper's frame: the rotated frame for
  # the antimeridian — after the projection's `rotate`, before `center` and the raw
  # projection — and for the circle the rotated and centered frame of the clip test
  # (spec/07 §1.5), the circle about its origin. d3 works in radians; the port keeps
  # degrees so that a vertex the clip passes through is the very float the projection would
  # have been given without it, and every tolerance d3 states in radians is restated in
  # degrees (`epsilon/0`). A point may carry a third element, d3's `point[2]` flag, which
  # the small-circle clip sets on its intersections and the rejoin reads.

  alias Visualize.Geo.Clip.Rejoin
  alias Visualize.Geo.PolygonContains

  @type point :: {float(), float()} | {float(), float(), term()}

  @doc "Whether a point is drawn (index.js:147–149: a point outside is not)."
  @callback visible?(clipper :: struct(), lon :: number(), lat :: number()) :: boolean()

  @doc """
  The line cut into its visible segments, as d3's `clipLine` streams them into a buffer
  (buffer.js): one list per `lineStart`, in order; and its `clean` code — 1 no intersections,
  2 intersections with the first and last segments to be rejoined, 0 intersections
  otherwise (antimeridian.js:11–13).
  """
  @callback clip_line(clipper :: struct(), [point()]) :: {[[point()]], 0..3}

  @doc """
  The points that walk the clip edge from `from` to `to` in `direction` (1 or -1), the
  whole edge when both are `nil` (d3's `interpolate`).
  """
  @callback interpolate(clipper :: struct(), from :: point() | nil, to :: point() | nil, 1 | -1) ::
              [point()]

  @doc "The point the polygon is tested for containing (d3's `start`)."
  @callback start(clipper :: struct()) :: {number(), number()}

  # d3's ε (math.js) is 1e-6 radians.
  @epsilon 1.0e-6 * 180 / :math.pi()

  @doc false
  @spec epsilon() :: float()
  def epsilon, do: @epsilon

  @doc false
  # A line clipped (index.js:151–163): its visible segments, each drawn as its own subpath.
  @spec line(struct(), [point()]) :: [[{float(), float()}]]
  def line(%module{} = clipper, points) do
    {segments, _clean} = module.clip_line(clipper, points)
    Enum.map(segments, &strip/1)
  end

  @doc false
  # A polygon clipped (index.js:113–137, 165–208): its rings — GeoJSON's, each closed by
  # repeating its first vertex — as the rings to draw, each closed by the caller.
  #
  # A ring the clip leaves whole is returned as it was given, its closing vertex kept (d3
  # drops it, `Z` closing the ring either way); the cut rings are rejoined along the clip
  # edge (rejoin.js), and a polygon that crosses nothing but contains the clip edge's start
  # is the whole edge (index.js:129–134).
  @spec polygon(struct(), [[point()]]) :: [[{float(), float()}]]
  def polygon(%module{} = clipper, rings) do
    {whole, segments, polygon} =
      Enum.reduce(rings, {[], [], []}, fn ring, acc -> ring_end(clipper, ring, acc) end)

    whole = Enum.reverse(whole)
    segments = segments |> Enum.reverse() |> Enum.concat()
    start_inside = PolygonContains.contains?(Enum.reverse(polygon), module.start(clipper))

    rejoined =
      cond do
        segments != [] ->
          Rejoin.rejoin(
            segments,
            &compare_key/1,
            start_inside,
            &module.interpolate(clipper, &1, &2, &3)
          )

        start_inside ->
          [module.interpolate(clipper, nil, nil, 1)]

        true ->
          []
      end

    Enum.map(whole ++ rejoined, &strip/1)
  end

  # index.js:165–208. GeoJSON closes a ring by repeating its first vertex; d3's stream
  # drops the last vertex (stream.js:52, `closed`) and the clip appends the first again.
  defp ring_end(_clipper, [], acc), do: acc
  defp ring_end(_clipper, [_], acc), do: acc

  defp ring_end(%module{} = clipper, ring, {whole, segments, polygon}) do
    ring = Enum.drop(ring, -1)
    {ring_segments, clean} = module.clip_line(clipper, ring ++ [hd(ring)])
    polygon = [ring | polygon]

    cond do
      ring_segments == [] ->
        {whole, segments, polygon}

      # No intersections (index.js:191–201): the ring as it is, if it has an edge.
      Bitwise.band(clean, 1) == 1 ->
        case ring_segments do
          [[_, _ | _] = segment | _] -> {[segment | whole], segments, polygon}
          _ -> {whole, segments, polygon}
        end

      # Rejoin connected segments (index.js:205): the last runs on into the first.
      true ->
        ring_segments =
          if length(ring_segments) > 1 and Bitwise.band(clean, 2) == 2 do
            [first | rest] = ring_segments
            {middle, [last]} = Enum.split(rest, -1)
            middle ++ [last ++ first]
          else
            ring_segments
          end

        valid = Enum.filter(ring_segments, &match?([_, _ | _], &1))
        {whole, [valid | segments], polygon}
    end
  end

  # index.js:220–223: intersections are ordered along the clip edge — up the western side
  # from the south, then down the eastern side from the north. `compareIntersection(a, b)`
  # is the difference of this key, in degrees.
  defp compare_key(point) do
    {lon, lat} = {elem(point, 0), elem(point, 1)}
    if lon < 0, do: lat - 90 - @epsilon, else: 90 - lat
  end

  defp strip(points), do: Enum.map(points, fn point -> {elem(point, 0), elem(point, 1)} end)
end
