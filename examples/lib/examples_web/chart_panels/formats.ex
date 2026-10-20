defmodule ExamplesWeb.ChartPanels.Formats do
  @moduledoc """
  **Stored forms** (spec/14 §9, §11, §19.7, §12.6, #781, work item #820): the chart's design
  as the JSON a host stores — `Visualize.Chart.to_json/1`, read back by `from_json/2` —
  one of its styles as a fragment a host's library keeps (`Visualize.Chart.Fragment`), and
  the chart's own document refused two ways before a key of it is decoded: stamped a newer
  version, and holding a misspelled and a retired tag (D-182).

  Closed by default: the forms are made when the panel opens, so a page that never opens
  it pays nothing for them.
  """

  use Phoenix.Component

  alias ExamplesWeb.Highlight
  alias Visualize.Chart
  alias Visualize.Chart.{Fragment, Validator}

  @doc "The panel's state for `module`: closed, its forms not made yet."
  @spec init(module()) :: map()
  def init(module), do: %{module: module, open: false, forms: nil}

  @doc "Opening makes the forms; closing hides them."
  @spec event(map(), map()) :: map()
  def event(%{open: false} = state, %{"action" => "open"}),
    do: %{state | open: true, forms: state.forms || forms(state.module)}

  def event(state, %{"action" => "close"}), do: %{state | open: false}
  def event(state, _params), do: state

  @doc """
  The forms of `module`'s design: its JSON and whether it reads back equal, a style as a
  fragment and whether that reads back equal, and the refused documents with their faults.
  """
  @spec forms(module()) :: map()
  def forms(module) do
    {design, _sources} = module.design([])
    chart = Chart.from_map!(design)
    {:ok, json} = Chart.to_json(chart)
    document = Jason.decode!(json)

    %{
      json: Jason.encode!(document, pretty: true),
      round_trip: Chart.from_json(json) == {:ok, chart},
      fragment: fragment(chart),
      refused: refused(document)
    }
  end

  # The first of the design's named styles, as a fragment a host's library stores: a
  # design's `styles` holding that one entry. `nil` for a design that names none.
  defp fragment(%Chart{styles: styles}) when map_size(styles) == 0, do: nil

  defp fragment(%Chart{styles: styles}) do
    name = styles |> Map.keys() |> Enum.min()
    entry = %{styles: %{name => Map.fetch!(styles, name)}}
    {:ok, json} = Fragment.to_json(entry)

    %{
      name: name,
      json: json |> Jason.decode!() |> Jason.encode!(pretty: true),
      round_trip: Fragment.from_json(json) == {:ok, entry}
    }
  end

  # The chart's own document changed so the reader refuses it: a newer `version`, and —
  # for a design with a mark — its first mark's style holding a misspelled tag and one the
  # table retired. Each is `{title, change, faults}`.
  defp refused(document) do
    newer = Map.put(document, "version", 99)
    [{"Written by a newer library", ~s|"version": 99|, faults(newer)} | tagged(document)]
  end

  defp tagged(%{"marks" => [mark | marks]} = document) do
    style = [%{"$feild" => "series"}, %{"$styles" => "series"}]
    changed = %{document | "marks" => [Map.put(mark, "style", style) | marks]}

    [
      {"A tag misspelled, and one retired", ~s|"marks"[0]."style": #{Jason.encode!(style)}|,
       faults(changed)}
    ]
  end

  defp tagged(_document), do: []

  defp faults(document) do
    {:error, faults} = document |> Jason.encode!() |> Chart.from_json()
    Enum.map(faults, &Validator.format/1)
  end

  attr(:id, :string, required: true, doc: "the panel's id")
  attr(:state, :map, required: true, doc: "the panel's state, as `init/1` gives it")

  @doc "The panel: a button, then the forms once open."
  def panel(assigns) do
    ~H"""
    <section id={@id} class="panel chart-panel formats-panel">
      <h3 class="panel-title">Stored forms</h3>
      <p class="panel-note">
        A design is data, so a host stores it as JSON and reads it back; its parts travel
        as fragments in a library. A reader checks the version and every tag before it
        decodes a key, so a document it cannot read is refused at its path and makes no atom.
      </p>
      <button
        type="button"
        class="formats-toggle"
        phx-click="chart_panel"
        phx-value-panel="formats"
        phx-value-action={if @state.open, do: "close", else: "open"}
      >
        {if @state.open, do: "Hide the stored forms", else: "Show the stored forms"}
      </button>
      <div :if={@state.open} class="formats-body">
        <h4>The chart, as JSON</h4>
        <p class="panel-note">
          <code>Visualize.Chart.to_json/1</code>; <code>from_json/2</code>
          reads it back <strong class="formats-round-trip">{if @state.forms.round_trip,
            do: "equal to the chart",
            else: "different from the chart"}</strong>.
        </p>
        <div class="formats-json"><Highlight.code code={@state.forms.json} /></div>

        <%= if @state.forms.fragment do %>
          <h4>A style, as a fragment</h4>
          <p class="panel-note">
            The style <code>{inspect(@state.forms.fragment.name)}</code>
            as a library keeps it, <code>Visualize.Chart.Fragment.to_json/1</code>;
            <code>from_json/2</code>
            reads it back <strong class="formats-fragment-round-trip">{if @state.forms.fragment.round_trip,
              do: "equal",
              else: "different"}</strong>. A stored style entry, the singular <code>%&#123;style: …&#125;</code>, cannot be written yet when it holds a typed
            value (#823).
          </p>
          <div class="formats-json"><Highlight.code code={@state.forms.fragment.json} /></div>
        <% end %>

        <h4>Documents the reader refuses</h4>
        <div :for={{title, change, faults} <- @state.forms.refused} class="formats-refused">
          <p><strong>{title}</strong> — the chart's own document with <code>{change}</code>:</p>
          <p :for={fault <- faults} class="formats-fault">{fault}</p>
        </div>
      </div>
      <style>
        .formats-panel { margin-top: 1.5rem; }
        .formats-json { max-height: 20rem; overflow: auto; font-size: 0.75rem; }
        .formats-fault { color: #a3171c; font-family: monospace; font-size: 0.85rem; margin: 0.2rem 0; }
      </style>
    </section>
    """
  end
end
