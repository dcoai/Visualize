defmodule ExamplesWeb.ChartPanels.Zoom do
  @moduledoc """
  **Zoom** (spec/14 §3.9, §12.6, #705): the chart under `ZoomHook`, so a stroke written
  `non_scaling: true` can be watched keeping its width while every other stroke grows with
  the zoom.

  The chart is drawn once, as SVG, inside a `<g class="zoom-container">` the hook scales and
  translates in the browser; the hook reports each settled transform as `chart_zoom`, which
  the page takes and ignores — nothing on the server depends on the zoom. Nothing in the
  library zooms a chart's canvas yet (§3.9), so the panel is SVG alone.
  """

  use Phoenix.Component

  alias Examples.Charts.Design
  alias Visualize.Chart

  @doc "The panel's state for `module`: its chart, drawn once, titled for the panel."
  @spec init(module()) :: map()
  def init(module) do
    {width, height} = Design.size(module, [])

    svg =
      module
      |> Design.applied([])
      |> Chart.render(root: true, summary: false, title: module.title() <> " (zoom)")

    %{svg: svg, width: width, height: height}
  end

  @doc "The panel takes no event of its own."
  @spec event(map(), map()) :: map()
  def event(state, _params), do: state

  attr(:id, :string, required: true, doc: "the panel's id")
  attr(:state, :map, required: true, doc: "the panel's state, as `init/1` gives it")

  @doc "The panel: the chart under the hook."
  def panel(assigns) do
    ~H"""
    <section id={@id} class="panel chart-panel zoom-panel">
      <h3 class="panel-title">Zoom</h3>
      <p class="panel-note">
        Scroll over the chart to zoom, drag to pan. The trend lines grow with the zoom; the
        budget line is drawn with <code>stroke: %&#123;non_scaling: true&#125;</code> and keeps
        its hairline width on screen.
      </p>
      <svg
        id={@id <> "-svg"}
        class="zoom-frame"
        phx-hook="ZoomHook"
        phx-update="ignore"
        data-min-zoom="1"
        data-max-zoom="8"
        data-zoom-event="chart_zoom"
        viewBox={"0 0 #{@state.width} #{@state.height}"}
        role="group"
        aria-label="The chart under zoom"
      >
        <g class="zoom-container">{Phoenix.HTML.raw(@state.svg)}</g>
      </svg>
      <style>
        .zoom-panel { margin-top: 1.5rem; }
        .zoom-frame { width: 100%; height: auto; display: block; border: 1px solid #e5e7eb; border-radius: 8px; cursor: grab; overflow: hidden; background: white; }
      </style>
    </section>
    """
  end
end
