defmodule Visualize.Backend.CanvasBinary.Opcodes do
  @moduledoc """
  Command bytes of the canvas binary format, shared by every encoder module.

  Macros rather than functions so they are literals inside binary patterns as well
  as binary construction.
  """

  defmacro path, do: 0x01
  defmacro path_cubic, do: 0x02
  defmacro circles, do: 0x03
  defmacro rects, do: 0x04
  defmacro style, do: 0x10
  defmacro transform, do: 0x20
  defmacro save, do: 0x30
  defmacro restore, do: 0x31
  defmacro fill, do: 0x40
  defmacro stroke, do: 0x41
end
