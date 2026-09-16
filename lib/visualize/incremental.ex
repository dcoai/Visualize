defmodule Visualize.Incremental do
  @moduledoc """
  High-level API for incremental canvas rendering with scroll optimization.

  Use this module when building scrolling/panning visualizations to minimize
  data transfer and client-side rendering work.

  ## How it works

  Instead of sending the entire chart each frame, incremental rendering:

  1. Tracks the current viewport position
  2. On scroll, calculates which regions are newly exposed
  3. Encodes only the new data for those regions
  4. Client copies existing canvas content shifted, then renders new data

  Every entry point returns the event name `"canvas_incremental"` with a payload whose
  `mode` is `"full"`, `"scroll_x"`, `"scroll_y"`, `"scroll_xy"` or `"none"` (a zero
  delta: nothing to draw, nothing to push). `render_viewport/1` and `initial_render/1`
  hand the whole dataset to `build_element` with the viewport, canvas size and margin in
  the options map; it is the callback that decides what a full frame shows. Region
  builds receive the data filtered to the exposed region.

  ## Example Usage

  ```elixir
  # Initialize state in mount/3
  def mount(_params, _session, socket) do
    state = Visualize.Incremental.new(
      canvas_size: {800, 600},
      data: load_data(),
      x_accessor: &Map.get(&1, :x),
      y_accessor: &Map.get(&1, :y),
      build_element: &build_line_element/2
    )

    {:ok, assign(socket, incremental: state)}
  end

  # Handle scroll events
  def handle_event("scroll", %{"dx" => dx, "dy" => dy}, socket) do
    state = socket.assigns.incremental

    {event_type, payload, new_state} =
      Visualize.Incremental.scroll(state, {dx, dy})

    socket =
      socket
      |> assign(:incremental, new_state)
      |> push_event(event_type, payload)

    {:noreply, socket}
  end
  ```
  """

  alias Visualize.Backend.CanvasIncremental
  alias Visualize.IR.Element

  defstruct [
    :canvas_width,
    :canvas_height,
    :viewport_x,
    :viewport_y,
    :data,
    :x_accessor,
    :y_accessor,
    :build_element,
    :margin
  ]

  @type t :: %__MODULE__{
          canvas_width: number(),
          canvas_height: number(),
          viewport_x: number(),
          viewport_y: number(),
          data: list(),
          x_accessor: (any() -> number()),
          y_accessor: (any() -> number()),
          build_element: (list(), map() -> Element.t()),
          margin: map()
        }

  @type scroll_offset :: {dx :: number(), dy :: number()}
  @type bounds :: {x :: number(), y :: number(), width :: number(), height :: number()}

  @doc """
  Creates a new incremental rendering context.

  ## Options

    * `:canvas_size` - Required. `{width, height}` of the canvas in pixels.
    * `:data` - Required. The full dataset.
    * `:x_accessor` - Required. Function to extract x coordinate from data point.
    * `:y_accessor` - Required. Function to extract y coordinate from data point.
    * `:build_element` - Required. Function `(data, opts) -> Element.t()` to build
      the element tree for a subset of data.
    * `:viewport_x` - Initial x offset (default: 0).
    * `:viewport_y` - Initial y offset (default: 0).
    * `:margin` - Chart margins `%{top:, right:, bottom:, left:}` (default: all 0),
      passed to `build_element` as `margin` in its options map.

  ## Example

      Visualize.Incremental.new(
        canvas_size: {800, 600},
        data: my_data,
        x_accessor: &(&1.timestamp),
        y_accessor: &(&1.value),
        build_element: fn data, _opts ->
          # Build your chart element from the data subset
          build_line_chart(data)
        end
      )
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    {width, height} = Keyword.fetch!(opts, :canvas_size)

    %__MODULE__{
      canvas_width: width,
      canvas_height: height,
      viewport_x: Keyword.get(opts, :viewport_x, 0),
      viewport_y: Keyword.get(opts, :viewport_y, 0),
      data: Keyword.fetch!(opts, :data),
      x_accessor: Keyword.fetch!(opts, :x_accessor),
      y_accessor: Keyword.fetch!(opts, :y_accessor),
      build_element: Keyword.fetch!(opts, :build_element),
      margin: Keyword.get(opts, :margin, %{top: 0, right: 0, bottom: 0, left: 0})
    }
  end

  @doc """
  Handles a scroll event, returning the incremental update payload.

  ## Parameters

    - `state` - Current incremental state
    - `delta` - `{dx, dy}` scroll delta in pixels

  ## Returns

  A tuple of `{event_type, payload, new_state}` where:

    - `event_type` - Always `"canvas_incremental"`
    - `payload` - Map with `:binary`, `:dx`, `:dy`, `:mode` keys; `mode` is `"full"`
      (the scroll was too large: the whole viewport is re-sent), `"scroll_x"`,
      `"scroll_y"` or `"scroll_xy"` (copy-shift plus the exposed regions), or `"none"`
      for a zero delta, whose `binary` is empty and which the client ignores
    - `new_state` - Updated state with new viewport position

  ## Example

      {event_type, payload, new_state} = Visualize.Incremental.scroll(state, {20, 0})
      push_event(socket, event_type, payload)
  """
  @spec scroll(t(), scroll_offset()) ::
          {String.t(), map(), t()}
  def scroll(state, {dx, dy}) do
    canvas_size = {state.canvas_width, state.canvas_height}

    # Update viewport position
    new_state = %{state | viewport_x: state.viewport_x + dx, viewport_y: state.viewport_y + dy}

    mode = CanvasIncremental.scroll_mode({dx, dy}, canvas_size)

    case mode do
      :none ->
        {"canvas_incremental", %{binary: "", dx: 0, dy: 0, mode: "none"}, new_state}

      :full_redraw ->
        # Scroll too large or no scroll - full redraw
        {binary, new_state} = render_viewport(new_state)

        payload = %{
          binary: Base.encode64(binary),
          dx: 0,
          dy: 0,
          mode: "full"
        }

        {"canvas_incremental", payload, new_state}

      _ ->
        # Incremental update
        regions = CanvasIncremental.exposed_regions({dx, dy}, canvas_size)

        # Build elements for each exposed region
        region_elements = build_region_elements(new_state, regions)

        binary = CanvasIncremental.encode_incremental({dx, dy}, canvas_size, region_elements)

        payload = %{
          binary: Base.encode64(binary),
          dx: dx,
          dy: dy,
          mode: mode_to_string(mode)
        }

        {"canvas_incremental", payload, new_state}
    end
  end

  @doc """
  Renders the full viewport, for initial render or forced refresh.

  ## Returns

  A tuple of `{binary, new_state}` where binary is the full chart encoded
  for canvas rendering.
  """
  @spec render_viewport(t()) :: {binary(), t()}
  def render_viewport(state) do
    element = state.build_element.(state.data, build_opts(state))

    # Encode as full redraw
    binary =
      CanvasIncremental.encode_full_redraw(element, {state.canvas_width, state.canvas_height})

    {binary, state}
  end

  @doc """
  Updates the data in the incremental state.

  Use this when the underlying data changes and you need to refresh.
  """
  @spec update_data(t(), list()) :: t()
  def update_data(state, new_data) do
    %{state | data: new_data}
  end

  @doc """
  Returns the payload for an initial full render.

  Use this in mount/3 to send the initial chart state.
  """
  @spec initial_render(t()) :: {String.t(), map(), t()}
  def initial_render(state) do
    {binary, new_state} = render_viewport(state)

    payload = %{
      binary: Base.encode64(binary),
      dx: 0,
      dy: 0,
      mode: "full"
    }

    {"canvas_incremental", payload, new_state}
  end

  # Private functions

  defp build_region_elements(state, regions) do
    Enum.map(regions, fn bounds ->
      # Filter data to this region (in screen coordinates)
      region_data = filter_data_to_region(state, bounds)
      opts = Map.put(build_opts(state), :clip_region, bounds)
      {bounds, state.build_element.(region_data, opts)}
    end)
  end

  # What `build_element` is told about the frame it draws.
  defp build_opts(state) do
    %{
      viewport_x: state.viewport_x,
      viewport_y: state.viewport_y,
      canvas_width: state.canvas_width,
      canvas_height: state.canvas_height,
      margin: state.margin
    }
  end

  defp filter_data_to_region(state, {rx, ry, rw, rh}) do
    accessor = fn point ->
      {state.x_accessor.(point), state.y_accessor.(point)}
    end

    CanvasIncremental.filter_to_regions(
      state.data,
      [{rx, ry, rw, rh}],
      accessor
    )
  end

  defp mode_to_string(:scroll_x), do: "scroll_x"
  defp mode_to_string(:scroll_y), do: "scroll_y"
  defp mode_to_string(:scroll_xy), do: "scroll_xy"
end
