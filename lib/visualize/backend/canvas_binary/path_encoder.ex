defmodule Visualize.Backend.CanvasBinary.PathEncoder do
  @moduledoc """
  Encodes a full path command stream (`0x02`) for the canvas binary format, and the
  number coercion the SVG and IR encoders share.
  """

  alias Visualize.Backend.CanvasBinary.Opcodes
  require Opcodes

  @doc false
  def encode_cubic_path(commands) do
    # For cubic paths, encode full command stream
    # Format: [cmd_type: u8][args...]
    command_data =
      commands
      |> Enum.map(&encode_path_command/1)
      |> IO.iodata_to_binary()

    cmd_count = length(commands)
    <<Opcodes.path_cubic()::8, cmd_count::little-32, command_data::binary>>
  end

  defp encode_path_command({:M, x, y}) do
    <<0x01::8, x::little-float-64, y::little-float-64>>
  end

  defp encode_path_command({:L, x, y}) do
    <<0x02::8, x::little-float-64, y::little-float-64>>
  end

  defp encode_path_command({:C, x1, y1, x2, y2, x, y}) do
    <<0x03::8, x1::little-float-64, y1::little-float-64, x2::little-float-64, y2::little-float-64,
      x::little-float-64, y::little-float-64>>
  end

  defp encode_path_command({:Q, x1, y1, x, y}) do
    <<0x04::8, x1::little-float-64, y1::little-float-64, x::little-float-64, y::little-float-64>>
  end

  defp encode_path_command(:Z) do
    <<0x05::8>>
  end

  # SVG arc: rx, ry, rotation, large_arc, sweep, x, y
  defp encode_path_command({:A, rx, ry, rotation, large_arc, sweep, x, y}) do
    <<0x06::8, rx::little-float-64, ry::little-float-64, rotation::little-float-64,
      large_arc::little-32, sweep::little-32, x::little-float-64, y::little-float-64>>
  end

  defp encode_path_command({:a, rx, ry, rotation, large_arc, sweep, dx, dy}) do
    # Relative arc - encode as absolute (will need current position tracking on decode)
    <<0x07::8, rx::little-float-64, ry::little-float-64, rotation::little-float-64,
      large_arc::little-32, sweep::little-32, dx::little-float-64, dy::little-float-64>>
  end

  # Horizontal lineto (absolute) - H x
  defp encode_path_command({:H, x}) do
    <<0x08::8, x::little-float-64>>
  end

  # Vertical lineto (absolute) - V y
  defp encode_path_command({:V, y}) do
    <<0x09::8, y::little-float-64>>
  end

  # Horizontal lineto (relative) - h dx
  defp encode_path_command({:h, dx}) do
    <<0x0A::8, dx::little-float-64>>
  end

  # Vertical lineto (relative) - v dy
  defp encode_path_command({:v, dy}) do
    <<0x0B::8, dy::little-float-64>>
  end

  # Relative moveto - m dx dy
  defp encode_path_command({:m, dx, dy}) do
    <<0x0C::8, dx::little-float-64, dy::little-float-64>>
  end

  # Relative lineto - l dx dy
  defp encode_path_command({:l, dx, dy}) do
    <<0x0D::8, dx::little-float-64, dy::little-float-64>>
  end

  # Relative cubic bezier - c
  defp encode_path_command({:c, dx1, dy1, dx2, dy2, dx, dy}) do
    <<0x0E::8, dx1::little-float-64, dy1::little-float-64, dx2::little-float-64,
      dy2::little-float-64, dx::little-float-64, dy::little-float-64>>
  end

  # Relative quadratic bezier - q
  defp encode_path_command({:q, dx1, dy1, dx, dy}) do
    <<0x0F::8, dx1::little-float-64, dy1::little-float-64, dx::little-float-64,
      dy::little-float-64>>
  end

  defp encode_path_command(_), do: <<>>

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
