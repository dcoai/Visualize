defmodule Visualize.SVG.Path do
  @moduledoc """
  SVG path command builder.

  This module provides backward compatibility by delegating to `Visualize.IR.Path`.
  For new code, consider using `Visualize.IR.Path` directly for backend-agnostic
  path construction.

  ## Examples

      iex> alias Visualize.SVG.Path
      iex> Path.new()
      ...> |> Path.move_to(10, 20)
      ...> |> Path.line_to(100, 200)
      ...> |> Path.close()
      ...> |> Path.to_string()
      "M10,20L100,200Z"

  """

  # The struct is now IR.Path, but we keep the SVG.Path name for compatibility
  # by using defdelegate and creating an alias

  alias Visualize.IR.Path, as: IRPath

  @type t :: IRPath.t()
  @type command :: IRPath.command()

  # Delegate all functions to IR.Path
  defdelegate new(), to: IRPath
  defdelegate move_to(path, x, y), to: IRPath
  defdelegate move_to_rel(path, dx, dy), to: IRPath
  defdelegate line_to(path, x, y), to: IRPath
  defdelegate line_to_rel(path, dx, dy), to: IRPath
  defdelegate horizontal_to(path, x), to: IRPath
  defdelegate horizontal_to_rel(path, dx), to: IRPath
  defdelegate vertical_to(path, y), to: IRPath
  defdelegate vertical_to_rel(path, dy), to: IRPath
  defdelegate curve_to(path, x1, y1, x2, y2, x, y), to: IRPath
  defdelegate curve_to_rel(path, dx1, dy1, dx2, dy2, dx, dy), to: IRPath
  defdelegate smooth_curve_to(path, x2, y2, x, y), to: IRPath
  defdelegate smooth_curve_to_rel(path, dx2, dy2, dx, dy), to: IRPath
  defdelegate quad_to(path, x1, y1, x, y), to: IRPath
  defdelegate quad_to_rel(path, dx1, dy1, dx, dy), to: IRPath
  defdelegate smooth_quad_to(path, x, y), to: IRPath
  defdelegate smooth_quad_to_rel(path, dx, dy), to: IRPath
  defdelegate arc_to(path, rx, ry, x_rotation, large_arc, sweep, x, y), to: IRPath
  defdelegate arc_to_rel(path, rx, ry, x_rotation, large_arc, sweep, dx, dy), to: IRPath
  defdelegate close(path), to: IRPath

  # New utility functions from IR.Path
  defdelegate empty?(path), to: IRPath
  defdelegate command_count(path), to: IRPath
  defdelegate concat(paths), to: IRPath
  defdelegate append(path1, path2), to: IRPath
  defdelegate transform(path, transform_fn), to: IRPath

  @doc """
  Converts the path to an SVG path string (the `d` attribute value).

  The one `d` serialisation is `Visualize.IR.Path.to_string/1` (D-12).
  """
  @spec to_string(t()) :: String.t()
  def to_string(%IRPath{} = path), do: IRPath.to_string(path)
end

# String.Chars implementation for backward compatibility
# (IR.Path doesn't have this by default since it's backend-agnostic)
defimpl String.Chars, for: Visualize.IR.Path do
  def to_string(path), do: Visualize.IR.Path.to_string(path)
end
