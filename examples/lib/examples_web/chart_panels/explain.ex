defmodule ExamplesWeb.ChartPanels.Explain do
  @moduledoc """
  **Why it looks as it does** (spec/14 §12.6, §17.3, #705): click an element of the chart
  and see `Visualize.Chart.explain/2` at it — each part of its style, whether its kind
  draws it, and the layers that set it.

  Closed until opened, since opening draws the chart: its design under the theme the page
  picked (#792) as SVG with `paths: true`, so every node the frame draws carries its path, under
  `BuilderHook` in scope `graph` — the builder's own gesture — whose click pushes `pick`
  with the node's path. The answer is drawn by the builder inspector's own component,
  `Visualize.Chart.Builder.Inspector.look/1`.
  """

  use Phoenix.Component

  alias Examples.Charts.Design
  alias Visualize.Chart
  alias Visualize.Chart.Builder.Inspector

  @doc "The panel's state for the gallery chart `module` under Default: closed, nothing picked."
  @spec init(module()) :: map()
  def init(module), do: themed(module, nil)

  @doc """
  The panel's state for the gallery chart `module` under the picker's theme `key`
  (`Examples.Themes`, #792): closed, nothing picked.
  """
  @spec themed(module(), String.t() | nil) :: map()
  def themed(module, key), do: init(module.title(), applier(module, key))

  @doc """
  The state with the chart applied by `applied` from now on — the page picked another
  theme (#792): an open panel draws the chart again, and the element it explains is
  explained again, for the same datum, so its style stack shows the new theme's layer.
  """
  @spec retheme(map(), (-> Chart.Applied.t())) :: map()
  def retheme(state, applied) when is_function(applied, 0) do
    state = %{state | applied: applied}

    if state.open do
      %{state | open: false}
      |> event(%{"action" => "open"})
      |> reexplain(state.node, state.datum)
    else
      state
    end
  end

  @doc "The function that applies `module` under the picker's theme `key`, for `retheme/2`."
  @spec applier(module(), String.t() | nil) :: (-> Chart.Applied.t())
  def applier(module, key), do: fn -> Design.applied(module, theme: key) end

  defp reexplain(state, nil, _datum), do: state

  defp reexplain(state, node, datum) do
    state = event(state, %{"node" => node})
    if datum in [nil, 0], do: state, else: event(state, %{"datum" => Integer.to_string(datum)})
  end

  @doc """
  The panel's state for any applied chart: `title` names it, and `applied` makes it — a
  function, called when the panel opens and at each pick, so a chart applied with a host's
  generators and assigns (spec/14 §3.13) is explained as it is drawn.
  """
  @spec init(String.t(), (-> Chart.Applied.t())) :: map()
  def init(title, applied) when is_function(applied, 0),
    do: %{
      title: title,
      applied: applied,
      open: false,
      svg: nil,
      node: nil,
      look: nil,
      data: [],
      datum: nil
    }

  @doc """
  The state after an event: `open` draws the chart, `close` hides it, and a picked `node`
  is explained where it is a path `explain/2` takes, and named as explaining nothing where
  it is not. A mark whose style stack names a style by a field (`{:field, f}`, spec/14
  §3.6) lays that style per datum, so it is explained for one datum per value of `f` its
  rows hold, the first at once and another by `datum`, its position among them.
  """
  @spec event(map(), map()) :: map()
  def event(%{open: false} = state, %{"action" => "open"}) do
    svg =
      state.applied.()
      |> Chart.render(
        root: true,
        paths: true,
        summary: false,
        title: state.title <> " (explain)"
      )

    %{state | open: true, svg: svg}
  end

  def event(state, %{"action" => "close"}), do: %{state | open: false}

  def event(%{open: true} = state, %{"node" => node}) when is_binary(node) do
    applied = state.applied.()

    case path(node, Map.keys(applied.frames)) do
      nil ->
        %{state | node: node, look: nil, data: [], datum: nil}

      at ->
        data = data(applied, at)
        datum = if data == [], do: nil, else: 0
        %{state | node: node, data: data, datum: datum, look: explained(applied, at, data, datum)}
    end
  end

  def event(%{open: true, data: [_ | _] = data} = state, %{"datum" => word}) do
    case Enum.find(0..(length(data) - 1), &(Integer.to_string(&1) == word)) do
      nil ->
        state

      datum ->
        applied = state.applied.()
        at = path(state.node, Map.keys(applied.frames))
        %{state | datum: datum, look: explained(applied, at, data, datum)}
    end
  end

  def event(state, _params), do: state

  @doc """
  The path `explain/2` takes for a drawn node's `data-node`, or `nil` for a node it does not
  explain. A frame's name is matched against `frames`, the design's, and never made an atom.

      iex> ExamplesWeb.ChartPanels.Explain.path("marks[2]", [:main])
      [:marks, 2]
      iex> ExamplesWeb.ChartPanels.Explain.path("frames.main.axes[1]", [:main])
      [:frames, :main, :axes, 1]
      iex> ExamplesWeb.ChartPanels.Explain.path("frames.main", [:main])
      nil
  """
  @spec path(String.t(), [atom()]) :: [atom() | non_neg_integer()] | nil
  def path(node, frames) do
    case Regex.run(
           ~r/^(?:(marks|labels)\[(\d+)\]|frames\.([^.]+)\.(?:axes\[(\d+)\]|(legend)))$/,
           node
         ) do
      [_, kind, i] -> [String.to_existing_atom(kind), String.to_integer(i)]
      [_, "", "", frame, i] -> frame_path(frame, frames, [:axes, String.to_integer(i)])
      [_, "", "", frame, "", "legend"] -> frame_path(frame, frames, [:legend])
      nil -> nil
    end
  end

  defp frame_path(word, frames, rest) do
    case Enum.find(frames, &(to_string(&1) == word)) do
      nil -> nil
      frame -> [:frames, frame | rest]
    end
  end

  defp explained(applied, at, [], _datum), do: Chart.explain(applied, at: at)

  defp explained(applied, at, data, datum),
    do: Chart.explain(applied, at: at, datum: data |> Enum.at(datum) |> elem(1))

  # One datum per value of the field a mark's stack names a style by — `{label, row}` —
  # or none for a node with no such entry.
  defp data(applied, [:marks, i]) do
    mark = Enum.at(applied.chart.marks, i)

    case styled_by(Map.get(mark, :style)) do
      {:field, field} ->
        applied.sources
        |> Map.get(source(mark.data), [])
        |> Visualize.Data.Table.rows()
        |> Enum.uniq_by(&Visualize.Data.Table.get(&1, field))
        |> Enum.map(&{"#{field} = #{Visualize.Data.Table.get(&1, field)}", &1})

      nil ->
        []
    end
  end

  defp data(_applied, _at), do: []

  # The field a mark's style reads per datum: a stack's `{:field, f}` entry (spec/14 §3.6),
  # else a field a generator call takes as an argument, wherever in the style it stands —
  # a stack entry or a paint (§3.13) — or `nil`.
  defp styled_by(style) do
    Enum.find(List.wrap(style), &match?({:field, _}, &1)) || generated_field(style)
  end

  defp generated_field({:generate, _name, args}),
    do: Enum.find(args, &match?({:field, _}, &1))

  defp generated_field(list) when is_list(list), do: Enum.find_value(list, &generated_field/1)

  defp generated_field(map) when is_map(map) and not is_struct(map),
    do: map |> Map.values() |> generated_field()

  defp generated_field(_term), do: nil

  defp source(%{source: source}), do: source
  defp source(source), do: source

  # The chart with the picked node outlined: `BuilderHook` marks the drawn node the root's
  # `data-builder-selected` names.
  defp selected(svg, nil), do: svg

  defp selected(svg, node),
    do: String.replace(svg, "<svg ", ~s(<svg data-builder-selected="#{node}" ), global: false)

  attr(:id, :string, required: true, doc: "the panel's id")
  attr(:state, :map, required: true, doc: "the panel's state, as `init/1` gives it")

  @doc "The panel: closed, a button; open, the chart to click and what the click explains."
  def panel(assigns) do
    ~H"""
    <section id={@id} class="panel chart-panel explain-panel">
      <h3 class="panel-title">Why it looks as it does</h3>
      <p class="panel-note">
        Click a mark, an axis, the legend or a label to see <code>Visualize.Chart.explain/2</code>
        for it: each part of its style, whether its kind draws it, and every layer that set
        it — the theme, the defaults, named styles and what they extend, the data's choice.
      </p>
      <button
        type="button"
        class="explain-toggle"
        phx-click="chart_panel"
        phx-value-panel="explain"
        phx-value-action={if @state.open, do: "close", else: "open"}
      >
        {if @state.open, do: "Hide the chart", else: "Explain an element"}
      </button>
      <div :if={@state.open} class="explain-body">
        <div
          id={@id <> "-graph"}
          class="explain-graph"
          phx-hook="BuilderHook"
          data-builder-scope="graph"
        >
          {Phoenix.HTML.raw(selected(@state.svg, @state.node))}
        </div>
        <div class="explain-answer">
          <p :if={@state.node == nil} class="explain-hint">Nothing picked yet.</p>
          <p :if={@state.node != nil and @state.look == nil} class="explain-hint">
            <code>{@state.node}</code> has no style of its own to explain; pick a mark, an
            axis, the legend or a label.
          </p>
          <div
            :if={@state.data != []}
            class="explain-data"
            role="group"
            aria-label="Explain for a datum"
          >
            <span class="explain-hint">Styled by data; explained for</span>
            <button
              :for={{{label, _row}, i} <- Enum.with_index(@state.data)}
              type="button"
              phx-click="chart_panel"
              phx-value-panel="explain"
              phx-value-datum={i}
              aria-pressed={to_string(@state.datum == i)}
              class={"explain-datum" <> if(@state.datum == i, do: " active", else: "")}
            >
              {label}
            </button>
          </div>
          <Inspector.look
            :if={@state.look}
            id={@id <> "-look"}
            look={@state.look}
            label={@state.node}
          />
        </div>
      </div>
      <style>
        .explain-panel { margin-top: 1.5rem; }
        .explain-toggle { border: 1px solid #d1d5db; background: white; border-radius: 6px; padding: 0.35rem 0.85rem; cursor: pointer; }
        .explain-body { display: grid; grid-template-columns: minmax(0, 3fr) minmax(240px, 2fr); gap: 1rem; margin-top: 0.75rem; }
        @media (max-width: 800px) { .explain-body { grid-template-columns: 1fr; } }
        .explain-graph svg { width: 100%; height: auto; display: block; cursor: pointer; }
        .explain-graph [data-node]:hover:not(:has([data-node]:hover)) { outline: 1px dashed #667eea; }
        .explain-graph .vis-builder-graph-selected { outline: 2px solid #667eea; }
        .explain-hint { color: #666; }
        .explain-data { display: flex; flex-wrap: wrap; gap: 0.35rem; align-items: center; margin-bottom: 0.5rem; font-size: 0.85rem; }
        .explain-datum { border: 1px solid #d1d5db; background: white; border-radius: 6px; padding: 0.15rem 0.5rem; cursor: pointer; }
        .explain-datum.active { background: #667eea; border-color: #667eea; color: white; }
        .explain-answer .vis-builder-context-title { font-size: 0.95rem; margin: 0 0 0.5rem; }
        .explain-answer .vis-builder-look-part { border-top: 1px solid #e5e7eb; padding: 0.4rem 0; }
        .explain-answer .vis-builder-look-undrawn { opacity: 0.55; }
        .explain-answer .vis-builder-look-name { margin: 0; font-size: 0.9rem; }
        .explain-answer .vis-builder-look-note { color: #888; font-weight: normal; }
        .explain-answer .vis-builder-look-value { margin: 0.15rem 0; font-family: monospace; font-size: 0.8rem; color: #333; }
        .explain-answer .vis-builder-look-chain { margin: 0; padding-left: 1.2rem; font-size: 0.8rem; }
        .explain-answer .vis-builder-look-link span { margin-right: 0.4rem; }
        .explain-answer .vis-builder-look-layer { font-weight: 600; }
        .explain-answer .vis-builder-look-set { font-family: monospace; color: #555; }
      </style>
    </section>
    """
  end
end
