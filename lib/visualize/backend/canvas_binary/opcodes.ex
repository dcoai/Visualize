defmodule Visualize.Backend.CanvasBinary.Opcodes do
  @moduledoc """
  Command bytes of the canvas binary format, shared by every encoder module.

  Macros rather than functions so they are literals inside binary patterns as well
  as binary construction.
  """

  @doc false
  defmacro path, do: 0x01
  @doc false
  defmacro path_cubic, do: 0x02
  @doc false
  defmacro circles, do: 0x03
  @doc false
  defmacro rects, do: 0x04
  @doc false
  defmacro path32, do: 0x05
  @doc false
  defmacro path_cubic32, do: 0x06
  @doc false
  defmacro style, do: 0x10
  @doc false
  defmacro transform, do: 0x20
  @doc false
  defmacro save, do: 0x30
  @doc false
  defmacro restore, do: 0x31
  @doc false
  defmacro fill, do: 0x40
  @doc false
  defmacro stroke, do: 0x41
end
