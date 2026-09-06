defmodule Visualize.Backend.CanvasBinary do
  import Bitwise

  @moduledoc """
  Binary encoding for Canvas 2D rendering commands.

  Uses Nx to efficiently encode path and shape data as binary that can be
  transferred to the browser and decoded directly into typed arrays for
  fast Canvas rendering.

  ## Binary Format

  The format uses a simple command-based structure:

  ```
  [header: 1 byte][payload...]

  Header byte meanings:
    0x01 = Path (line data)
    0x02 = Circles
    0x03 = Rectangles
    0x10 = Style block
    0x20 = Transform
  ```

  ### Path format (0x01):
  ```
  [0x01][point_count: u32][x0: f64][y0: f64][x1: f64][y1: f64]...
  ```

  ### Style format (0x10):
  ```
  [0x10][flags: u8][stroke_width: f32][r: u8][g: u8][b: u8][a: u8]...
  ```

  ## Performance

  Binary encoding reduces payload size by ~80% compared to JSON and eliminates
  JSON parsing overhead in the browser. The browser can create Float64Array
  views directly on the binary data.

  ## Requirements

  Requires the `nx` package to be installed.
  """

  alias Visualize.Backend.CanvasBinary.{Opcodes, PathEncoder, SVG}
  alias Visualize.IR.{Element, Path, Transform}
  require Opcodes

  @doc """
  Checks if Nx is available for binary encoding.
  """
  @spec available?() :: boolean()
  def available? do
    Code.ensure_loaded?(Nx)
  end

  @doc """
  Encodes a path element as binary data.

  Returns `{:ok, binary}` on success or `{:error, reason}` if Nx is not available.
  """

  @spec encode_path(Path.t()) :: {:ok, binary()} | {:error, :nx_not_available}
  def encode_path(%Path{commands: commands}) do
    if available?() do
      {:ok, do_encode_path(commands)}
    else
      {:error, :nx_not_available}
    end
  end

  @doc """
  Encodes a path element as binary, raising on error.
  """
  @spec encode_path!(Path.t()) :: binary()
  def encode_path!(%Path{} = path) do
    case encode_path(path) do
      {:ok, binary} -> binary
      {:error, reason} -> raise "Failed to encode path: #{reason}"
    end
  end

  @doc """
  Encodes an element tree as binary data.

  Returns a binary blob that can be sent to the browser and decoded
  by the CanvasBinaryChart JavaScript hook.

  Accepts either Visualize.IR.Element or Visualize.SVG.Element structs.
  """
  @spec encode_element(Element.t() | Visualize.SVG.Element.t()) ::
          {:ok, binary()} | {:error, :nx_not_available}
  def encode_element(%Element{} = element) do
    if available?() do
      {:ok, do_encode_element(element)}
    else
      {:error, :nx_not_available}
    end
  end

  def encode_element(%Visualize.SVG.Element{} = svg_element) do
    if available?() do
      {:ok, SVG.encode_element(svg_element)}
    else
      {:error, :nx_not_available}
    end
  end

  @doc """
  Encodes element, raising on error.
  """
  @spec encode_element!(Element.t() | Visualize.SVG.Element.t()) :: binary()
  def encode_element!(%Element{} = element) do
    case encode_element(element) do
      {:ok, binary} -> binary
      {:error, reason} -> raise "Failed to encode element: #{reason}"
    end
  end

  def encode_element!(%Visualize.SVG.Element{} = svg_element) do
    case encode_element(svg_element) do
      {:ok, binary} -> binary
      {:error, reason} -> raise "Failed to encode SVG element: #{reason}"
    end
  end

  @doc """
  Encodes binary data as base64 for embedding in HTML attributes.
  """
  @spec to_base64(binary()) :: String.t()
  def to_base64(binary) when is_binary(binary) do
    Base.encode64(binary)
  end

  # ============================================================
  # Internal Encoding Functions
  # ============================================================

  defp do_encode_path(commands) do
    # Extract points from path commands
    {points, has_cubic} = extract_path_points(commands)

    if has_cubic do
      PathEncoder.encode_cubic_path(commands)
    else
      encode_simple_path(points)
    end
  end

  defp extract_path_points(commands) do
    {points, has_complex} =
      Enum.reduce(commands, {[], false}, fn cmd, {pts, complex} ->
        case cmd do
          {:M, x, y} -> {[{x, y} | pts], complex}
          {:L, x, y} -> {[{x, y} | pts], complex}
          {:C, _, _, _, _, x, y} -> {[{x, y} | pts], true}
          {:Q, _, _, x, y} -> {[{x, y} | pts], true}
          {:A, _, _, _, _, _, x, y} -> {[{x, y} | pts], true}
          {:a, _, _, _, _, _, _, _} -> {pts, true}
          :Z -> {pts, complex}
          _ -> {pts, complex}
        end
      end)

    {Enum.reverse(points), has_complex}
  end

  defp encode_simple_path(points) do
    count = length(points)

    # Create tensor from points
    coords =
      points
      |> Enum.flat_map(fn {x, y} -> [x, y] end)
      |> Nx.tensor(type: :f64)

    binary = Nx.to_binary(coords)

    # Header: command type + point count
    <<Opcodes.path()::8, count::little-32, binary::binary>>
  end

  defp do_encode_element(%Element{type: :path, path: path, style: style, transform: transform}) do
    parts = []

    # Transform
    parts =
      if transform && transform.operations != [] do
        parts ++ [encode_transform(transform)]
      else
        parts
      end

    # Style
    parts =
      if map_size(style) > 0 do
        parts ++ [encode_style(style)]
      else
        parts
      end

    # Path data
    parts = parts ++ [do_encode_path(path.commands)]

    # Draw commands
    parts = parts ++ encode_draw_commands(style)

    IO.iodata_to_binary(parts)
  end

  defp do_encode_element(%Element{
         type: :circle,
         attrs: attrs,
         style: style,
         transform: transform
       }) do
    %{cx: cx, cy: cy, r: r} = attrs

    parts = []

    parts =
      if transform && transform.operations != [] do
        parts ++ [encode_transform(transform)]
      else
        parts
      end

    parts =
      if map_size(style) > 0 do
        parts ++ [encode_style(style)]
      else
        parts
      end

    # Circle data
    parts =
      parts ++
        [
          <<Opcodes.circles()::8, 1::little-32, cx::little-float-64, cy::little-float-64,
            r::little-float-64>>
        ]

    # Draw commands
    parts = parts ++ encode_draw_commands(style)

    IO.iodata_to_binary(parts)
  end

  defp do_encode_element(%Element{type: :rect, attrs: attrs, style: style, transform: transform}) do
    %{x: x, y: y, width: w, height: h} = attrs

    parts = []

    parts =
      if transform && transform.operations != [] do
        parts ++ [encode_transform(transform)]
      else
        parts
      end

    parts =
      if map_size(style) > 0 do
        parts ++ [encode_style(style)]
      else
        parts
      end

    # Rect data
    parts =
      parts ++
        [
          <<Opcodes.rects()::8, 1::little-32, x::little-float-64, y::little-float-64,
            w::little-float-64, h::little-float-64>>
        ]

    # Draw commands
    parts = parts ++ encode_draw_commands(style)

    IO.iodata_to_binary(parts)
  end

  defp do_encode_element(%Element{type: :group, children: children, transform: transform}) do
    parts = [<<Opcodes.save()::8>>]

    parts =
      if transform && transform.operations != [] do
        parts ++ [encode_transform(transform)]
      else
        parts
      end

    # Encode all children
    child_data = Enum.map(children, &do_encode_element/1)
    parts = parts ++ child_data

    parts = parts ++ [<<Opcodes.restore()::8>>]

    IO.iodata_to_binary(parts)
  end

  defp do_encode_element(%Element{type: :root, children: children}) do
    children
    |> Enum.map(&do_encode_element/1)
    |> IO.iodata_to_binary()
  end

  defp do_encode_element(_element) do
    <<>>
  end

  defp encode_transform(%Transform{operations: ops}) do
    # For now, encode just translate which is most common
    case ops do
      [{:translate, x, y}] ->
        <<Opcodes.transform()::8, 0x01::8, x::little-float-64, y::little-float-64>>

      [{:translate, x, y}, {:scale, sx, sy}] ->
        <<Opcodes.transform()::8, 0x03::8, x::little-float-64, y::little-float-64,
          sx::little-float-64, sy::little-float-64>>

      _ ->
        # General 2D transform matrix
        {a, b, c, d, e, f} = compute_transform_matrix(ops)

        <<Opcodes.transform()::8, 0xFF::8, a::little-float-64, b::little-float-64,
          c::little-float-64, d::little-float-64, e::little-float-64, f::little-float-64>>
    end
  end

  defp compute_transform_matrix(ops) do
    Enum.reduce(ops, {1.0, 0.0, 0.0, 1.0, 0.0, 0.0}, fn op, {a, b, c, d, e, f} ->
      case op do
        {:translate, tx, ty} ->
          {a, b, c, d, e + tx, f + ty}

        {:scale, sx, sy} ->
          {a * sx, b * sy, c * sx, d * sy, e * sx, f * sy}

        {:rotate, angle} ->
          rad = angle * :math.pi() / 180
          cos_a = :math.cos(rad)
          sin_a = :math.sin(rad)

          {a * cos_a + c * sin_a, b * cos_a + d * sin_a, c * cos_a - a * sin_a,
           d * cos_a - b * sin_a, e, f}

        _ ->
          {a, b, c, d, e, f}
      end
    end)
  end

  defp encode_style(style) do
    # Flags: bit 0 = has fill, bit 1 = has stroke, bit 2 = has stroke_width
    flags = 0
    parts = []

    {flags, parts} =
      case style[:fill] do
        nil ->
          {flags, parts}

        :none ->
          {flags, parts}

        color ->
          {r, g, b, a} = parse_color(color)
          {flags ||| 0x01, parts ++ [<<r::8, g::8, b::8, a::8>>]}
      end

    {flags, parts} =
      case style[:stroke] do
        nil ->
          {flags, parts}

        :none ->
          {flags, parts}

        color ->
          {r, g, b, a} = parse_color(color)
          {flags ||| 0x02, parts ++ [<<r::8, g::8, b::8, a::8>>]}
      end

    {flags, parts} =
      case style[:stroke_width] do
        nil -> {flags, parts}
        w -> {flags ||| 0x04, parts ++ [<<w::little-float-32>>]}
      end

    {flags, parts} =
      case style[:opacity] do
        nil -> {flags, parts}
        o -> {flags ||| 0x08, parts ++ [<<o::little-float-32>>]}
      end

    <<Opcodes.style()::8, flags::8>> <> IO.iodata_to_binary(parts)
  end

  defp encode_draw_commands(style) do
    cmds = []

    cmds =
      case style[:fill] do
        nil -> cmds
        :none -> cmds
        _ -> cmds ++ [<<Opcodes.fill()::8>>]
      end

    cmds =
      case style[:stroke] do
        nil -> cmds
        :none -> cmds
        _ -> cmds ++ [<<Opcodes.stroke()::8>>]
      end

    cmds
  end

  defp parse_color(color) when is_binary(color) do
    cond do
      String.starts_with?(color, "#") ->
        parse_hex_color(color)

      String.starts_with?(color, "rgb") ->
        parse_rgb_color(color)

      true ->
        # Named color - default to black
        {0, 0, 0, 255}
    end
  end

  defp parse_color(_), do: {0, 0, 0, 255}

  defp parse_hex_color("#" <> hex) do
    case String.length(hex) do
      3 ->
        <<r::binary-1, g::binary-1, b::binary-1>> = hex

        {String.to_integer(r <> r, 16), String.to_integer(g <> g, 16),
         String.to_integer(b <> b, 16), 255}

      6 ->
        {r, _} = Integer.parse(String.slice(hex, 0, 2), 16)
        {g, _} = Integer.parse(String.slice(hex, 2, 2), 16)
        {b, _} = Integer.parse(String.slice(hex, 4, 2), 16)
        {r, g, b, 255}

      8 ->
        {r, _} = Integer.parse(String.slice(hex, 0, 2), 16)
        {g, _} = Integer.parse(String.slice(hex, 2, 2), 16)
        {b, _} = Integer.parse(String.slice(hex, 4, 2), 16)
        {a, _} = Integer.parse(String.slice(hex, 6, 2), 16)
        {r, g, b, a}

      _ ->
        {0, 0, 0, 255}
    end
  end

  defp parse_rgb_color(color) do
    case Regex.run(~r/rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)/, color) do
      [_, r, g, b] ->
        {String.to_integer(r), String.to_integer(g), String.to_integer(b), 255}

      [_, r, g, b, a] ->
        alpha = (String.to_float(a) * 255) |> round()
        {String.to_integer(r), String.to_integer(g), String.to_integer(b), alpha}

      _ ->
        {0, 0, 0, 255}
    end
  end
end
