defmodule ExamplesWeb.GalleryLive do
  use Phoenix.LiveView

  # The gallery's order is Examples.Gallery's, which the chart page steps through (#484).
  @charts Examples.Gallery.charts()

  @size {320, 220}

  # The previews are never rendered in this process (#397): the cached ones are assigned at
  # mount, and once connected a task per missing one renders and sends it; a dead render
  # shows a placeholder where the cache is empty.
  def mount(_params, _session, socket) do
    previews =
      for {module, _slug} <- @charts,
          {:ok, svg} <- [Examples.Previews.get(module, @size)],
          into: %{},
          do: {module, svg}

    socket = assign(socket, charts: @charts, previews: previews)
    {:ok, if(connected?(socket), do: start_previews(socket), else: socket)}
  end

  def handle_info({ref, {:preview, module, svg}}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, update(socket, :previews, &Map.put(&1, module, svg))}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket), do: {:noreply, socket}

  defp start_previews(socket) do
    for {module, _slug} <- @charts, not Map.has_key?(socket.assigns.previews, module) do
      Task.Supervisor.async_nolink(Examples.TaskSupervisor, fn ->
        {:preview, module, Examples.Previews.render(module, @size)}
      end)
    end

    socket
  end

  def render(assigns) do
    ~H"""
    <ExamplesWeb.SiteHeader.header tab={:charts} />
    <main>
      <p class="gallery-note">
        Every chart here is a design (spec/14): a map that says what the chart is, applied to rows and rendered by the
        library on any backend. Open one for the <code>Visualize.Chart.Build</code>
        calls that make it — the thing to copy — the map
        they fold to, and the same design on SVG and canvas.
      </p>
      <div class="gallery">
        <%= for {module, slug} <- @charts do %>
          <div class="chart-card">
            <a href={"/chart/#{slug}"}>
              <div class="chart-preview">
                <%= if svg = @previews[module] do %>
                  {Phoenix.HTML.raw(svg)}
                <% else %>
                  <div class="chart-preview-pending" aria-label="rendering"></div>
                <% end %>
              </div>
              <div class="chart-info">
                <h3>{module.title()}</h3>
                <p>{module.description()}</p>
              </div>
            </a>
          </div>
        <% end %>
      </div>
    </main>
    """
  end
end
