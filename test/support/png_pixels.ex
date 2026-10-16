defmodule Visualize.PNGPixels do
  @moduledoc """
  Decodes the PNGs `Visualize.Render.to_png/2` writes — 8-bit RGBA, not interlaced — to
  their pixels, for the raster tests and goldens (spec/12 §6): the `IDAT` data inflated
  and each scanline's filter undone (PNG §9). Test support only.
  """

  @signature <<137, 80, 78, 71, 13, 10, 26, 10>>

  @doc "The width and height in a PNG's `IHDR` chunk, which follows the signature directly."
  @spec size(binary()) :: {pos_integer(), pos_integer()}
  def size(<<@signature, _len::32, "IHDR", w::32, h::32, _::binary>>), do: {w, h}

  @doc "`{width, height, pixels}`, `pixels` the rows top to bottom, four bytes a pixel."
  @spec decode(binary()) :: {pos_integer(), pos_integer(), binary()}
  def decode(<<@signature, rest::binary>> = png) do
    {w, h} = size(png)
    <<_::32, "IHDR", _::64, 8, 6, 0, 0, 0, _::binary>> = rest
    data = :zlib.uncompress(for {"IDAT", chunk} <- chunks(rest), into: "", do: chunk)
    stride = w * 4
    {rows, _prior} = unfilter_rows(data, stride, :binary.copy(<<0>>, stride), [])
    {w, h, IO.iodata_to_binary(rows)}
  end

  @doc """
  One `{r, g, b, a}` pixel of an image `decode/1` returned. It takes the decoded image and
  never the PNG, so a test that samples many pixels decodes once (#732): decoding per read
  made a sampling test cost its sample count in whole-image decodes.
  """
  @spec pixel({pos_integer(), pos_integer(), binary()}, non_neg_integer(), non_neg_integer()) ::
          {byte(), byte(), byte(), byte()}
  def pixel({w, h, pixels}, x, y)
      when is_binary(pixels) and x in 0..(w - 1)//1 and y in 0..(h - 1)//1 do
    <<r, g, b, a>> = binary_part(pixels, (y * w + x) * 4, 4)
    {r, g, b, a}
  end

  @doc """
  The count of pixels of two equal-sized pixel binaries with any channel further apart than
  `tolerance`.
  """
  @spec differing(binary(), binary(), non_neg_integer()) :: non_neg_integer()
  def differing(a, b, tolerance) when byte_size(a) == byte_size(b),
    do: differing(a, b, tolerance, 0)

  defp differing(<<>>, <<>>, _tolerance, count), do: count

  defp differing(<<r1, g1, b1, a1, ra::binary>>, <<r2, g2, b2, a2, rb::binary>>, t, count) do
    far = abs(r1 - r2) > t or abs(g1 - g2) > t or abs(b1 - b2) > t or abs(a1 - a2) > t
    differing(ra, rb, t, if(far, do: count + 1, else: count))
  end

  defp chunks(<<>>), do: []

  defp chunks(<<len::32, type::binary-4, data::binary-size(len), _crc::32, rest::binary>>),
    do: [{type, data} | chunks(rest)]

  defp unfilter_rows(<<>>, _stride, prior, rows), do: {Enum.reverse(rows), prior}

  defp unfilter_rows(data, stride, prior, rows) do
    <<filter, line::binary-size(^stride), rest::binary>> = data
    row = unfilter(filter, line, prior, 0, <<>>)
    unfilter_rows(rest, stride, row, [row | rows])
  end

  # `out` is the row decoded so far; `a` is its byte four back, `b` the row above's byte
  # and `c` the row above's byte four back.
  defp unfilter(_filter, <<>>, _prior, _i, out), do: out

  defp unfilter(filter, <<byte, rest::binary>>, prior, i, out) do
    a = if i >= 4, do: :binary.at(out, i - 4), else: 0
    b = :binary.at(prior, i)
    c = if i >= 4, do: :binary.at(prior, i - 4), else: 0
    value = rem(byte + predict(filter, a, b, c), 256)
    unfilter(filter, rest, prior, i + 1, <<out::binary, value>>)
  end

  defp predict(0, _a, _b, _c), do: 0
  defp predict(1, a, _b, _c), do: a
  defp predict(2, _a, b, _c), do: b
  defp predict(3, a, b, _c), do: div(a + b, 2)

  defp predict(4, a, b, c) do
    p = a + b - c
    {pa, pb, pc} = {abs(p - a), abs(p - b), abs(p - c)}

    cond do
      pa <= pb and pa <= pc -> a
      pb <= pc -> b
      true -> c
    end
  end
end
