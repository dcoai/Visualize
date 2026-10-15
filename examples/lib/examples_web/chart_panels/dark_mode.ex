defmodule ExamplesWeb.ChartPanels.DarkMode do
  @moduledoc """
  **Automatic dark mode** (spec/08 §7.3, spec/14 §12.6, #705): the chart's design applied
  with no theme — the implicit default — drawn twice, as `Visualize.Chart.render/2` writes
  it and with `color_scheme: false`.

  The gallery applies every chart with its palette's theme, and a theme the host sets turns
  the automatic dark mode off, so the chart above the panel never shows it. Here the first
  drawing's root carries the `prefers-color-scheme` rule and follows the viewer's own
  setting; the switch previews either scheme by reading the rule's media condition as
  always (`@media all`) or never (`@media not all`) true. The second drawing carries no
  rule and is the same under all three.
  """

  use Phoenix.Component

  alias Examples.Charts.Design
  alias Visualize.{Chart, Theme}

  @schemes [system: "Your system", light: "Light", dark: "Dark"]
  @rule "@media (prefers-color-scheme: dark)"

  @doc "The panel's state for `module`: both drawings, the viewer's own scheme shown."
  @spec init(module()) :: map()
  def init(module), do: Map.put(drawings(module), :scheme, :system)

  @doc """
  The state after a `chart_panel` event: `scheme` is matched against the three by name, and
  a word that is none of them changes nothing and makes no atom.
  """
  @spec event(map(), map()) :: map()
  def event(state, %{"scheme" => word}) do
    case Enum.find(Keyword.keys(@schemes), &(Atom.to_string(&1) == word)) do
      nil -> state
      key -> %{state | scheme: key}
    end
  end

  def event(state, _params), do: state

  @doc """
  The two drawings of `module`'s design under the implicit theme: `implicit`, whose root
  carries the automatic dark mode rule, and `fixed`, drawn with `color_scheme: false`. Each
  is titled for what it is, so the two roots — and the chart above them — never share an
  id, which the rule is scoped to.
  """
  @spec drawings(module()) :: %{implicit: String.t(), fixed: String.t()}
  def drawings(module) do
    {design, sources} = module.design([])
    {:ok, applied} = Chart.apply(design, sources: sources, size: Design.size(module, []))
    opts = [root: true, responsive: true, summary: false]

    %{
      implicit: Chart.render(applied, [title: module.title() <> " (implicit theme)"] ++ opts),
      fixed:
        Chart.render(
          applied,
          [title: module.title() <> " (color_scheme: false)", color_scheme: false] ++ opts
        )
    }
  end

  @doc """
  The implicit drawing as a viewer in `scheme` sees it: `:system` as written, `:dark` with
  the rule's media condition always true, `:light` with it never true.
  """
  @spec preview(String.t(), :system | :light | :dark) :: String.t()
  def preview(svg, :system), do: svg
  def preview(svg, :dark), do: String.replace(svg, @rule, "@media all")
  def preview(svg, :light), do: String.replace(svg, @rule, "@media not all")

  attr(:id, :string, required: true, doc: "the panel's id")
  attr(:state, :map, required: true, doc: "the panel's state, as `init/1` gives it")

  @doc "The panel: the switch and the two drawings."
  def panel(assigns) do
    assigns =
      assign(assigns,
        schemes: @schemes,
        scheme: assigns.state.scheme,
        implicit: assigns.state.implicit,
        fixed: assigns.state.fixed,
        dark: Theme.dark().background
      )

    ~H"""
    <section id={@id} class="panel chart-panel dark-mode-panel">
      <h3 class="panel-title">Automatic dark mode</h3>
      <p class="panel-note">
        The chart above is drawn in the palette's theme, and a theme the host sets turns
        automatic dark mode off. Below, the same design is applied with no theme: its root
        carries a rule that swaps every slot and every name of the color table to the dark
        theme's when the viewer prefers dark, the transforms with them. Beside it, the same
        chart rendered with <code>color_scheme: false</code> carries no rule.
      </p>
      <div class="scheme-switch" role="group" aria-label="Preview a color scheme">
        <span class="scheme-switch-label">Viewer prefers:</span>
        <button
          :for={{key, word} <- @schemes}
          type="button"
          phx-click="chart_panel"
          phx-value-panel="dark_mode"
          phx-value-scheme={key}
          aria-pressed={to_string(@scheme == key)}
          class={"scheme-btn" <> if(@scheme == key, do: " active", else: "")}
        >
          {word}
        </button>
      </div>
      <div class="scheme-pair">
        <figure class={"scheme-view scheme-#{@scheme}"} data-scheme={@scheme}>
          <figcaption>No theme named: follows the viewer</figcaption>
          {Phoenix.HTML.raw(preview(@implicit, @scheme))}
        </figure>
        <figure class="scheme-view scheme-fixed">
          <figcaption><code>color_scheme: false</code>: stays light</figcaption>
          {Phoenix.HTML.raw(@fixed)}
        </figure>
      </div>
      <style>
        .dark-mode-panel { margin-top: 1.5rem; }
        .scheme-switch { display: flex; flex-wrap: wrap; gap: 0.5rem; align-items: center; margin-bottom: 0.75rem; }
        .scheme-switch-label { color: #666; font-size: 0.9rem; }
        .scheme-btn { border: 1px solid #d1d5db; background: white; border-radius: 6px; padding: 0.25rem 0.75rem; cursor: pointer; }
        .scheme-btn.active { background: #667eea; border-color: #667eea; color: white; }
        .scheme-pair { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 1rem; }
        .scheme-view { margin: 0; padding: 0.5rem; border: 1px solid #e5e7eb; border-radius: 8px; background: white; }
        .scheme-view figcaption { font-size: 0.85rem; color: #666; margin-bottom: 0.25rem; }
        .scheme-view svg { width: 100%; height: auto; display: block; }
        .scheme-dark { background: <%= @dark %>; }
        .scheme-dark figcaption { color: #c7cbd3; }
        @media (prefers-color-scheme: dark) {
          .scheme-system { background: <%= @dark %>; }
          .scheme-system figcaption { color: #c7cbd3; }
        }
      </style>
    </section>
    """
  end
end
