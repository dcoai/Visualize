defmodule Visualize.PNGPixelsTest do
  @moduledoc """
  The raster tests' PNG reader (spec/12 §6): it decodes an image once, and a pixel is read
  from the decoded image, never from the PNG, so no test can decode per pixel (#732).
  """
  use ExUnit.Case, async: true

  alias Visualize.PNGPixels

  # A two-by-two RGBA PNG, its rows unfiltered and then Sub-filtered, as resvg writes them.
  defp png do
    rows = <<0, 255, 0, 0, 255, 0, 0, 255, 255>> <> <<1, 10, 20, 30, 40, 5, 5, 5, 5>>
    ihdr = <<2::32, 2::32, 8, 6, 0, 0, 0>>

    <<137, 80, 78, 71, 13, 10, 26, 10>> <>
      chunk("IHDR", ihdr) <> chunk("IDAT", :zlib.compress(rows)) <> chunk("IEND", "")
  end

  defp chunk(type, data),
    do: <<byte_size(data)::32, type::binary, data::binary, :erlang.crc32(type <> data)::32>>

  test "a pixel is read from the decoded image, each scanline's filter undone" do
    image = PNGPixels.decode(png())
    assert {2, 2, _pixels} = image
    assert PNGPixels.size(png()) == {2, 2}
    assert PNGPixels.pixel(image, 0, 0) == {255, 0, 0, 255}
    assert PNGPixels.pixel(image, 1, 0) == {0, 0, 255, 255}
    assert PNGPixels.pixel(image, 0, 1) == {10, 20, 30, 40}
    assert PNGPixels.pixel(image, 1, 1) == {15, 25, 35, 45}
  end

  # A PNG passed where the decoded image belongs fails the suite as it compiles: the type
  # checker sees a binary where `pixel/3` takes a tuple, and a warning is an error here.
  test "a point off the image is no pixel" do
    image = PNGPixels.decode(png())
    assert_raise FunctionClauseError, fn -> PNGPixels.pixel(image, 2, 0) end
    assert_raise FunctionClauseError, fn -> PNGPixels.pixel(image, 0, -1) end
  end
end
