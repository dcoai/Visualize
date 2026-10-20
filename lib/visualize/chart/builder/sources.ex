if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Sources do
    @moduledoc """
    The data page (spec/14 §19.10, #372): what the *sources* root shows — one row per source
    of the composed design, its name, its columns with their types, and its generator while
    designing (a `Visualize.Signals` signal under the source's name) or the host's rows.

    One list, one name: a signal's fields are always its source's `fields`, written from
    the row, so the two cannot drift. This module renders; the builder holds the design,
    the signals and the tick.

    This module compiles only when `Phoenix.Component` is loaded (spec/10 §1.1, D-45, D-85).
    """

    import Visualize.Chart.Names, only: [is_name: 1]

    use Phoenix.Component

    alias Visualize.Chart.{Names, Schema, Var}
    alias Visualize.Signals

    @numbers [:window, :period, :min, :max, :seed]

    attr(:id, :string, required: true, doc: "the panel's id")
    attr(:rows, :list, required: true, doc: "the page's rows, as `rows/5` gives them")
    attr(:tick, :integer, default: 0, doc: "the tick the pool stands at")
    attr(:playing, :boolean, default: false, doc: "whether the tick advances")
    attr(:tick_ms, :integer, default: 500, doc: "the tick's period")
    attr(:pool, :list, default: [], doc: "the host's pool names, for a source's default")
    attr(:defaults?, :boolean, default: true, doc: "whether a source's `default` is offered")
    attr(:target, :any, default: nil, doc: "the `phx-target` of the panel's events")

    @doc "Renders the data page."
    def panel(assigns) do
      ~H"""
      <div id={@id} class="vis-builder-sources">
        <h3 class="vis-builder-context-title vis-builder-sidebar-title-row">
          data
          <button
            type="button"
            class="vis-builder-add"
            title="add a source: two columns and a sine while designing"
            aria-label="add a source"
            phx-click="add_source"
            phx-target={@target}
          >+</button>
        </h3>
        <p :if={@rows == []} class="vis-builder-context-note">
          no data yet — a source is the columns the chart draws, generated while it is designed or bound by the host
        </p>
        <section :for={{row, n} <- Enum.with_index(@rows)} class="vis-builder-source" data-builder-source={row.name} data-builder-node={"sources." <> row.name}>
          <form id={"#{@id}-source-#{n}-name"} class="vis-builder-source-name" phx-change="rename_source" phx-target={@target} phx-submit="submitted">
            <input type="hidden" name="source" value={row.name} />
            <input
              type="text"
              name="name"
              value={row.name}
              class="vis-builder-name"
              aria-label={"the name of #{row.name}"}
              phx-debounce="blur"
            />
            <span :if={row.layer} class="vis-builder-section-layer">{row.layer}</span>
            <button
              type="button"
              class="vis-builder-item-remove"
              title={"remove #{row.name}"}
              aria-label={"remove #{row.name}"}
              phx-click="remove_source"
              phx-value-source={row.name}
              phx-target={@target}
            >×</button>
          </form>
          <ol class="vis-builder-columns">
            <li :for={{column, m} <- Enum.with_index(row.columns)} class="vis-builder-column">
              <span :if={column.var} class="vis-builder-var-chip vis-builder-var-chip-bound">var(:{column.var})</span>
              <form :if={!column.var} id={"#{@id}-source-#{n}-column-#{m}-name"} class="vis-builder-column-name" phx-change="rename_column" phx-target={@target} phx-submit="submitted">
                <input type="hidden" name="source" value={row.name} />
                <input type="hidden" name="column" value={column.name} />
                <input
                  type="text"
                  name="name"
                  value={column.name}
                  aria-label={"the name of #{column.name}"}
                  phx-debounce="blur"
                />
              </form>
              <form :if={!column.var} id={"#{@id}-source-#{n}-column-#{m}-type"} class="vis-builder-column-type" phx-change="set_column_type" phx-target={@target} phx-submit="submitted">
                <input type="hidden" name="source" value={row.name} />
                <input type="hidden" name="column" value={column.name} />
                <select name="type" aria-label={"the type of #{column.name}"}>
                  <option value="" selected={column.type == nil}>type</option>
                  <option :for={type <- Schema.column_types()} value={type} selected={column.type == type}>{type}</option>
                </select>
              </form>
              <span :if={column.suggested} class="vis-builder-item-text" title="what the rows suggest">{column.suggested}</span>
              <button
                type="button"
                class="vis-builder-item-remove"
                title={"remove #{column.name}"}
                aria-label={"remove #{column.name} from #{row.name}"}
                phx-click="remove_column"
                phx-value-source={row.name}
                phx-value-column={column.name}
                phx-target={@target}
              >×</button>
            </li>
          </ol>
          <div class="vis-builder-column-picks" :if={row.picks != []}>
            <button
              :for={pick <- row.picks}
              type="button"
              class="vis-builder-column-pick"
              title={"#{pick} — in the rows, not declared"}
              phx-click="add_column"
              phx-value-source={row.name}
              phx-value-name={pick}
              phx-target={@target}
            >+ {pick}</button>
          </div>
          <form id={"#{@id}-source-#{n}-add-column"} class="vis-builder-column-add" phx-submit="add_column" phx-target={@target}>
            <input type="hidden" name="source" value={row.name} />
            <span class="vis-builder-item-add" data-builder-bind="fields">
              <input type="text" name="name" class="vis-builder-item-box" placeholder="+ add a column" aria-label={"a column to add to #{row.name}"} />
            </span>
          </form>
          <form id={"#{@id}-source-#{n}-generator"} class="vis-builder-generator" phx-change="set_generator" phx-target={@target} phx-submit="submitted">
            <input type="hidden" name="source" value={row.name} />
            <label class="vis-builder-field">
              <span class="vis-builder-key">while designing</span>
              <select name="kind" aria-label={"the generator of #{row.name}"}>
                <option value="" selected={row.signal == nil}>none</option>
                <option :for={kind <- Signals.kinds()} value={kind} selected={row.signal != nil and row.signal.kind == kind}>{kind}</option>
              </select>
            </label>
            <span :if={row.signal == nil and row.host_rows > 0} class="vis-builder-item-text">{row.host_rows} rows from the host</span>
            <span :if={row.signal == nil and row.host_rows == 0} class="vis-builder-item-text">no rows — pick a generator</span>
          </form>
          <form :if={row.signal} id={"#{@id}-source-#{n}-signal"} class="vis-builder-signals" phx-change="edit_signal" phx-target={@target} phx-submit="submitted">
            <div class="vis-builder-signal-numbers">
              <label :for={{key, value} <- row.signal.numbers} class="vis-builder-field">
                <span class="vis-builder-key">{key}</span>
                <input type="number" name={"#{row.name}.#{key}"} value={value} step="any" />
              </label>
            </div>
          </form>
          <form :if={@defaults?} id={"#{@id}-source-#{n}-default"} class="vis-builder-source-default" phx-change="set_default_source" phx-target={@target} phx-submit="submitted">
            <input type="hidden" name="source" value={row.name} />
            <label class="vis-builder-field">
              <span class="vis-builder-key">from the host</span>
              <input
                type="text"
                name="default"
                list={@id <> "-pool"}
                value={row.default}
                placeholder="its own name"
                aria-label={"the pool entry that fills #{row.name}"}
                phx-debounce="blur"
              />
            </label>
          </form>
        </section>
        <datalist :if={@defaults?} id={@id <> "-pool"}>
          <option :for={name <- @pool} value={name}></option>
        </datalist>
        <div class="vis-builder-play">
          <button
            type="button"
            class="vis-builder-play-button"
            phx-click={if(@playing, do: "pause", else: "play")}
            phx-target={@target}
            aria-pressed={to_string(@playing)}
          >{if @playing, do: "pause", else: "play"}</button>
          <span class="vis-builder-item-text">tick {@tick}</span>
          <form id={@id <> "-tick"} class="vis-builder-tick-period" phx-change="tick_ms" phx-target={@target} phx-submit="submitted">
            <label class="vis-builder-control-label" for={@id <> "-ms"}>every</label>
            <input id={@id <> "-ms"} type="number" name="ms" value={@tick_ms} min="50" step="50" />
            <span class="vis-builder-item-text">ms</span>
          </form>
        </div>
      </div>
      """
    end

    @doc """
    The page's rows (spec/14 §19.10, #372), sorted by name: for every source the composed
    design declares, its columns — each with the type the design gives it and, when it
    gives none, what the rows suggest — its signal's kind and numbers when it has one, the
    host's row count, and its `default`. `owners` maps a source's name to the layer that
    declares it, shown beside the name.

        iex> design = %{sources: %{feed: %{fields: [:t, :v], types: %{t: :time}}}}
        iex> signals = %{feed: Visualize.Signals.new(:sine, [:t, :v], window: 8)}
        iex> [row] = Visualize.Chart.Builder.Sources.rows(design, signals, %{}, %{}, %{})
        iex> {row.name, Enum.map(row.columns, &{&1.name, &1.type}), row.signal.kind, row.signal.numbers}
        {"feed", [{"t", :time}, {"v", nil}], :sine, [window: 8, period: 12, min: 0, max: 100, seed: 0]}
        iex> [row] = Visualize.Chart.Builder.Sources.rows(design, %{}, %{feed: [%{t: 1, v: 2, w: 3}]}, %{feed: %{t: :number, v: :number, w: :number}}, %{})
        iex> {row.picks, row.host_rows, Enum.map(row.columns, & &1.suggested)}
        {["w"], 1, [nil, :number]}
    """
    @spec rows(map(), %{atom() => Signals.t()}, map(), map(), %{atom() => term()}) :: [map()]
    def rows(design, signals, pool, pool_types, owners) do
      sources = Map.get(design, :sources) || %{}

      for {name, node} <- Enum.sort_by(sources, fn {name, _} -> to_string(name) end),
          is_map(node) do
        fields = List.wrap(Map.get(node, :fields, []))
        names = fields |> Enum.filter(&is_name/1) |> Enum.map(&Names.name/1)
        types = Map.get(node, :types) || %{}
        # The host's pool and its rows' types by the name's spelling (D-195).
        suggested = spelled(pool_types, name) || %{}
        signal = spelled(signals, name)

        %{
          name: to_string(name),
          layer: owners |> Map.get(name) |> then(&(&1 && to_string(&1))),
          columns:
            for field <- fields, is_name(field) or is_struct(field, Var) do
              case field do
                %Var{name: var} ->
                  %{name: "var(:#{var})", var: to_string(var), type: nil, suggested: nil}

                field ->
                  type = spelled(types, field)

                  %{
                    name: to_string(field),
                    var: nil,
                    type: type,
                    suggested: if(type == nil, do: spelled(suggested, field))
                  }
              end
            end,
          picks:
            for(
              column <- suggested |> Map.keys() |> Enum.map(&Names.name/1) |> Enum.sort(),
              column not in names,
              do: column
            ),
          signal:
            signal &&
              %{kind: signal.kind, numbers: for(key <- @numbers, do: {key, Map.get(signal, key)})},
          host_rows: if(signal, do: 0, else: host_rows(pool, name)),
          default: Map.get(node, :default)
        }
      end
    end

    defp spelled(map, name) when is_map(map) do
      case Names.fetch(map, name) do
        {:ok, value} -> value
        :error -> nil
      end
    end

    defp spelled(_map, _name), do: nil

    defp host_rows(pool, name) do
      case spelled(pool, name) do
        nil -> 0
        source -> source |> Visualize.Data.Table.rows() |> length()
      end
    end

    @doc """
    A signal edited by one number of the page (spec/14 §19.10): `window`, `period`, `min`,
    `max` or `seed`; anything unreadable leaves the signal as it is. A signal's kind and
    fields are the row's — `set_generator` and the columns — not this.

        iex> s = Visualize.Signals.new(:sine, [:t, :v])
        iex> Visualize.Chart.Builder.Sources.edit(s, "window", "12").window
        12
        iex> Visualize.Chart.Builder.Sources.edit(s, "window", "none") == s
        true
        iex> Visualize.Chart.Builder.Sources.edit(s, "fields", "a, b") == s
        true
    """
    @spec edit(Signals.t(), String.t(), String.t()) :: Signals.t()
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
