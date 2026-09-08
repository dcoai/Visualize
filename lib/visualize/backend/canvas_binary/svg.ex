defmodule Visualize.Backend.CanvasBinary.SVG do
  @moduledoc """
  Encodes `Visualize.SVG.Element` trees into the canvas binary format: element geometry,
  presentation attributes, `transform` strings and `d` path strings.
  """

  import Bitwise

  alias Visualize.Backend.CanvasBinary.{Opcodes, PathEncoder}
  require Opcodes

  # SVG Element Encoding

  @doc false
  def encode_element(%Visualize.SVG.Element{tag: :svg, children: children}, precision) do
    children
    |> Enum.map(&encode_element(&1, precision))
    |> IO.iodata_to_binary()
  end

  def encode_element(%Visualize.SVG.Element{tag: :g, attrs: attrs, children: children}, precision) do
    parts = []

    # Handle transform attribute
    parts =
      case Map.get(attrs, :transform) do
        nil -> parts
        transform_str -> parts ++ [encode_svg_transform(transform_str)]
      end

    # Save context if we have transform
    parts =
      if Map.has_key?(attrs, :transform) do
        [<<Opcodes.save()::8>>] ++ parts
      else
        parts
      end

    # Encode children
    child_data =
      children
      |> Enum.map(&encode_element(&1, precision))
      |> IO.iodata_to_binary()

    parts = parts ++ [child_data]

    # Restore context if we saved
    parts =
      if Map.has_key?(attrs, :transform) do
        parts ++ [<<Opcodes.restore()::8>>]
      else
        parts
      end

    IO.iodata_to_binary(parts)
  end

  def encode_element(%Visualize.SVG.Element{tag: :rect, attrs: attrs}, _precision) do
    x = Map.get(attrs, :x, 0) |> PathEncoder.to_float()
    y = Map.get(attrs, :y, 0) |> PathEncoder.to_float()
    width = Map.get(attrs, :width, 0) |> PathEncoder.to_float()
    height = Map.get(attrs, :height, 0) |> PathEncoder.to_float()

    parts = []

    # Style
    parts = parts ++ [encode_svg_style(attrs)]

    # Rectangle command
    parts =
      parts ++
        [
          <<Opcodes.rects()::8, 1::little-32, x::little-float-64, y::little-float-64,
            width::little-float-64, height::little-float-64>>
        ]

    # Draw commands
    parts = parts ++ encode_svg_draw_commands(attrs)

    IO.iodata_to_binary(parts)
  end

  def encode_element(%Visualize.SVG.Element{tag: :circle, attrs: attrs}, _precision) do
    cx = Map.get(attrs, :cx, 0) |> PathEncoder.to_float()
    cy = Map.get(attrs, :cy, 0) |> PathEncoder.to_float()
    r = Map.get(attrs, :r, 0) |> PathEncoder.to_float()

    parts = []

    # Style
    parts = parts ++ [encode_svg_style(attrs)]

    # Circle command
    parts =
      parts ++
        [
          <<Opcodes.circles()::8, 1::little-32, cx::little-float-64, cy::little-float-64,
            r::little-float-64>>
        ]

    # Draw commands
    parts = parts ++ encode_svg_draw_commands(attrs)

    IO.iodata_to_binary(parts)
  end

  def encode_element(%Visualize.SVG.Element{tag: :path, attrs: attrs}, precision) do
    d = Map.get(attrs, :d, "")

    case parse_svg_path(d) do
      [] ->
        <<>>

      commands ->
        parts = []

        # Style
        parts = parts ++ [encode_svg_style(attrs)]

        # Path data
        parts = parts ++ [PathEncoder.encode_cubic_path(commands, precision)]

        # Draw commands
        parts = parts ++ encode_svg_draw_commands(attrs)

        IO.iodata_to_binary(parts)
    end
  end

  def encode_element(%Visualize.SVG.Element{tag: :line, attrs: attrs}, precision) do
    x1 = Map.get(attrs, :x1, 0) |> PathEncoder.to_float()
    y1 = Map.get(attrs, :y1, 0) |> PathEncoder.to_float()
    x2 = Map.get(attrs, :x2, 0) |> PathEncoder.to_float()
    y2 = Map.get(attrs, :y2, 0) |> PathEncoder.to_float()

    parts = []

    # Style
    parts = parts ++ [encode_svg_style(attrs)]

    # Path as move + line
    commands = [{:M, x1, y1}, {:L, x2, y2}]
    parts = parts ++ [PathEncoder.encode_cubic_path(commands, precision)]

    # Always stroke lines
    parts = parts ++ [<<Opcodes.stroke()::8>>]

    IO.iodata_to_binary(parts)
  end

  def encode_element(%Visualize.SVG.Element{tag: :text}, _precision) do
    # Text not supported in binary canvas format
    <<>>
  end

  def encode_element(_element, _precision) do
    <<>>
  end

  defp encode_svg_style(attrs) do
    fill = Map.get(attrs, :fill)
    stroke = Map.get(attrs, :stroke)
    stroke_width = Map.get(attrs, :stroke_width) || Map.get(attrs, :"stroke-width")

    opacity =
      Map.get(attrs, :opacity) || Map.get(attrs, :fill_opacity) || Map.get(attrs, :"fill-opacity")

    flags = 0
    data = []

    # Fill color (skip if none or not specified)
    {flags, data} =
      if has_color?(fill) do
        {r, g, b, a} = parse_color(fill, opacity)
        {flags ||| 0x01, data ++ [<<r::8, g::8, b::8, a::8>>]}
      else
        {flags, data}
      end

    # Stroke color
    {flags, data} =
      if has_color?(stroke) do
        stroke_opacity =
          Map.get(attrs, :stroke_opacity) || Map.get(attrs, :"stroke-opacity") || 1.0

        {r, g, b, a} = parse_color(stroke, stroke_opacity)
        {flags ||| 0x02, data ++ [<<r::8, g::8, b::8, a::8>>]}
      else
        {flags, data}
      end

    # Stroke width
    {flags, data} =
      if stroke_width do
        sw = PathEncoder.to_float(stroke_width)
        {flags ||| 0x04, data ++ [<<sw::little-float-32>>]}
      else
        {flags, data}
      end

    if flags == 0 do
      <<>>
    else
      IO.iodata_to_binary([<<Opcodes.style()::8, flags::8>> | data])
    end
  end

  defp has_color?(nil), do: false
  defp has_color?(:none), do: false
  defp has_color?("none"), do: false
  defp has_color?(_), do: true

  defp none?(nil), do: true
  defp none?(:none), do: true
  defp none?("none"), do: true
  defp none?(_), do: false

  defp encode_svg_draw_commands(attrs) do
    fill = Map.get(attrs, :fill)
    stroke = Map.get(attrs, :stroke)

    cmds = []
    cmds = if has_color?(fill), do: cmds ++ [<<Opcodes.fill()::8>>], else: cmds
    cmds = if has_color?(stroke), do: cmds ++ [<<Opcodes.stroke()::8>>], else: cmds

    # Default to fill if nothing specified (and not explicitly none)
    if cmds == [] && !none?(fill) do
      [<<Opcodes.fill()::8>>]
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
            <<Opcodes.transform()::8, 0x01::8, x::little-float-64, 0.0::little-float-64>>

          [_, x_str, y_str] ->
            x = parse_number_string(x_str)
            y = parse_number_string(y_str)
            <<Opcodes.transform()::8, 0x01::8, x::little-float-64, y::little-float-64>>

          _ ->
            <<>>
        end

      String.starts_with?(transform_str, "scale(") ->
        case Regex.run(~r/scale\(([-\d.]+),?\s*([-\d.]+)?\)/, transform_str) do
          [_, s_str] ->
            s = parse_number_string(s_str)

            <<Opcodes.transform()::8, 0x03::8, 0.0::little-float-64, 0.0::little-float-64,
              s::little-float-64, s::little-float-64>>

          [_, sx_str, sy_str] ->
            sx = parse_number_string(sx_str)
            sy = parse_number_string(sy_str)

            <<Opcodes.transform()::8, 0x03::8, 0.0::little-float-64, 0.0::little-float-64,
              sx::little-float-64, sy::little-float-64>>

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
      {f, _} ->
        f

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
        {rx, ry, rotation, large_arc, sweep, x, y, rest} =
          parse_arc_numbers(String.slice(str, 1..-1//1))

        parse_path_commands(rest, [{:A, rx, ry, rotation, large_arc, sweep, x, y} | acc])

      String.starts_with?(str, "a") ->
        {rx, ry, rotation, large_arc, sweep, dx, dy, rest} =
          parse_arc_numbers(String.slice(str, 1..-1//1))

        parse_path_commands(rest, [{:a, rx, ry, rotation, large_arc, sweep, dx, dy} | acc])

      String.starts_with?(str, "Z") or String.starts_with?(str, "z") ->
        parse_path_commands(String.slice(str, 1..-1//1), [:Z | acc])

      true ->
        # Try to parse implicit lineto (numbers after moveto)
        case parse_number(str) do
          {nil, _} ->
            Enum.reverse(acc)

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

    {rx || 0, ry || 0, rotation || 0, trunc(large_arc || 0), trunc(sweep || 0), x || 0, y || 0,
     rest}
  end

  defp parse_number(str) do
    str = str |> String.trim_leading() |> String.replace(~r/^,\s*/, "")

    case Regex.run(~r/^(-?[\d.]+(?:e[-+]?\d+)?)/, str) do
      [match, num_str] ->
        num =
          case Float.parse(num_str) do
            {n, _} -> n
            :error -> 0.0
          end

        rest = String.slice(str, String.length(match)..-1//1)
        {num, rest}

      _ ->
        {nil, str}
    end
  end

  defp alpha_byte(nil), do: 255
  defp alpha_byte(n) when is_number(n), do: trunc(n * 255)

  defp alpha_byte(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> trunc(f * 255)
      :error -> 255
    end
  end

  # A colour is parsed by `Visualize.Color.parse/1` (an atom by its name); the supplied
  # opacity is the alpha unless the colour syntax carried its own (`rgba()`, `#rgba`,
  # `#rrggbbaa`). `"none"` is transparent; anything unparseable is black.
  defp parse_color("none", _opacity), do: {0, 0, 0, 0}

  defp parse_color(color, opacity) when is_atom(color),
    do: parse_color(Atom.to_string(color), opacity)

  defp parse_color(color, opacity) when is_binary(color) do
    case Visualize.Color.parse(color) do
      %Visualize.Color{opacity: own} = parsed when own < 1.0 ->
        {r, g, b, _} = Visualize.Color.to_rgba(parsed)
        {r, g, b, trunc(own * 255)}

      %Visualize.Color{} = parsed ->
        {r, g, b, _} = Visualize.Color.to_rgba(parsed)
        {r, g, b, alpha_byte(opacity)}

      nil ->
        {0, 0, 0, alpha_byte(opacity)}
    end
  end
end
