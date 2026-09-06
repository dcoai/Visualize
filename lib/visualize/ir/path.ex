defmodule Visualize.IR.Path do
  @moduledoc """
  Backend-agnostic path command representation.

  Stores drawing commands as tuples that can be converted to
  any output format by backends (SVG, Canvas, etc.).

  ## Command Types

  - Movement: `{:M, x, y}`, `{:m, dx, dy}` (absolute/relative move)
  - Lines: `{:L, x, y}`, `{:l, dx, dy}`, `{:H, x}`, `{:V, y}`
  - Curves: `{:C, x1, y1, x2, y2, x, y}` (cubic bezier)
  - Arcs: `{:A, rx, ry, rotation, large_arc, sweep, x, y}`
  - Close: `:Z`

  ## Examples

      iex> alias Visualize.IR.Path
      iex> Path.new()
      ...> |> Path.move_to(10, 20)
      ...> |> Path.line_to(100, 200)
      ...> |> Path.close()
      %Visualize.IR.Path{commands: [{:M, 10, 20}, {:L, 100, 200}, :Z]}

  """

  alias Visualize.IR.Transform

  defstruct commands: [], metadata: %{}

  @type t :: %__MODULE__{commands: [command()], metadata: map()}
  @type command ::
          {:M, number(), number()}
          | {:m, number(), number()}
          | {:L, number(), number()}
          | {:l, number(), number()}
          | {:H, number()}
          | {:h, number()}
          | {:V, number()}
          | {:v, number()}
          | {:C, number(), number(), number(), number(), number(), number()}
          | {:c, number(), number(), number(), number(), number(), number()}
          | {:S, number(), number(), number(), number()}
          | {:s, number(), number(), number(), number()}
          | {:Q, number(), number(), number(), number()}
          | {:q, number(), number(), number(), number()}
          | {:T, number(), number()}
          | {:t, number(), number()}
          | {:A, number(), number(), number(), integer(), integer(), number(), number()}
          | {:a, number(), number(), number(), integer(), integer(), number(), number()}
          | :Z

  @doc """
  Creates a new empty path.
  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Move to absolute position.
  """
  @spec move_to(t(), number(), number()) :: t()
  def move_to(%__MODULE__{} = path, x, y) do
    append_command(path, {:M, x, y})
  end

  @doc """
  Move to relative position.
  """
  @spec move_to_rel(t(), number(), number()) :: t()
  def move_to_rel(%__MODULE__{} = path, dx, dy) do
    append_command(path, {:m, dx, dy})
  end

  @doc """
  Line to absolute position.
  """
  @spec line_to(t(), number(), number()) :: t()
  def line_to(%__MODULE__{} = path, x, y) do
    append_command(path, {:L, x, y})
  end

  @doc """
  Line to relative position.
  """
  @spec line_to_rel(t(), number(), number()) :: t()
  def line_to_rel(%__MODULE__{} = path, dx, dy) do
    append_command(path, {:l, dx, dy})
  end

  @doc """
  Horizontal line to absolute x.
  """
  @spec horizontal_to(t(), number()) :: t()
  def horizontal_to(%__MODULE__{} = path, x) do
    append_command(path, {:H, x})
  end

  @doc """
  Horizontal line to relative x.
  """
  @spec horizontal_to_rel(t(), number()) :: t()
  def horizontal_to_rel(%__MODULE__{} = path, dx) do
    append_command(path, {:h, dx})
  end

  @doc """
  Vertical line to absolute y.
  """
  @spec vertical_to(t(), number()) :: t()
  def vertical_to(%__MODULE__{} = path, y) do
    append_command(path, {:V, y})
  end

  @doc """
  Vertical line to relative y.
  """
  @spec vertical_to_rel(t(), number()) :: t()
  def vertical_to_rel(%__MODULE__{} = path, dy) do
    append_command(path, {:v, dy})
  end

  @doc """
  Cubic Bezier curve to absolute position.
  """
  @spec curve_to(t(), number(), number(), number(), number(), number(), number()) :: t()
  def curve_to(%__MODULE__{} = path, x1, y1, x2, y2, x, y) do
    append_command(path, {:C, x1, y1, x2, y2, x, y})
  end

  @doc """
  Cubic Bezier curve to relative position.
  """
  @spec curve_to_rel(t(), number(), number(), number(), number(), number(), number()) :: t()
  def curve_to_rel(%__MODULE__{} = path, dx1, dy1, dx2, dy2, dx, dy) do
    append_command(path, {:c, dx1, dy1, dx2, dy2, dx, dy})
  end

  @doc """
  Smooth cubic Bezier curve to absolute position.
  """
  @spec smooth_curve_to(t(), number(), number(), number(), number()) :: t()
  def smooth_curve_to(%__MODULE__{} = path, x2, y2, x, y) do
    append_command(path, {:S, x2, y2, x, y})
  end

  @doc """
  Smooth cubic Bezier curve to relative position.
  """
  @spec smooth_curve_to_rel(t(), number(), number(), number(), number()) :: t()
  def smooth_curve_to_rel(%__MODULE__{} = path, dx2, dy2, dx, dy) do
    append_command(path, {:s, dx2, dy2, dx, dy})
  end

  @doc """
  Quadratic Bezier curve to absolute position.
  """
  @spec quad_to(t(), number(), number(), number(), number()) :: t()
  def quad_to(%__MODULE__{} = path, x1, y1, x, y) do
    append_command(path, {:Q, x1, y1, x, y})
  end

  @doc """
  Quadratic Bezier curve to relative position.
  """
  @spec quad_to_rel(t(), number(), number(), number(), number()) :: t()
  def quad_to_rel(%__MODULE__{} = path, dx1, dy1, dx, dy) do
    append_command(path, {:q, dx1, dy1, dx, dy})
  end

  @doc """
  Smooth quadratic Bezier curve to absolute position.
  """
  @spec smooth_quad_to(t(), number(), number()) :: t()
  def smooth_quad_to(%__MODULE__{} = path, x, y) do
    append_command(path, {:T, x, y})
  end

  @doc """
  Smooth quadratic Bezier curve to relative position.
  """
  @spec smooth_quad_to_rel(t(), number(), number()) :: t()
  def smooth_quad_to_rel(%__MODULE__{} = path, dx, dy) do
    append_command(path, {:t, dx, dy})
  end

  @doc """
  Arc to absolute position.

  - `rx`, `ry`: radii of the ellipse
  - `x_rotation`: rotation of the ellipse in degrees
  - `large_arc`: 0 or 1, whether to use the larger arc
  - `sweep`: 0 or 1, direction of the arc
  - `x`, `y`: end point
  """
  @spec arc_to(t(), number(), number(), number(), integer(), integer(), number(), number()) :: t()
  def arc_to(%__MODULE__{} = path, rx, ry, x_rotation, large_arc, sweep, x, y) do
    append_command(path, {:A, rx, ry, x_rotation, large_arc, sweep, x, y})
  end

  @doc """
  Arc to relative position.
  """
  @spec arc_to_rel(t(), number(), number(), number(), integer(), integer(), number(), number()) ::
          t()
  def arc_to_rel(%__MODULE__{} = path, rx, ry, x_rotation, large_arc, sweep, dx, dy) do
    append_command(path, {:a, rx, ry, x_rotation, large_arc, sweep, dx, dy})
  end

  @doc """
  Close the path.
  """
  @spec close(t()) :: t()
  def close(%__MODULE__{} = path) do
    append_command(path, :Z)
  end

  @doc """
  Returns whether the path is empty (has no commands).
  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{commands: []}), do: true
  def empty?(%__MODULE__{}), do: false

  @doc """
  Returns the number of commands in the path.
  """
  @spec command_count(t()) :: non_neg_integer()
  def command_count(%__MODULE__{commands: commands}), do: length(commands)

  @doc """
  Combines multiple paths into one.
  """
  @spec concat([t()]) :: t()
  def concat(paths) when is_list(paths) do
    commands = Enum.flat_map(paths, & &1.commands)
    %__MODULE__{commands: commands}
  end

  @doc """
  Appends commands from another path.
  """
  @spec append(t(), t()) :: t()
  def append(%__MODULE__{commands: c1}, %__MODULE__{commands: c2}) do
    %__MODULE__{commands: c1 ++ c2}
  end

  @doc """
  Applies an affine transform to every coordinate of the path.

  The transform is a matrix `{a, b, c, d, e, f}` (`t:Visualize.IR.Transform.matrix/0`) or a
  `Visualize.IR.Transform`, which is folded with `Visualize.IR.Transform.to_matrix/1`.
  Absolute end and control points get the full affine map; relative deltas get its linear
  part only. `H`/`V`/`h`/`v` are resolved against the current point and stay single-axis
  when the transform keeps that axis (no rotation or skew into it), otherwise they become
  `L`/`l`. An arc's end point is mapped, its radii and rotation are those of the exact image
  ellipse, and its sweep flag flips under a reflection. `:Z` is untouched.

  ## Examples

      iex> alias Visualize.IR.Path
      iex> Path.new() |> Path.move_to(1, 2) |> Path.line_to_rel(3, 4) |> Path.horizontal_to(9)
      ...> |> Path.transform({1, 0, 0, 1, 10, 20})
      %Visualize.IR.Path{commands: [{:M, 11, 22}, {:l, 3, 4}, {:H, 19}]}

  """
  @spec transform(t(), Transform.matrix() | Transform.t()) :: t()
  def transform(%__MODULE__{} = path, %Transform{} = t),
    do: transform(path, Transform.to_matrix(t))

  def transform(%__MODULE__{commands: commands} = path, {_, _, _, _, _, _} = m) do
    {transformed, _} =
      Enum.map_reduce(commands, {:first, {0, 0}, {0, 0}}, fn cmd, state ->
        transform_command(cmd, m, state)
      end)

    %{path | commands: transformed}
  end

  # The state is `{position, current_point, subpath_start}`; `position` is `:first` for the
  # leading command, where SVG reads a relative `m` as absolute.
  defp transform_command({:M, x, y}, m, _state) do
    {nx, ny} = point(m, {x, y})
    {{:M, nx, ny}, {:rest, {x, y}, {x, y}}}
  end

  defp transform_command({:m, dx, dy}, m, {:first, _, _}) do
    {nx, ny} = point(m, {dx, dy})
    {{:m, nx, ny}, {:rest, {dx, dy}, {dx, dy}}}
  end

  defp transform_command({:m, dx, dy}, m, {_, {cx, cy}, _}) do
    {ndx, ndy} = delta(m, {dx, dy})
    {{:m, ndx, ndy}, {:rest, {cx + dx, cy + dy}, {cx + dx, cy + dy}}}
  end

  defp transform_command({:L, x, y}, m, {_, _, start}) do
    {nx, ny} = point(m, {x, y})
    {{:L, nx, ny}, {:rest, {x, y}, start}}
  end

  defp transform_command({:l, dx, dy}, m, {_, {cx, cy}, start}) do
    {ndx, ndy} = delta(m, {dx, dy})
    {{:l, ndx, ndy}, {:rest, {cx + dx, cy + dy}, start}}
  end

  defp transform_command({:H, x}, {_, b, _, _, _, _} = m, {_, {_, cy}, start}) do
    {nx, ny} = point(m, {x, cy})
    cmd = if b == 0, do: {:H, nx}, else: {:L, nx, ny}
    {cmd, {:rest, {x, cy}, start}}
  end

  defp transform_command({:h, dx}, {_, b, _, _, _, _} = m, {_, {cx, cy}, start}) do
    {ndx, ndy} = delta(m, {dx, 0})
    cmd = if b == 0, do: {:h, ndx}, else: {:l, ndx, ndy}
    {cmd, {:rest, {cx + dx, cy}, start}}
  end

  defp transform_command({:V, y}, {_, _, c, _, _, _} = m, {_, {cx, _}, start}) do
    {nx, ny} = point(m, {cx, y})
    cmd = if c == 0, do: {:V, ny}, else: {:L, nx, ny}
    {cmd, {:rest, {cx, y}, start}}
  end

  defp transform_command({:v, dy}, {_, _, c, _, _, _} = m, {_, {cx, cy}, start}) do
    {ndx, ndy} = delta(m, {0, dy})
    cmd = if c == 0, do: {:v, ndy}, else: {:l, ndx, ndy}
    {cmd, {:rest, {cx, cy + dy}, start}}
  end

  defp transform_command({:C, x1, y1, x2, y2, x, y}, m, {_, _, start}) do
    {nx1, ny1} = point(m, {x1, y1})
    {nx2, ny2} = point(m, {x2, y2})
    {nx, ny} = point(m, {x, y})
    {{:C, nx1, ny1, nx2, ny2, nx, ny}, {:rest, {x, y}, start}}
  end

  defp transform_command({:c, dx1, dy1, dx2, dy2, dx, dy}, m, {_, {cx, cy}, start}) do
    {ndx1, ndy1} = delta(m, {dx1, dy1})
    {ndx2, ndy2} = delta(m, {dx2, dy2})
    {ndx, ndy} = delta(m, {dx, dy})
    {{:c, ndx1, ndy1, ndx2, ndy2, ndx, ndy}, {:rest, {cx + dx, cy + dy}, start}}
  end

  defp transform_command({:S, x2, y2, x, y}, m, {_, _, start}) do
    {nx2, ny2} = point(m, {x2, y2})
    {nx, ny} = point(m, {x, y})
    {{:S, nx2, ny2, nx, ny}, {:rest, {x, y}, start}}
  end

  defp transform_command({:s, dx2, dy2, dx, dy}, m, {_, {cx, cy}, start}) do
    {ndx2, ndy2} = delta(m, {dx2, dy2})
    {ndx, ndy} = delta(m, {dx, dy})
    {{:s, ndx2, ndy2, ndx, ndy}, {:rest, {cx + dx, cy + dy}, start}}
  end

  defp transform_command({:Q, x1, y1, x, y}, m, {_, _, start}) do
    {nx1, ny1} = point(m, {x1, y1})
    {nx, ny} = point(m, {x, y})
    {{:Q, nx1, ny1, nx, ny}, {:rest, {x, y}, start}}
  end

  defp transform_command({:q, dx1, dy1, dx, dy}, m, {_, {cx, cy}, start}) do
    {ndx1, ndy1} = delta(m, {dx1, dy1})
    {ndx, ndy} = delta(m, {dx, dy})
    {{:q, ndx1, ndy1, ndx, ndy}, {:rest, {cx + dx, cy + dy}, start}}
  end

  defp transform_command({:T, x, y}, m, {_, _, start}) do
    {nx, ny} = point(m, {x, y})
    {{:T, nx, ny}, {:rest, {x, y}, start}}
  end

  defp transform_command({:t, dx, dy}, m, {_, {cx, cy}, start}) do
    {ndx, ndy} = delta(m, {dx, dy})
    {{:t, ndx, ndy}, {:rest, {cx + dx, cy + dy}, start}}
  end

  defp transform_command({:A, rx, ry, rot, large, sweep, x, y}, m, {_, _, start}) do
    {nrx, nry, nrot, nsweep} = ellipse(m, rx, ry, rot, sweep)
    {nx, ny} = point(m, {x, y})
    {{:A, nrx, nry, nrot, large, nsweep, nx, ny}, {:rest, {x, y}, start}}
  end

  defp transform_command({:a, rx, ry, rot, large, sweep, dx, dy}, m, {_, {cx, cy}, start}) do
    {nrx, nry, nrot, nsweep} = ellipse(m, rx, ry, rot, sweep)
    {ndx, ndy} = delta(m, {dx, dy})
    {{:a, nrx, nry, nrot, large, nsweep, ndx, ndy}, {:rest, {cx + dx, cy + dy}, start}}
  end

  defp transform_command(:Z, _m, {_, _, start}), do: {:Z, {:rest, start, start}}

  defp point(m, p), do: Transform.apply_matrix(m, p)
  defp delta({a, b, c, d, _, _}, p), do: Transform.apply_matrix({a, b, c, d, 0, 0}, p)

  # The image of the ellipse `rotate(rot) scale(rx, ry)` under the linear part of `m`,
  # read off the closed-form SVD of the 2×2 product: the singular values are the new radii
  # and the left rotation is the new axis angle. A negative determinant is a reflection,
  # which reverses the arc's direction.
  defp ellipse({a, b, c, d, _, _}, rx, ry, rot, sweep) do
    rad = rot * :math.pi() / 180
    cos = :math.cos(rad)
    sin = :math.sin(rad)
    p = rx * (a * cos + c * sin)
    q = ry * (c * cos - a * sin)
    r = rx * (b * cos + d * sin)
    s = ry * (d * cos - b * sin)
    e = (p + s) / 2
    f = (p - s) / 2
    g = (r + q) / 2
    h = (r - q) / 2
    big_q = :math.sqrt(e * e + h * h)
    big_r = :math.sqrt(f * f + g * g)
    reflected? = a * d - b * c < 0
    new_sweep = if reflected?, do: 1 - sweep, else: sweep
    # A circle has no axis: its rotation is kept as given rather than read off the SVD.
    angle =
      if big_r == 0,
        do: rot,
        else: normalise_degrees((:math.atan2(h, e) + :math.atan2(g, f)) / 2 * 180 / :math.pi())

    {big_q + big_r, abs(big_q - big_r), angle, new_sweep}
  end

  # An ellipse's axis angle is defined modulo a half turn; canonical form is `[0, 180)`.
  defp normalise_degrees(deg) do
    r = :math.fmod(deg, 180.0)
    if r < 0, do: r + 180.0, else: r
  end

  defp append_command(%__MODULE__{commands: commands} = path, command) do
    %{path | commands: commands ++ [command]}
  end

  # ============================================================
  # Normalisation
  # ============================================================

  @doc """
  Rewrites the smooth curve commands `S`/`s`/`T`/`t` as `C`/`c`/`Q`/`q`.

  The first control point is the reflection of the previous command's last control point
  about the current point when that command was a cubic (for `S`) or a quadratic (for
  `T`), and the current point itself otherwise — SVG's rule. Every other command is kept as
  it is, so relative commands stay relative.

  ## Examples

      iex> alias Visualize.IR.Path
      iex> Path.new() |> Path.move_to(0, 0) |> Path.curve_to(1, 1, 2, 1, 3, 0)
      ...> |> Path.smooth_curve_to(5, -1, 6, 0) |> Path.expand_smooth()
      %Visualize.IR.Path{commands: [{:M, 0, 0}, {:C, 1, 1, 2, 1, 3, 0}, {:C, 4, -1, 5, -1, 6, 0}]}

  """
  @spec expand_smooth(t()) :: t()
  def expand_smooth(%__MODULE__{commands: commands} = path) do
    {expanded, _} = Enum.map_reduce(commands, initial_state(), &expand_smooth_command/2)
    %{path | commands: expanded}
  end

  @doc """
  Rewrites every command as an absolute `M`, `L`, `C`, `Q`, `A` or `Z`.

  Relative commands are resolved against the current point (a leading `m` is absolute, as
  SVG reads it), `H`/`V` become `L`, and the smooth commands are expanded as in
  `expand_smooth/1`. An arc keeps its radii, rotation and flags. The result draws the same
  figure and is what a target without relative commands, such as Canvas, replays.

  ## Examples

      iex> alias Visualize.IR.Path
      iex> Path.new() |> Path.move_to(1, 1) |> Path.line_to_rel(2, 0) |> Path.vertical_to(5)
      ...> |> Path.close() |> Path.absolute()
      %Visualize.IR.Path{commands: [{:M, 1, 1}, {:L, 3, 1}, {:L, 3, 5}, :Z]}

  """
  @spec absolute(t()) :: t()
  def absolute(%__MODULE__{commands: commands} = path) do
    {absolute, _} = Enum.map_reduce(commands, initial_state(), &absolute_command/2)
    %{path | commands: absolute}
  end

  # The walker's state: the current point, the subpath start, the last cubic and quadratic
  # control points (absolute; `nil` when the previous command was not of that kind) and
  # whether the next command is the path's first.
  defp initial_state, do: %{cur: {0, 0}, start: {0, 0}, cubic: nil, quad: nil, first?: true}

  defp expand_smooth_command({:S, x2, y2, x, y}, state) do
    {x1, y1} = reflect(state.cubic, state.cur)
    cmd = {:C, x1, y1, x2, y2, x, y}
    {cmd, step(cmd, state)}
  end

  defp expand_smooth_command({:s, dx2, dy2, dx, dy}, %{cur: {cx, cy}} = state) do
    {x1, y1} = reflect(state.cubic, state.cur)
    cmd = {:c, x1 - cx, y1 - cy, dx2, dy2, dx, dy}
    {cmd, step(cmd, state)}
  end

  defp expand_smooth_command({:T, x, y}, state) do
    {x1, y1} = reflect(state.quad, state.cur)
    cmd = {:Q, x1, y1, x, y}
    {cmd, step(cmd, state)}
  end

  defp expand_smooth_command({:t, dx, dy}, %{cur: {cx, cy}} = state) do
    {x1, y1} = reflect(state.quad, state.cur)
    cmd = {:q, x1 - cx, y1 - cy, dx, dy}
    {cmd, step(cmd, state)}
  end

  defp expand_smooth_command(cmd, state), do: {cmd, step(cmd, state)}

  defp absolute_command(cmd, state) do
    {expanded, _} = expand_smooth_command(cmd, state)
    next = step(expanded, state)
    {absolutize(expanded, state), next}
  end

  defp absolutize({:M, x, y}, _), do: {:M, x, y}
  defp absolutize({:m, dx, dy}, %{first?: true}), do: {:M, dx, dy}
  defp absolutize({:m, dx, dy}, %{cur: {cx, cy}}), do: {:M, cx + dx, cy + dy}
  defp absolutize({:L, x, y}, _), do: {:L, x, y}
  defp absolutize({:l, dx, dy}, %{cur: {cx, cy}}), do: {:L, cx + dx, cy + dy}
  defp absolutize({:H, x}, %{cur: {_, cy}}), do: {:L, x, cy}
  defp absolutize({:h, dx}, %{cur: {cx, cy}}), do: {:L, cx + dx, cy}
  defp absolutize({:V, y}, %{cur: {cx, _}}), do: {:L, cx, y}
  defp absolutize({:v, dy}, %{cur: {cx, cy}}), do: {:L, cx, cy + dy}
  defp absolutize({:C, _, _, _, _, _, _} = cmd, _), do: cmd

  defp absolutize({:c, dx1, dy1, dx2, dy2, dx, dy}, %{cur: {cx, cy}}),
    do: {:C, cx + dx1, cy + dy1, cx + dx2, cy + dy2, cx + dx, cy + dy}

  defp absolutize({:Q, _, _, _, _} = cmd, _), do: cmd

  defp absolutize({:q, dx1, dy1, dx, dy}, %{cur: {cx, cy}}),
    do: {:Q, cx + dx1, cy + dy1, cx + dx, cy + dy}

  defp absolutize({:A, _, _, _, _, _, _, _} = cmd, _), do: cmd

  defp absolutize({:a, rx, ry, rot, large, sweep, dx, dy}, %{cur: {cx, cy}}),
    do: {:A, rx, ry, rot, large, sweep, cx + dx, cy + dy}

  defp absolutize(:Z, _), do: :Z

  # The control point a smooth command reflects: the previous one of its kind, else the
  # current point (which makes the first control point the current point itself).
  defp reflect(nil, cur), do: cur
  defp reflect({px, py}, {cx, cy}), do: {2 * cx - px, 2 * cy - py}

  # Advances the walker past one (already smooth-expanded) command.
  defp step({:M, x, y}, state),
    do: %{state | cur: {x, y}, start: {x, y}, cubic: nil, quad: nil, first?: false}

  defp step({:m, dx, dy}, %{first?: true} = state), do: step({:M, dx, dy}, state)

  defp step({:m, dx, dy}, %{cur: {cx, cy}} = state), do: step({:M, cx + dx, cy + dy}, state)

  defp step({:L, x, y}, state), do: %{state | cur: {x, y}, cubic: nil, quad: nil, first?: false}
  defp step({:l, dx, dy}, %{cur: {cx, cy}} = state), do: step({:L, cx + dx, cy + dy}, state)
  defp step({:H, x}, %{cur: {_, cy}} = state), do: step({:L, x, cy}, state)
  defp step({:h, dx}, %{cur: {cx, cy}} = state), do: step({:L, cx + dx, cy}, state)
  defp step({:V, y}, %{cur: {cx, _}} = state), do: step({:L, cx, y}, state)
  defp step({:v, dy}, %{cur: {cx, cy}} = state), do: step({:L, cx, cy + dy}, state)

  defp step({:C, _, _, x2, y2, x, y}, state),
    do: %{state | cur: {x, y}, cubic: {x2, y2}, quad: nil, first?: false}

  defp step({:c, _, _, dx2, dy2, dx, dy}, %{cur: {cx, cy}} = state),
    do: %{state | cur: {cx + dx, cy + dy}, cubic: {cx + dx2, cy + dy2}, quad: nil, first?: false}

  defp step({:Q, x1, y1, x, y}, state),
    do: %{state | cur: {x, y}, cubic: nil, quad: {x1, y1}, first?: false}

  defp step({:q, dx1, dy1, dx, dy}, %{cur: {cx, cy}} = state),
    do: %{state | cur: {cx + dx, cy + dy}, cubic: nil, quad: {cx + dx1, cy + dy1}, first?: false}

  defp step({:A, _, _, _, _, _, x, y}, state), do: step({:L, x, y}, state)

  defp step({:a, _, _, _, _, _, dx, dy}, %{cur: {cx, cy}} = state),
    do: step({:L, cx + dx, cy + dy}, state)

  defp step(:Z, %{start: start} = state),
    do: %{state | cur: start, cubic: nil, quad: nil, first?: false}

  # ============================================================
  # Serialization
  # ============================================================

  @doc """
  Converts the path to an SVG path data string.

  ## Examples

      iex> alias Visualize.IR.Path
      iex> Path.new() |> Path.move_to(10, 20) |> Path.line_to(100, 200) |> Path.to_string()
      "M10,20L100,200"

  """
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{commands: commands}) do
    commands
    |> Enum.map(&command_to_string/1)
    |> Enum.join("")
  end

  defp command_to_string({:M, x, y}), do: "M#{format_num(x)},#{format_num(y)}"
  defp command_to_string({:m, dx, dy}), do: "m#{format_num(dx)},#{format_num(dy)}"
  defp command_to_string({:L, x, y}), do: "L#{format_num(x)},#{format_num(y)}"
  defp command_to_string({:l, dx, dy}), do: "l#{format_num(dx)},#{format_num(dy)}"
  defp command_to_string({:H, x}), do: "H#{format_num(x)}"
  defp command_to_string({:h, dx}), do: "h#{format_num(dx)}"
  defp command_to_string({:V, y}), do: "V#{format_num(y)}"
  defp command_to_string({:v, dy}), do: "v#{format_num(dy)}"

  defp command_to_string({:C, x1, y1, x2, y2, x, y}) do
    "C#{format_num(x1)},#{format_num(y1)},#{format_num(x2)},#{format_num(y2)},#{format_num(x)},#{format_num(y)}"
  end

  defp command_to_string({:c, dx1, dy1, dx2, dy2, dx, dy}) do
    "c#{format_num(dx1)},#{format_num(dy1)},#{format_num(dx2)},#{format_num(dy2)},#{format_num(dx)},#{format_num(dy)}"
  end

  defp command_to_string({:S, x2, y2, x, y}) do
    "S#{format_num(x2)},#{format_num(y2)},#{format_num(x)},#{format_num(y)}"
  end

  defp command_to_string({:s, dx2, dy2, dx, dy}) do
    "s#{format_num(dx2)},#{format_num(dy2)},#{format_num(dx)},#{format_num(dy)}"
  end

  defp command_to_string({:Q, x1, y1, x, y}) do
    "Q#{format_num(x1)},#{format_num(y1)},#{format_num(x)},#{format_num(y)}"
  end

  defp command_to_string({:q, dx1, dy1, dx, dy}) do
    "q#{format_num(dx1)},#{format_num(dy1)},#{format_num(dx)},#{format_num(dy)}"
  end

  defp command_to_string({:T, x, y}), do: "T#{format_num(x)},#{format_num(y)}"
  defp command_to_string({:t, dx, dy}), do: "t#{format_num(dx)},#{format_num(dy)}"

  defp command_to_string({:A, rx, ry, rot, large, sweep, x, y}) do
    "A#{format_num(rx)},#{format_num(ry)},#{format_num(rot)},#{large},#{sweep},#{format_num(x)},#{format_num(y)}"
  end

  defp command_to_string({:a, rx, ry, rot, large, sweep, dx, dy}) do
    "a#{format_num(rx)},#{format_num(ry)},#{format_num(rot)},#{large},#{sweep},#{format_num(dx)},#{format_num(dy)}"
  end

  defp command_to_string(:Z), do: "Z"

  defp format_num(n), do: format_number(n)

  @doc """
  The number formatter every serialiser shares (D-12, D-32): an integer verbatim; a float
  with at most four decimals, trailing zeros and point trimmed, never in exponent notation,
  and never `-0`.

  ## Examples

      iex> Visualize.IR.Path.format_number(1.5)
      "1.5"
      iex> Visualize.IR.Path.format_number(1.0e20)
      "100000000000000000000"
      iex> Visualize.IR.Path.format_number(-0.00001)
      "0"

  """
  @spec format_number(number()) :: String.t()
  def format_number(n) when is_integer(n), do: Integer.to_string(n)

  def format_number(n) when is_float(n) do
    :erlang.float_to_binary(Float.round(n, 4) + 0.0, decimals: 4)
    |> String.trim_trailing("0")
    |> String.trim_trailing(".")
  end
end
