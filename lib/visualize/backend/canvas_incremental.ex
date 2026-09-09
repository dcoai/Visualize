defmodule Visualize.Backend.CanvasIncremental do
  @moduledoc """
  Incremental rendering support for canvas binary format.

  Provides utilities for calculating scroll regions, determining
  when copy optimization is beneficial, and encoding incremental updates.

  ## Overview

  Instead of clearing and redrawing the entire canvas each frame,
  this module enables:

  1. Copy existing canvas content shifted by scroll offset
  2. Only render newly exposed data in the exposed regions
  3. Fall back to full redraw when scroll is too large

  ## Binary Format

  Incremental updates use command `0x60`:

  ```
  [0x60]                  # header
  [mode: u8]              # 0x01=scroll_x, 0x02=scroll_y, 0x03=scroll_xy, 0x00=full
  [dx: f32]               # horizontal scroll (pixels)
  [dy: f32]               # vertical scroll (pixels)
  [region_count: u8]      # number of exposed regions (0-3)
  [regions...]            # region data
  ```

  `exposed_regions/2` yields at most two regions (one strip, or an L of two); the record
  admits three and `encode_incremental/3` raises on more (D-38).

  Each region:
  ```
  [x: f32][y: f32][w: f32][h: f32]  # bounds
  [data_length: u32]                 # byte length of commands
  [commands...]                      # standard binary commands
  ```
  """

  alias Visualize.Backend.CanvasBinary
  alias Visualize.IR.Element

  @cmd_incremental_update 0x60

  # 50% of canvas dimension = fallback to full redraw
  @scroll_threshold 0.5

  @type scroll_offset :: {dx :: number(), dy :: number()}
  @type bounds :: {x :: number(), y :: number(), width :: number(), height :: number()}
  @type canvas_size :: {width :: number(), height :: number()}

  @doc """
  Determines if copy optimization is worthwhile.

  Returns false if scroll distance > 50% of canvas dimension in either axis,
  as the overhead of copy+partial-render would exceed full redraw.

  ## Examples

      iex> alias Visualize.Backend.CanvasIncremental
      iex> CanvasIncremental.copy_beneficial?({50, 0}, {800, 600})
      true

  A 500px scroll exceeds 400px, half of the 800px width, so a full redraw is cheaper:

      iex> alias Visualize.Backend.CanvasIncremental
      iex> CanvasIncremental.copy_beneficial?({500, 0}, {800, 600})
      false

  """
  @spec copy_beneficial?(scroll_offset(), canvas_size()) :: boolean()
  def copy_beneficial?({dx, dy}, {width, height}) do
    abs(dx) < width * @scroll_threshold and
      abs(dy) < height * @scroll_threshold
  end

  @doc """
  Calculates the scroll mode based on scroll direction.

  Returns:
  - `:none` - a zero offset: nothing moved and nothing is exposed (D-38)
  - `:scroll_x` - horizontal only
  - `:scroll_y` - vertical only
  - `:scroll_xy` - diagonal (both axes)
  - `:full_redraw` - scroll too large, use full redraw
  """
  @spec scroll_mode(scroll_offset(), canvas_size()) ::
          :none | :scroll_x | :scroll_y | :scroll_xy | :full_redraw
  def scroll_mode({dx, dy}, {width, height}) do
    cond do
      dx == 0 and dy == 0 -> :none
      not copy_beneficial?({dx, dy}, {width, height}) -> :full_redraw
      dy == 0 -> :scroll_x
      dx == 0 -> :scroll_y
      true -> :scroll_xy
    end
  end

  @doc """
  Calculates the exposed regions after a scroll operation.

  Returns 0-2 regions depending on scroll direction:
  - No scroll: no regions
  - Horizontal only: 1 vertical strip (left or right edge)
  - Vertical only: 1 horizontal strip (top or bottom edge)
  - Diagonal: 2 regions forming an L-shape (avoiding overlap)

  The regions are where new data needs to be rendered after the
  canvas content is copied/shifted.

  ## Examples

  Scrolling right by 20px on an 800 x 600 canvas exposes the right edge:

      iex> alias Visualize.Backend.CanvasIncremental
      iex> CanvasIncremental.exposed_regions({20, 0}, {800, 600})
      [{780.0, 0.0, 20.0, 600.0}]

  Scrolling left by 20px exposes the left edge:

      iex> alias Visualize.Backend.CanvasIncremental
      iex> CanvasIncremental.exposed_regions({-20, 0}, {800, 600})
      [{0.0, 0.0, 20.0, 600.0}]

  A diagonal scroll exposes an L of two strips, the second shortened by the first:

      iex> alias Visualize.Backend.CanvasIncremental
      iex> CanvasIncremental.exposed_regions({20, 30}, {800, 600})
      [{780.0, 0.0, 20.0, 600.0}, {0.0, 570.0, 780.0, 30.0}]

  """
  @spec exposed_regions(scroll_offset(), canvas_size()) :: [bounds()]
  def exposed_regions({dx, dy}, {width, height}) do
    dx = to_float(dx)
    dy = to_float(dy)
    width = to_float(width)
    height = to_float(height)

    cond do
      # No scroll
      dx == 0 and dy == 0 ->
        []

      # Horizontal only
      dy == 0 ->
        [horizontal_region(dx, width, height)]

      # Vertical only
      dx == 0 ->
        [vertical_region(dy, width, height)]

      # Diagonal - L-shaped region (2 strips)
      true ->
        h_region = horizontal_region(dx, width, height)
        v_region = vertical_region_excluding_corner(dy, dx, width, height)
        [h_region, v_region]
    end
    |> Enum.reject(&empty_region?/1)
  end

  # Horizontal strip for horizontal scroll
  defp horizontal_region(dx, width, height) when dx > 0 do
    # Scrolled right (content moved left) -> expose right edge
    {width - dx, 0.0, dx, height}
  end

  defp horizontal_region(dx, _width, height) when dx < 0 do
    # Scrolled left (content moved right) -> expose left edge
    {0.0, 0.0, abs(dx), height}
  end

  defp horizontal_region(_dx, _width, _height), do: {0.0, 0.0, 0.0, 0.0}

  # Vertical strip for vertical scroll
  defp vertical_region(dy, width, height) when dy > 0 do
    # Scrolled down (content moved up) -> expose bottom edge
    {0.0, height - dy, width, dy}
  end

  defp vertical_region(dy, width, _height) when dy < 0 do
    # Scrolled up (content moved down) -> expose top edge
    {0.0, 0.0, width, abs(dy)}
  end

  defp vertical_region(_dy, _width, _height), do: {0.0, 0.0, 0.0, 0.0}

  # Vertical strip excluding the corner already covered by horizontal strip
  defp vertical_region_excluding_corner(dy, dx, width, height) when dy > 0 and dx > 0 do
    # Bottom strip, excluding right corner
    {0.0, height - dy, width - dx, dy}
  end

  defp vertical_region_excluding_corner(dy, dx, width, height) when dy > 0 and dx < 0 do
    # Bottom strip, excluding left corner
    {abs(dx), height - dy, width - abs(dx), dy}
  end

  defp vertical_region_excluding_corner(dy, dx, width, _height) when dy < 0 and dx > 0 do
    # Top strip, excluding right corner
    {0.0, 0.0, width - dx, abs(dy)}
  end

  defp vertical_region_excluding_corner(dy, dx, width, _height) when dy < 0 and dx < 0 do
    # Top strip, excluding left corner
    {abs(dx), 0.0, width - abs(dx), abs(dy)}
  end

  defp vertical_region_excluding_corner(_dy, _dx, _width, _height), do: {0.0, 0.0, 0.0, 0.0}

  defp empty_region?({_, _, w, h}), do: w <= 0 or h <= 0

  defp to_float(n) when is_float(n), do: n
  defp to_float(n) when is_integer(n), do: n * 1.0

  @doc """
  Filters data points to only those visible in the given regions.

  ## Parameters

    - `data` - List of data points
    - `regions` - List of bounds `{x, y, width, height}`
    - `accessor` - Function that extracts `{x, y}` from a data point

  ## Example

      data = [%{x: 10, y: 20}, %{x: 790, y: 300}]
      regions = [{780.0, 0.0, 20.0, 600.0}]
      accessor = fn d -> {d.x, d.y} end

      filter_to_regions(data, regions, accessor)
      # => [%{x: 790, y: 300}]
  """
  @spec filter_to_regions(list(), [bounds()], (any() -> {number(), number()})) :: list()
  def filter_to_regions(data, regions, accessor) do
    Enum.filter(data, fn point ->
      {px, py} = accessor.(point)

      Enum.any?(regions, fn {rx, ry, rw, rh} ->
        px >= rx and px <= rx + rw and
          py >= ry and py <= ry + rh
      end)
    end)
  end

  @doc """
  Encodes an incremental update with scroll offset and region data.

  ## Parameters

    - `scroll` - `{dx, dy}` scroll offset in pixels
    - `canvas_size` - `{width, height}` of the canvas
    - `region_elements` - List of `{bounds, element}` tuples for each exposed region

  ## Returns

  Binary data in incremental format that can be decoded by CanvasIncrementalChart hook.

  Raises `ArgumentError` for more than three regions (the record's `region_count` is one
  byte and `exposed_regions/2` never yields more than two) and for a zero offset, which
  is not an incremental update (`scroll_mode/2` classifies it `:none`).
  """
  @max_regions 3

  @spec encode_incremental(scroll_offset(), canvas_size(), [{bounds(), Element.t()}]) :: binary()
  def encode_incremental({dx, dy}, {width, height}, region_elements) do
    if length(region_elements) > @max_regions do
      raise ArgumentError,
            "encode_incremental/3 takes at most #{@max_regions} regions, got #{length(region_elements)}"
    end

    mode = scroll_mode({dx, dy}, {width, height})

    if mode == :none do
      raise ArgumentError, "a zero scroll offset is not an incremental update"
    end

    mode_byte = mode_to_byte(mode)

    dx_f32 = to_float(dx)
    dy_f32 = to_float(dy)

    region_count = length(region_elements)

    regions_binary =
      region_elements
      |> Enum.map(fn {{x, y, w, h}, element} ->
        element_binary = CanvasBinary.encode_element!(element)
        data_length = byte_size(element_binary)

        <<
          to_float(x)::little-float-32,
          to_float(y)::little-float-32,
          to_float(w)::little-float-32,
          to_float(h)::little-float-32,
          data_length::little-32,
          element_binary::binary
        >>
      end)
      |> IO.iodata_to_binary()

    <<
      @cmd_incremental_update::8,
      mode_byte::8,
      dx_f32::little-float-32,
      dy_f32::little-float-32,
      region_count::8,
      regions_binary::binary
    >>
  end

  @doc """
  Encodes a full redraw command (when scroll is too large for optimization).

  This signals to the client to clear and redraw everything.
  """
  @spec encode_full_redraw(Element.t()) :: binary()
  def encode_full_redraw(element) do
    element_binary = CanvasBinary.encode_element!(element)

    <<
      @cmd_incremental_update::8,
      # mode = full redraw
      0x00::8,
      0.0::little-float-32,
      0.0::little-float-32,
      # no regions
      0::8,
      element_binary::binary
    >>
  end

  defp mode_to_byte(:full_redraw), do: 0x00
  defp mode_to_byte(:scroll_x), do: 0x01
  defp mode_to_byte(:scroll_y), do: 0x02
  defp mode_to_byte(:scroll_xy), do: 0x03
end
