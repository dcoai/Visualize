defmodule Visualize.Chart.Label.Polar do
  @moduledoc false
  # A label's polar placement and rotation (spec/14 §5.5, §6.1, #137): the point moved
  # along the ray from a centre, and the text turned about its own position — by degrees,
  # or along (`:radial`) or across (`:tangent`) the ray with the flip that keeps it upright.

  alias Visualize.IR.{Element, Transform}

  @doc false
  # The label's point along the ray from `centre` through the anchor point: `by` beyond a
  # sector's rim — its outer radius outward, its inner inward, `radii` — or beyond any
  # other mark's own point; with the baseline and the text anchor of its side: `:start`
  # right of the centre, `:end` left, `:middle` on the vertical. A point at the centre has
  # no ray and stays, anchored `:middle`.
  @spec place(
          :outward | :inward,
          {number(), number()},
          {number(), number()},
          {number(), number()} | nil,
          number()
        ) :: {number(), number(), String.t(), atom()}
  def place(direction, {px, py}, {cx, cy}, radii, by) do
    case unit({px - cx, py - cy}) do
      nil ->
        {px, py, "0.32em", :middle}

      {ux, uy} ->
        sign = if direction == :outward, do: 1, else: -1

        from =
          case {radii, direction} do
            {{_r0, r1}, :outward} -> r1
            {{r0, _r1}, :inward} -> r0
            _ -> :math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy))
          end

        r = from + sign * by
        {cx + r * ux, cy + r * uy, "0.32em", side(sign * ux)}
    end
  end

  @doc false
  # The rotation of a text at `point` about `centre`, and the text anchor it leaves:
  # `nil` for none; a number as it is; `:radial` the ray's angle, anchored `:start`, or
  # flipped a half turn on the left and anchored `:end`, so the text runs toward the
  # centre and ends at the point; `:tangent` a quarter turn from the ray, flipped on the
  # lower half, anchored `:middle`.
  @spec rotation(term(), {number(), number()}, {number(), number()}, atom()) ::
          {number() | nil, atom()}
  def rotation(nil, _point, _centre, anchor), do: {nil, anchor}
  def rotation(degrees, _point, _centre, anchor) when is_number(degrees), do: {degrees, anchor}

  def rotation(kind, {px, py}, {cx, cy}, anchor) when kind in [:radial, :tangent] do
    case unit({px - cx, py - cy}) do
      nil ->
        {nil, anchor}

      {ux, uy} ->
        theta = :math.atan2(uy, ux) * 180 / :math.pi()

        # A radial label runs outward from the point on the right (:start) and, flipped,
        # toward the centre on the left, ending at the point (:end); a tangent label is
        # centred on its point.
        case kind do
          :radial when ux < 0 -> {normal(theta + 180), :end}
          :radial -> {normal(theta), :start}
          :tangent when uy > 0 -> {normal(theta - 90), :middle}
          :tangent -> {normal(theta + 90), :middle}
        end
    end
  end

  @doc false
  # The text turned about its own position by `degrees`, or as it is for `nil`.
  @spec rotate(Element.t(), number() | nil) :: Element.t()
  def rotate(text, nil), do: text

  def rotate(%Element{attrs: attrs} = text, degrees) do
    x = Map.get(attrs, :x, 0)
    y = Map.get(attrs, :y, 0)
    %{text | transform: Transform.rotate(text.transform || Transform.new(), degrees, x, y)}
  end

  # Degrees in (−180, 180], so a half turn reads as itself and not as 360.
  defp normal(deg) do
    d = :math.fmod(deg, 360.0)
    d = if d > 180.0, do: d - 360.0, else: d
    if d <= -180.0, do: d + 360.0, else: d
  end

  defp unit({dx, dy}) do
    len = :math.sqrt(dx * dx + dy * dy)
    if len < 1.0e-9, do: nil, else: {dx / len, dy / len}
  end

  defp side(ux) when ux > 1.0e-3, do: :start
  defp side(ux) when ux < -1.0e-3, do: :end
  defp side(_ux), do: :middle
end
