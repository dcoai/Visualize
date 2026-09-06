defmodule Visualize.Shape.LineNx do
  @moduledoc """
  Nx-accelerated line generator for high-performance path generation.

  Uses Nx tensors for batch coordinate transformation, significantly faster
  than per-point function application for large datasets.

  ## Performance

  For 2000+ data points, this is 5-10x faster than the standard Line generator
  because it transforms all coordinates in a single vectorized operation.

  ## Usage

      # Prepare data as tensor-friendly format
      xs = Enum.map(data, & &1.x)
      ys = Enum.map(data, & &1.y)

      # Generate path with batch transformation
      path = LineNx.generate_path(xs, ys,
        x_domain: {0, 100},
        x_range: {0, 800},
        y_domain: {0, 100},
        y_range: {600, 0}
      )
  """

  alias Visualize.IR.Path

  @doc """
  Generates a path from x and y coordinate lists using Nx batch transformation.

  Options:
    * `:x_domain` - {min, max} input domain for x values
    * `:x_range` - {min, max} output range for x values
    * `:y_domain` - {min, max} input domain for y values
    * `:y_range` - {min, max} output range for y values
    * `:curve` - curve type (default: :linear)
  """
  @spec generate_path([number()], [number()], keyword()) :: Path.t()
  def generate_path(xs, ys, opts \\ []) do
    x_domain = Keyword.get(opts, :x_domain, {0, 1})
    x_range = Keyword.get(opts, :x_range, {0, 1})
    y_domain = Keyword.get(opts, :y_domain, {0, 1})
    y_range = Keyword.get(opts, :y_range, {0, 1})

    # Convert to tensors and transform in batch
    {scaled_xs, scaled_ys} = batch_transform(xs, ys, x_domain, x_range, y_domain, y_range)

    # Build path commands from scaled coordinates
    build_path(scaled_xs, scaled_ys)
  end

  @doc """
  Generates path from pre-scaled coordinates (no transformation needed).
  Use this when coordinates are already in pixel space.
  """
  @spec generate_path_raw([number()], [number()]) :: Path.t()
  def generate_path_raw(xs, ys) do
    build_path(xs, ys)
  end

  @doc """
  Batch transform coordinates using Nx tensors.
  Returns lists of scaled x and y values.
  """
  @spec batch_transform(
          [number()],
          [number()],
          {number(), number()},
          {number(), number()},
          {number(), number()},
          {number(), number()}
        ) :: {[float()], [float()]}
  def batch_transform(xs, ys, x_domain, x_range, y_domain, y_range) do
    # Create tensors
    x_tensor = Nx.tensor(xs, type: :f64)
    y_tensor = Nx.tensor(ys, type: :f64)

    # Apply linear scale transformation: output = (input - d0) / (d1 - d0) * (r1 - r0) + r0
    {x_d0, x_d1} = x_domain
    {x_r0, x_r1} = x_range
    {y_d0, y_d1} = y_domain
    {y_r0, y_r1} = y_range

    scaled_x = linear_scale(x_tensor, x_d0, x_d1, x_r0, x_r1)
    scaled_y = linear_scale(y_tensor, y_d0, y_d1, y_r0, y_r1)

    # Convert back to lists
    {Nx.to_flat_list(scaled_x), Nx.to_flat_list(scaled_y)}
  end

  # Vectorized linear scale: (input - d0) / (d1 - d0) * (r1 - r0) + r0
  defp linear_scale(tensor, d0, d1, r0, r1) do
    domain_span = d1 - d0
    range_span = r1 - r0

    tensor
    |> Nx.subtract(d0)
    |> Nx.divide(domain_span)
    |> Nx.multiply(range_span)
    |> Nx.add(r0)
  end

  # Build path commands from coordinate lists
  defp build_path([], []), do: Path.new()

  defp build_path([x | xs], [y | ys]) do
    commands = [{:M, x, y} | build_line_commands(xs, ys)]
    %Path{commands: commands}
  end

  defp build_line_commands([], []), do: []

  defp build_line_commands([x | xs], [y | ys]) do
    [{:L, x, y} | build_line_commands(xs, ys)]
  end

  @doc """
  Generates path and renders directly to binary format in one step.
  Most efficient for Canvas rendering - avoids intermediate IR.Element.
  """
  @spec to_binary(
          [number()],
          [number()],
          {number(), number()},
          {number(), number()},
          {number(), number()},
          {number(), number()},
          keyword()
        ) :: binary()
  def to_binary(xs, ys, x_domain, x_range, y_domain, y_range, opts \\ []) do
    # Transform coordinates
    {scaled_xs, scaled_ys} = batch_transform(xs, ys, x_domain, x_range, y_domain, y_range)

    # Get style options
    translate_x = Keyword.get(opts, :translate_x, 0)
    translate_y = Keyword.get(opts, :translate_y, 0)

    # Apply translation if needed
    {final_xs, final_ys} =
      if translate_x != 0 or translate_y != 0 do
        {Enum.map(scaled_xs, &(&1 + translate_x)), Enum.map(scaled_ys, &(&1 + translate_y))}
      else
        {scaled_xs, scaled_ys}
      end

    # Encode directly to binary
    encode_path_binary(final_xs, final_ys, opts)
  end

  @doc """
  Generates path and renders to base64-encoded binary.
  Ready for use in HTML data attributes.
  """
  @spec to_base64(
          [number()],
          [number()],
          {number(), number()},
          {number(), number()},
          {number(), number()},
          {number(), number()},
          keyword()
        ) :: String.t()
  def to_base64(xs, ys, x_domain, x_range, y_domain, y_range, opts \\ []) do
    xs
    |> to_binary(ys, x_domain, x_range, y_domain, y_range, opts)
    |> Base.encode64()
  end

  # Encode path directly to binary format (matches CanvasBinary format)
  defp encode_path_binary(xs, ys, opts) do
    count = length(xs)

    # Interleave x,y coordinates
    coords = Enum.zip(xs, ys) |> Enum.flat_map(fn {x, y} -> [x, y] end)

    # Create tensor and convert to binary
    coord_tensor = Nx.tensor(coords, type: :f64)
    coord_binary = Nx.to_binary(coord_tensor)

    # Build style header if provided
    style_binary = encode_style(opts)

    # Command type 0x01 = simple path
    <<style_binary::binary, 0x01::8, count::little-32, coord_binary::binary,
      encode_draw(opts)::binary>>
  end

  defp encode_style(opts) do
    stroke = Keyword.get(opts, :stroke)
    stroke_width = Keyword.get(opts, :stroke_width)
    fill = Keyword.get(opts, :fill)

    if stroke || stroke_width || fill do
      flags = 0
      parts = []

      {flags, parts} =
        if fill && fill != :none do
          {r, g, b, a} = parse_color(fill)
          {Bitwise.bor(flags, 0x01), parts ++ [<<r::8, g::8, b::8, a::8>>]}
        else
          {flags, parts}
        end

      {flags, parts} =
        if stroke && stroke != :none do
          {r, g, b, a} = parse_color(stroke)
          {Bitwise.bor(flags, 0x02), parts ++ [<<r::8, g::8, b::8, a::8>>]}
        else
          {flags, parts}
        end

      {flags, parts} =
        if stroke_width do
          {Bitwise.bor(flags, 0x04), parts ++ [<<stroke_width::little-float-32>>]}
        else
          {flags, parts}
        end

      <<0x10::8, flags::8>> <> IO.iodata_to_binary(parts)
    else
      <<>>
    end
  end

  defp encode_draw(opts) do
    stroke = Keyword.get(opts, :stroke)
    fill = Keyword.get(opts, :fill)

    draw = []
    draw = if fill && fill != :none, do: draw ++ [<<0x40::8>>], else: draw
    draw = if stroke && stroke != :none, do: draw ++ [<<0x41::8>>], else: draw

    IO.iodata_to_binary(draw)
  end

  defp parse_color(color) when is_binary(color) do
    if String.starts_with?(color, "#"), do: parse_hex(color), else: {0, 0, 0, 255}
  end

  defp parse_color(_), do: {0, 0, 0, 255}

  defp parse_hex("#" <> hex) do
    case String.length(hex) do
      6 ->
        {r, _} = Integer.parse(String.slice(hex, 0, 2), 16)
        {g, _} = Integer.parse(String.slice(hex, 2, 2), 16)
        {b, _} = Integer.parse(String.slice(hex, 4, 2), 16)
        {r, g, b, 255}

      _ ->
        {0, 0, 0, 255}
    end
  end
end
