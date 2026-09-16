if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Sources do
    @moduledoc """
    The sources tab (spec/14 §19.10): the chart's signals — generated sources of
    `Visualize.Signals` — one row each, edited in place, added, removed, and played.

    A signal stands in for the host's feed while the chart is designed: the pool the
    preview binds is the host's under the chart's signals at the tick, and a deployed design
    binds to the host's alone. This module renders; the builder holds the signals and the
    tick.

    This module compiles only when `Phoenix.Component` is loaded (spec/10 §1.1, D-45, D-85).
    """

    use Phoenix.Component

    alias Visualize.Signals

    attr(:id, :string, required: true, doc: "the panel's id")
    attr(:signals, :map, default: %{}, doc: "the chart's signals by name")
    attr(:tick, :integer, default: 0, doc: "the tick the pool stands at")
    attr(:playing, :boolean, default: false, doc: "whether the tick advances")
    attr(:tick_ms, :integer, default: 500, doc: "the tick's period")
    attr(:target, :any, default: nil, doc: "the `phx-target` of the panel's events")

    @doc "Renders the sources tab."
    def panel(assigns) do
      assigns = assign(assigns, rows: rows(assigns.signals))

      ~H"""
      <div id={@id} class="vis-builder-sources">
        <h3 class="vis-builder-context-title vis-builder-sidebar-title-row">
          sources
          <button
            type="button"
            class="vis-builder-add"
            title="declare a signal: a sine over t and value"
            aria-label="add a signal"
            phx-click="add_signal"
            phx-target={@target}
          >+</button>
        </h3>
        <p :if={@rows == []} class="vis-builder-context-note">
          no signals yet — a signal is a generated source the chart draws while it is designed
        </p>
        <form :if={@rows != []} class="vis-builder-signals" phx-change="edit_signal" phx-target={@target} phx-submit="submitted">
          <fieldset :for={row <- @rows} class="vis-builder-signal">
            <legend class="vis-builder-signal-name">
              {row.name}
              <button
                type="button"
                class="vis-builder-item-remove"
                title={"remove #{row.name}"}
                aria-label={"remove #{row.name}"}
                phx-click="remove_signal"
                phx-value-name={row.name}
                phx-target={@target}
              >×</button>
            </legend>
            <label class="vis-builder-field">
              <span class="vis-builder-key">kind</span>
              <select name={"#{row.name}.kind"}>
                <option :for={kind <- Signals.kinds()} value={kind} selected={row.kind == kind}>{kind}</option>
              </select>
            </label>
            <label class="vis-builder-field">
              <span class="vis-builder-key">fields</span>
              <input type="text" name={"#{row.name}.fields"} value={row.fields} placeholder="t, value" />
            </label>
            <div class="vis-builder-signal-numbers">
              <label :for={{key, value} <- row.numbers} class="vis-builder-field">
                <span class="vis-builder-key">{key}</span>
                <input type="number" name={"#{row.name}.#{key}"} value={value} step="any" />
              </label>
            </div>
          </fieldset>
        </form>
        <div class="vis-builder-play">
          <button
            type="button"
            class="vis-builder-play-button"
            phx-click={if(@playing, do: "pause", else: "play")}
            phx-target={@target}
            aria-pressed={to_string(@playing)}
          >{if @playing, do: "pause", else: "play"}</button>
          <span class="vis-builder-item-text">tick {@tick}</span>
          <form class="vis-builder-tick-period" phx-change="tick_ms" phx-target={@target} phx-submit="submitted">
            <label class="vis-builder-control-label" for={@id <> "-ms"}>every</label>
            <input id={@id <> "-ms"} type="number" name="ms" value={@tick_ms} min="50" step="50" />
            <span class="vis-builder-item-text">ms</span>
          </form>
        </div>
      </div>
      """
    end

    @doc """
    The signals as the tab's rows, sorted by name: the fields as one comma-separated
    string, the numbers as `{key, value}` pairs.

        iex> [row] = Visualize.Chart.Builder.Sources.rows(%{feed: Visualize.Signals.new(:sine, [:t, :v], window: 8)})
        iex> {row.name, row.kind, row.fields, row.numbers}
        {"feed", :sine, "t, v", [window: 8, period: 12, min: 0, max: 100, seed: 0]}
    """
    @spec rows(%{atom() => Signals.t()}) :: [map()]
    def rows(signals) do
      for {name, signal} <- Enum.sort_by(signals, fn {name, _} -> to_string(name) end) do
        %{
          name: to_string(name),
          kind: signal.kind,
          fields: Enum.map_join(signal.fields, ", ", &to_string/1),
          numbers:
            for(key <- [:window, :period, :min, :max, :seed], do: {key, Map.get(signal, key)})
        }
      end
    end

    @doc """
    A signal edited by one control of the tab (spec/14 §19.10): `kind`, `fields` (a
    comma-separated list, at least the time column), or a number; anything unreadable
    leaves the signal as it is.

        iex> s = Visualize.Signals.new(:sine, [:t, :v])
        iex> Visualize.Chart.Builder.Sources.edit(s, "fields", "hour, cpu, mem").fields
        [:hour, :cpu, :mem]
        iex> Visualize.Chart.Builder.Sources.edit(s, "kind", "square").kind
        :square
        iex> Visualize.Chart.Builder.Sources.edit(s, "window", "12").window
        12
        iex> Visualize.Chart.Builder.Sources.edit(s, "window", "none") == s
        true
    """
    @spec edit(Signals.t(), String.t(), String.t()) :: Signals.t()
    def edit(signal, "kind", value) do
      case Enum.find(Signals.kinds(), &(to_string(&1) == value)) do
        nil -> signal
        kind -> %{signal | kind: kind}
      end
    end

    def edit(signal, "fields", value) do
      fields =
        value
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.map(&String.to_atom/1)

      if fields == [], do: signal, else: %{signal | fields: fields}
    end

    def edit(signal, key, value) when key in ["window", "period", "min", "max", "seed"] do
      atom = String.to_existing_atom(key)

      case number(value) do
        {:ok, n} when atom == :window and is_integer(n) and n > 0 -> Map.put(signal, atom, n)
        {:ok, n} when atom == :seed and is_integer(n) -> Map.put(signal, atom, n)
        {:ok, n} when atom in [:period, :min, :max] -> Map.put(signal, atom, n)
        _other -> signal
      end
    end

    def edit(signal, _key, _value), do: signal

    defp number(value) do
      case Integer.parse(String.trim(value)) do
        {n, ""} ->
          {:ok, n}

        _ ->
          case Float.parse(String.trim(value)) do
            {f, ""} -> {:ok, f}
            _ -> :error
          end
      end
    end
  end
end
