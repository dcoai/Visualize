defmodule ExamplesWeb.IncrementalLive do
  use Phoenix.LiveView
  import Phoenix.Component

  alias Visualize.{Scale, Shape}
  alias Visualize.IR.{Element, Transform}
  alias Visualize.Backend.{CanvasBinary, CanvasIncremental}

  @width 800
  @height 500
  @margin %{top: 20, right: 20, bottom: 30, left: 40}
  @data_points 500

  def mount(_params, _session, socket) do
    # Generate initial data
    data = generate_data(@data_points)

    socket =
      socket
      |> assign(:data, data)
      |> assign(:viewport_x, 0)
      |> assign(:viewport_y, 0)
      |> assign(:scroll_speed, 5)
      |> assign(:auto_scroll, false)
      |> assign(:last_scroll, nil)
      |> assign(:stats, %{mode: "initial", regions: 0, bytes: 0})

    {:ok, socket}
  end

  def handle_event("scroll", %{"direction" => direction}, socket) do
    {dx, dy} = case direction do
      "left" -> {-socket.assigns.scroll_speed, 0}
      "right" -> {socket.assigns.scroll_speed, 0}
      "up" -> {0, -socket.assigns.scroll_speed}
      "down" -> {0, socket.assigns.scroll_speed}
      _ -> {0, 0}
    end

    socket = handle_scroll(socket, dx, dy)
    {:noreply, socket}
  end

  def handle_event("set_speed", %{"speed" => speed}, socket) do
    {:noreply, assign(socket, :scroll_speed, String.to_integer(speed))}
  end

  def handle_event("toggle_auto", _params, socket) do
    socket = assign(socket, :auto_scroll, not socket.assigns.auto_scroll)

    if socket.assigns.auto_scroll do
      send(self(), :auto_scroll_tick)
    end

    {:noreply, socket}
  end

  def handle_event("initial_render", _params, socket) do
    # Send initial full render
    socket = send_full_render(socket)
    {:noreply, socket}
  end

  def handle_info(:auto_scroll_tick, socket) do
    if socket.assigns.auto_scroll do
      # Schedule next tick
      Process.send_after(self(), :auto_scroll_tick, 50)

      # Scroll right continuously
      socket = handle_scroll(socket, socket.assigns.scroll_speed, 0)
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  defp handle_scroll(socket, dx, dy) do
    canvas_size = {@width, @height}

    # Update viewport
    new_vx = socket.assigns.viewport_x + dx
    new_vy = socket.assigns.viewport_y + dy

    socket = assign(socket, viewport_x: new_vx, viewport_y: new_vy)

    # Determine scroll mode
    mode = CanvasIncremental.scroll_mode({dx, dy}, canvas_size)

    case mode do
      :full_redraw ->
        send_full_render(socket)

      _ ->
        send_incremental_render(socket, dx, dy, mode)
    end
  end

  defp send_full_render(socket) do
    element = build_chart(socket.assigns.data, socket.assigns.viewport_x, socket.assigns.viewport_y)
    binary = CanvasIncremental.encode_full_redraw(element)
    encoded = Base.encode64(binary)

    socket
    |> assign(:stats, %{mode: "full", regions: 0, bytes: byte_size(binary)})
    |> assign(:last_scroll, nil)
    |> push_event("canvas_incremental", %{
      binary: encoded,
      dx: 0,
      dy: 0,
      mode: "full"
    })
  end

  defp send_incremental_render(socket, dx, dy, mode) do
    canvas_size = {@width, @height}

    # Calculate exposed regions
    regions = CanvasIncremental.exposed_regions({dx, dy}, canvas_size)

    # Build elements for each region
    # For demo purposes, we'll render the same line in each region
    # In a real app, you'd filter data to only points in each region
    region_elements = Enum.map(regions, fn bounds ->
      element = build_chart(socket.assigns.data, socket.assigns.viewport_x, socket.assigns.viewport_y)
      {bounds, element}
    end)

    binary = CanvasIncremental.encode_incremental({dx, dy}, canvas_size, region_elements)
    encoded = Base.encode64(binary)

    mode_str = case mode do
      :scroll_x -> "scroll_x"
      :scroll_y -> "scroll_y"
      :scroll_xy -> "scroll_xy"
    end

    socket
    |> assign(:stats, %{mode: mode_str, regions: length(regions), bytes: byte_size(binary)})
    |> assign(:last_scroll, %{dx: dx, dy: dy})
    |> push_event("canvas_incremental", %{
      binary: encoded,
      dx: dx,
      dy: dy,
      mode: mode_str
    })
  end

  defp build_chart(data, viewport_x, viewport_y) do
    inner_width = @width - @margin.left - @margin.right
    inner_height = @height - @margin.top - @margin.bottom

    # Apply viewport offset to data
    shifted_data = Enum.map(data, fn %{x: x, y: y} ->
      %{x: x - viewport_x, y: y - viewport_y}
    end)

    {min_x, max_x} = shifted_data |> Enum.map(& &1.x) |> Enum.min_max()
    {min_y, max_y} = shifted_data |> Enum.map(& &1.y) |> Enum.min_max()

    x_scale = Scale.Linear.new()
      |> Scale.Linear.domain([min_x, max_x])
      |> Scale.Linear.range([0, inner_width])

    y_scale = Scale.Linear.new()
      |> Scale.Linear.domain([min_y - 5, max_y + 5])
      |> Scale.Linear.range([inner_height, 0])

    line = Shape.Line.new()
      |> Shape.Line.x(fn d -> Scale.Linear.apply(x_scale, d.x) end)
      |> Shape.Line.y(fn d -> Scale.Linear.apply(y_scale, d.y) end)
      |> Shape.Line.curve(:monotone_x)

    path = Shape.Line.generate_path(line, shifted_data)

    line_element = Element.path(path, %{
      stroke: "#4e79a7",
      stroke_width: 2,
      fill: :none
    })

    chart_group = Element.group([line_element],
      transform: Transform.translate(@margin.left, @margin.top)
    )

    Element.root(@width, @height, children: [chart_group])
  end

  defp generate_data(count) do
    for i <- 0..(count - 1) do
      x = i * 2
      y = :math.sin(x / 20) * 100 + :math.cos(x / 15) * 50 + 200 + :rand.uniform() * 10
      %{x: x, y: y}
    end
  end

  def render(assigns) do
    ~H"""
    <div style="padding: 20px; font-family: sans-serif;">
      <h1>Incremental Canvas Rendering Demo</h1>
      <p>This demo shows the copy+shift optimization for scrolling charts.</p>

      <div style="margin-bottom: 20px;">
        <h3>Controls</h3>
        <div style="display: flex; gap: 10px; margin-bottom: 10px;">
          <button phx-click="scroll" phx-value-direction="left">← Left</button>
          <button phx-click="scroll" phx-value-direction="right">Right →</button>
          <button phx-click="scroll" phx-value-direction="up">↑ Up</button>
          <button phx-click="scroll" phx-value-direction="down">Down ↓</button>
        </div>

        <div style="display: flex; gap: 10px; align-items: center; margin-bottom: 10px;">
          <label>Scroll Speed:</label>
          <input type="range" min="1" max="100" value={@scroll_speed}
                 phx-change="set_speed" name="speed" />
          <span><%= @scroll_speed %>px</span>
        </div>

        <div style="display: flex; gap: 10px; align-items: center;">
          <button phx-click="toggle_auto">
            <%= if @auto_scroll, do: "Stop Auto-Scroll", else: "Start Auto-Scroll" %>
          </button>
          <button phx-click="initial_render">Full Render</button>
        </div>
      </div>

      <div style="margin-bottom: 20px;">
        <h3>Stats</h3>
        <table style="border-collapse: collapse;">
          <tr>
            <td style="padding: 5px; border: 1px solid #ccc;"><strong>Mode:</strong></td>
            <td style="padding: 5px; border: 1px solid #ccc;"><%= @stats.mode %></td>
          </tr>
          <tr>
            <td style="padding: 5px; border: 1px solid #ccc;"><strong>Regions:</strong></td>
            <td style="padding: 5px; border: 1px solid #ccc;"><%= @stats.regions %></td>
          </tr>
          <tr>
            <td style="padding: 5px; border: 1px solid #ccc;"><strong>Payload:</strong></td>
            <td style="padding: 5px; border: 1px solid #ccc;"><%= @stats.bytes %> bytes</td>
          </tr>
          <tr>
            <td style="padding: 5px; border: 1px solid #ccc;"><strong>Viewport:</strong></td>
            <td style="padding: 5px; border: 1px solid #ccc;">(<%= @viewport_x %>, <%= @viewport_y %>)</td>
          </tr>
          <%= if @last_scroll do %>
          <tr>
            <td style="padding: 5px; border: 1px solid #ccc;"><strong>Last Scroll:</strong></td>
            <td style="padding: 5px; border: 1px solid #ccc;">(<%= @last_scroll.dx %>, <%= @last_scroll.dy %>)</td>
          </tr>
          <% end %>
        </table>
      </div>

      <div style="border: 1px solid #ccc; display: inline-block;">
        <div id="incremental-canvas"
             phx-hook="CanvasIncrementalChart"
             phx-update="ignore"
             data-width={@width}
             data-height={@height}>
          <canvas width={@width} height={@height} style="display: block;"></canvas>
        </div>
      </div>

      <div style="margin-top: 20px; color: #666;">
        <h3>How it works</h3>
        <ul>
          <li><strong>Full mode:</strong> Clears canvas and redraws everything (used for initial render or large scrolls)</li>
          <li><strong>scroll_x mode:</strong> Copies canvas shifted horizontally, draws new data on exposed edge</li>
          <li><strong>scroll_y mode:</strong> Copies canvas shifted vertically, draws new data on exposed edge</li>
          <li><strong>scroll_xy mode:</strong> Diagonal scroll, draws L-shaped new region</li>
        </ul>
        <p>When scroll distance exceeds 50% of canvas dimension, falls back to full redraw.</p>
      </div>
    </div>
    """
  end
end
