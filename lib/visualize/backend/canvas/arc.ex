defmodule Visualize.Backend.Canvas.Arc do
  @moduledoc """
  Converts an SVG arc command to a Canvas `ellipse` call.

  Canvas draws arcs from a centre, radii and two angles; SVG describes them by their end
  points, radii, rotation and two flags. This is the endpoint-to-centre conversion of the
  SVG specification (implementation notes §B.2.4), the same maths the browser hooks used
  to carry, done once on the server so every Canvas output format is executable
  (spec/09 §3.3.2, D-37).
  """

  @doc false
  # The Canvas command for `{:A, rx, ry, rot, large, sweep, x2, y2}` from `{x1, y1}`:
  # nothing when the end points coincide (SVG omits the arc), a `lineTo` when a radius is
  # zero, else `{:ellipse, [cx, cy, rx, ry, rotation, start, end, anticlockwise]}` with
  # angles in radians.
  @spec to_command(
          {number(), number()},
          {number(), number()},
          number(),
          number(),
          number(),
          0 | 1,
          0 | 1
        ) :: [{atom(), list()}]
  def to_command({x1, y1}, {x2, y2}, _rx, _ry, _rot, _large, _sweep)
      when x1 == x2 and y1 == y2,
      do: []

  def to_command(_from, {x2, y2}, rx, ry, _rot, _large, _sweep) when rx == 0 or ry == 0,
    do: [{:lineTo, [x2, y2]}]

  def to_command({x1, y1}, {x2, y2}, rx, ry, rot, large, sweep) do
    phi = rot * :math.pi() / 180
    cos_phi = :math.cos(phi)
    sin_phi = :math.sin(phi)
    rx = abs(rx) * 1.0
    ry = abs(ry) * 1.0

    # Step 1: the end points in the ellipse's own frame, about the chord midpoint.
    dx2 = (x1 - x2) / 2
    dy2 = (y1 - y2) / 2
    x1p = cos_phi * dx2 + sin_phi * dy2
    y1p = -sin_phi * dx2 + cos_phi * dy2

    # Radii too small for the chord are scaled up until they fit (§B.2.5).
    lambda = x1p * x1p / (rx * rx) + y1p * y1p / (ry * ry)

    {rx, ry} =
      if lambda > 1, do: {rx * :math.sqrt(lambda), ry * :math.sqrt(lambda)}, else: {rx, ry}

    rx_sq = rx * rx
    ry_sq = ry * ry
    x1p_sq = x1p * x1p
    y1p_sq = y1p * y1p

    # Step 2: the centre in that frame.
    sq = (rx_sq * ry_sq - rx_sq * y1p_sq - ry_sq * x1p_sq) / (rx_sq * y1p_sq + ry_sq * x1p_sq)
    root = :math.sqrt(max(sq, 0.0))
    coef = if large != sweep, do: root, else: -root
    cxp = coef * (rx * y1p / ry)
    cyp = coef * -(ry * x1p / rx)

    # Step 3: back to user space.
    cx = cos_phi * cxp - sin_phi * cyp + (x1 + x2) / 2
    cy = sin_phi * cxp + cos_phi * cyp + (y1 + y2) / 2

    # Step 4: the start angle and the sweep.
    ux = (x1p - cxp) / rx
    uy = (y1p - cyp) / ry
    vx = (-x1p - cxp) / rx
    vy = (-y1p - cyp) / ry
    theta1 = angle({1.0, 0.0}, {ux, uy})
    dtheta = angle({ux, uy}, {vx, vy})

    dtheta =
      cond do
        sweep == 0 and dtheta > 0 -> dtheta - 2 * :math.pi()
        sweep == 1 and dtheta < 0 -> dtheta + 2 * :math.pi()
        true -> dtheta
      end

    [{:ellipse, [cx, cy, rx, ry, phi, theta1, theta1 + dtheta, sweep == 0]}]
  end

  # The signed angle from `u` to `v`.
  defp angle({ux, uy}, {vx, vy}) do
    dot = ux * vx + uy * vy
    len = :math.sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
    sign = if ux * vy - uy * vx < 0, do: -1, else: 1
    sign * :math.acos(max(-1.0, min(1.0, dot / len)))
  end
end
