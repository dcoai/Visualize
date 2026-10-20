defmodule ExamplesWeb.ChartPanels.Units do
  @moduledoc """
  **Units** (spec/14 §3.9, §11, §12.6, #784): every size of the chart written in a unit,
  as the call that wrote it, the user units it resolves to (`Visualize.Units.to_px/1`, at
  CSS's ratios) and the JSON a stored design writes it as, `{"$unit": [n, "unit"]}` —
  read from `Visualize.Chart.to_json/1` of the chart's own design, so the panel shows what
  is stored rather than a copy of it.
  """

  use Phoenix.Component

  alias Visualize.Chart

  @doc """
  The panel's state for `module`: a row per style of its design that sizes a stroke in a
  unit — `{style, dash JSON, width JSON, dash px, width px}` — in the design's order.
  """
  @spec init(module()) :: map()
  def init(module) do
    {design, _sources} = module.design([])
    chart = Chart.from_map!(design)
    {:ok, json} = Chart.to_json(chart)
    stored = json |> Jason.decode!() |> Map.fetch!("styles")

    rows =
      for {name, style} <- Enum.sort_by(chart.styles, &unit_order(module, elem(&1, 0))),
          %{stroke: %{dash: [{_, _} = dash | _], width: {_, _} = width}} <- [style] do
        %{"stroke" => %{"dash" => [dash_json | _], "width" => width_json}} = stored[name]

        %{
          name: name,
          dash: Jason.encode!(dash_json),
          width: Jason.encode!(width_json),
          dash_px: Visualize.Units.to_px(dash),
          width_px: Visualize.Units.to_px(width)
        }
      end

    %{rows: rows}
  end

  # The module's own order of its unit styles, where it gives one.
  defp unit_order(module, name) do
    if function_exported?(module, :unit_names, 0),
      do: Enum.find_index(module.unit_names(), &(&1 == name)) || 99,
      else: 0
  end

  @doc "The panel takes no event of its own."
  @spec event(map(), map()) :: map()
  def event(state, _params), do: state

  attr(:id, :string, required: true, doc: "the panel's id")
  attr(:state, :map, required: true, doc: "the panel's state, as `init/1` gives it")

  @doc "The panel: one row per unit, its call, its JSON and its user units."
  def panel(assigns) do
    ~H"""
    <section id={@id} class="panel chart-panel units-panel">
      <h3 class="panel-title">Units, resolved and stored</h3>
      <p class="panel-note">
        Each line of <em>One length, six units</em>
        is dashed and widened in its own unit. Every unit is resolved on the server, so SVG and
        the canvas draw the same number; a stored design writes the unit as
        <code>&#123;"$unit": [n, "unit"]&#125;</code>
        (from <code>Visualize.Chart.to_json/1</code>).
      </p>
      <table class="units-table">
        <tr>
          <th>style</th>
          <th>dash, as JSON</th>
          <th>width, as JSON</th>
          <th>user units</th>
        </tr>
        <tr :for={row <- @state.rows}>
          <td><code>{row.name}</code></td>
          <td><code>{row.dash}</code></td>
          <td><code>{row.width}</code></td>
          <td>{format(row.dash_px)} dash, {format(row.width_px)} wide</td>
        </tr>
      </table>
      <style>
        .units-panel { margin-top: 1.5rem; }
        .units-table { border-collapse: collapse; font-size: 0.85rem; }
        .units-table th, .units-table td { padding: 0.25rem 0.6rem; text-align: left; border-bottom: 1px solid #eee; }
      </style>
    </section>
    """
  end

  defp format(px), do: :erlang.float_to_binary(px * 1.0, decimals: 2)
end
