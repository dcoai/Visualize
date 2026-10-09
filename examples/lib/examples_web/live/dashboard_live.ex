defmodule ExamplesWeb.DashboardLive do
  @moduledoc """
  The synced dashboard (#467, spec/10 §4.3 and §6.4): three panels over one day, each a
  design that joins the group `"dashboard"` with one key, `interaction: %{sync: ...}`.

  Hovering one panel moves every panel's crosshair to the same instant, and brushing a
  window on one shows it on all three at once, though the panels differ in width and
  margin: what travels between them is the time in milliseconds, never a pixel. Only the
  panel brushed pushes `brush_select`, once, on release, with the window as `domain`, so
  the page counts one server event per window whichever panel was brushed. The page then
  summarises each metric over the window on the server.
  """
  use Phoenix.LiveView

  import Visualize.Chart.Build

  alias Examples.Charts.Design
  alias ExamplesWeb.Panel
  alias Visualize.Chart
  alias Visualize.Hooks.Crosshair

  @group "dashboard"
  @start ~U[2026-01-01 00:00:00Z]
  @step_minutes 10
  @samples 144

  # {id, title, unit, width, left margin}: one wide panel over two narrow ones, so the
  # members of the group share no pixel mapping.
  @panels [
    {:requests, "Requests", "req/s", 900, 50},
    {:latency, "Latency", "ms", 440, 64},
    {:errors, "Errors", "%", 440, 44}
  ]
  @height 180

  @doc "The panels' ids, titles and units, in the order the page shows them."
  def panels, do: for({id, title, unit, _w, _left} <- @panels, do: {id, title, unit})

  @doc "The rows of one metric: one sample every ten minutes over the day, `t` and `v`."
  def rows(id) do
    for i <- 0..(@samples - 1) do
      hour = i * @step_minutes / 60
      %{t: DateTime.add(@start, i * @step_minutes * 60, :second), v: value(id, hour, i)}
    end
  end

  defp value(:requests, hour, i),
    do:
      Float.round(
        400 + 300 * :math.sin((hour - 8) / 24 * 2 * :math.pi()) + 30 * :math.sin(i / 3),
        1
      )

  defp value(:latency, hour, i),
    do:
      Float.round(
        120 + 60 * :math.sin((hour - 9) / 24 * 2 * :math.pi()) + 15 * :math.cos(i / 4),
        1
      )

  defp value(:errors, hour, i),
    do: Float.round(max(0.0, 1.5 + :math.sin(hour / 3) + 0.5 * :math.sin(i / 2)), 2)

  @doc "One panel's design: a time x and a line, joined to the group by one key."
  def design(id, left) do
    Design.fold([
      chart(meta: %{name: "#{id}"}),
      source(:metric, [:t, :v]),
      interaction(sync: @group),
      style(:trace, stroke: :series_1, stroke_width: 2),
      cartesian(margin: %{top: 12, right: 16, bottom: 28, left: left}),
      time_scale(:x),
      linear_scale(:y, domain: [0, :auto], nice: true),
      axis(:x, :bottom, ticks: 6),
      axis(:y, :left, ticks: 4, grid: true),
      line(:metric, %{x: :t, y: :v}, style: :trace)
    ])
  end

  @doc """
  Every panel rendered once: its SVG, the crosshair's arrays (with the group's attributes)
  and the brush's extent, the plot area in the chart's pixels.
  """
  def build do
    for {id, title, unit, width, left} <- @panels do
      {:ok, applied} =
        Chart.apply(design(id, left), sources: %{metric: rows(id)}, size: {width, @height})

      frame = applied.frame
      %{left: l, top: t} = frame.margin

      %{
        id: id,
        title: title,
        unit: unit,
        width: width,
        svg: Chart.render(applied, root: true, title: "#{title} over the day"),
        crosshair: Crosshair.attrs(frame, applied.sources),
        extent: Enum.join([l, t, l + frame.plot.width, t + frame.plot.height], ",")
      }
    end
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, panels: build(), window: nil, events: 0, summary: nil)}
  end

  # One event per window, from the panel brushed, carrying the window in milliseconds.
  def handle_event("brush_select", %{"domain" => [from, to]}, socket) do
    window = {from, to}

    {:noreply,
     socket
     |> update(:events, &(&1 + 1))
     |> assign(window: window, summary: summary(window))}
  end

  def handle_event("brush_clear", _params, socket) do
    {:noreply, socket |> update(:events, &(&1 + 1)) |> assign(window: nil, summary: nil)}
  end

  @doc "Each metric's mean and peak over a window of milliseconds since the epoch."
  def summary({from, to}) do
    for {id, title, unit} <- panels() do
      values =
        for %{t: t, v: v} <- rows(id),
            ms = DateTime.to_unix(t, :millisecond),
            ms >= from and ms <= to,
            do: v

      case values do
        [] -> {title, unit, nil, nil}
        _ -> {title, unit, Float.round(Enum.sum(values) / length(values), 2), Enum.max(values)}
      end
    end
  end

  defp clock(ms),
    do: ms |> round() |> DateTime.from_unix!(:millisecond) |> Calendar.strftime("%H:%M")

  def render(assigns) do
    ~H"""
    <ExamplesWeb.SiteHeader.header tab={:interaction} />
    <main>
      <a href="/" class="back-link"><span>&larr;</span> Back to Gallery</a>

      <div class="panels">
        <Panel.panel id="panel-dashboard">
          <:title>Synced dashboard</:title>
          <p class="panel-note">
            Three panels, each a design that joins one sync group with <code>interaction(sync: "dashboard")</code>. Hover one to move every crosshair
            to the same time; drag across one to brush a window, shown on all three at once.
            The panels differ in width and margin: the group shares the time, not a pixel.
            Double-click a panel to clear the window.
          </p>

          <div class="dash-grid">
            <Panel.panel :for={panel <- @panels} heading="h3" class={"dash-panel dash-#{panel.id}"}>
              <:title>{panel.title} <small>({panel.unit})</small></:title>
              <div id={"dash-#{panel.id}"} phx-hook="CrosshairHook" {panel.crosshair}>
                <div
                  id={"dash-#{panel.id}-brush"}
                  phx-hook="BrushHook"
                  phx-update="ignore"
                  data-brush-type="x"
                  data-brush-extent={panel.extent}
                >
                  {Phoenix.HTML.raw(panel.svg)}
                </div>
              </div>
            </Panel.panel>
          </div>

          <p class="dash-window">
            <%= if @window do %>
              <% {from, to} = @window %> Window: <strong>{clock(from)} – {clock(to)}</strong>
            <% else %>
              No window brushed.
            <% end %>
            Server events received: <strong id="dash-events">{@events}</strong>
            — one per window, whichever panel was brushed.
          </p>

          <table :if={@summary} class="dash-summary">
            <tr>
              <th>Metric</th><th>Mean</th><th>Peak</th>
            </tr>
            <tr :for={{title, unit, mean, peak} <- @summary}>
              <td>{title}</td>
              <td>{if mean, do: "#{mean} #{unit}", else: "–"}</td>
              <td>{if peak, do: "#{peak} #{unit}", else: "–"}</td>
            </tr>
          </table>
        </Panel.panel>

        <Panel.panel id="panel-code">
          <:title>The design key and the markup</:title>
          <pre><code><%= design_code() %></code></pre>
        </Panel.panel>
      </div>
    </main>

    <style>
      .dash-grid { display: grid; grid-template-columns: repeat(2, max-content); gap: 20px; }
      .dash-requests { grid-column: 1 / span 2; }
      .dash-panel small { color: #888; font-weight: normal; }
      .dash-panel [phx-hook="CrosshairHook"] { display: inline-block; }
      .crosshair-rule { stroke-dasharray: 3 3; }
      .dash-window { margin-top: 1rem; color: #444; }
      .dash-summary { margin-top: 0.5rem; border-collapse: collapse; }
      .dash-summary th, .dash-summary td { padding: 0.25rem 1rem 0.25rem 0; text-align: left; }
    </style>
    """
  end

  defp design_code do
    """
    # One key per panel joins the group (spec/14 §2.9).
    interaction(sync: "dashboard")

    # The crosshair's arrays carry the group; the brush reads it from the chart's SVG.
    <div id="requests" phx-hook="CrosshairHook" {Crosshair.attrs(applied.frame, applied.sources)}>
      <div id="requests-brush" phx-hook="BrushHook" phx-update="ignore" data-brush-type="x">
        {raw(svg)}
      </div>
    </div>

    # Only the panel brushed pushes, once, with the window in milliseconds.
    def handle_event("brush_select", %{"domain" => [from, to]}, socket)
    """
  end
end
