defmodule Visualize.Geo.Clip.Antimeridian do
  @moduledoc false
  # d3-geo's src/clip/antimeridian.js (v3.1.1): the clip of every projection without a
  # `clip_angle` (spec/07 §2.2). A line is cut where it crosses ±180° in the rotated frame,
  # or passes over a pole; a polygon is closed along the seam and the poles. In degrees, as
  # `Visualize.Geo.Clip` says, so π is 180 and π/2 is 90.
  #
  # `step` is the one addition: d3 draws the seam between its interpolation points and its
  # adaptive resampling (projection/resample.js) curves it under the projection. The
  # library does not resample, so with a `step` the edge this clip walks is sampled every
  # `step` degrees along the seam and the poles — on a pseudo-cylindrical map the seam is a
  # curve, and a straight chord would cut inside the outline (`Projection.sphere/1` samples
  # the same edge every degree). `step: nil` is d3 at `precision(0)`: no samples.

  @behaviour Visualize.Geo.Clip

  alias Visualize.Geo.Clip

  defstruct step: 1

  @type t :: %__MODULE__{step: pos_integer() | nil}

  @radians :math.pi() / 180

  # antimeridian.js:5: every point is visible.
  @impl true
  def visible?(_clipper, _lon, _lat), do: true

  # antimeridian.js:8: the south pole on the antimeridian.
  @impl true
  def start(_clipper), do: {-180, -90}

  # antimeridian.js:14–57. The state is d3's `lambda0`, `phi0`, `sign0` and `clean`, with
  # `nil` for its NaN before the first point; the segments are buffered (buffer.js) in
  # reverse, each in reverse.
  @impl true
  def clip_line(_clipper, points) do
    if crosses?(points), do: cut(points), else: {[strip(points)], 1}
  end

  # Neither branch of `point/2` can fire unless two consecutive longitudes are at least
  # 180° − ε apart, and without one the cut is the line as it came, clean: most lines
  # are, and this is the walk without its state.
  defp crosses?([a, b | rest]) do
    abs(elem(b, 0) - elem(a, 0)) >= 180 - Clip.epsilon() or crosses?([b | rest])
  end

  defp crosses?(_), do: false

  defp strip(points), do: Enum.map(points, fn point -> {elem(point, 0), elem(point, 1)} end)

  defp cut(points) do
    state = %{lambda0: nil, phi0: nil, sign0: nil, clean: 1, line: [], lines: []}
    state = Enum.reduce(points, state, &point/2)
    {Enum.reverse([Enum.reverse(state.line) | state.lines]), 2 - state.clean}
  end

  defp point(point, %{lambda0: lambda0, phi0: phi0, sign0: sign0} = state) do
    {lambda1, phi1} = {elem(point, 0), elem(point, 1)}
    sign1 = if lambda1 > 0, do: 180, else: -180
    eps = Clip.epsilon()

    {state, lambda1} =
      cond do
        is_nil(lambda0) ->
          {state, lambda1}

        # The line crosses a pole (antimeridian.js:28–35).
        abs(abs(lambda1 - lambda0) - 180) < eps ->
          pole = if (phi0 + phi1) / 2 > 0, do: 90, else: -90

          state =
            state
            |> emit({lambda0, pole})
            |> emit({sign0, pole})
            |> line_end()
            |> emit({sign1, pole})
            |> emit({lambda1, pole})

          {%{state | clean: 0}, lambda1}

        # The line crosses the antimeridian (antimeridian.js:36–45), the degenerate ends
        # nudged off it by d3's `sign * epsilon`: π · 1e-6 radians, 180 · 1e-6 degrees.
        sign0 != sign1 and abs(lambda1 - lambda0) >= 180 ->
          lambda0 = if abs(lambda0 - sign0) < eps, do: lambda0 - sign0 * 1.0e-6, else: lambda0
          lambda1 = if abs(lambda1 - sign1) < eps, do: lambda1 - sign1 * 1.0e-6, else: lambda1
          phi = intersect(lambda0, phi0, lambda1, phi1)

          state =
            state
            |> emit({sign0, phi})
            |> line_end()
            |> emit({sign1, phi})

          {%{state | clean: 0}, lambda1}

        true ->
          {state, lambda1}
      end

    state
    |> emit({lambda1, phi1})
    |> Map.merge(%{lambda0: lambda1, phi0: phi1, sign0: sign1})
  end

  defp emit(state, point), do: %{state | line: [point | state.line]}

  defp line_end(state),
    do: %{state | lines: [Enum.reverse(state.line) | state.lines], line: []}

  # antimeridian.js:59–68: the latitude where the great circle through the two points
  # meets the antimeridian.
  defp intersect(lambda0, phi0, lambda1, phi1) do
    {l0, p0, l1, p1} = {lambda0 * @radians, phi0 * @radians, lambda1 * @radians, phi1 * @radians}
    sin_l0_l1 = :math.sin(l0 - l1)

    if abs(sin_l0_l1) > 1.0e-6 do
      cos_p0 = :math.cos(p0)
      cos_p1 = :math.cos(p1)

      :math.atan(
        (:math.sin(p0) * cos_p1 * :math.sin(l1) - :math.sin(p1) * cos_p0 * :math.sin(l0)) /
          (cos_p0 * cos_p1 * sin_l0_l1)
      ) / @radians
    else
      (phi0 + phi1) / 2
    end
  end

  # antimeridian.js:70–92, then sampled when `step` is set.
  @impl true
  def interpolate(%__MODULE__{step: step}, from, to, direction) do
    points = interpolate(from, to, direction)

    case {step, from} do
      {nil, _} ->
        points

      {_, nil} ->
        sample(points, step)

      _ ->
        # The edge runs from `from` through the points to `to`; `from` and, where d3 does
        # not emit it here, `to` are drawn by the segments either side.
        [from | points ++ [to]] |> sample(step) |> tl() |> Enum.drop(-1)
    end
  end

  defp interpolate(nil, _to, direction) do
    phi = direction * 90

    [
      {-180, phi},
      {0, phi},
      {180, phi},
      {180, 0},
      {180, -phi},
      {0, -phi},
      {-180, -phi},
      {-180, 0},
      {-180, phi}
    ]
  end

  defp interpolate(from, to, direction) do
    if abs(elem(from, 0) - elem(to, 0)) > Clip.epsilon() do
      lambda = if elem(from, 0) < elem(to, 0), do: 180, else: -180
      phi = direction * lambda / 2
      [{-lambda, phi}, {0, phi}, {lambda, phi}]
    else
      [{elem(to, 0), elem(to, 1)}]
    end
  end

  # Every edge that runs along one side of the seam or along one pole is sampled at no
  # more than `step` degrees.
  defp sample([first | rest], step) do
    {points, _} =
      Enum.flat_map_reduce(rest, first, fn b, a -> {between(a, b, step) ++ [b], b} end)

    [first | points]
  end

  defp between(a, b, step) do
    {la, pa} = {elem(a, 0), elem(a, 1)}
    {lb, pb} = {elem(b, 0), elem(b, 1)}
    eps = Clip.epsilon()

    cond do
      abs(abs(la) - 180) < eps and abs(abs(lb) - 180) < eps and la * lb > 0 ->
        for t <- steps(pb - pa, step), do: {la, pa + t}

      abs(abs(pa) - 90) < eps and abs(abs(pb) - 90) < eps and pa * pb > 0 ->
        for t <- steps(lb - la, step), do: {la + t, pa}

      true ->
        []
    end
  end

  # The offsets of the interior samples of a run of `delta` degrees.
  defp steps(delta, step) do
    n = ceil(abs(delta) / step)
    for k <- 1..(n - 1)//1, do: delta * k / n
  end
end
