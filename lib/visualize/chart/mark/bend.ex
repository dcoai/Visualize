defmodule Visualize.Chart.Mark.Bend do
  @moduledoc """
  The polar transform (spec/14 §5.2, #391): a mark laid out in `(angle, r)` — every `x` an
  angle in radians clockwise from 12 o'clock, every `y` a radius from the centre — bent
  around the arc.

  A pure function of the mark's elements, so every backend draws the same geometry:
  a point goes to `(r · sin a, −r · cos a)` (spec/04 §6.2); a straight segment is sampled
  at no more than 2° of angle and bent point by point, so a line wraps around the arc;
  a curve is sampled along its parameter, so it is interpolated in `(angle, r)` before it
  bends; a rect becomes an annular sector; a circle keeps its radius at the bent centre;
  a text moves to the bent point; a group's children bend, and a `translate` in a
  transform bends as a point.

      iex> Visualize.Chart.Mark.Bend.point({:math.pi() / 2, 10})
      {10.0, 0.0}

      iex> line = Visualize.IR.Element.line(0, 10, :math.pi(), 10)
      iex> %Visualize.IR.Element{type: :path, path: path} = Visualize.Chart.Mark.Bend.bend(line)
      iex> length(path.commands)
      91
  """

  alias Visualize.IR.{Element, Path, Transform}

  # The largest angle a sampled segment spans: 2° in radians.
  @step :math.pi() / 90

  @doc "One point `{angle, r}` bent to `{x, y}`: `(r · sin a, −r · cos a)`, rounded to six decimals."
  @spec point({number(), number()}) :: {float(), float()}
  def point({angle, r}), do: {crisp(r * :math.sin(angle)), crisp(-r * :math.cos(angle))}

  @doc """
  An element bent around the arc: its geometry read as `(angle, r)` and drawn in the
  plane about the centre.
  """
  @spec bend(Element.t()) :: Element.t()
  def bend(%Element{} = element), do: bend(element, [])

  @doc """
  As `bend/1` with options: `chords: true` joins the ends of a straight segment with one
  line instead of sampling it along the arc — a categorical angle's polygon (spec/14
  §5.2, #393); a horizontal run (`H`, a step curve's tread) is still sampled, since a run
  at one radius is an arc.
  """
  @spec bend(Element.t(), keyword()) :: Element.t()
  def bend(%Element{type: :group, children: children} = group, opts) do
    %{group | children: Enum.map(children, &bend(&1, opts))} |> bend_transform()
  end

  def bend(%Element{type: :path, path: %Path{} = path} = element, opts) do
    %{element | path: %{path | commands: commands(path.commands, opts)}} |> bend_transform()
  end

  def bend(%Element{type: :line, attrs: %{x1: x1, y1: y1, x2: x2, y2: y2}} = element, opts) do
    {mx, my} = point({x1, y1})
    commands = [{:M, mx, my} | segment({x1, y1}, {x2, y2}, opts)]

    %{element | type: :path, path: %Path{commands: commands}}
    |> Map.update!(:attrs, &Map.drop(&1, [:x1, :y1, :x2, :y2]))
    |> bend_transform()
  end

  def bend(%Element{type: :rect, attrs: %{x: x, y: y, width: w, height: h}} = element, _opts) do
    %{element | type: :path, path: %Path{commands: sector(x, x + w, y, y + h)}}
    |> Map.update!(:attrs, &Map.drop(&1, [:x, :y, :width, :height, :rx, :ry]))
    |> bend_transform()
  end

  def bend(%Element{type: :circle, attrs: %{cx: cx, cy: cy} = attrs} = element, _opts) do
    {x, y} = point({cx, cy})
    %{element | attrs: %{attrs | cx: x, cy: y}} |> bend_transform()
  end

  def bend(%Element{type: :text, attrs: %{x: x, y: y} = attrs} = element, _opts) do
    {bx, by} = point({x, y})
    %{element | attrs: %{attrs | x: bx, y: by}} |> bend_transform()
  end

  def bend(%Element{} = element, _opts), do: bend_transform(element)

  # A translate in the element's transform is a point of the layout: bent as one.
  defp bend_transform(%Element{transform: %Transform{operations: ops} = t} = element) do
    bent =
      Enum.map(ops, fn
        {:translate, x, y} ->
          {bx, by} = point({x, y})
          {:translate, bx, by}

        other ->
          other
      end)

    %{element | transform: %{t | operations: bent}}
  end

  defp bend_transform(element), do: element

  # -- paths --------------------------------------------------------------------------

  # Every command made absolute, sampled where it draws, and bent; the current point is
  # kept in (angle, r) so a relative command and a sample both have their origin.
  defp commands(commands, opts) do
    {bent, _state} =
      Enum.flat_map_reduce(commands, {nil, nil, nil}, fn command, {current, start, control} ->
        command(command, current, start, control, opts)
      end)

    bent
  end

  # Each clause: the bent commands, and the new {current, subpath start, last control}.
  defp command({:M, x, y}, _current, _start, _control, _opts) do
    {bx, by} = point({x, y})
    {[{:M, bx, by}], {{x, y}, {x, y}, nil}}
  end

  defp command({:m, dx, dy}, nil, start, control, opts),
    do: command({:M, dx, dy}, nil, start, control, opts)

  defp command({:m, dx, dy}, {cx, cy}, start, control, opts),
    do: command({:M, cx + dx, cy + dy}, {cx, cy}, start, control, opts)

  defp command({:L, x, y}, current, start, _control, opts) do
    {segment(current || {x, y}, {x, y}, opts), {{x, y}, start, nil}}
  end

  defp command({:l, dx, dy}, {cx, cy} = current, start, control, opts),
    do: command({:L, cx + dx, cy + dy}, current, start, control, opts)

  # A horizontal run is a run at one radius — an arc, sampled even where straight
  # segments are chords (a step curve's treads, spec/14 §5.2, #393).
  defp command({:H, x}, {_cx, cy} = current, start, control, opts),
    do: command({:L, x, cy}, current, start, control, Keyword.put(opts, :chords, false))

  defp command({:h, dx}, {cx, cy} = current, start, control, opts),
    do: command({:L, cx + dx, cy}, current, start, control, Keyword.put(opts, :chords, false))

  defp command({:V, y}, {cx, _cy} = current, start, control, opts),
    do: command({:L, cx, y}, current, start, control, opts)

  defp command({:v, dy}, {cx, cy} = current, start, control, opts),
    do: command({:L, cx, cy + dy}, current, start, control, opts)

  defp command({:C, x1, y1, x2, y2, x, y}, current, start, _control, _opts) do
    {sampled(current, {x, y}, &cubic(current, {x1, y1}, {x2, y2}, {x, y}, &1)),
     {{x, y}, start, {x2, y2}}}
  end

  defp command({:c, x1, y1, x2, y2, x, y}, {cx, cy} = current, start, control, opts),
    do:
      command(
        {:C, cx + x1, cy + y1, cx + x2, cy + y2, cx + x, cy + y},
        current,
        start,
        control,
        opts
      )

  # A smooth cubic's first control point reflects the previous one about the current point.
  defp command({:S, x2, y2, x, y}, {cx, cy} = current, start, control, opts) do
    {x1, y1} = reflect(control, {cx, cy})
    command({:C, x1, y1, x2, y2, x, y}, current, start, control, opts)
  end

  defp command({:s, x2, y2, x, y}, {cx, cy} = current, start, control, opts),
    do: command({:S, cx + x2, cy + y2, cx + x, cy + y}, current, start, control, opts)

  defp command({:Q, x1, y1, x, y}, current, start, _control, _opts) do
    {sampled(current, {x, y}, &quadratic(current, {x1, y1}, {x, y}, &1)),
     {{x, y}, start, {x1, y1}}}
  end

  defp command({:q, x1, y1, x, y}, {cx, cy} = current, start, control, opts),
    do: command({:Q, cx + x1, cy + y1, cx + x, cy + y}, current, start, control, opts)

  defp command({:T, x, y}, {cx, cy} = current, start, control, opts) do
    {x1, y1} = reflect(control, {cx, cy})
    command({:Q, x1, y1, x, y}, current, start, control, opts)
  end

  defp command({:t, x, y}, {cx, cy} = current, start, control, opts),
    do: command({:T, cx + x, cy + y}, current, start, control, opts)

  # An arc in (angle, r) is sampled as the chord it subtends: its parametrisation is not
  # worth keeping through a bend that will curve it again.
  defp command({:A, _rx, _ry, _rot, _large, _sweep, x, y}, current, start, control, opts),
    do: command({:L, x, y}, current, start, control, opts)

  defp command({:a, rx, ry, rot, large, sweep, dx, dy}, {cx, cy} = current, start, control, opts),
    do: command({:A, rx, ry, rot, large, sweep, cx + dx, cy + dy}, current, start, control, opts)

  defp command(:Z, _current, start, _control, _opts), do: {[:Z], {start, start, nil}}

  # A straight segment in (angle, r): `L` commands at no more than 2° apart, bent.
  defp segment({a0, r0}, {a1, r1}, opts) do
    n = if Keyword.get(opts, :chords, false), do: 1, else: max(1, ceil(abs(a1 - a0) / @step))

    for i <- 1..n//1 do
      t = i / n
      {x, y} = point({a0 + (a1 - a0) * t, r0 + (r1 - r0) * t})
      {:L, x, y}
    end
  end

  # A curve sampled along its parameter: as many samples as its angular span asks, and
  # at least eight, so a short curve still curves.
  defp sampled({a0, _} = _current, {a1, _}, at) do
    n = max(8, ceil(abs(a1 - a0) / @step))

    for i <- 1..n//1 do
      {x, y} = point(at.(i / n))
      {:L, x, y}
    end
  end

  defp cubic({x0, y0}, {x1, y1}, {x2, y2}, {x3, y3}, t) do
    u = 1 - t
    a = u * u * u
    b = 3 * u * u * t
    c = 3 * u * t * t
    d = t * t * t
    {a * x0 + b * x1 + c * x2 + d * x3, a * y0 + b * y1 + c * y2 + d * y3}
  end

  defp quadratic({x0, y0}, {x1, y1}, {x2, y2}, t) do
    u = 1 - t
    a = u * u
    b = 2 * u * t
    c = t * t
    {a * x0 + b * x1 + c * x2, a * y0 + b * y1 + c * y2}
  end

  defp reflect(nil, current), do: current
  defp reflect({px, py}, {cx, cy}), do: {2 * cx - px, 2 * cy - py}

  # -- sectors ------------------------------------------------------------------------

  # An annular sector from the angles `a0..a1` between the radii `r0..r1`: the outer arc
  # forward, the inner arc back, closed; a wedge to the centre when the inner radius is 0.
  defp sector(a0, a1, r0, r1) do
    {inner, outer} = {min(r0, r1), max(r0, r1)}
    {from, to} = {min(a0, a1), max(a0, a1)}
    large = if to - from > :math.pi(), do: 1, else: 0
    {ox0, oy0} = point({from, outer})
    {ox1, oy1} = point({to, outer})

    outer_arc = [{:M, ox0, oy0}, {:A, outer, outer, 0, large, 1, ox1, oy1}]

    inner_arc =
      if inner == 0 do
        [{:L, 0, 0}]
      else
        {ix1, iy1} = point({to, inner})
        {ix0, iy0} = point({from, inner})
        [{:L, ix1, iy1}, {:A, inner, inner, 0, large, 0, ix0, iy0}]
      end

    outer_arc ++ inner_arc ++ [:Z]
  end

  # Six decimals, negative zero folded (D-6), as every polar coordinate prints.
  defp crisp(x) do
    case Float.round(x * 1.0, 6) do
      r when r == 0 -> 0.0
      r -> r
    end
  end
end
