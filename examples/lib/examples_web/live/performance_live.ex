defmodule ExamplesWeb.PerformanceLive do
  @moduledoc """
  The comparison view over the gallery (spec/14 §12.6, #322, #328): a chart picked from
  the gallery and run headless through each backend by `Examples.Compare.run/3`, or
  every design compared in one table — each comparison a task off the view's process.

  The page once held six hand-built chart types with renderers of their own; the
  gallery's designs are the charts now, and every chart page's drawer runs the same
  comparison for the chart in front of the person.
  """

  use Phoenix.LiveView

  alias Examples.Compare
  alias ExamplesWeb.ChartLive

  @ticks [20, 100, 500]

  @impl true
  def mount(_params, _session, socket) do
    charts =
      ChartLive.charts()
      |> Enum.map(fn {slug, module} -> %{slug: slug, module: module, title: module.title()} end)
      |> Enum.sort_by(& &1.title)

    {:ok,
     assign(socket,
       charts: charts,
       slug: "line",
       ticks: 100,
       ticks_choices: @ticks,
       rows: nil,
       all: nil,
       task: nil,
       error: nil
     )}
  end

  @impl true
  def handle_event("pick", %{"slug" => slug, "ticks" => ticks}, socket) do
    true = Enum.any?(socket.assigns.charts, &(&1.slug == slug))
    {:noreply, assign(socket, slug: slug, ticks: String.to_integer(ticks), rows: nil)}
  end

  def handle_event("compare", _params, %{assigns: %{task: nil}} = socket) do
    %{slug: slug, ticks: ticks} = socket.assigns
    module = ChartLive.charts()[slug]
    opts_for = fn tick -> [width: 700, height: 450, palette: :default, animation_tick: tick] end
    {:noreply, start_task(socket, fn -> {:rows, Compare.run(module, opts_for, ticks)} end, :rows)}
  end

  def handle_event("compare_all", _params, %{assigns: %{task: nil}} = socket) do
    %{charts: charts, ticks: ticks} = socket.assigns

    work = fn ->
      opts_for = fn tick -> [width: 700, height: 450, palette: :default, animation_tick: tick] end

      {:all,
       for chart <- charts, row <- Compare.run(chart.module, opts_for, ticks) do
         Map.merge(row, %{slug: chart.slug, title: chart.title})
       end}
    end

    {:noreply, start_task(socket, work, :all)}
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # A comparison in a task, or the reason there is none (#340).
  defp start_task(socket, work, key) do
    case Examples.Run.supervisor() do
      :ok ->
        task = Task.Supervisor.async_nolink(Examples.TaskSupervisor, work)
        assign(socket, [task: task, error: nil] ++ [{key, nil}])

      {:error, message} ->
        assign(socket, error: message)
    end
  end

  @impl true
  def handle_info({ref, result}, %{assigns: %{task: %Task{ref: ref}}} = socket) do
    Process.demonitor(ref, [:flush])

    case result do
      {:rows, rows} -> {:noreply, assign(socket, task: nil, rows: rows)}
      {:all, all} -> {:noreply, assign(socket, task: nil, all: all)}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{assigns: %{task: %Task{ref: ref}}} = socket) do
    {:noreply, assign(socket, task: nil, error: inspect(reason))}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def terminate(_reason, %{assigns: %{task: %Task{pid: pid}}}) do
    Task.Supervisor.terminate_child(Examples.TaskSupervisor, pid)
  end

  def terminate(_reason, _socket), do: :ok

  @impl true
  def render(assigns) do
    ~H"""
    <ExamplesWeb.SiteHeader.header tab={:performance} />
    <main>
      <div class="page-intro">
        <h2>Performance Test</h2>
        <p>
          A chart of the gallery run headless through each backend — SVG whole per tick, Canvas as the compiled split,
          Incremental for a streaming design — with the mean render time and bytes per frame (spec/14 §12.6).
          Every chart's own page runs the same comparison live, with a target FPS and the metrics, in its Performance drawer.
        </p>
      </div>

      <form phx-change="pick" class="compare-controls">
        <label>Chart
          <select name="slug">
            <option :for={c <- @charts} value={c.slug} selected={c.slug == @slug}><%= c.title %></option>
          </select>
        </label>
        <label>Ticks
          <select name="ticks">
            <option :for={t <- @ticks_choices} value={t} selected={t == @ticks}><%= t %></option>
          </select>
        </label>
        <button type="button" phx-click="compare" class="perf-btn perf-start" disabled={@task != nil}>Compare this chart</button>
        <button type="button" phx-click="compare_all" class="perf-btn" disabled={@task != nil}>Compare every design</button>
        <a href={"/chart/#{@slug}"} class="compare-link">open its page →</a>
        <span :if={@task} class="compare-running">comparing…</span>
      </form>

      <p :if={@error} class="perf-error" role="alert">the comparison failed: <%= @error %></p>

      <table :if={@rows} class="perf-compare">
        <caption><%= title(@charts, @slug) %>, <%= @ticks %> ticks per backend</caption>
        <thead><tr><th>Backend</th><th>Render / frame</th><th>Bytes / frame</th><th>Static bytes</th></tr></thead>
        <tbody>
          <tr :for={row <- @rows}>
            <td><%= backend(row.backend) %></td>
            <td><%= ms(row.avg_render_us) %></td>
            <td><%= kb(row.avg_bytes) %></td>
            <td><%= kb(row.static_bytes) %></td>
          </tr>
        </tbody>
      </table>

      <table :if={@all} class="perf-compare">
        <caption>Every design, <%= @ticks %> ticks per backend</caption>
        <thead><tr><th>Chart</th><th>Backend</th><th>Render / frame</th><th>Bytes / frame</th><th>Static bytes</th></tr></thead>
        <tbody>
          <tr :for={row <- @all}>
            <td><a href={"/chart/#{row.slug}"}><%= row.title %></a></td>
            <td><%= backend(row.backend) %></td>
            <td><%= ms(row.avg_render_us) %></td>
            <td><%= kb(row.avg_bytes) %></td>
            <td><%= kb(row.static_bytes) %></td>
          </tr>
        </tbody>
      </table>
    </main>

    <style>
      <%= Phoenix.HTML.raw(ExamplesWeb.PerformanceDrawer.css()) %>
      .compare-controls { display: flex; flex-wrap: wrap; align-items: center; gap: 1rem; margin: 1rem 0; }
      .compare-controls label { display: flex; align-items: center; gap: 0.4rem; font-size: 13px; color: #555; }
      .compare-controls select { padding: 0.35rem; border: 1px solid #ddd; border-radius: 6px; font: inherit; }
      .compare-link { font-size: 13px; }
      .compare-running { color: #666; font-size: 13px; }
      .perf-compare { background: #fff; }
    </style>
    """
  end

  defp title(charts, slug), do: Enum.find(charts, &(&1.slug == slug)).title
  defp backend(b), do: b |> to_string() |> String.capitalize() |> String.replace("Svg", "SVG")
  defp ms(us), do: "#{Float.round(us / 1000, 2)} ms"
  defp kb(bytes), do: "#{Float.round(bytes / 1024, 1)} KB"
end
