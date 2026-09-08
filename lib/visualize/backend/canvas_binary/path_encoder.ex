defmodule Visualize.Backend.CanvasBinary.PathEncoder do
  @moduledoc """
  Encodes the path records of the canvas binary format — the point list (`path`,
  `path32`) and the full command stream (`path_cubic`, `path_cubic32`) in either
  coordinate width (spec/09 §4.3, §4.5) — and the number coercion the SVG and IR
  encoders share.
  """

  alias Visualize.Backend.CanvasBinary.Opcodes
  require Opcodes

  @doc false
  # The point list: `count` then one `x y` pair per point, f32 or f64 by the precision.
  def encode_polyline(points, precision) do
    w = bits(precision)

    coords =
      points
      |> Enum.map(fn {x, y} ->
        <<x * 1.0::little-float-size(w), y * 1.0::little-float-size(w)>>
      end)
      |> IO.iodata_to_binary()

    <<polyline_opcode(precision)::8, length(points)::little-32, coords::binary>>
  end

  @doc false
  # The full command stream: `count` then one record per command. The caller expands the
  # smooth curves first (`Visualize.IR.Path.expand_smooth/1`); a command without a
  # sub-opcode is a bug and fails to match rather than encoding to nothing (D-36).
  def encode_cubic_path(commands, precision) do
    w = bits(precision)

    command_data =
      commands
      |> Enum.map(&encode_path_command(&1, w))
      |> IO.iodata_to_binary()

    <<cubic_opcode(precision)::8, length(commands)::little-32, command_data::binary>>
  end

  defp bits(:f32), do: 32
  defp bits(:f64), do: 64

  defp polyline_opcode(:f32), do: Opcodes.path32()
  defp polyline_opcode(:f64), do: Opcodes.path()

  defp cubic_opcode(:f32), do: Opcodes.path_cubic32()
  defp cubic_opcode(:f64), do: Opcodes.path_cubic()

  # One command record: the sub-opcode of spec/09 §4.3.2, then its arguments at `w` bits
  # each (the arc flags stay u32).
  defp encode_path_command({:M, x, y}, w),
    do: <<0x01, x::little-float-size(w), y::little-float-size(w)>>

  defp encode_path_command({:L, x, y}, w),
    do: <<0x02, x::little-float-size(w), y::little-float-size(w)>>

  defp encode_path_command({:C, x1, y1, x2, y2, x, y}, w) do
    <<0x03, x1::little-float-size(w), y1::little-float-size(w), x2::little-float-size(w),
      y2::little-float-size(w), x::little-float-size(w), y::little-float-size(w)>>
  end

  defp encode_path_command({:Q, x1, y1, x, y}, w) do
    <<0x04, x1::little-float-size(w), y1::little-float-size(w), x::little-float-size(w),
      y::little-float-size(w)>>
  end

  defp encode_path_command(:Z, _w), do: <<0x05>>

  # SVG arc: rx, ry, rotation, large_arc, sweep, x, y.
  defp encode_path_command({:A, rx, ry, rotation, large_arc, sweep, x, y}, w) do
    <<0x06, rx::little-float-size(w), ry::little-float-size(w),
      rotation * 1.0::little-float-size(w), large_arc::little-32, sweep::little-32,
      x::little-float-size(w), y::little-float-size(w)>>
  end

  # Relative arc: the decoder resolves the end point against the current point.
  defp encode_path_command({:a, rx, ry, rotation, large_arc, sweep, dx, dy}, w) do
    <<0x07, rx::little-float-size(w), ry::little-float-size(w),
      rotation * 1.0::little-float-size(w), large_arc::little-32, sweep::little-32,
      dx::little-float-size(w), dy::little-float-size(w)>>
  end

  defp encode_path_command({:H, x}, w), do: <<0x08, x::little-float-size(w)>>
  defp encode_path_command({:V, y}, w), do: <<0x09, y::little-float-size(w)>>
  defp encode_path_command({:h, dx}, w), do: <<0x0A, dx::little-float-size(w)>>
  defp encode_path_command({:v, dy}, w), do: <<0x0B, dy::little-float-size(w)>>

  defp encode_path_command({:m, dx, dy}, w),
    do: <<0x0C, dx::little-float-size(w), dy::little-float-size(w)>>

  defp encode_path_command({:l, dx, dy}, w),
    do: <<0x0D, dx::little-float-size(w), dy::little-float-size(w)>>

  defp encode_path_command({:c, dx1, dy1, dx2, dy2, dx, dy}, w) do
    <<0x0E, dx1::little-float-size(w), dy1::little-float-size(w), dx2::little-float-size(w),
      dy2::little-float-size(w), dx::little-float-size(w), dy::little-float-size(w)>>
  end

  defp encode_path_command({:q, dx1, dy1, dx, dy}, w) do
    <<0x0F, dx1::little-float-size(w), dy1::little-float-size(w), dx::little-float-size(w),
      dy::little-float-size(w)>>
  end

  @doc false
  def to_float(n) when is_number(n), do: n * 1.0

  def to_float(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  def to_float(_), do: 0.0
end
