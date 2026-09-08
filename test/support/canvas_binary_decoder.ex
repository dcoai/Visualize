defmodule Visualize.CanvasBinaryDecoder do
  @moduledoc """
  A decoder for the canvas binary format of spec/09 §4 and §5, written against the record
  layouts the specification states — not against the encoder — so that
  `decode(encode(x))` is a genuine round trip (D-36).

  `decode/1` returns the records of a stream in order:

  - `{:path, [{x, y}]}`, `{:path_cubic, [command]}` with `Visualize.IR.Path` commands, and
    `{:path32, [{x, y}]}`, `{:path_cubic32, [command]}` for the f32 records (D-73), and
    `{:cubic_run, {x0, y0}, [{x1, y1, x2, y2, x, y}]}` for the cubic run (D-74)
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

      [{:path32, [{x, y} | rest]}] ->
        %Path{commands: [{:M, x, y} | Enum.map(rest, fn {lx, ly} -> {:L, lx, ly} end)]}

      [{:path32, []}] ->
        %Path{commands: []}

      [{:path_cubic, commands}] ->
        %Path{commands: commands}

      [{:path_cubic32, commands}] ->
        %Path{commands: commands}

      [{:cubic_run, {x0, y0}, curves}] ->
        %Path{
          commands: [
            {:M, x0, y0}
            | Enum.map(curves, fn {x1, y1, x2, y2, x, y} -> {:C, x1, y1, x2, y2, x, y} end)
          ]
        }
    end
  end

  defp decode(<<>>, acc), do: Enum.reverse(acc)

  defp decode(<<0x01, count::little-32, rest::binary>>, acc) do
    {points, rest} = take(rest, count, &point(64, &1))
    decode(rest, [{:path, points} | acc])
  end

  defp decode(<<0x02, count::little-32, rest::binary>>, acc) do
    {commands, rest} = take(rest, count, &command(64, &1))
    decode(rest, [{:path_cubic, commands} | acc])
  end

  # The f32 records (spec/09 §4.3.8–4.3.9): the same layouts at 32 bits a coordinate.
  defp decode(<<0x05, count::little-32, rest::binary>>, acc) do
    {points, rest} = take(rest, count, &point(32, &1))
    decode(rest, [{:path32, points} | acc])
  end

  defp decode(<<0x06, count::little-32, rest::binary>>, acc) do
    {commands, rest} = take(rest, count, &command(32, &1))
    decode(rest, [{:path_cubic32, commands} | acc])
  end

  # The cubic run (spec/09 §4.3.10): the start point, then six f32 per curve.
  defp decode(<<0x07, count::little-32, rest::binary>>, acc) do
    {start, rest} = point(32, rest)
    {curves, rest} = take(rest, count, &curve/1)
    decode(rest, [{:cubic_run, start, curves} | acc])
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

  defp curve(rest) do
    {[x1, y1, x2, y2, x, y], rest} = floats(32, rest, 6)
    {{x1, y1, x2, y2, x, y}, rest}
  end

  defp point(w, rest) do
    {[x, y], rest} = floats(w, rest, 2)
    {{x, y}, rest}
  end

  defp circle(<<cx::little-float-64, cy::little-float-64, r::little-float-64, rest::binary>>),
    do: {{cx, cy, r}, rest}

  defp rect(
         <<x::little-float-64, y::little-float-64, w::little-float-64, h::little-float-64,
           rest::binary>>
       ),
       do: {{x, y, w, h}, rest}

  defp rgba(<<r::8, g::8, b::8, a::8, rest::binary>>), do: {{r, g, b, a}, rest}
  defp f32(<<v::little-float-32, rest::binary>>), do: {v, rest}

  # The sub-opcodes of spec/09 §4.3.2 with their IR command and the count of float
  # arguments, each `w` bits wide (64 for `path_cubic`, 32 for `path_cubic32`, §4.3.9).
  # `Z` has none and the arcs carry two u32 flags between their floats.
  @commands %{
    0x01 => {:M, 2},
    0x02 => {:L, 2},
    0x03 => {:C, 6},
    0x04 => {:Q, 4},
    0x08 => {:H, 1},
    0x09 => {:V, 1},
    0x0A => {:h, 1},
    0x0B => {:v, 1},
    0x0C => {:m, 2},
    0x0D => {:l, 2},
    0x0E => {:c, 6},
    0x0F => {:q, 4}
  }

  defp command(_w, <<0x05, rest::binary>>), do: {:Z, rest}

  defp command(w, <<arc, rest::binary>>) when arc in [0x06, 0x07] do
    {[rx, ry, rot], rest} = floats(w, rest, 3)
    <<large::little-32, sweep::little-32, rest::binary>> = rest
    {[x, y], rest} = floats(w, rest, 2)
    tag = if arc == 0x06, do: :A, else: :a
    {{tag, rx, ry, rot, large, sweep, x, y}, rest}
  end

  defp command(w, <<sub, rest::binary>>) do
    {tag, arity} = Map.fetch!(@commands, sub)
    {args, rest} = floats(w, rest, arity)
    {List.to_tuple([tag | args]), rest}
  end

  defp floats(_w, rest, 0), do: {[], rest}

  defp floats(w, rest, count) do
    <<v::little-float-size(^w), rest::binary>> = rest
    {values, rest} = floats(w, rest, count - 1)
    {[v | values], rest}
  end
end
