defmodule ExamplesWeb.PerformanceDrawer do
  @moduledoc """
  The performance drawer under a chart (spec/14 §12.6, #322): one line collapsed, and
  open, the controls of a run over the chart — backend, target FPS, flow control where
  the backend acks, Start and Stop — the metrics rows of `Examples.Run`, and Compare's
  table. Every control is the page's event; the drawer draws and never runs.
  """

  use Phoenix.Component

  alias Examples.{Frames, Run}

  attr(:run, Run, required: true, doc: "the run, `Examples.Run`")
  attr(:backend, :atom, required: true, doc: "the backend the run renders on")
  attr(:backends, :list, required: true, doc: "the backends the chart offers")
  attr(:open, :boolean, default: false, doc: "whether the drawer is open")
  attr(:compare, :list, default: nil, doc: "Compare's rows, `Examples.Compare.run/3`")
  attr(:comparing, :boolean, default: false, doc: "whether a comparison is running")
  attr(:ticks, :integer, default: 100, doc: "the ticks Compare runs per backend")

  def performance(assigns) do
    assigns = assign(assigns, acks?: Frames.acks?(assigns.backend))

    ~H"""
    <section class={"perf-drawer" <> if(@open, do: " perf-drawer-open", else: "")} id="performance-drawer">
      <button type="button" class="perf-drawer-toggle" phx-click="drawer_toggle" aria-expanded={to_string(@open)}>
        <span class="perf-drawer-caret"><%= if @open, do: "▾", else: "▸" %></span>
        Performance
        <span class="perf-drawer-summary">
          <%= backend_name(@backend) %> ·
          <%= if @run.running, do: "#{trunc(@run.fps)} fps", else: "idle" %>
        </span>
      </button>

      <div :if={@open} class="perf-drawer-body">
        <div class="perf-controls">
          <div class="perf-group" role="radiogroup" aria-label="backend">
            <span class="perf-label">Backend</span>
            <button
              :for={b <- @backends}
              type="button"
              class={"perf-chip" <> if(b == @backend, do: " perf-chip-on", else: "")}
              aria-pressed={to_string(b == @backend)}
              disabled={@run.running}
              phx-click="run_backend"
              phx-value-backend={b}
            ><%= backend_name(b) %></button>
          </div>

          <form phx-change="run_fps" class="perf-group">
            <label class="perf-label" for="perf-fps">Target FPS</label>
            <input id="perf-fps" type="range" name="fps" min="10" max="2010" step="10" value={@run.target_fps} class="perf-slider" />
            <span class="perf-value"><%= if @run.target_fps > 2000, do: "∞", else: @run.target_fps %></span>
          </form>

          <button
            :if={@acks?}
            type="button"
            class={"perf-chip" <> if(@run.flow_control, do: " perf-chip-on", else: "")}
            title="Hold frames back while 250 ms of them are in flight"
            phx-click="run_flow_control"
          >
            <%= cond do
              not @run.flow_control -> "Flow control OFF"
              @run.acking == :no -> "Flow control: no acks"
              true -> "Flow control ON (250 ms)"
            end %>
          </button>

          <button :if={not @run.running} type="button" class="perf-btn perf-start" phx-click="run_start">Start</button>
          <button :if={@run.running} type="button" class="perf-btn perf-stop" phx-click="run_stop">Stop</button>
          <button type="button" class="perf-btn" disabled={@comparing or @run.running} phx-click="run_compare">
            <%= if @comparing, do: "Comparing…", else: "Compare (#{@ticks} ticks)" %>
          </button>
        </div>

        <p :if={@run.error} class="perf-error" role="alert">the render failed and the run stopped: <%= @run.error %></p>

        <div class="perf-metrics">
          <.metric value={trunc(@run.fps)} label="FPS" />
          <.metric value={if(@run.target_fps > 2000, do: "∞", else: @run.target_fps)} label="Target" />
          <.metric :if={@acks?} value={trunc(@run.client_fps)} label="Client FPS" />
          <.metric :if={@acks?} value={Run.in_flight(@run)} label="In flight" />
          <.metric :if={@acks?} value={if(@run.target_fps > 2000, do: "—", else: "#{round(@run.lag)} ms")} label="Lag" />
          <.metric :if={@acks?} value={@run.dropped} label="Dropped" />
          <.metric :if={@acks?} value={if(@run.ack_age, do: "#{@run.ack_age} ms", else: "none")} label="Last ack" />
          <.metric :if={@acks?} value={@run.stalls} label="Stalls" />
          <.metric value={@run.skipped} label="Skipped" />
          <.metric value={Float.round(Run.avg_render_us(@run) / 1000, 2)} label="Render ms" />
          <.metric value={Float.round(@run.payload_size / 1024, 1)} label="Payload KB" />
          <.metric value={@run.frame} label="Frame" />
        </div>

        <table :if={@compare} class="perf-compare">
          <caption>This chart, <%= @ticks %> ticks per backend, headless</caption>
          <thead>
            <tr><th>Backend</th><th>Render / frame</th><th>Bytes / frame</th><th>Static bytes</th></tr>
          </thead>
          <tbody>
            <tr :for={row <- @compare}>
              <td><%= backend_name(row.backend) %></td>
              <td><%= Float.round(row.avg_render_us / 1000, 2) %> ms</td>
              <td><%= Float.round(row.avg_bytes / 1024, 1) %> KB</td>
              <td><%= Float.round(row.static_bytes / 1024, 1) %> KB</td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
    """
  end

  attr(:value, :any, required: true)
  attr(:label, :string, required: true)

  defp metric(assigns) do
    ~H"""
    <div class="perf-metric">
      <span class="perf-metric-value"><%= @value %></span>
      <span class="perf-metric-label"><%= @label %></span>
    </div>
    """
  end

  defp backend_name(:svg), do: "SVG"
  defp backend_name(:canvas), do: "Canvas"
  defp backend_name(other), do: to_string(other)

  @doc "The drawer's stylesheet, inlined by the page."
  def css do
    """
    .perf-drawer { margin-top: 1rem; border: 1px solid #e5e7eb; border-radius: 8px; background: #fff; }
    .perf-drawer-toggle { display: flex; align-items: center; gap: 0.5rem; width: 100%; padding: 0.6rem 0.9rem; border: none; background: none; font: inherit; font-weight: 600; color: #333; cursor: pointer; text-align: left; }
    .perf-drawer-caret { width: 1em; color: #888; }
    .perf-drawer-summary { margin-left: auto; font-weight: 400; color: #666; font-variant-numeric: tabular-nums; }
    .perf-drawer-body { padding: 0 0.9rem 0.9rem; border-top: 1px solid #f0f0f0; }
    .perf-controls { display: flex; flex-wrap: wrap; align-items: center; gap: 0.75rem 1.25rem; padding: 0.75rem 0; }
    .perf-group { display: flex; align-items: center; gap: 0.4rem; }
    .perf-label { font-size: 13px; color: #555; }
    .perf-chip { padding: 0.35rem 0.7rem; border: 1px solid #ddd; border-radius: 6px; background: #fff; font: inherit; font-size: 13px; cursor: pointer; }
    .perf-chip-on { border-color: #667eea; background: #eef0fb; color: #3b4bb8; }
    .perf-chip:disabled { opacity: 0.6; cursor: default; }
    .perf-slider { width: 120px; }
    .perf-value { min-width: 2.5rem; font-weight: 600; font-variant-numeric: tabular-nums; }
    .perf-btn { padding: 0.45rem 0.9rem; border: none; border-radius: 6px; background: #e5e7eb; font: inherit; font-size: 13px; font-weight: 600; cursor: pointer; }
    .perf-btn:disabled { opacity: 0.6; cursor: default; }
    .perf-start { background: #16a34a; color: #fff; }
    .perf-stop { background: #dc2626; color: #fff; }
    .perf-error { color: #b91c1c; font-size: 13px; }
    .perf-metrics { display: grid; grid-template-columns: repeat(auto-fill, minmax(86px, 1fr)); gap: 0.5rem; padding: 0.6rem 0.9rem; border-radius: 6px; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: #fff; }
    .perf-metric { display: flex; flex-direction: column; align-items: center; }
    .perf-metric-value { font-size: 1.1rem; font-weight: 700; font-variant-numeric: tabular-nums; }
    .perf-metric-label { font-size: 0.7rem; opacity: 0.85; text-transform: uppercase; letter-spacing: 0.03em; }
    .perf-compare { width: 100%; margin-top: 0.75rem; border-collapse: collapse; font-size: 13px; }
    .perf-compare caption { text-align: left; color: #666; padding-bottom: 0.3rem; }
    .perf-compare th, .perf-compare td { padding: 0.35rem 0.5rem; border-bottom: 1px solid #eee; text-align: right; }
    .perf-compare th:first-child, .perf-compare td:first-child { text-align: left; }
    """
  end
end
