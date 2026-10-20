defmodule ExamplesWeb.ChartPanels do
  @moduledoc """
  The panels a chart page draws under its chart (spec/14 §12.6, #705).

  A gallery module that exports `panels/0` names the panels its page carries, from the set
  here; a module without it carries none. Each panel is a module with three functions — its
  state for a chart (`init/1`), that state after one of its events (`event/2`) and its
  markup (`panel/1`, a function component taking `id` and `state`) — and the page holds every panel's state by name, made afresh when it
  loads a chart and kept across a palette or a backend change. A panel's buttons push
  `chart_panel` with the panel's name, which the page hands to `event/3`.
  """

  use Phoenix.Component

  alias ExamplesWeb.ChartPanels.{DarkMode, Explain, Formats, Units, Zoom}

  @panels %{dark_mode: DarkMode, zoom: Zoom, units: Units, explain: Explain, formats: Formats}

  @doc """
  The panels of `module`'s page: those it names, in its order — none for a module without
  `panels/0` — then `:explain` and `:formats`, which every chart page carries.
  """
  @spec of(module()) :: [atom()]
  def of(module) do
    named =
      if Code.ensure_loaded?(module) and function_exported?(module, :panels, 0) do
        for name <- module.panels() do
          (Map.has_key?(@panels, name) and name not in [:explain, :formats]) ||
            raise ArgumentError, "#{inspect(module)} names no chart panel #{inspect(name)}"

          name
        end
      else
        []
      end

    named ++ [:explain, :formats]
  end

  @doc """
  Every panel's state for `module`, by name, in its order; *Why it looks as it does*
  explains the chart under the picker's theme `theme` (#792), Default when `nil`.
  """
  @spec init(module(), String.t() | nil) :: [{atom(), map()}]
  def init(module, theme \\ nil) do
    for name <- of(module) do
      case name do
        :explain -> {name, Explain.themed(module, theme)}
        name -> {name, Map.fetch!(@panels, name).init(module)}
      end
    end
  end

  @doc """
  The panels after the page picked the theme `theme` (#792): *Why it looks as it does*
  explains `module` under it from now on; every other panel's state is kept.
  """
  @spec retheme([{atom(), map()}], module(), String.t()) :: [{atom(), map()}]
  def retheme(panels, module, theme) do
    Enum.map(panels, fn
      {:explain, state} -> {:explain, Explain.retheme(state, Explain.applier(module, theme))}
      panel -> panel
    end)
  end

  @doc """
  The panels after a `chart_panel` event: the panel `params["panel"]` names takes it; a name
  that is none of the chart's changes nothing and makes no atom.
  """
  @spec event([{atom(), map()}], map()) :: [{atom(), map()}]
  def event(panels, %{"panel" => word} = params) do
    Enum.map(panels, fn {name, state} ->
      if Atom.to_string(name) == word,
        do: {name, Map.fetch!(@panels, name).event(state, params)},
        else: {name, state}
    end)
  end

  def event(panels, _params), do: panels

  attr(:panels, :list, required: true, doc: "every panel's state, as `init/1` gives it")
  attr(:slug, :string, required: true, doc: "the chart's slug, which keys each panel's id")

  @doc "Every panel of the chart, in its order."
  def panels(assigns) do
    ~H"""
    <%= for {name, state} <- @panels do %>
      <DarkMode.panel :if={name == :dark_mode} id={"chart-panel-#{name}-#{@slug}"} state={state} />
      <Zoom.panel :if={name == :zoom} id={"chart-panel-#{name}-#{@slug}"} state={state} />
      <Units.panel :if={name == :units} id={"chart-panel-#{name}-#{@slug}"} state={state} />
      <Explain.panel :if={name == :explain} id={"chart-panel-#{name}-#{@slug}"} state={state} />
      <Formats.panel :if={name == :formats} id={"chart-panel-#{name}-#{@slug}"} state={state} />
    <% end %>
    """
  end
end
