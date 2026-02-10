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

  alias Visualize.IR.{Path, Element, Transform}

  # Command type headers
  @cmd_path 0x01
  @cmd_path_cubic 0x02
  @cmd_circles 0x03
  @cmd_rects 0x04
  @cmd_style 0x10
  @cmd_transform 0x20
  @cmd_save 0x30
  @cmd_restore 0x31
  @cmd_fill 0x40
  @cmd_stroke 0x41

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
  @spec encode_element(Element.t() | Visualize.SVG.Element.t()) :: {:ok, binary()} | {:error, :nx_not_available}
  def encode_element(%Element{} = element) do
    if available?() do
      {:ok, do_encode_element(element)}
    else
      {:error, :nx_not_available}
    end
  end

  def encode_element(%Visualize.SVG.Element{} = svg_element) do
    if available?() do
      {:ok, do_encode_svg_element(svg_element)}
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
      encode_cubic_path(commands)
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
    <<@cmd_path::8, count::little-32, binary::binary>>
  end

  defp encode_cubic_path(commands) do
    # For cubic paths, encode full command stream
    # Format: [cmd_type: u8][args...]
    command_data =
      commands
      |> Enum.map(&encode_path_command/1)
      |> IO.iodata_to_binary()

    cmd_count = length(commands)
    <<@cmd_path_cubic::8, cmd_count::little-32, command_data::binary>>
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
    <<0x0E::8, dx1::little-float-64, dy1::little-float-64, dx2::little-float-64, dy2::little-float-64,
      dx::little-float-64, dy::little-float-64>>
  end

  # Relative quadratic bezier - q
  defp encode_path_command({:q, dx1, dy1, dx, dy}) do
    <<0x0F::8, dx1::little-float-64, dy1::little-float-64, dx::little-float-64, dy::little-float-64>>
  end

  defp encode_path_command(_), do: <<>>

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

  defp do_encode_element(%Element{type: :circle, attrs: attrs, style: style, transform: transform}) do
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
    parts = parts ++ [<<@cmd_circles::8, 1::little-32, cx::little-float-64, cy::little-float-64, r::little-float-64>>]

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
    parts = parts ++ [<<@cmd_rects::8, 1::little-32, x::little-float-64, y::little-float-64, w::little-float-64, h::little-float-64>>]

    # Draw commands
    parts = parts ++ encode_draw_commands(style)

    IO.iodata_to_binary(parts)
  end

  defp do_encode_element(%Element{type: :group, children: children, transform: transform}) do
    parts = [<<@cmd_save::8>>]

    parts =
      if transform && transform.operations != [] do
        parts ++ [encode_transform(transform)]
      else
        parts
      end

    # Encode all children
    child_data = Enum.map(children, &do_encode_element/1)
    parts = parts ++ child_data

    parts = parts ++ [<<@cmd_restore::8>>]

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

  # ============================================================
  # SVG Element Encoding
  # ============================================================

  defp do_encode_svg_element(%Visualize.SVG.Element{tag: :svg, children: children}) do
    children
    |> Enum.map(&do_encode_svg_element/1)
    |> IO.iodata_to_binary()
  end

  defp do_encode_svg_element(%Visualize.SVG.Element{tag: :g, attrs: attrs, children: children}) do
    parts = []

    # Handle transform attribute
    parts = case Map.get(attrs, :transform) do
      nil -> parts
      transform_str -> parts ++ [encode_svg_transform(transform_str)]
    end

    # Save context if we have transform
    parts = if Map.has_key?(attrs, :transform) do
      [<<@cmd_save::8>>] ++ parts
    else
      parts
    end

    # Encode children
    child_data = children
    |> Enum.map(&do_encode_svg_element/1)
    |> IO.iodata_to_binary()

    parts = parts ++ [child_data]

    # Restore context if we saved
    parts = if Map.has_key?(attrs, :transform) do
      parts ++ [<<@cmd_restore::8>>]
    else
      parts
    end

    IO.iodata_to_binary(parts)
  end

  defp do_encode_svg_element(%Visualize.SVG.Element{tag: :rect, attrs: attrs}) do
    x = Map.get(attrs, :x, 0) |> to_float()
    y = Map.get(attrs, :y, 0) |> to_float()
    width = Map.get(attrs, :width, 0) |> to_float()
    height = Map.get(attrs, :height, 0) |> to_float()

    parts = []

    # Style
    parts = parts ++ [encode_svg_style(attrs)]

    # Rectangle command
    parts = parts ++ [<<@cmd_rects::8, 1::little-32, x::little-float-64, y::little-float-64,
                       width::little-float-64, height::little-float-64>>]

    # Draw commands
    parts = parts ++ encode_svg_draw_commands(attrs)

    IO.iodata_to_binary(parts)
  end

  defp do_encode_svg_element(%Visualize.SVG.Element{tag: :circle, attrs: attrs}) do
    cx = Map.get(attrs, :cx, 0) |> to_float()
    cy = Map.get(attrs, :cy, 0) |> to_float()
    r = Map.get(attrs, :r, 0) |> to_float()

    parts = []

    # Style
    parts = parts ++ [encode_svg_style(attrs)]

    # Circle command
    parts = parts ++ [<<@cmd_circles::8, 1::little-32, cx::little-float-64, cy::little-float-64, r::little-float-64>>]

    # Draw commands
    parts = parts ++ encode_svg_draw_commands(attrs)

    IO.iodata_to_binary(parts)
  end

  defp do_encode_svg_element(%Visualize.SVG.Element{tag: :path, attrs: attrs}) do
    d = Map.get(attrs, :d, "")

    case parse_svg_path(d) do
      [] -> <<>>
      commands ->
        parts = []

        # Style
        parts = parts ++ [encode_svg_style(attrs)]

        # Path data
        parts = parts ++ [encode_cubic_path(commands)]

        # Draw commands
        parts = parts ++ encode_svg_draw_commands(attrs)

        IO.iodata_to_binary(parts)
    end
  end

  defp do_encode_svg_element(%Visualize.SVG.Element{tag: :line, attrs: attrs}) do
    x1 = Map.get(attrs, :x1, 0) |> to_float()
    y1 = Map.get(attrs, :y1, 0) |> to_float()
    x2 = Map.get(attrs, :x2, 0) |> to_float()
    y2 = Map.get(attrs, :y2, 0) |> to_float()

    parts = []

    # Style
    parts = parts ++ [encode_svg_style(attrs)]

    # Path as move + line
    commands = [{:M, x1, y1}, {:L, x2, y2}]
    parts = parts ++ [encode_cubic_path(commands)]

    # Always stroke lines
    parts = parts ++ [<<@cmd_stroke::8>>]

    IO.iodata_to_binary(parts)
  end

  defp do_encode_svg_element(%Visualize.SVG.Element{tag: :text}) do
    # Text not supported in binary canvas format
    <<>>
  end

  defp do_encode_svg_element(_element) do
    <<>>
  end

  defp encode_svg_style(attrs) do
    fill = Map.get(attrs, :fill)
    stroke = Map.get(attrs, :stroke)
    stroke_width = Map.get(attrs, :stroke_width) || Map.get(attrs, :"stroke-width")
    opacity = Map.get(attrs, :opacity) || Map.get(attrs, :fill_opacity) || Map.get(attrs, :"fill-opacity")

    flags = 0
    data = []

    # Fill color (skip if none or not specified)
    {flags, data} = if has_color?(fill) do
      {r, g, b, a} = parse_color(fill, opacity)
      {flags ||| 0x01, data ++ [<<r::8, g::8, b::8, a::8>>]}
    else
      {flags, data}
    end

    # Stroke color
    {flags, data} = if has_color?(stroke) do
      stroke_opacity = Map.get(attrs, :stroke_opacity) || Map.get(attrs, :"stroke-opacity") || 1.0
      {r, g, b, a} = parse_color(stroke, stroke_opacity)
      {flags ||| 0x02, data ++ [<<r::8, g::8, b::8, a::8>>]}
    else
      {flags, data}
    end

    # Stroke width
    {flags, data} = if stroke_width do
      sw = to_float(stroke_width)
      {flags ||| 0x04, data ++ [<<sw::little-float-32>>]}
    else
      {flags, data}
    end

    if flags == 0 do
      <<>>
    else
      IO.iodata_to_binary([<<@cmd_style::8, flags::8>> | data])
    end
  end

  defp has_color?(nil), do: false
  defp has_color?(:none), do: false
  defp has_color?("none"), do: false
  defp has_color?(_), do: true

  defp is_none?(nil), do: true
  defp is_none?(:none), do: true
  defp is_none?("none"), do: true
  defp is_none?(_), do: false

  defp encode_svg_draw_commands(attrs) do
    fill = Map.get(attrs, :fill)
    stroke = Map.get(attrs, :stroke)

    cmds = []
    cmds = if has_color?(fill), do: cmds ++ [<<@cmd_fill::8>>], else: cmds
    cmds = if has_color?(stroke), do: cmds ++ [<<@cmd_stroke::8>>], else: cmds

    # Default to fill if nothing specified (and not explicitly none)
    if cmds == [] && !is_none?(fill) do
      [<<@cmd_fill::8>>]
    else
      cmds
    end
  end

  defp encode_svg_transform(transform_str) when is_binary(transform_str) do
    cond do
      String.starts_with?(transform_str, "translate(") ->
        case Regex.run(~r/translate\(([-\d.]+),?\s*([-\d.]+)?\)/, transform_str) do
          [_, x_str] ->
            x = parse_number_string(x_str)
            <<@cmd_transform::8, 0x01::8, x::little-float-64, 0.0::little-float-64>>
          [_, x_str, y_str] ->
            x = parse_number_string(x_str)
            y = parse_number_string(y_str)
            <<@cmd_transform::8, 0x01::8, x::little-float-64, y::little-float-64>>
          _ ->
            <<>>
        end

      String.starts_with?(transform_str, "scale(") ->
        case Regex.run(~r/scale\(([-\d.]+),?\s*([-\d.]+)?\)/, transform_str) do
          [_, s_str] ->
            s = parse_number_string(s_str)
            <<@cmd_transform::8, 0x03::8, 0.0::little-float-64, 0.0::little-float-64, s::little-float-64, s::little-float-64>>
          [_, sx_str, sy_str] ->
            sx = parse_number_string(sx_str)
            sy = parse_number_string(sy_str)
            <<@cmd_transform::8, 0x03::8, 0.0::little-float-64, 0.0::little-float-64, sx::little-float-64, sy::little-float-64>>
          _ ->
            <<>>
        end

      true ->
        <<>>
    end
  end

  defp encode_svg_transform(_), do: <<>>

  defp parse_number_string(str) do
    case Float.parse(str) do
      {f, _} -> f
      :error ->
        case Integer.parse(str) do
          {i, _} -> i * 1.0
          :error -> 0.0
        end
    end
  end

  defp parse_svg_path(""), do: []
  defp parse_svg_path(d) when is_binary(d) do
    # Simple SVG path parser
    d
    |> String.trim()
    |> parse_path_commands([])
  end

  defp parse_path_commands("", acc), do: Enum.reverse(acc)
  defp parse_path_commands(str, acc) do
    str = String.trim_leading(str)

    cond do
      str == "" ->
        Enum.reverse(acc)

      String.starts_with?(str, "M") ->
        {x, y, rest} = parse_two_numbers(String.slice(str, 1..-1//1))
        parse_path_commands(rest, [{:M, x, y} | acc])

      String.starts_with?(str, "m") ->
        {dx, dy, rest} = parse_two_numbers(String.slice(str, 1..-1//1))
        parse_path_commands(rest, [{:m, dx, dy} | acc])

      String.starts_with?(str, "L") ->
        {x, y, rest} = parse_two_numbers(String.slice(str, 1..-1//1))
        parse_path_commands(rest, [{:L, x, y} | acc])

      String.starts_with?(str, "l") ->
        {dx, dy, rest} = parse_two_numbers(String.slice(str, 1..-1//1))
        parse_path_commands(rest, [{:l, dx, dy} | acc])

      String.starts_with?(str, "H") ->
        {x, rest} = parse_one_number(String.slice(str, 1..-1//1))
        parse_path_commands(rest, [{:H, x} | acc])

      String.starts_with?(str, "h") ->
        {dx, rest} = parse_one_number(String.slice(str, 1..-1//1))
        parse_path_commands(rest, [{:h, dx} | acc])

      String.starts_with?(str, "V") ->
        {y, rest} = parse_one_number(String.slice(str, 1..-1//1))
        parse_path_commands(rest, [{:V, y} | acc])

      String.starts_with?(str, "v") ->
        {dy, rest} = parse_one_number(String.slice(str, 1..-1//1))
        parse_path_commands(rest, [{:v, dy} | acc])

      String.starts_with?(str, "C") ->
        {x1, y1, x2, y2, x, y, rest} = parse_six_numbers(String.slice(str, 1..-1//1))
        parse_path_commands(rest, [{:C, x1, y1, x2, y2, x, y} | acc])

      String.starts_with?(str, "c") ->
        {dx1, dy1, dx2, dy2, dx, dy, rest} = parse_six_numbers(String.slice(str, 1..-1//1))
        parse_path_commands(rest, [{:c, dx1, dy1, dx2, dy2, dx, dy} | acc])

      String.starts_with?(str, "Q") ->
        {x1, y1, x, y, rest} = parse_four_numbers(String.slice(str, 1..-1//1))
        parse_path_commands(rest, [{:Q, x1, y1, x, y} | acc])

      String.starts_with?(str, "q") ->
        {dx1, dy1, dx, dy, rest} = parse_four_numbers(String.slice(str, 1..-1//1))
        parse_path_commands(rest, [{:q, dx1, dy1, dx, dy} | acc])

      String.starts_with?(str, "A") ->
        {rx, ry, rotation, large_arc, sweep, x, y, rest} = parse_arc_numbers(String.slice(str, 1..-1//1))
        parse_path_commands(rest, [{:A, rx, ry, rotation, large_arc, sweep, x, y} | acc])

      String.starts_with?(str, "a") ->
        {rx, ry, rotation, large_arc, sweep, dx, dy, rest} = parse_arc_numbers(String.slice(str, 1..-1//1))
        parse_path_commands(rest, [{:a, rx, ry, rotation, large_arc, sweep, dx, dy} | acc])

      String.starts_with?(str, "Z") or String.starts_with?(str, "z") ->
        parse_path_commands(String.slice(str, 1..-1//1), [:Z | acc])

      true ->
        # Try to parse implicit lineto (numbers after moveto)
        case parse_number(str) do
          {nil, _} -> Enum.reverse(acc)
          {x, rest} ->
            {y, rest2} = parse_one_number(rest)
            parse_path_commands(rest2, [{:L, x, y} | acc])
        end
    end
  end

  defp parse_one_number(str) do
    {n, rest} = parse_number(String.trim_leading(str))
    {n || 0, rest}
  end

  defp parse_two_numbers(str) do
    {x, rest} = parse_number(String.trim_leading(str))
    {y, rest2} = parse_number(String.trim_leading(rest))
    {x || 0, y || 0, rest2}
  end

  defp parse_four_numbers(str) do
    {a, rest} = parse_number(String.trim_leading(str))
    {b, rest} = parse_number(String.trim_leading(rest))
    {c, rest} = parse_number(String.trim_leading(rest))
    {d, rest} = parse_number(String.trim_leading(rest))
    {a || 0, b || 0, c || 0, d || 0, rest}
  end

  defp parse_six_numbers(str) do
    {a, rest} = parse_number(String.trim_leading(str))
    {b, rest} = parse_number(String.trim_leading(rest))
    {c, rest} = parse_number(String.trim_leading(rest))
    {d, rest} = parse_number(String.trim_leading(rest))
    {e, rest} = parse_number(String.trim_leading(rest))
    {f, rest} = parse_number(String.trim_leading(rest))
    {a || 0, b || 0, c || 0, d || 0, e || 0, f || 0, rest}
  end

  defp parse_arc_numbers(str) do
    {rx, rest} = parse_number(String.trim_leading(str))
    {ry, rest} = parse_number(String.trim_leading(rest))
    {rotation, rest} = parse_number(String.trim_leading(rest))
    {large_arc, rest} = parse_number(String.trim_leading(rest))
    {sweep, rest} = parse_number(String.trim_leading(rest))
    {x, rest} = parse_number(String.trim_leading(rest))
    {y, rest} = parse_number(String.trim_leading(rest))
    {rx || 0, ry || 0, rotation || 0, trunc(large_arc || 0), trunc(sweep || 0), x || 0, y || 0, rest}
  end

  defp parse_number(str) do
    str = str |> String.trim_leading() |> String.replace(~r/^,\s*/, "")
    case Regex.run(~r/^(-?[\d.]+(?:e[-+]?\d+)?)/, str) do
      [match, num_str] ->
        num = case Float.parse(num_str) do
          {n, _} -> n
          :error -> 0.0
        end
        rest = String.slice(str, String.length(match)..-1//1)
        {num, rest}
      _ ->
        {nil, str}
    end
  end

  defp to_float(n) when is_number(n), do: n * 1.0
  defp to_float(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> 0.0
    end
  end
  defp to_float(_), do: 0.0

  defp parse_color(color, opacity) when is_atom(color) do
    # Handle atom colors like :current_color, :black, etc.
    case color do
      :current_color -> {0, 0, 0, 255}  # Default to black for currentColor
      :black -> {0, 0, 0, 255}
      :white -> {255, 255, 255, 255}
      :red -> {255, 0, 0, 255}
      :green -> {0, 128, 0, 255}
      :blue -> {0, 0, 255, 255}
      _ -> {0, 0, 0, 255}
    end
  end

  defp parse_color(color, opacity) when is_binary(color) do
    opacity = case opacity do
      nil -> 1.0
      n when is_number(n) -> n
      s when is_binary(s) ->
        case Float.parse(s) do
          {f, _} -> f
          :error -> 1.0
        end
    end

    a = trunc(opacity * 255)

    cond do
      String.starts_with?(color, "#") && String.length(color) == 7 ->
        <<r::8, g::8, b::8>> = Base.decode16!(String.slice(color, 1..-1//1), case: :mixed)
        {r, g, b, a}

      String.starts_with?(color, "#") && String.length(color) == 4 ->
        [r, g, b] = String.slice(color, 1..-1//1)
                    |> String.graphemes()
                    |> Enum.map(fn c ->
          <<v::8>> = Base.decode16!(c <> c, case: :mixed)
          v
        end)
        {r, g, b, a}

      String.starts_with?(color, "rgb(") ->
        case Regex.run(~r/rgb\((\d+),\s*(\d+),\s*(\d+)\)/, color) do
          [_, r, g, b] ->
            {String.to_integer(r), String.to_integer(g), String.to_integer(b), a}
          _ ->
            {0, 0, 0, a}
        end

      String.starts_with?(color, "rgba(") ->
        case Regex.run(~r/rgba\((\d+),\s*(\d+),\s*(\d+),\s*([\d.]+)\)/, color) do
          [_, r, g, b, alpha] ->
            {alpha_f, _} = Float.parse(alpha)
            {String.to_integer(r), String.to_integer(g), String.to_integer(b), trunc(alpha_f * 255)}
          _ ->
            {0, 0, 0, a}
        end

      true ->
        # Named colors (basic support)
        case color do
          "black" -> {0, 0, 0, a}
          "white" -> {255, 255, 255, a}
          "red" -> {255, 0, 0, a}
          "green" -> {0, 128, 0, a}
          "blue" -> {0, 0, 255, a}
          "none" -> {0, 0, 0, 0}
          _ -> {0, 0, 0, a}
        end
    end
  end

  defp encode_transform(%Transform{operations: ops}) do
    # For now, encode just translate which is most common
    case ops do
      [{:translate, x, y}] ->
        <<@cmd_transform::8, 0x01::8, x::little-float-64, y::little-float-64>>

      [{:translate, x, y}, {:scale, sx, sy}] ->
        <<@cmd_transform::8, 0x03::8, x::little-float-64, y::little-float-64, sx::little-float-64, sy::little-float-64>>

      _ ->
        # General 2D transform matrix
        {a, b, c, d, e, f} = compute_transform_matrix(ops)
        <<@cmd_transform::8, 0xFF::8, a::little-float-64, b::little-float-64, c::little-float-64,
          d::little-float-64, e::little-float-64, f::little-float-64>>
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
          {a * cos_a + c * sin_a, b * cos_a + d * sin_a,
           c * cos_a - a * sin_a, d * cos_a - b * sin_a, e, f}

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
        nil -> {flags, parts}
        :none -> {flags, parts}
        color ->
          {r, g, b, a} = parse_color(color)
          {flags ||| 0x01, parts ++ [<<r::8, g::8, b::8, a::8>>]}
      end

    {flags, parts} =
      case style[:stroke] do
        nil -> {flags, parts}
        :none -> {flags, parts}
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

    <<@cmd_style::8, flags::8>> <> IO.iodata_to_binary(parts)
  end

  defp encode_draw_commands(style) do
    cmds = []

    cmds =
      case style[:fill] do
        nil -> cmds
        :none -> cmds
        _ -> cmds ++ [<<@cmd_fill::8>>]
      end

    cmds =
      case style[:stroke] do
        nil -> cmds
        :none -> cmds
        _ -> cmds ++ [<<@cmd_stroke::8>>]
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
        alpha = String.to_float(a) * 255 |> round()
        {String.to_integer(r), String.to_integer(g), String.to_integer(b), alpha}

      _ ->
        {0, 0, 0, 255}
    end
  end
end
