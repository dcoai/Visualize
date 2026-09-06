defmodule Visualize.CanvasBinaryDecoder do
  @moduledoc """
  A decoder for the canvas binary format of spec/09 §4 and §5, written against the record
  layouts the specification states — not against the encoder — so that
  `decode(encode(x))` is a genuine round trip (D-36).

  `decode/1` returns the records of a stream in order:

  - `{:path, [{x, y}]}`, `{:path_cubic, [command]}` with `Visualize.IR.Path` commands
  - `{:circles, [{cx, cy, r}]}`, `{:rects, [{x, y, w, h}]}`
  - `{:style, %{fill:, stroke:, stroke_width:, opacity:}}` (`nil` for an absent field)
  - `{:transform, :translate, {tx, ty}}`, `{:transform, :translate_scale, {tx, ty, sx, sy}}`,
    `{:transform, :matrix, {a, b, c, d, e, f}}`
  - `:save`, `:restore`, `:fill`, `:stroke`
  - `{:incremental, mode, dx, dy, [{{x, y, w, h}, records}]}` and `{:full_redraw, records}`
    for the `0x60` records of `Visualize.Backend.CanvasIncremental`

  An unknown opcode or a truncated record raises, since either is an encoder bug.
  """

  alias Visualize.IR.Path

  @spec decode(binary()) :: [term()]
  def decode(binary), do: decode(binary, [])

  @doc "The one path record of a stream as a `Visualize.IR.Path`."
  @spec decode_path(binary()) :: Path.t()
  def decode_path(binary) do
    case decode(binary) do
      [{:path, [{x, y} | rest]}] ->
        %Path{commands: [{:M, x, y} | Enum.map(rest, fn {lx, ly} -> {:L, lx, ly} end)]}

      [{:path, []}] ->
        %Path{commands: []}

      [{:path_cubic, commands}] ->
        %Path{commands: commands}
    end
  end

  defp decode(<<>>, acc), do: Enum.reverse(acc)

  defp decode(<<0x01, count::little-32, rest::binary>>, acc) do
    {points, rest} = take(rest, count, &point/1)
    decode(rest, [{:path, points} | acc])
  end

  defp decode(<<0x02, count::little-32, rest::binary>>, acc) do
    {commands, rest} = take(rest, count, &command/1)
    decode(rest, [{:path_cubic, commands} | acc])
  end

  defp decode(<<0x03, count::little-32, rest::binary>>, acc) do
    {circles, rest} = take(rest, count, &circle/1)
    decode(rest, [{:circles, circles} | acc])
  end

  defp decode(<<0x04, count::little-32, rest::binary>>, acc) do
    {rects, rest} = take(rest, count, &rect/1)
    decode(rest, [{:rects, rects} | acc])
  end

  defp decode(<<0x10, flags::8, rest::binary>>, acc) do
    import Bitwise
    {fill, rest} = if (flags &&& 0x01) != 0, do: rgba(rest), else: {nil, rest}
    {stroke, rest} = if (flags &&& 0x02) != 0, do: rgba(rest), else: {nil, rest}
    {width, rest} = if (flags &&& 0x04) != 0, do: f32(rest), else: {nil, rest}
    {opacity, rest} = if (flags &&& 0x08) != 0, do: f32(rest), else: {nil, rest}
    style = %{fill: fill, stroke: stroke, stroke_width: width, opacity: opacity}
    decode(rest, [{:style, style} | acc])
  end

  defp decode(<<0x20, 0x01, tx::little-float-64, ty::little-float-64, rest::binary>>, acc),
    do: decode(rest, [{:transform, :translate, {tx, ty}} | acc])

  defp decode(
         <<0x20, 0x03, tx::little-float-64, ty::little-float-64, sx::little-float-64,
           sy::little-float-64, rest::binary>>,
         acc
       ),
       do: decode(rest, [{:transform, :translate_scale, {tx, ty, sx, sy}} | acc])

  defp decode(
         <<0x20, 0xFF, a::little-float-64, b::little-float-64, c::little-float-64,
           d::little-float-64, e::little-float-64, f::little-float-64, rest::binary>>,
         acc
       ),
       do: decode(rest, [{:transform, :matrix, {a, b, c, d, e, f}} | acc])

  defp decode(<<0x30, rest::binary>>, acc), do: decode(rest, [:save | acc])
  defp decode(<<0x31, rest::binary>>, acc), do: decode(rest, [:restore | acc])
  defp decode(<<0x40, rest::binary>>, acc), do: decode(rest, [:fill | acc])
  defp decode(<<0x41, rest::binary>>, acc), do: decode(rest, [:stroke | acc])

  defp decode(<<0x60, 0x00, _dx::little-float-32, _dy::little-float-32, 0, data::binary>>, acc),
    do: Enum.reverse([{:full_redraw, decode(data)} | acc])

  defp decode(
         <<0x60, mode::8, dx::little-float-32, dy::little-float-32, count::8, rest::binary>>,
         acc
       ) do
    {regions, rest} = take(rest, count, &region/1)
    mode = Enum.at([:full_redraw, :scroll_x, :scroll_y, :scroll_xy], mode)
    decode(rest, [{:incremental, mode, dx, dy, regions} | acc])
  end

  defp region(
         <<x::little-float-32, y::little-float-32, w::little-float-32, h::little-float-32,
           length::little-32, data::binary-size(length), rest::binary>>
       ),
       do: {{{x, y, w, h}, decode(data)}, rest}

  defp take(rest, 0, _fun), do: {[], rest}

  defp take(rest, count, fun) do
    {item, rest} = fun.(rest)
    {items, rest} = take(rest, count - 1, fun)
    {[item | items], rest}
  end

  defp point(<<x::little-float-64, y::little-float-64, rest::binary>>), do: {{x, y}, rest}

  defp circle(<<cx::little-float-64, cy::little-float-64, r::little-float-64, rest::binary>>),
    do: {{cx, cy, r}, rest}

  defp rect(
         <<x::little-float-64, y::little-float-64, w::little-float-64, h::little-float-64,
           rest::binary>>
       ),
       do: {{x, y, w, h}, rest}

  defp rgba(<<r::8, g::8, b::8, a::8, rest::binary>>), do: {{r, g, b, a}, rest}
  defp f32(<<v::little-float-32, rest::binary>>), do: {v, rest}

  # The `path_cubic` sub-opcodes of spec/09 §4.3.2.
  defp command(<<0x01, x::little-float-64, y::little-float-64, rest::binary>>),
    do: {{:M, x, y}, rest}

  defp command(<<0x02, x::little-float-64, y::little-float-64, rest::binary>>),
    do: {{:L, x, y}, rest}

  defp command(
         <<0x03, x1::little-float-64, y1::little-float-64, x2::little-float-64,
           y2::little-float-64, x::little-float-64, y::little-float-64, rest::binary>>
       ),
       do: {{:C, x1, y1, x2, y2, x, y}, rest}

  defp command(
         <<0x04, x1::little-float-64, y1::little-float-64, x::little-float-64, y::little-float-64,
           rest::binary>>
       ),
       do: {{:Q, x1, y1, x, y}, rest}

  defp command(<<0x05, rest::binary>>), do: {:Z, rest}

  defp command(
         <<0x06, rx::little-float-64, ry::little-float-64, rot::little-float-64, large::little-32,
           sweep::little-32, x::little-float-64, y::little-float-64, rest::binary>>
       ),
       do: {{:A, rx, ry, rot, large, sweep, x, y}, rest}

  defp command(
         <<0x07, rx::little-float-64, ry::little-float-64, rot::little-float-64, large::little-32,
           sweep::little-32, x::little-float-64, y::little-float-64, rest::binary>>
       ),
       do: {{:a, rx, ry, rot, large, sweep, x, y}, rest}

  defp command(<<0x08, x::little-float-64, rest::binary>>), do: {{:H, x}, rest}
  defp command(<<0x09, y::little-float-64, rest::binary>>), do: {{:V, y}, rest}
  defp command(<<0x0A, x::little-float-64, rest::binary>>), do: {{:h, x}, rest}
  defp command(<<0x0B, y::little-float-64, rest::binary>>), do: {{:v, y}, rest}

  defp command(<<0x0C, x::little-float-64, y::little-float-64, rest::binary>>),
    do: {{:m, x, y}, rest}

  defp command(<<0x0D, x::little-float-64, y::little-float-64, rest::binary>>),
    do: {{:l, x, y}, rest}

  defp command(
         <<0x0E, x1::little-float-64, y1::little-float-64, x2::little-float-64,
           y2::little-float-64, x::little-float-64, y::little-float-64, rest::binary>>
       ),
       do: {{:c, x1, y1, x2, y2, x, y}, rest}

  defp command(
         <<0x0F, x1::little-float-64, y1::little-float-64, x::little-float-64, y::little-float-64,
           rest::binary>>
       ),
       do: {{:q, x1, y1, x, y}, rest}
end
