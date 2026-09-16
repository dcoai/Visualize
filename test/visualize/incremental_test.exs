defmodule Visualize.IncrementalTest do
  @moduledoc "Scroll classification, region bounds and the state contract (spec/09 §5, §7; D-38)."
  use ExUnit.Case, async: true

  alias Visualize.Backend.CanvasBinary.Decoder
  alias Visualize.Backend.CanvasIncremental
  alias Visualize.Incremental
  alias Visualize.IR.Element

  doctest CanvasIncremental

  @size {800, 600}

  test "a zero offset is :none, not a full redraw" do
    assert CanvasIncremental.scroll_mode({0, 0}, @size) == :none
    assert CanvasIncremental.scroll_mode({0.0, 0}, @size) == :none
    assert CanvasIncremental.scroll_mode({20, 0}, @size) == :scroll_x
    assert CanvasIncremental.scroll_mode({0, -20}, @size) == :scroll_y
    assert CanvasIncremental.scroll_mode({20, 30}, @size) == :scroll_xy
    assert CanvasIncremental.scroll_mode({500, 0}, @size) == :full_redraw
  end

  test "exposed_regions/2 yields zero, one or two regions" do
    assert CanvasIncremental.exposed_regions({0, 0}, @size) == []
    assert length(CanvasIncremental.exposed_regions({20, 0}, @size)) == 1
    assert length(CanvasIncremental.exposed_regions({-20, 30}, @size)) == 2
  end

  test "encode_incremental/4 refuses more than three regions and a zero offset" do
    region = {{0.0, 0.0, 1.0, 1.0}, Element.group([])}

    assert_raise ArgumentError, fn ->
      CanvasIncremental.encode_incremental({20, 0}, @size, List.duplicate(region, 4))
    end

    assert_raise ArgumentError, fn ->
      CanvasIncremental.encode_incremental({0, 0}, @size, [region])
    end

    binary = CanvasIncremental.encode_incremental({20, 0}, @size, List.duplicate(region, 3))

    assert [{:incremental, :scroll_x, 20.0, +0.0, {+0.0, +0.0, 800.0, 600.0}, regions}] =
             Decoder.decode(binary)

    assert length(regions) == 3
  end

  test "the record names what scrolls: the viewport, the whole canvas by default (D-106, #294)" do
    region = {{0.0, 0.0, 1.0, 1.0}, Element.group([])}
    plot = {60, 40, 810, 410}

    # The viewport is written after the offset, one 27-byte header in every mode.
    binary = CanvasIncremental.encode_incremental({5, 0}, {900, 500}, [region], viewport: plot)

    assert <<0x60, 0x01, 5.0::little-float-32, +0.0::little-float-32, 60.0::little-float-32,
             40.0::little-float-32, 810.0::little-float-32, 410.0::little-float-32, 1, _::binary>> =
             binary

    assert [{:incremental, :scroll_x, 5.0, +0.0, {60.0, 40.0, 810.0, 410.0}, [_]}] =
             Decoder.decode(binary)

    # The offset is classified against the viewport's size, since that is what is copied:
    # 500 px is a full redraw of a 810 px plot and a scroll of a 2000 px canvas.
    wide = CanvasIncremental.encode_incremental({500, 0}, {2000, 500}, [region], viewport: plot)

    assert [{:incremental, :full_redraw, 500.0, +0.0, {60.0, 40.0, 810.0, 410.0}, [_]}] =
             Decoder.decode(wide)

    whole = CanvasIncremental.encode_incremental({500, 0}, {2000, 500}, [region])

    assert [{:incremental, :scroll_x, 500.0, +0.0, {+0.0, +0.0, 2000.0, 500.0}, [_]}] =
             Decoder.decode(whole)

    # A full redraw carries the canvas size, or zeros from the arity-1 call.
    assert [{:full_redraw, {+0.0, +0.0, 900.0, 500.0}, [:save, :restore]}] =
             Element.group([])
             |> CanvasIncremental.encode_full_redraw({900, 500})
             |> Decoder.decode()

    assert [{:full_redraw, {+0.0, +0.0, +0.0, +0.0}, [:save, :restore]}] =
             Element.group([]) |> CanvasIncremental.encode_full_redraw() |> Decoder.decode()
  end

  defp state(build_element) do
    Incremental.new(
      canvas_size: @size,
      data: [%{x: 10, y: 20}, %{x: 790, y: 300}],
      x_accessor: & &1.x,
      y_accessor: & &1.y,
      build_element: build_element,
      margin: %{top: 1, right: 2, bottom: 3, left: 4}
    )
  end

  test "scroll/2 with a zero delta is a \"none\" payload and leaves the viewport alone" do
    state = state(fn _data, _opts -> flunk("nothing to build") end)

    assert {"canvas_incremental", %{binary: "", dx: 0, dy: 0, mode: "none"}, ^state} =
             Incremental.scroll(state, {0, 0})
  end

  test "build_element receives the whole dataset, the viewport and the margin for a full frame" do
    parent = self()

    state =
      state(fn data, opts ->
        send(parent, {:built, data, opts})
        Element.group([])
      end)

    {"canvas_incremental", %{mode: "full"}, _} = Incremental.initial_render(state)

    assert_received {:built, [%{x: 10}, %{x: 790}],
                     %{
                       viewport_x: 0,
                       viewport_y: 0,
                       canvas_width: 800,
                       canvas_height: 600,
                       margin: %{top: 1, right: 2, bottom: 3, left: 4}
                     }}
  end

  test "a scroll builds each exposed region from the data inside it" do
    parent = self()

    state =
      state(fn data, opts ->
        send(parent, {:built, data, opts.clip_region})
        Element.group([])
      end)

    {"canvas_incremental", %{mode: "scroll_x", dx: 20, dy: 0}, new_state} =
      Incremental.scroll(state, {20, 0})

    assert new_state.viewport_x == 20
    assert_received {:built, [%{x: 790}], {780.0, +0.0, 20.0, 600.0}}
  end
end
