if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder do
    @moduledoc """
    An embeddable editor of typed fragments (spec/14 §18, §19).

    A `Phoenix.LiveComponent`, not a `Phoenix.LiveView`: a LiveView owns a route and a
    session, and this embeds in whatever page a host already has.

        <.live_component module={Visualize.Chart.Builder} id="builder"
                         layers={@layers} sources={@sources} on_save={:design_saved} />

    The host owns the route, the layers the builder starts with, the pool of sample sources
    the preview binds to, the library of saved fragments (`Visualize.Chart.Builder.Store`)
    and what saving means. The builder owns the editing state alone: a **stack of use
    sites** (§19.3) — each a fragment used at a position, with what is masked, bound and
    added there — and, when a library entry is opened, that entry's fragment. The one thing
    that leaves it is a message: saving sends `{on_save, id, structure}` to the host
    LiveView process, where `structure` is the stack as a composite (§19.6); a host that
    wants a flat design flattens it with `Visualize.Chart.flatten/2`. It pushes no event
    and patches no URL (D-85).

    ## Assigns

    * `id` - the component id (required)
    * `layers` - the fragments the stack starts with, in precedence order, the higher
      later: a design map, a `Visualize.Chart` or a `{name, layer}` pair (default `[]`).
      Each is seeded as an inline-only use site (§19.9).
    * `sources` - the pool of sample sources the preview binds the design's slots to, as
      `Visualize.Chart.apply/2` takes it (default `%{}`)
    * `vars` - the values the preview applies the design's variables with (default `%{}`)
    * `theme` - a `Visualize.Theme` for the preview, `nil` for the design's own
    * `store` - a module implementing `Visualize.Chart.Builder.Store`, or `{module, context}`
      with what the host wants every callback told (spec/14 §19.7), or `nil` for no
      library (default `nil`)
    * `on_save` - the tag of the message saving sends (default `:visualize_chart_saved`)
    * `styles` - render the stylesheet in a `<style>` element (default `true`); `false` when
      the host ships `Visualize.Chart.Builder.css/0` through its own asset pipeline
    * `class` - appended to the builder's root class

    ## Handling the message

        def handle_info({:design_saved, "builder", structure}, socket) do
          {:ok, design, _missing} = Visualize.Chart.flatten(structure, &MyStore.fetch/1)
          {:noreply, assign(socket, design: design)}
        end

    This module compiles only when `Phoenix.Component` is loaded: `phoenix_live_view` is an
    optional dependency, so an application that only renders predefined charts never
    compiles a line of the builder, which `scripts/consumer_check.exs` proves on every
    pipeline (spec/10 §1.1, D-45, D-85).
    """

    use Phoenix.LiveComponent

    alias Visualize.Chart

    alias Visualize.Chart.Builder.{
      Document,
      Editor,
      Fills,
      Fonts,
      Inspector,
      Layers,
      Library,
      Masks,
      Page,
      Palette,
      Params,
      Picker,
      Place,
      Preview,
      Sources,
      Stack,
      Store,
      Styles,
      StyleStack,
      Variables
    }

    alias Visualize.Chart.{Composite, Fragment, Schema, Use, Validator, Var}
    alias Visualize.{Signals, Theme}

    @doc false
    # The assigns a host may leave out, and their defaults (spec/14 §18.2). `attr/3` applies
    # these at a `<.live_component>` call site; they are applied here too, so the component
    # is renderable directly under `Phoenix.LiveViewTest.render_component/2`.
    def defaults do
      [
        layers: [],
        sources: %{},
        vars: %{},
        theme: nil,
        store: nil,
        on_save: :visualize_chart_saved,
        on_deploy: :visualize_chart_deployed,
        source_defaults: true,
        tick_ms: 500,
        styles: true,
        class: nil
      ]
    end

    attr(:id, :string, required: true, doc: "the component id")

    attr(:layers, :list,
      default: [],
      doc: "the fragments the stack starts with, the higher later"
    )

    attr(:sources, :map, default: %{}, doc: "the pool the preview binds the design's slots to")
    attr(:vars, :map, default: %{}, doc: "the values the preview applies the variables with")
    attr(:theme, :any, default: nil, doc: "a `Visualize.Theme` for the preview")

    attr(:source_defaults, :boolean,
      default: true,
      doc: "whether a source's `default` is offered in the form (spec/14 §18.1, §19.10)"
    )

    attr(:tick_ms, :integer,
      default: 500,
      doc: "the period of the signals' tick while playing (spec/14 §19.10)"
    )

    attr(:store, :any,
      default: nil,
      doc: "a `Visualize.Chart.Builder.Store`, or `{module, context}`"
    )

    attr(:on_save, :any, default: :visualize_chart_saved, doc: "the tag of the save message")

    attr(:on_deploy, :any,
      default: :visualize_chart_deployed,
      doc: "the tag of the deploy message: the flat design, where save's carries structure"
    )

    attr(:styles, :boolean,
      default: true,
      doc: "render the stylesheet, `false` if the host ships it"
    )

    attr(:class, :string, default: nil, doc: "appended to the builder's root class")

    @impl true
    def mount(socket) do
      {:ok,
       assign(socket,
         uses: [],
         labels: %{},
         selected: nil,
         open: nil,
         charts: [],
         chart: nil,
         next_chart: 1,
         signals: %{},
         tick: 0,
         playing: false,
         stack_vars: %{},
         notice: nil,
         facet: nil,
         added: nil,
         library_view: :group,
         style_entry: nil,
         field: nil,
         adding: false,
         context: :inspect,
         library_open: true,
         context_width: 400,
         collapsed: MapSet.new(),
         guessed: MapSet.new(),
         expanded: MapSet.new(),
         find: "",
         node_label: "design"
       )}
    end

    @impl true
    def update(%{tick: :next}, socket) do
      if socket.assigns.playing,
        do: {:ok, socket |> update(:tick, &(&1 + 1)) |> schedule()},
        else: {:ok, socket}
    end

    def update(assigns, socket) do
      socket =
        socket
        |> assign(Map.drop(assigns, [:layers]))
        |> seed(assigns)
        |> then(&Enum.reduce(defaults(), &1, fn pair, acc -> default(pair, acc) end))

      # The parameters form edits the builder's own copy of the bindings: the host gives the
      # values the builder starts with and never hears of a change (spec/14 §18.11, D-88).
      {:ok, assign_new(socket, :bindings, fn -> socket.assigns.vars end)}
    end

    # `layers` is seeded and not controlled, because the stack is what the builder writes
    # to: adopting the host's list on every parent render would discard the edit that render
    # was caused by. A list that differs from the one the host last gave is a host
    # deliberately replacing the stack and is taken; an equal one leaves the editing session
    # alone (spec/14 §18.1, D-95). Each fragment becomes an inline-only use (§19.9).
    defp seed(socket, %{layers: layers}) do
      if Map.get(socket.assigns, :host_layers, :unseeded) == layers do
        socket
      else
        {uses, labels} = Stack.seed(layers)

        socket
        |> assign(host_layers: layers)
        |> seeded_chart(uses, labels)
      end
    end

    defp seed(socket, _assigns), do: socket

    # The host's layers are the first chart of the workspace (spec/14 §19.9); a host
    # replacing its list replaces that chart's stack and leaves the others alone.
    defp seeded_chart(%{assigns: %{charts: []}} = socket, uses, labels) do
      socket
      |> assign(uses: uses, labels: labels, stack_vars: %{}, open: nil, signals: %{})
      |> assign(selected: selection(socket.assigns.selected, uses))
      |> added_chart("chart 1")
    end

    defp seeded_chart(socket, uses, labels) do
      first = hd(socket.assigns.charts)

      socket
      |> park()
      |> update(:charts, fn charts ->
        List.update_at(
          charts,
          0,
          &%{&1 | uses: uses, labels: labels, selected: selection(&1.selected, uses)}
        )
      end)
      |> load(first.id)
    end

    # A selection that names a use the seeded stack has is kept — a host may seed one, and
    # the person's place survives a replaced list of the same shape — else the first use.
    defp selection(selected, uses) do
      case Stack.get(uses, selected) do
        nil -> uses |> List.first() |> then(&(&1 && &1.id))
        use -> use.id
      end
    end

    defp default({key, value}, socket), do: assign_new(socket, key, fn -> value end)

    @impl true
    def render(assigns) do
      assigns = assign(assigns, editing(assigns))

      ~H"""
      <div id={@id} class={class("vis-builder", @class)}>
        <Styles.styles :if={@styles} />
        <div class="vis-builder-toolbar">
          <span class="vis-builder-layer-count">{length(@uses)}</span>
          <form :if={@store} class="vis-builder-new" phx-submit="new_fragment" phx-target={@myself}>
            <label class="vis-builder-control-label" for={@id <> "-new-kind"}>New</label>
            <select id={@id <> "-new-kind"} name="kind" class="vis-builder-new-kind">
              <option :for={kind <- Stack.kinds()} value={kind}>{kind}</option>
            </select>
            <button type="submit" class="vis-builder-new-submit">New</button>
          </form>
          <form :if={@store} class="vis-builder-keep" phx-submit="put_design" phx-target={@myself}>
            <label class="vis-builder-control-label" for={@id <> "-keep"}>
              {if @open, do: "Save as", else: "Save the chart as"}
            </label>
            <input
              id={@id <> "-keep"}
              type="text"
              name="name"
              class="vis-builder-name"
              value={(@open && @open.name) || ""}
              placeholder="Group:sub-group:name"
            />
            <button type="submit" class="vis-builder-put">Save to library</button>
          </form>
          <button type="button" class="vis-builder-save" phx-click="save" phx-target={@myself}>
            Save
          </button>
          <button
            :if={@preview?}
            type="button"
            class="vis-builder-deploy"
            phx-click="deploy"
            phx-target={@myself}
            title="flatten the stack through the library and hand the host the design"
          >
            Deploy
          </button>
        </div>
        <p :if={@notice} class="vis-builder-notice">{@notice}</p>
        <div class={
          class(
            "vis-builder-panels",
            cond do
              @store && @library_open -> "vis-builder-panels-library"
              @store -> "vis-builder-panels-library vis-builder-panels-library-folded"
              true -> nil
            end
          )
        } style={"--vis-builder-context: #{@context_width}px"}>
          <Library.panel
            :if={@store && @library_open}
            id={@id <> "-library"}
            entries={Store.list(@store)}
            view={@library_view}
            open={(@open && @open.id) || @added}
            target={@myself}
          />
          <aside :if={@store && !@library_open} class="vis-builder-library-rail">
            <button
              type="button"
              class="vis-builder-library-fold"
              title="show the library"
              aria-label="show the library"
              aria-expanded="false"
              phx-click="library_fold"
              phx-target={@myself}
            >▸</button>
            <span class="vis-builder-library-rail-word">Library</span>
          </aside>
          <aside class="vis-builder-sidebar">
            <h2 class="vis-builder-sidebar-title vis-builder-sidebar-title-row">
              Charts
              <button
                type="button"
                class="vis-builder-add"
                title="add a chart: one frame layer to start"
                aria-label="add a chart"
                phx-click="add_chart"
                phx-target={@myself}
              >+</button>
            </h2>
            <ol class="vis-builder-charts">
              <li
                :for={row <- @chart_rows}
                class={"vis-builder-chart" <> if(row.selected?, do: " vis-builder-chart-selected", else: "")}
              >
                <div class="vis-builder-chart-row">
                  <button
                    type="button"
                    class="vis-builder-chart-toggle"
                    title={if(row.expanded, do: "collapse", else: "expand")}
                    aria-label={"#{if(row.expanded, do: "collapse", else: "expand")} #{row.name}"}
                    aria-expanded={to_string(row.expanded)}
                    phx-click="toggle_chart"
                    phx-value-chart={row.id}
                    phx-target={@myself}
                  >{if row.expanded, do: "▾", else: "▸"}</button>
                  <button
                    type="button"
                    class="vis-builder-chart-name"
                    title={row.title}
                    phx-click="select_chart"
                    phx-value-chart={row.id}
                    phx-target={@myself}
                  >{row.name}<span :if={row.kind} class="vis-builder-chart-kind">{row.kind}</span></button>
                  <button
                    :if={row.selected?}
                    type="button"
                    class="vis-builder-add"
                    title="add an empty site below the selected layer"
                    aria-label="add a site"
                    aria-expanded={to_string(@adding)}
                    phx-click="adding"
                    phx-target={@myself}
                  >+</button>
                  <button
                    type="button"
                    class="vis-builder-chart-close"
                    title={"close #{row.name}"}
                    aria-label={"close #{row.name}"}
                    phx-click="close_chart"
                    phx-value-chart={row.id}
                    phx-target={@myself}
                  >×</button>
                </div>
                <div :if={row.selected? and @adding} class="vis-builder-add-menu" role="menu" aria-label="a kind to add">
                  <button
                    :for={kind <- Stack.kinds() -- [:composite]}
                    type="button"
                    class="vis-builder-add-kind"
                    role="menuitem"
                    phx-click="add_site"
                    phx-value-kind={kind}
                    phx-target={@myself}
                  >{kind}</button>
                </div>
                <Layers.panel
                  :if={row.selected? and row.expanded}
                  id={@id <> "-layers"}
                  layers={@layers}
                  selected={@selected_index}
                  disabled={@disabled}
                  locked={@locked}
                  target={@myself}
                />
                <ol :if={not row.selected? and row.expanded} class="vis-builder-layers vis-builder-layers-other">
                  <li :for={{name, index} <- row.layers} class="vis-builder-layer">
                    <button
                      type="button"
                      class="vis-builder-layer-name vis-builder-layer-other"
                      phx-click="select_chart_layer"
                      phx-value-chart={row.id}
                      phx-value-index={index}
                      phx-target={@myself}
                    >{name}</button>
                  </li>
                </ol>
              </li>
            </ol>
            <p :if={@missing != []} class="vis-builder-missing">
              {length(@missing)} {if length(@missing) == 1, do: "reference", else: "references"} no longer exist — showing through
            </p>
            <p :if={@unplaced != []} class="vis-builder-missing">
              not placed: {Enum.join(@unplaced, ", ")} — a style, scale, source or var needs a name to be declared under
            </p>
          </aside>
          <main class="vis-builder-main">
            <div
              id={@id <> "-graph"}
              class="vis-builder-graph"
              phx-hook="BuilderHook"
              data-builder-target={@myself}
              data-builder-scope="graph"
            >
              <Preview.panel
                :if={@preview?}
                design={@design}
                sources={@bound_pool}
                vars={@bindings}
                theme={@theme}
                selected={@entry.label}
              />
              <p :if={!@preview?} class="vis-builder-context-note">
                a {@kind} has no chart to look at; its form is in the inspector
              </p>
            </div>
          </main>
          <aside
            id={@id <> "-context"}
            class="vis-builder-context"
            phx-hook="BuilderHook"
            data-builder-target={@myself}
            data-builder-scope="resize"
          >
            <div class="vis-builder-context-handle" data-builder-resize="true" title="drag to resize the inspector" aria-hidden="true"></div>
            <nav
              id={@id <> "-nodes"}
              class="vis-builder-nodes"
              phx-hook="BuilderHook"
              data-builder-target={@myself}
              data-builder-scope="root"
            >
              <button
                :for={tab <- @tabs}
                type="button"
                class={tab.class}
                title={tab.title}
                data-builder-bind-root={tab.label}
                phx-click="select_root"
                phx-value-root={tab.label}
                phx-target={@myself}
              >{tab.label}</button>
            </nav>
            <nav class="vis-builder-context-icons" aria-label="context panels">
              <button
                :for={{panel, icon, word} <- context_icons()}
                type="button"
                class={"vis-builder-context-icon" <> if(@context == panel, do: " vis-builder-context-icon-on", else: "")}
                title={word}
                aria-label={word}
                aria-pressed={to_string(@context == panel)}
                phx-click="context"
                phx-value-panel={panel}
                phx-target={@myself}
              >{Phoenix.HTML.raw(icon)}</button>
            </nav>
            <div :if={@context == :inspect} class="vis-builder-inspect">
              <details
                :for={top <- @page.tops}
                :if={@page.sections?}
                class={"vis-builder-section vis-builder-section-top" <> if(top.needs > 0, do: " vis-builder-section-needs", else: "") <> if(top.other?, do: " vis-builder-section-other", else: "")}
                open={not MapSet.member?(@collapsed, top.label)}
              >
                <summary
                  class="vis-builder-section-title"
                  title={if(top.layer, do: "#{top.label} — in #{top.layer}", else: top.label)}
                  phx-click="toggle_section"
                  phx-value-section={top.label}
                  phx-target={@myself}
                >{top.name}<span :if={top.layer} class="vis-builder-section-layer">{top.layer}</span></summary>
                <Page.page
                  id={@id <> "-page-" <> top.slug}
                  kind={top.kind}
                  node={top.node}
                  path={top.path}
                  label={top.label}
                  before={top.before}
                  collapsed={@collapsed}
                  errors={@errors}
                  refs={@refs}
                  selected={@field}
                  selected_node={@entry.label}
                  found={@find_hit}
                  theme={@colour.theme}
                  defs={@defs}
                  pool={@pool}
                  hidden={if(@source_defaults, do: [], else: [:default])}
                  columns={@columns}
                  source_name={@source_name}
                  owners={@page.owners}
                  layer={@page.layer}
                  locked={@page.locked}
                  guessed={@guessed}
                  target={@myself}
                />
              </details>
              <div
                :if={not @page.sections? and @page.single.layer}
                class={"vis-builder-page-head" <> if(@page.single.other?, do: " vis-builder-section-other", else: "") <> if(MapSet.member?(@page.locked, @page.single.layer), do: " vis-builder-page-locked", else: "")}
                title={"#{@page.single.label} — in #{@page.single.layer}"}
              >
                <span class="vis-builder-section-layer">{@page.single.layer}</span>
              </div>
              <Page.page
                :if={not @page.sections?}
                id={@id <> "-page"}
                kind={@page.single.kind}
                node={@page.single.node}
                path={@page.single.path}
                label={@page.single.label}
                before={@page.single.before}
                collapsed={@collapsed}
                errors={@errors}
                refs={@refs}
                selected={@field}
                selected_node={@entry.label}
                found={@find_hit}
                theme={@colour.theme}
                defs={@defs}
                pool={@pool}
                hidden={if(@source_defaults, do: [], else: [:default])}
                columns={@columns}
                source_name={@source_name}
                owners={@page.owners}
                layer={@page.layer}
                locked={@page.locked}
                guessed={@guessed}
                target={@myself}
              />
            </div>
            <StyleStack.panel
              :if={@context == :inspect and @style_site}
              id={@id <> "-style-stack"}
              value={@style_site.value}
              fallback={@style_site.fallback}
              design={@design}
              open={@style_entry}
              target={@myself}
            />
            <Editor.panel
              :if={@context == :inspect && @style_site && @style_entry}
              id={@id <> "-style-editor"}
              class="vis-builder-style-panel"
              kind={:style}
              node={StyleStack.resolved(@design, @style_site.stack)}
              origins={StyleStack.origins(@design, @style_site.stack)}
              strip={false}
              event="edit_style"
              refs={@refs}
              theme={@colour.theme}
              defs={@defs}
              target={@myself}
            />
            <Sources.panel
              :if={@context == :sources}
              id={@id <> "-sources"}
              signals={@signals}
              tick={@tick}
              playing={@playing}
              tick_ms={@tick_ms}
              target={@myself}
            />
            <Picker.panel
              :if={@context == :colour}
              id={@id <> "-picker"}
              key={@colour.key}
              spec={@colour.spec}
              value={@colour.value}
              swatches={@colour.swatches}
              recent={@colour.recent}
              target={@myself}
            />
            <Fonts.panel
              :if={@context == :font}
              id={@id <> "-fonts"}
              kind={@entry.kind}
              node={@editing}
              target={@myself}
            />
            <Masks.panel
              :if={@context == :inspect && @site && !(@style_site && @style_entry)}
              id={@id <> "-masks"}
              use={@site.use}
              label={@site.label}
              fragment={@site.fragment}
              free={@site.free}
              keyless={@site.use.id in @keyless}
              pool={@pool}
              target={@myself}
            />
            <Variables.panel
              :if={@context == :variables}
              id={@id <> "-variables"}
              layers={@layers}
              design={@design}
              bindings={@bindings}
              sites={@sites}
              expanded={@expanded}
              find={@find}
              target={@myself}
            />
          </aside>
        </div>
        <div class="vis-builder-tray">
          <Palette.panel design={@design} open={@open_style} target={@myself} />
          <Inspector.panel id={@id <> "-inspector"} layers={@layers} target={@myself} />
          <Document.panel design={@design} kind={@kind} target={@myself} />
        </div>
      </div>
      """
    end

    @doc """
    Returns the builder's stylesheet as a binary (spec/14 §18.13).

    The builder renders this itself unless the host passes `styles={false}`;
    `Visualize.Chart.Builder.Styles.install!/0` writes it beside the hooks for a host that
    would rather own the file.
    """
    @spec css() :: binary()
    defdelegate css(), to: Styles

    @doc """
    Renders the stylesheet in a `<style>` element (spec/14 §18.13).
    """
    defdelegate styles(assigns), to: Styles

    # -- the message, and the library ----------------------------------------------------

    # Save sends structure, never the flattened result (spec/14 §19.6, D-103).
    @impl true
    def handle_event("save", _params, socket) do
      %{on_save: tag, id: id} = socket.assigns
      send(self(), {tag, id, structure(socket.assigns)})
      {:noreply, assign(socket, :notice, nil)}
    end

    # Click opens; only drag composes (spec/14 §19.8).
    def handle_event("add_layer", %{"name" => submitted}, socket) do
      case fetch(socket.assigns.store, submitted) do
        {:ok, entry} -> {:noreply, opened_entry(socket, entry)}
        :error -> {:noreply, assign(socket, :notice, "no fragment is stored under #{submitted}")}
      end
    end

    # Deploy is the other verb: the structure flattened through the store, and the flat
    # design sent — never while a non-composite kind is open (spec/14 §19.6, D-103).
    def handle_event("deploy", _params, socket) do
      %{on_deploy: tag, id: id, store: store, open: open} = socket.assigns

      if open != nil and open.kind != :composite do
        {:noreply, assign(socket, :notice, "deploy a composite; a #{open.kind} is not a chart")}
      else
        case Chart.flatten(structure(socket.assigns), Stack.fetch(store)) do
          {:ok, _design, %{keyless: [_ | _] = keyless}} ->
            names =
              Enum.map_join(
                keyless,
                ", ",
                &Stack.label(socket.assigns.labels, Stack.get(socket.assigns.uses, &1))
              )

            {:noreply,
             assign(socket, :notice, "not deployed: #{names} need a key to be declared under")}

          {:ok, design, %{missing: missing}} ->
            send(self(), {tag, id, design})
            {:noreply, assign(socket, :notice, showed_through(missing))}

          {:error, {:cycle, chain}} ->
            {:noreply,
             assign(
               socket,
               :notice,
               "not deployed: the stack refers to itself through #{inspect(chain)}"
             )}
        end
      end
    end

    # A new fragment of a kind starts empty and valid (spec/14 §19.8); a design is the
    # deployed tier and is not one to start (§19.6).
    def handle_event("new_fragment", %{"kind" => "design"}, socket) do
      {:noreply,
       assign(socket, :notice, "a design is what Deploy makes; start a composite instead")}
    end

    def handle_event("new_fragment", %{"kind" => submitted}, socket) do
      case Enum.find(Stack.kinds(), &(to_string(&1) == submitted)) do
        nil ->
          {:noreply, assign(socket, :notice, "#{submitted} is not a kind of fragment")}

        kind ->
          entry = %{id: nil, name: nil, kind: kind, fragment: Stack.empty(kind)}
          {:noreply, opened_entry(socket, entry)}
      end
    end

    # -- the charts (spec/14 §18.8, §19.9) ------------------------------------------------

    # A new chart is one frame layer: a chart minimally is a frame.
    def handle_event("add_chart", _params, socket) do
      use = %{Use.new(nil, []) | ref: nil, local: Stack.empty(:frame)}
      n = socket.assigns.next_chart

      {:noreply,
       socket
       |> park()
       |> assign(
         uses: [use],
         labels: %{use.id => "new frame"},
         stack_vars: %{},
         signals: %{},
         selected: use.id,
         open: nil,
         node_label: "design",
         facet: nil,
         style_entry: nil,
         field: nil,
         context: :inspect,
         notice: nil
       )
       |> added_chart("chart #{n}")}
    end

    def handle_event("select_chart", %{"chart" => id}, socket) do
      {:noreply, socket |> park() |> load(String.to_integer(id))}
    end

    def handle_event("toggle_chart", %{"chart" => id}, socket) do
      id = String.to_integer(id)

      {:noreply,
       update(socket, :charts, fn charts ->
         Enum.map(charts, &if(&1.id == id, do: %{&1 | expanded: not &1.expanded}, else: &1))
       end)}
    end

    # A layer of another chart is selected by selecting its chart first.
    def handle_event("select_chart_layer", %{"chart" => id, "index" => index}, socket) do
      {:noreply, socket |> park() |> load(String.to_integer(id)) |> select(position(index))}
    end

    # Closing a chart removes it and selects its neighbour; the last chart stays.
    def handle_event("close_chart", %{"chart" => id}, socket) do
      id = String.to_integer(id)
      %{charts: charts} = socket.assigns

      case charts do
        [_only] ->
          {:noreply,
           assign(socket, :notice, "the last chart stays; add another to close this one")}

        _many ->
          socket = park(socket)
          index = Enum.find_index(charts, &(&1.id == id))
          remaining = Enum.reject(socket.assigns.charts, &(&1.id == id))
          neighbour = Enum.at(remaining, min(index, length(remaining) - 1))

          socket
          |> assign(:charts, remaining)
          |> then(&if(socket.assigns.chart == id, do: load(&1, neighbour.id), else: &1))
          |> then(&{:noreply, &1})
      end
    end

    # The first draft's close: the selected chart closes.
    def handle_event("close", _params, socket) do
      handle_event("close_chart", %{"chart" => to_string(socket.assigns.chart)}, socket)
    end

    # Saving names the entry, never the body. The workspace and a composite are saved as
    # structure; any other kind is saved as the lowest tier that holds it — one bare inline
    # site is its body, anything more is structure — and is refused if what it flattens to
    # is no longer that kind, or is not valid as one (spec/14 §19.6, §19.8).
    def handle_event("put_design", %{"name" => name}, socket) do
      %{store: store} = socket.assigns
      trimmed = String.trim(name)

      cond do
        is_nil(store) ->
          {:noreply, assign(socket, :notice, "no store is configured")}

        trimmed == "" ->
          {:noreply, assign(socket, :notice, "a saved fragment needs a name")}

        true ->
          {:noreply, put(socket, kept(socket.assigns), trimmed)}
      end
    end

    # -- the strip -----------------------------------------------------------------------

    def handle_event("select_node", %{"node" => label}, socket) do
      {:noreply, assign(socket, node_label: label, facet: nil, field: nil, context: :inspect)}
    end

    # A click on the graph (spec/14 §18.16): the node the element draws is opened in the
    # layer that owns it — the highest enabled layer with a value under its path, the
    # provenance every write follows (§18.15) — selected first, then opened. A label the
    # composed design has no node for is a no-op.
    def handle_event("pick", %{"node" => label}, socket) do
      %{uses: uses, store: store, stack_vars: vars} = socket.assigns
      fetch = Stack.fetch(store)

      design =
        case Stack.design(uses, vars, fetch) do
          {:ok, design, _keyless} -> design
          {:error, _cycle} -> %{}
        end

      case Enum.find(Editor.nodes(design), &(&1.label == label)) do
        nil ->
          {:noreply, socket}

        node ->
          owner = socket.assigns |> owned(fetch, [node]) |> Map.get(node.path)
          at = Enum.find_index(uses, &(&1.id == owner))
          socket = if at, do: select(socket, at), else: socket
          {:noreply, opened(socket, label)}
      end
    end

    # Clicking into a field selects it, and the context panel becomes its picker
    # (spec/14 §19.10); the same click on the field already selected leaves it.
    def handle_event("select_field", %{"field" => key} = params, socket) do
      socket = aimed(socket, params)
      {:noreply, assign(socket, field: key, context: context_for(socket, key))}
    end

    # A section of the inspector folds and unfolds (spec/14 §18.15).
    def handle_event("toggle_section", %{"section" => key}, socket) do
      {:noreply,
       update(socket, :collapsed, fn set ->
         if MapSet.member?(set, key), do: MapSet.delete(set, key), else: MapSet.put(set, key)
       end)}
    end

    # The library folds to a rail and unfolds (spec/14 §18.16).
    def handle_event("library_fold", _params, socket) do
      {:noreply, update(socket, :library_open, &(not &1))}
    end

    # -- the signals (spec/14 §19.10) ------------------------------------------------------

    def handle_event("add_signal", _params, socket) do
      %{signals: signals} = socket.assigns

      name =
        map_size(signals)
        |> Stream.iterate(&(&1 + 1))
        |> Stream.map(&:"signal_#{&1 + 1}")
        |> Enum.find(&(not Map.has_key?(signals, &1)))

      signal = Signals.new(:sine, [:t, :value])

      {:noreply,
       socket
       |> assign(signals: Map.put(signals, name, signal), context: :sources, notice: nil)
       |> declared_source(name, signal)}
    end

    def handle_event("remove_signal", %{"name" => name}, socket) do
      {:noreply, update(socket, :signals, &Map.delete(&1, String.to_atom(name)))}
    end

    def handle_event("edit_signal", %{"_target" => [target]} = params, socket) do
      case String.split(target, ".", parts: 2) do
        [name, key] ->
          atom = String.to_atom(name)

          {:noreply,
           update(socket, :signals, fn signals ->
             case Map.fetch(signals, atom) do
               {:ok, signal} ->
                 Map.put(signals, atom, Sources.edit(signal, key, params[target] || ""))

               :error ->
                 signals
             end
           end)}

        _other ->
          {:noreply, socket}
      end
    end

    def handle_event("play", _params, socket) do
      {:noreply, socket |> assign(:playing, true) |> schedule()}
    end

    def handle_event("pause", _params, socket) do
      {:noreply, assign(socket, :playing, false)}
    end

    def handle_event("tick_ms", %{"ms" => ms}, socket) do
      case Integer.parse(to_string(ms)) do
        {n, _} when n >= 50 -> {:noreply, assign(socket, :tick_ms, n)}
        _other -> {:noreply, socket}
      end
    end

    # The inspector's width, dragged at its edge and kept within reason (spec/14 §18.16).
    def handle_event("context_width", %{"width" => width}, socket) do
      case Integer.parse(to_string(width)) do
        {n, _} -> {:noreply, assign(socket, :context_width, n |> max(300) |> min(800))}
        :error -> {:noreply, socket}
      end
    end

    # The icon row: which of the context's panels is open (spec/14 §19.10).
    def handle_event("context", %{"panel" => panel}, socket) do
      case Enum.find(context_icons(), fn {p, _, _} -> to_string(p) == panel end) do
        {p, _, _} -> {:noreply, assign(socket, :context, p)}
        nil -> {:noreply, socket}
      end
    end

    # Two views over one store; group is the default because it is the one a person
    # authored deliberately (spec/14 §19.8).
    def handle_event("library_view", %{"view" => "kind"}, socket),
      do: {:noreply, assign(socket, :library_view, :kind)}

    def handle_event("library_view", %{"view" => _group}, socket),
      do: {:noreply, assign(socket, :library_view, :group)}

    # A root opens as the chart declares it, whatever layer is selected (spec/14 §18.13,
    # §18.15). From the page of a site the design has no node of, a root of the design
    # takes the person to the highest layer that declares it, as the inspector does.
    def handle_event("select_root", %{"root" => root}, socket) do
      %{design: design, chart?: chart?, layers: layers, nodes: nodes} = editing(socket.assigns)
      label = if chart?, do: first_under(design, root), else: first_under_nodes(nodes, root)

      cond do
        label ->
          {:noreply, assign(socket, node_label: label, facet: nil, context: :inspect)}

        first_under(design, root) ->
          layers
          |> Enum.with_index()
          |> Enum.reverse()
          |> Enum.find(fn {{_label, fragment}, _index} -> first_under(fragment, root) end)
          |> case do
            nil ->
              {:noreply, socket}

            {{_label, _fragment}, index} ->
              {:noreply, socket |> select(index) |> opened(first_under(design, root))}
          end

        true ->
          {:noreply, socket}
      end
    end

    def handle_event("facet", %{"facet" => facet}, socket) do
      %{entry: entry} = editing(socket.assigns)
      facets = Enum.map(Schema.describe(entry.kind), & &1.facet)
      {:noreply, assign(socket, facet: Enum.find(facets, &(to_string(&1) == facet)), field: nil)}
    end

    # -- the stack -----------------------------------------------------------------------

    def handle_event("select_layer", %{"index" => index}, socket) do
      {:noreply, select(socket, position(index))}
    end

    # The keyboard has every gesture the pointer has (spec/14 §18.17): Enter and Space
    # select, the arrows move and focus follows the row to where the layer went.
    def handle_event("layer_key", %{"key" => key, "index" => index}, socket) do
      at = position(index)
      count = length(socket.assigns.uses)

      case key do
        enter when enter in ["Enter", " "] ->
          {:noreply, select(socket, at)}

        "ArrowUp" when at > 0 ->
          {:noreply, moved_by_key(socket, at, at - 1)}

        "ArrowDown" when at < count - 1 ->
          {:noreply, moved_by_key(socket, at, at + 1)}

        # A library layer opens, so the entry is edited where it lives (§18.8).
        "o" ->
          handle_event("open_layer", %{"index" => index}, socket)

        _other ->
          {:noreply, socket}
      end
    end

    # The lock on a library layer (spec/14 §18.8): the entry it references opens at the
    # chart level, as the library click opens it, and saving it reaches every chart that
    # references it. A layer with no reference has nothing to open.
    def handle_event("open_layer", %{"index" => index}, socket) do
      case Enum.at(socket.assigns.uses, position(index)) do
        %Use{ref: ref} when ref != nil ->
          case Store.get(socket.assigns.store, ref) do
            {:ok, entry} ->
              {:noreply, opened_entry(socket, entry)}

            :error ->
              {:noreply, assign(socket, :notice, "the library no longer holds this entry")}
          end

        _inline ->
          {:noreply, socket}
      end
    end

    # A library item from the keyboard: Enter opens, Insert adds above the selected layer.
    def handle_event("fragment_key", %{"key" => key, "name" => name}, socket) do
      case key do
        enter when enter in ["Enter", " "] ->
          handle_event("add_layer", %{"name" => name}, socket)

        # `i` copies and `I` links, as a drop and an Alt-drop do (spec/14 §18.17).
        insert when insert in ["Insert", "i"] ->
          handle_event("insert", %{"name" => name, "as" => "copy"}, socket)

        "I" ->
          handle_event("insert", %{"name" => name, "as" => "link"}, socket)

        _other ->
          {:noreply, socket}
      end
    end

    def handle_event("toggle_layer", %{"index" => index}, socket) do
      case Enum.at(socket.assigns.uses, position(index)) do
        nil ->
          {:noreply, socket}

        use ->
          {:noreply,
           update(socket, :uses, &Stack.update(&1, use.id, fn u -> Stack.toggle(u) end))}
      end
    end

    def handle_event("reorder", %{"scope" => "style", "from" => from, "to" => to}, socket) do
      {:noreply, restacked(socket, &shift(&1, position(from), position(to)))}
    end

    def handle_event("reorder", %{"from" => from, "to" => to}, socket) do
      {:noreply, update(socket, :uses, &Stack.move(&1, position(from), position(to)))}
    end

    # A style fragment dropped on a site's stack: its id goes into the stack where it was
    # dropped, and nothing is merged or copied (spec/14 §18.20, §19.6).
    def handle_event("insert", %{"scope" => "style", "name" => submitted, "at" => at}, socket) do
      case fetch(socket.assigns.store, submitted) do
        {:ok, %{kind: :style} = entry} ->
          {:noreply,
           socket
           |> restacked(fn stack ->
             List.insert_at(stack, clamp(position(at), stack), entry.id)
           end)
           |> assign(added: entry.id, notice: nil)}

        {:ok, entry} ->
          {:noreply,
           assign(
             socket,
             :notice,
             "#{entry.name} is a #{entry.kind}, and a style site takes a style"
           )}

        :error ->
          {:noreply, assign(socket, :notice, "no fragment is stored under #{submitted}")}
      end
    end

    # A library entry dropped on a reference field writes its id there — the same write the
    # field's select makes — and an entry of another kind is refused by name (spec/14
    # §19.10). A style field is a stack, so a style goes onto it as a drop on the stack does.
    def handle_event(
          "insert",
          %{"scope" => "ref", "field" => field, "name" => submitted} = params,
          socket
        ) do
      socket = aimed(socket, params)
      %{entry: entry} = editing(socket.assigns)

      with {:ok, stored} <- fetch(socket.assigns.store, submitted),
           %{key: key, type: type} <-
             Enum.find(Schema.describe(entry.kind), &(to_string(&1.key) == field)),
           kind when kind != nil <- ref_kind(type) do
        cond do
          stored.kind != kind ->
            {:noreply,
             assign(
               socket,
               :notice,
               "a #{kind} field takes a #{kind}; #{stored.name} is a #{stored.kind}"
             )}

          kind == :style ->
            handle_event("insert", %{"scope" => "style", "name" => submitted, "at" => 99}, socket)

          true ->
            {:noreply,
             socket |> update_layer(entry.path, key, {:ok, stored.id}) |> assign(:notice, nil)}
        end
      else
        :error -> {:noreply, assign(socket, :notice, "no fragment is stored under #{submitted}")}
        _other -> {:noreply, assign(socket, :notice, "#{field} is not a reference field")}
      end
    end

    # A fragment dragged out of the library lands at the position it was dropped at, as a
    # use referring to it (spec/14 §18.17, §19.3).
    # A library entry into the stack (spec/14 §18.17): a copy unless a link is asked for;
    # at the gap given, or above the selected layer when the drop was on the graph.
    def handle_event("insert", %{"name" => submitted} = params, socket) do
      at =
        case Map.get(params, "at") do
          nil -> (Stack.index_of(socket.assigns.uses, socket.assigns.selected) || -1) + 1
          given -> position(given)
        end

      link? = Map.get(params, "as") == "link"

      case fetch(socket.assigns.store, submitted) do
        {:ok, entry} ->
          case admits(socket.assigns.open, entry) do
            :ok when link? -> {:noreply, linked(socket, entry, at)}
            :ok -> {:noreply, copied(socket, entry, at)}
            {:refused, notice} -> {:noreply, assign(socket, :notice, notice)}
          end

        :error ->
          {:noreply, assign(socket, :notice, "no fragment is stored under #{submitted}")}
      end
    end

    def handle_event("inspect", %{"path" => path, "layer" => layer}, socket) do
      {:noreply, socket |> select(position(layer)) |> opened(path)}
    end

    # -- style stacks and the palette ----------------------------------------------------

    def handle_event("add_style_entry", %{"name" => submitted}, socket) do
      case Editor.parse({:ref, :style}, String.trim(submitted)) do
        {:ok, name} -> {:noreply, restacked(socket, &(&1 ++ [name]))}
        :error -> {:noreply, assign(socket, :notice, "a style entry needs a name")}
      end
    end

    def handle_event("remove_style_entry", %{"index" => index}, socket) do
      at = position(index)
      {:noreply, restacked(socket, &List.delete_at(&1, at))}
    end

    def handle_event("select_style_entry", %{"index" => index}, socket) do
      {:noreply, assign(socket, :style_entry, position(index))}
    end

    # Every edit at a site lands in its local style, never in a named entry (§18.19, D-98).
    def handle_event("edit_style", %{"_target" => [target]} = params, socket) do
      if Fills.control?(target) do
        {:noreply, filled(socket, target, params[target], &styled(&1, &2))}
      else
        {:noreply, Enum.reduce(Editor.changes(:style, params), socket, &styled(&2, &1))}
      end
    end

    def handle_event("edit_style", _params, socket), do: {:noreply, socket}

    def handle_event("add_style", %{"name" => submitted}, socket) do
      case Editor.parse({:ref, :style}, String.trim(submitted)) do
        {:ok, name} ->
          socket
          |> update_layer([:styles], name, {:ok, %{}})
          |> opened("styles." <> to_string(name))
          |> assign(:notice, nil)
          |> then(&{:noreply, &1})

        :error ->
          {:noreply, assign(socket, :notice, "a style needs a name")}
      end
    end

    def handle_event("select_style", %{"name" => submitted}, socket) do
      %{layers: layers} = editing(socket.assigns)

      case declaring(layers, submitted) do
        nil -> {:noreply, socket}
        index -> {:noreply, socket |> select(index) |> opened("styles." <> submitted)}
      end
    end

    # -- the form, the parameters, the document ------------------------------------------

    def handle_event("edit", %{"_target" => [target]} = params, socket) do
      socket = aimed(socket, params)
      %{entry: entry} = editing(socket.assigns)

      if String.ends_with?(target, ".pick") do
        {:noreply, picked(socket, entry, String.trim_trailing(target, ".pick"), params)}
      else
        edit_field(socket, entry, target, params)
      end
    end

    def handle_event("edit", _params, socket), do: {:noreply, socket}

    def handle_event("set_var", %{"_target" => [name]} = params, socket) do
      %{layers: layers} = editing(socket.assigns)
      free = Enum.find(Chart.free_vars(layers), &(to_string(&1.name) == name))
      {:noreply, bound(socket, free, params[name])}
    end

    # The key a name-keyed site is declared under, from the context panel (spec/14 §19.3):
    # the one surface that writes `Use.key`; blank removes it.
    def handle_event("set_key", params, socket) do
      %{selected: selected} = socket.assigns
      pool = pool(socket.assigns)

      # The pool list writes `key`; the box beneath it, a name the pool lacks, `key.other`
      # (spec/14 §19.10) — whichever changed.
      submitted =
        case params do
          %{"_target" => ["key.other"]} -> Map.get(params, "key.other")
          _other -> Map.get(params, "key")
        end

      key =
        case Editor.parse(:name, submitted) do
          {:ok, name} -> name
          :error -> nil
        end

      # A source chosen from the pool takes the pool's fields when it declares none
      # (spec/14 §19.10): one pick, and it previews.
      # The key is the site's own and is always written; the fields are the body's, and a
      # locked site keeps the entry's (§18.15).
      {:noreply,
       update(socket, :uses, fn uses ->
         Stack.update(uses, selected, fn u ->
           if Stack.locked?(u),
             do: %{u | key: key},
             else: %{u | key: key, local: filled(u.local, key, pool)}
         end)
       end)}
    end

    # A list of scalars as items (spec/14 §18.6): Enter in the + box appends one read by the
    # element's type; × removes by index. Both write the whole list, as the schema says.
    def handle_event("list_add", %{"field" => field} = params, socket) do
      socket = aimed(socket, params)
      %{entry: entry, editing: node} = editing(socket.assigns)
      typed = Map.get(params, "value") || Map.get(params, "#{field}.add") || ""

      with %{key: key, type: {:list, scalar}} <-
             Enum.find(Schema.describe(entry.kind), &(to_string(&1.key) == field)),
           {:ok, item} <- Editor.parse(scalar, typed) do
        list = if(is_map(node), do: Map.get(node, key, []), else: []) ++ [item]
        {:noreply, socket |> update_layer(entry.path, key, {:ok, list}) |> assign(:notice, nil)}
      else
        _other -> {:noreply, socket}
      end
    end

    def handle_event("list_remove", %{"field" => field, "index" => index} = params, socket) do
      socket = aimed(socket, params)
      %{entry: entry, editing: node} = editing(socket.assigns)

      with %{key: key, type: {:list, _}} <-
             Enum.find(Schema.describe(entry.kind), &(to_string(&1.key) == field)),
           list when is_list(list) <- is_map(node) && Map.get(node, key) do
        rest = List.delete_at(list, position(index))
        write = if rest == [], do: :error, else: {:ok, rest}
        {:noreply, update_layer(socket, entry.path, key, write)}
      else
        _other -> {:noreply, socket}
      end
    end

    # The + on the Layers title: a menu of the single kinds, and an empty inline site of the
    # chosen one directly below the selected layer, selected and opened (spec/14 §18.8).
    def handle_event("adding", _params, socket) do
      {:noreply, update(socket, :adding, &(not &1))}
    end

    def handle_event("add_site", %{"kind" => submitted}, socket) do
      case Enum.find(Stack.kinds() -- [:composite], &(to_string(&1) == submitted)) do
        nil ->
          {:noreply,
           assign(socket, notice: "#{submitted} is not a kind a site can be", adding: false)}

        # An axis, a label and a mark are placed as a drop in their home region would
        # place them (spec/14 §18.16); any other kind is the empty site it was.
        :axis ->
          {:noreply, placed(socket, :axis, Place.home(:axis), {0, 0})}

        :label ->
          {:noreply, placed(socket, :label, Place.home(:label), {0, 0})}

        :mark ->
          {:noreply, placed(socket, {:mark, :line}, Place.home({:mark, :line}), {0, 0})}

        kind ->
          %{uses: uses, labels: labels, selected: selected} = socket.assigns
          use = %{Use.new(nil, uses) | ref: nil, local: Stack.empty(kind)}
          at = (Stack.index_of(uses, selected) || length(uses) - 1) + 1

          {:noreply,
           assign(socket,
             uses: List.insert_at(uses, at, use),
             labels: Map.put(labels, use.id, "new #{kind}"),
             selected: use.id,
             node_label: "design",
             facet: nil,
             field: nil,
             context: :inspect,
             adding: false,
             notice: nil
           )}
      end
    end

    # -- the palette, and a drop on the graph (spec/14 §18.16) ------------------------------

    # A palette row from the keyboard: Insert places it in its home region.
    def handle_event("component_key", %{"key" => key, "component" => word}, socket) do
      case {key, Place.component(word)} do
        {insert, {:ok, component}} when insert in ["Insert", "i", "Enter", " "] ->
          {:noreply, placed(socket, component, Place.home(component), {0, 0})}

        _other ->
          {:noreply, socket}
      end
    end

    # A drop on the graph: a component, or a library entry, placed where it landed — by
    # the point in chart coordinates, or by the region the keyboard twin names.
    def handle_event("place", %{"component" => word} = params, socket) do
      case Place.component(word) do
        {:ok, component} ->
          {region, point} = where(socket, params, component)
          {:noreply, placed(socket, component, region, point)}

        :error ->
          {:noreply, assign(socket, :notice, "#{word} is not a component")}
      end
    end

    def handle_event("place", %{"name" => submitted} = params, socket) do
      case fetch(socket.assigns.store, submitted) do
        {:ok, entry} ->
          case admits(socket.assigns.open, entry) do
            :ok ->
              {region, _point} = where(socket, params, nil)
              link? = Map.get(params, "as") == "link"
              at = (Stack.index_of(socket.assigns.uses, socket.assigns.selected) || -1) + 1
              socket = if link?, do: linked(socket, entry, at), else: copied(socket, entry, at)
              {:noreply, if(link?, do: socket, else: snapped(socket, entry, at, region))}

            {:refused, notice} ->
              {:noreply, assign(socket, :notice, notice)}
          end

        :error ->
          {:noreply, assign(socket, :notice, "no fragment is stored under #{submitted}")}
      end
    end

    # -- variables as chips (spec/14 §19.9, §19.10) --------------------------------------

    def handle_event("find_variable", %{"find" => find}, socket) do
      {:noreply, assign(socket, :find, find)}
    end

    def handle_event("expand_variable", %{"name" => name}, socket) do
      expanded = socket.assigns.expanded

      expanded =
        if MapSet.member?(expanded, name),
          do: MapSet.delete(expanded, name),
          else: MapSet.put(expanded, name)

      {:noreply, assign(socket, :expanded, expanded)}
    end

    # A chip dropped on a field binds it: the field's key takes var(:name). A variable
    # already typed by a use of another type is refused by name; one used nowhere takes
    # the control's type by being used here (spec/14 §19.9).
    def handle_event("bind_field", %{"field" => field, "name" => name} = params, socket) do
      socket = aimed(socket, params)
      %{entry: entry, layers: layers, design: design} = editing(socket.assigns)

      with %{key: key, type: type} when type != :text <-
             Enum.find(Schema.describe(entry.kind), &(to_string(&1.key) == field)),
           {:ok, var} <- Editor.variable(name),
           :ok <- fits(Variables.list(layers, design), var.name, element(type), key) do
        case type do
          {:list, _scalar} ->
            # A list of scalars takes the variable as an item (§19.9): fields: [:t, var(:y)].
            %{editing: node} = editing(socket.assigns)
            list = if(is_map(node), do: Map.get(node, key, []), else: []) ++ [var]

            {:noreply,
             socket |> update_layer(entry.path, key, {:ok, list}) |> assign(:notice, nil)}

          _single ->
            {:noreply,
             socket |> update_layer(entry.path, key, {:ok, var}) |> assign(:notice, nil)}
        end
      else
        %{type: :text} ->
          # A text takes a variable as text among text, at the caret, by the hook (§7.1).
          {:noreply, socket}

        {:refused, notice} ->
          {:noreply, assign(socket, :notice, notice)}

        _other ->
          {:noreply, assign(socket, :notice, "#{field} is not a field here")}
      end
    end

    # A chip dropped on a strip tab binds the first key of that root the variable fits.
    def handle_event("bind_root", %{"root" => root, "name" => name}, socket) do
      %{layers: layers, design: design} = editing(socket.assigns)

      with {:ok, var} <- Editor.variable(name),
           {:noreply, socket} <- handle_event("select_root", %{"root" => root}, socket),
           %{entry: entry} <- editing(socket.assigns),
           %{key: key} <- first_fit(entry.kind, Variables.list(layers, design), var.name) do
        {:noreply, socket |> update_layer(entry.path, key, {:ok, var}) |> assign(:notice, nil)}
      else
        _other -> {:noreply, assign(socket, :notice, "nothing under #{root} takes #{name}")}
      end
    end

    def handle_event("unbind_field", %{"field" => field} = params, socket) do
      socket = aimed(socket, params)
      %{entry: entry} = editing(socket.assigns)

      case Enum.find(Schema.describe(entry.kind), &(to_string(&1.key) == field)) do
        nil -> {:noreply, socket}
        %{key: key} -> {:noreply, update_layer(socket, entry.path, key, :error)}
      end
    end

    # A patch dropped on a well writes that well's key, selected or not (spec/14 §19.10): a
    # word is a slot, a `#rrggbb` a literal, each through the edit the chooser would make;
    # the form the well sits in says which edit. A key that is not a colour refuses by name.
    def handle_event("drop_colour", %{"field" => field, "colour" => colour} = params, socket) do
      socket = aimed(socket, params)
      edit = if Map.get(params, "edit") == "edit_style", do: "edit_style", else: "edit"
      kind = if edit == "edit_style", do: :style, else: editing(socket.assigns).entry.kind

      stop? = String.starts_with?(field, "fill.stop.")

      case Enum.find(Schema.describe(kind), &(to_string(&1.key) == field)) do
        %{type: :colour} ->
          control = if String.starts_with?(colour, "#"), do: field, else: field <> ".slot"
          handle_event(edit, %{"_target" => [control], control => colour}, socket)

        nil when stop? ->
          control = if String.starts_with?(colour, "#"), do: field, else: field <> ".slot"
          handle_event(edit, %{"_target" => [control], control => colour}, socket)

        _other ->
          {:noreply, assign(socket, :notice, "#{field} is not a colour")}
      end
    end

    # A new variable is a var site of the stack, keyed by its name, with its default.
    def handle_event("create_variable", %{"name" => name} = params, socket) do
      case Editor.variable(name) do
        {:ok, var} -> {:noreply, declared(socket, var.name, Map.get(params, "default", ""))}
        :error -> {:noreply, assign(socket, :notice, "a variable needs a name")}
      end
    end

    # A field's value promoted: a variable named for the key, its literal as the default,
    # and the field bound to it.
    def handle_event("promote", %{"field" => field} = params, socket) do
      socket = aimed(socket, params)
      %{entry: entry, editing: node, layers: layers, design: design} = editing(socket.assigns)

      case Enum.find(Schema.describe(entry.kind), &(to_string(&1.key) == field)) do
        %{key: key} when is_map(node) and is_map_key(node, key) ->
          name = fresh_name(key, Variables.list(layers, design))

          {:noreply,
           socket
           |> declared(name, Map.fetch!(node, key))
           |> update_layer(entry.path, key, {:ok, %Visualize.Chart.Var{name: name}})}

        _other ->
          {:noreply, assign(socket, :notice, "#{field} has no value to promote")}
      end
    end

    # The declaration's default, from the expanded chip (spec/14 §19.10): written where the
    # stack declares the name — the highest site that does, a var site by its key or a
    # layer under its `vars` — else declared by a new var site on top, so it is what wins.
    def handle_event("set_default", %{"_target" => [name]} = params, socket) do
      %{uses: uses} = socket.assigns

      case Editor.variable(name) do
        {:ok, var} ->
          default = parsed_default(Map.get(params, name, ""))
          write = if default == nil, do: :error, else: {:ok, default}

          case declarer(uses, var.name) do
            nil ->
              {:noreply, declared(socket, var.name, default, :top)}

            {%Use{ref: ref} = site, _path} when ref != nil ->
              {:noreply, assign(socket, :notice, locked_notice(socket.assigns, site))}

            {site, path} ->
              {:noreply,
               update(
                 socket,
                 :uses,
                 &Stack.update(&1, site.id, fn u -> Stack.write(u, path, :default, write) end)
               )}
          end

        :error ->
          {:noreply, socket}
      end
    end

    # A mask checkbox: the path joins or leaves the selected site's mask (spec/14 §19.5).
    # An unchecked box submits nothing, which is the path leaving.
    def handle_event("mask", %{"_target" => [name]} = params, socket) do
      %{uses: uses, selected: selected} = socket.assigns

      case Stack.get(uses, selected) do
        nil ->
          {:noreply, socket}

        _use ->
          checked = Map.get(params, name) == "true"

          {:noreply,
           update(
             socket,
             :uses,
             &Stack.update(&1, selected, fn u -> Masks.toggle(u, name, checked) end)
           )}
      end
    end

    # A site's binding, from its row in the Variables tab (spec/14 §19.4, §19.10): a value,
    # one of the stack's own variables, or — blank — nothing, so the name flows up. This is
    # the one surface that writes `Use.vars`.
    def handle_event("bind_site", %{"site" => site, "_target" => [target]} = params, socket) do
      %{uses: uses, labels: labels, store: store} = socket.assigns
      index = position(site)

      with %Use{} = use <- Enum.at(uses, index),
           {name, control} <- control(target),
           %{free: free} <- Enum.find(Stack.sites([use], labels, Stack.fetch(store)), & &1),
           %{} = var <- Enum.find(free, &(to_string(&1.name) == name)) do
        bound =
          case {control, Editor.submitted(Params.expects(var), params[target])} do
            {:variable, _typed} -> Editor.variable(params[target])
            {:literal, typed} -> typed
          end

        {:noreply,
         update(socket, :uses, &Stack.update(&1, use.id, fn u -> rebound(u, var.name, bound) end))}
      else
        _other -> {:noreply, socket}
      end
    end

    def handle_event("import", %{"document" => document}, socket) do
      case Chart.from_json(document) do
        {:ok, chart} -> {:noreply, imported(socket, Chart.to_map(chart))}
        {:error, reason} -> {:noreply, assign(socket, :notice, notice(reason))}
      end
    end

    # -- what is being edited ------------------------------------------------------------

    defp kept(%{open: open, uses: uses, stack_vars: vars})
         when open == nil or open.kind == :composite,
         do: {:ok, :composite, Stack.structure(uses, vars)}

    defp kept(%{open: %{kind: kind}, uses: uses, stack_vars: vars, store: store}) do
      fragment = Stack.body(uses, vars)

      case Composite.flatten(fragment, Stack.fetch(store)) do
        {:error, {:cycle, _chain}} ->
          {:error, "the stack refers to itself, and cannot be saved until it does not"}

        {:ok, flat, _report} ->
          case {Fragment.kind(flat), Validator.validate(flat, kind)} do
            {^kind, :ok} ->
              {:ok, kind, fragment}

            {^kind, {:error, errors}} ->
              {:error, "not a valid #{kind}: " <> faults_notice(errors)}

            {other, _} ->
              {:error, drifted(kind, other)}
          end
      end
    end

    defp put(socket, {:error, notice}, _name), do: assign(socket, :notice, notice)

    defp put(socket, {:ok, kind, fragment}, name) do
      %{store: store, open: open} = socket.assigns
      entry = %{id: open && open.id, name: name, kind: kind, fragment: fragment}

      saved(socket, Store.put(store, entry), fn s, id ->
        if open, do: assign(s, :open, %{open | id: id, name: name}), else: s
      end)
    end

    defp faults_notice(errors), do: Enum.map_join(errors, "; ", &Validator.format/1)

    defp showed_through([]), do: nil

    defp showed_through(missing) do
      refs = Enum.map_join(missing, ", ", fn {_site, ref} -> Store.encode_id(ref) end)
      "deployed with #{length(missing)} reference(s) showing through: #{refs}"
    end

    defp moved_by_key(socket, from, to) do
      socket
      |> update(:uses, &Stack.move(&1, from, to))
      |> push_event("vis:focus", %{id: "#{socket.assigns.id}-layers-row-#{to}"})
    end

    # The kind a field refers to, when it is a reference field at all.
    defp ref_kind({:ref, kind}), do: kind
    defp ref_kind(_type), do: nil

    # Whether a variable fits a key's type: untyped fits anything; a typed one must match.
    # A list of scalars takes items of its element's type.
    defp element({:list, scalar}), do: scalar
    defp element(type), do: type

    # Whether a variable fits a key's type: untyped fits anything; a typed one must match —
    # and a field is a channel (a channel is a field or a constant), so a variable typed by
    # a mark's channel fits a source's field list and the other way round (§19.9).
    defp fits(vars, name, type, key) do
      case Enum.find(vars, &(&1.name == name)) do
        nil ->
          :ok

        %{type: nil} ->
          :ok

        %{type: other} when other in [:field, :channel] and type in [:field, :channel] ->
          :ok

        %{type: ^type} ->
          :ok

        %{type: other} ->
          {:refused, "#{name} is #{type_word(other)}; #{key} takes #{type_word(type)}"}
      end
    end

    defp first_fit(kind, vars, name) do
      typed = Enum.find(vars, &(&1.name == name))

      Enum.find(Schema.describe(kind), fn spec ->
        typed == nil or typed.type == nil or typed.type == spec.type
      end)
    end

    defp type_word({:enum, _}), do: "a choice"
    defp type_word({:ref, kind}), do: "a #{kind}"
    defp type_word({:one_of, [first | _]}), do: type_word(first)
    defp type_word(type), do: "a #{inspect(type)}"

    # A var site at the bottom of the stack, keyed by the name, with the default.
    defp declared(socket, name, default, where \\ :bottom) do
      %{uses: uses, labels: labels} = socket.assigns
      default = if is_binary(default), do: parsed_default(default), else: default
      body = if default == nil, do: %{}, else: %{default: default}
      use = %{Use.new(nil, uses) | ref: nil, local: %{var: body}, key: name}

      assign(socket,
        uses: if(where == :top, do: uses ++ [use], else: [use | uses]),
        labels: Map.put(labels, use.id, "var #{name}"),
        notice: nil
      )
    end

    # The highest site declaring a variable, and the path of its declaration in that
    # site's local: `[:var]` for a var site keyed by the name, `[:vars, name]` for a layer.
    defp declarer(uses, name) do
      uses
      |> Enum.reverse()
      |> Enum.find_value(fn use ->
        cond do
          use.key == name and match?({:var, _}, Fragment.wrapped(use.local)) ->
            {use, [:var]}

          is_map(use.local) and is_map(Map.get(use.local, :vars)) and
              Map.has_key?(use.local.vars, name) ->
            {use, [:vars, name]}

          true ->
            nil
        end
      end)
    end

    defp parsed_default(string) do
      case Editor.parse(:term, string) do
        {:ok, value} -> value
        :error -> nil
      end
    end

    defp fresh_name(key, vars) do
      taken = Enum.map(vars, & &1.name)

      Stream.iterate(1, &(&1 + 1))
      |> Enum.find_value(fn
        1 -> if key in taken, do: nil, else: key
        n -> if :"#{key}_#{n}" in taken, do: nil, else: :"#{key}_#{n}"
      end)
    end

    defp control(target) do
      case String.split(target, ".", parts: 2) do
        [name, "var"] -> {name, :variable}
        [name] -> {name, :literal}
        _other -> nil
      end
    end

    defp rebound(use, name, {:ok, value}), do: %{use | vars: Map.put(use.vars, name, value)}
    defp rebound(use, name, :error), do: %{use | vars: Map.delete(use.vars, name)}

    # A composer opened on a kind takes only that kind; the workspace, a composite and a
    # design take anything (spec/14 §19.6).
    defp admits(nil, _entry), do: :ok
    defp admits(%{kind: :composite}, _entry), do: :ok
    defp admits(%{kind: kind}, %{kind: kind}), do: :ok

    defp admits(%{kind: kind}, entry),
      do: {:refused, "a #{kind} composer takes a #{kind}; #{entry.name} is a #{entry.kind}"}

    # What the editor is looking at: the resolved layers, the design they stand for, the
    # target's nodes, the open one and its value, and the faults application reports.
    defp editing(assigns) do
      fetch = Stack.fetch(assigns.store)
      {layers, missing} = Stack.resolve(assigns.uses, assigns.labels, fetch)

      {design, cycle, keyless} =
        case Stack.design(assigns.uses, assigns.stack_vars, fetch) do
          {:ok, design, %{keyless: keyless}} -> {design, nil, keyless}
          {:error, {:cycle, chain}} -> {%{}, chain, []}
        end

      kind = (assigns.open && assigns.open.kind) || :composite
      # The page is the chart's (spec/14 §18.15): the nodes are walked over the composed
      # design, and each is owned by the highest layer that gives a value under it. A
      # selected site that gives the design nothing — keyless, disabled, empty — has no
      # node there, so its page is its own fragment, as every layer's once was.
      chart_nodes = Editor.nodes(design)
      owned = owned(assigns, fetch, chart_nodes)
      selected_use = Stack.get(assigns.uses, assigns.selected)
      mine = for {path, id} <- owned, selected_use && id == selected_use.id, do: path

      {nodes, layer} =
        if selected_use == nil or mine != [] do
          {chart_nodes, design}
        else
          fragment = target_fragment(assigns)
          {Editor.nodes(fragment), fragment}
        end

      # The design root itself is not a place to edit: its keys are Deploy's (`version`)
      # or sites of their own (§19.8), so a layer opens on its first real node — the
      # first the selected layer owns, where it owns one.
      entry =
        case assigns.node_label do
          "design" ->
            first_node(nodes, mine)

          label ->
            Enum.find(nodes, &(&1.label == label)) || implied(label) || first_node(nodes, mine)
        end

      errors = faults(kind, design, assigns, cycle)
      {tabs, children} = strip(nodes, entry, design, errors, layer == design)

      %{
        layers: layers,
        missing: missing,
        design: design,
        nodes: nodes,
        entry: entry,
        tabs: tabs,
        chips: chips(children, entry, assigns.facet),
        page: page(nodes, entry, layer, errors, owned, assigns),
        needs: needs(errors),
        style_site: style_site(entry, at(layer, entry.path)),
        open_style: open_style(entry),
        variables: variables(layers, design),
        sites: Stack.sites(assigns.uses, assigns.labels, fetch),
        find_hit: find_hit(assigns.find),
        site: site(assigns, fetch),
        refs: refs(design, assigns.store),
        colour: colour(assigns, entry, at(layer, entry.path), design),
        defs: Map.get(design, :defs, %{}),
        pool: assigns |> pool() |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort(),
        bound_pool: pool(assigns),
        columns: columns(pool(assigns)),
        source_name: source_name(assigns, fetch),
        editing: at(layer, entry.path),
        errors: errors,
        chart?: layer == design,
        keyless: keyless,
        unplaced: Enum.map(keyless, &Stack.label(assigns.labels, Stack.get(assigns.uses, &1))),
        kind: kind,
        preview?: kind == :composite,
        chart_rows: chart_rows(assigns),
        selected_index: Stack.index_of(assigns.uses, assigns.selected),
        disabled: disabled(assigns.uses),
        locked: locked(assigns.uses)
      }
    end

    # The selected site for its context: what it contributes before its mask, and what it
    # still needs (spec/14 §19.10).
    defp site(%{uses: uses, labels: labels, selected: selected}, fetch) do
      case Stack.get(uses, selected) do
        nil ->
          nil

        use ->
          free =
            case Stack.sites([use], labels, fetch) do
              [%{free: free}] -> free
              [] -> []
            end

          %{
            use: use,
            label: Stack.label(labels, use),
            fragment: Stack.unmasked(use, fetch),
            free: free
          }
      end
    end

    # A reference may be a local name or a library id of the kind (spec/14 §19.10).
    defp refs(design, store) do
      entries = if store, do: Store.list(store), else: []
      ids = fn kind -> for %{kind: ^kind, id: id} <- entries, do: id end

      %{
        style: Palette.names(design) ++ ids.(:style),
        scale: Map.keys(get_in(design, [:frame, :scales]) || %{}) ++ ids.(:scale),
        source: Map.keys(Map.get(design, :sources, %{})) ++ ids.(:source)
      }
    end

    # The colour chooser (spec/14 §19.10): the selected colour field, if the selected field
    # is one, with the theme's slots in their colours and the literals the design already
    # uses; the theme itself is what every well shows its colour through.
    defp colour(%{field: field}, entry, node, design) do
      theme = design |> Map.get(:theme, :default) |> theme()

      spec =
        field &&
          Enum.find(
            Schema.describe(entry.kind),
            &(to_string(&1.key) == field and &1.type == :colour)
          )

      # A stop well of a fill's gradient (§18.6): the chooser writes `fill.stop.<i>`.
      stop = field && stop_colour(field, node, design)

      %{
        theme: theme,
        key: (spec && spec.key) || (stop && field),
        spec: spec || %{type: :colour, range: nil},
        value: if(spec && is_map(node), do: Map.get(node, spec.key), else: stop && stop.colour),
        swatches:
          Enum.map(
            Theme.colour_slots(theme),
            &{to_string(&1), Theme.resolve(theme, &1, :literal)}
          ),
        recent: recent_colours(design)
      }
    end

    # The colour of a gradient stop the selected field names, from the fill of the node
    # being edited (§18.6); nil when the field is not a stop well.
    defp stop_colour("fill.stop." <> i, node, design) do
      with {index, ""} <- Integer.parse(i),
           {:paint, name} <- is_map(node) && Map.get(node, :fill),
           %{stops: stops} when is_list(stops) <- get_in(design, [:defs, name]),
           %{colour: colour} <- Enum.at(stops, index) do
        %{colour: colour}
      else
        _other -> nil
      end
    end

    defp stop_colour(_field, _node, _design), do: nil

    # A colour field opens the colour panel and a font key the font panel; any other field
    # leaves the panel where it is.
    defp context_for(socket, key) do
      %{entry: entry} = editing(socket.assigns)

      stop? = is_binary(key) and String.starts_with?(key, "fill.stop.")

      case Enum.find(Schema.describe(entry.kind), &(to_string(&1.key) == key)) do
        nil when stop? ->
          :colour

        %{type: :colour} ->
          :colour

        %{key: k} when k in [:font_family, :font_size, :font_weight, :font_style, :text_anchor] ->
          :font

        _other ->
          socket.assigns.context
      end
    end

    defp context_icons do
      [
        {:inspect,
         ~s|<svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="4" y="4" width="16" height="16" rx="2"/><path d="M8 9 H16 M8 13 H16 M8 17 H12"/></svg>|,
         "inspect"},
        {:sources,
         ~s|<svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M3 12 C6 4 9 4 12 12 C15 20 18 20 21 12"/></svg>|,
         "sources"},
        {:colour,
         ~s|<svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="8"/><circle cx="9" cy="10" r="1.5" fill="currentColor"/><circle cx="14" cy="8.5" r="1.5" fill="currentColor"/><circle cx="15.5" cy="13" r="1.5" fill="currentColor"/></svg>|,
         "colour"},
        {:font,
         ~s|<svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M5 19 L12 4 L19 19"/><path d="M8 13 H16"/></svg>|,
         "font"},
        {:variables,
         ~s|<svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M6 6 C4 6 4 10 4 12 C4 14 4 18 6 18"/><path d="M18 6 C20 6 20 10 20 12 C20 14 20 18 18 18"/><path d="M9 9 L15 15 M15 9 L9 15"/></svg>|,
         "variables"}
      ]
    end

    # Every "#rrggbb" the design's styles carry, once each, in order of first use.
    defp recent_colours(design) do
      design
      |> Map.get(:styles, %{})
      |> Map.values()
      |> Enum.flat_map(fn style -> if is_map(style), do: Map.values(style), else: [] end)
      |> Enum.filter(&(is_binary(&1) and String.starts_with?(&1, "#")))
      |> Enum.uniq()
    end

    defp theme(:dark), do: Theme.dark()
    defp theme(map) when is_map(map) and not is_struct(map), do: Theme.new(map)
    defp theme(_other), do: Theme.default()

    # The find box names a variable exactly to highlight its fields; a partial match
    # filters the list only.
    defp find_hit(find) do
      case String.trim(find || "") do
        "" -> nil
        name -> name
      end
    end

    # The Charts panel's rows (spec/14 §18.8): every chart of the workspace, the selected
    # one's layers drawn by the stack panel, another's as names to select.
    defp chart_rows(%{charts: charts, chart: selected} = assigns) do
      for chart <- charts do
        live? = chart.id == selected
        state = if live?, do: assigns, else: chart
        kind = state.open && state.open.kind != :composite && state.open.kind

        %{
          id: chart.id,
          name: chart.name,
          kind: kind,
          title: if(kind, do: "a #{kind} opened from the library", else: "a chart"),
          selected?: live?,
          expanded: chart.expanded,
          layers:
            if(live?,
              do: [],
              else:
                state.uses
                |> Enum.with_index()
                |> Enum.map(fn {use, i} -> {Stack.label(state.labels, use), i} end)
            )
        }
      end
    end

    defp disabled(uses) do
      uses
      |> Enum.with_index()
      |> Enum.reject(fn {use, _index} -> Stack.enabled?(use) end)
      |> MapSet.new(fn {_use, index} -> index end)
    end

    # The positions whose site references a library entry: locked in the chart (§18.8).
    defp locked(uses) do
      uses
      |> Enum.with_index()
      |> Enum.filter(fn {use, _index} -> Stack.locked?(use) end)
      |> MapSet.new(fn {_use, index} -> index end)
    end

    # A composite or a design is applied, so its faults are the design's; any other kind is
    # validated as that kind — per-kind validity (spec/14 §19.8).
    defp faults(_kind, _design, _assigns, [_ | _] = chain), do: [{[], {:cycle, chain}}]

    defp faults(:composite, design, %{bindings: vars, theme: theme} = assigns, nil) do
      case Chart.apply(design, sources: pool(assigns), vars: vars, theme: theme) do
        {:ok, _applied} -> []
        {:error, errors} -> errors
      end
    end

    defp faults(kind, design, _assigns, nil) do
      case Validator.validate(design, kind) do
        :ok -> []
        {:error, errors} -> errors
      end
    end

    # The strip: every root the stacked design declares, in the schema's order, then the
    # Variables tab; the open root's children and the node's facets as one row of chips.
    defp strip(nodes, entry, design, errors, chart?) do
      open_root = root(entry.label)
      here = nodes |> Enum.map(&root(&1.label)) |> Enum.uniq()
      needs = needs(errors)

      tabs =
        for root <- roots(design, here) do
          count = Map.get(needs, root, 0)

          %{
            label: root,
            open: root == open_root,
            elsewhere: root not in here,
            class: tab_class(root == open_root, root in here, count),
            title: tab_title(root, root in here, chart?, count)
          }
        end

      children =
        for node <- nodes, root(node.label) == open_root, node.label != open_root do
          %{
            label: leaf(node.label, open_root),
            node: node.label,
            open: node.label == entry.label,
            needs: Map.get(needs, node.label, 0)
          }
        end

      {tabs, children}
    end

    # What the design still needs, by the node that holds it (spec/14 §18.13): every fault
    # counted under its root and under each node on its path, so a tab and a chip can say
    # how many things under them are still needed.
    defp needs(errors) do
      errors
      |> Enum.flat_map(fn {path, _reason} -> owners(path) end)
      |> Enum.frequencies()
    end

    # The labels of every node above a fault's path: `marks[0].channels.x` is owed by
    # `marks`, `marks[0]` and `marks[0].channels`.
    defp owners(path) do
      path
      |> Enum.scan([], fn key, acc -> acc ++ [key] end)
      |> Enum.map(&Editor.label/1)
      |> Enum.uniq()
      |> Enum.reject(&(&1 == "design"))
    end

    # Every root but the design's own, the frame first (spec/14 §18.13): design is the
    # deployed tier, not a node to edit, and a chart starts from its frame.
    defp roots(design, here) do
      declared = design |> Editor.nodes() |> Enum.map(&root(&1.label)) |> Enum.uniq()
      # Neither the design's own root nor `vars` is a tab: a declaration is the variable
      # panel's (§19.10), where it is made, defaulted and bound in one place.
      # `meta` is not a tab either: the frame's page opens with the design's name (§18.15).
      roots =
        Enum.reject(
          declared ++ Enum.reject(here, &(&1 in declared)),
          &(&1 in ["design", "vars", "meta"])
        )

      Enum.filter(roots, &(&1 == "frame")) ++ Enum.reject(roots, &(&1 == "frame"))
    end

    # A node the layer does not carry yet but a page shows a form for — the frame's meta
    # (§18.15) — is implied by its label: writing to it creates it.
    defp implied("meta"), do: %{path: [:meta], kind: :meta, label: "meta"}
    defp implied(_label), do: nil

    defp first_node(nodes, mine) do
      Enum.find(nodes, &(&1.label != "design" and &1.path in mine)) ||
        Enum.find(nodes, &(&1.label != "design")) || hd(nodes)
    end

    # The selected use, resolved: the page of a site the design has no node of.
    defp target_fragment(%{uses: uses, labels: labels, selected: selected, store: store}) do
      case Stack.get(uses, selected) do
        nil ->
          %{}

        use ->
          {[{_label, fragment}], _missing} = Stack.resolve([use], labels, Stack.fetch(store))
          fragment
      end
    end

    defp tab_class(open?, here?, count) do
      ["vis-builder-node"]
      |> then(&if open?, do: &1 ++ ["vis-builder-node-open"], else: &1)
      |> then(&if here?, do: &1, else: &1 ++ ["vis-builder-node-elsewhere"])
      |> then(&if count > 0, do: &1 ++ ["vis-builder-node-needs"], else: &1)
      |> Enum.join(" ")
    end

    defp tab_title(root, here?, chart?, count) do
      base =
        cond do
          chart? -> "#{root} of the chart"
          here? -> "#{root} of this site"
          true -> "#{root} — this site declares none; opens the layer that does"
        end

      case count do
        0 -> base
        1 -> base <> " — 1 thing still needed"
        n -> base <> " — #{n} things still needed"
      end
    end

    defp chips(children, entry, facet) do
      facets = Editor.facets(entry.kind)
      open = if facet in facets, do: facet, else: List.first(facets)

      nodes =
        for child <- children do
          %{
            label: child.label,
            node: child.node,
            facet: nil,
            event: "select_node",
            class:
              chip(child.open, nil) <>
                if(child.needs > 0, do: " vis-builder-chip-needs", else: "")
          }
        end

      case facets do
        [_single] ->
          nodes

        many ->
          nodes ++
            for {one, index} <- Enum.with_index(many) do
              %{
                label: to_string(one),
                node: nil,
                facet: one,
                event: "facet",
                class: chip(one == open, index == 0 and nodes != [])
              }
            end
      end
    end

    defp chip(open?, first_facet?) do
      ["vis-builder-chip"]
      |> then(&if open?, do: &1 ++ ["vis-builder-chip-open"], else: &1)
      |> then(&if first_facet?, do: &1 ++ ["vis-builder-chip-divided"], else: &1)
      |> Enum.join(" ")
    end

    defp style_site(entry, node) do
      case Schema.key(entry.kind, :style) do
        nil ->
          nil

        %{default: fallback} ->
          value = is_map(node) && Map.get(node, :style)
          %{value: value, fallback: fallback, stack: current_stack(value || nil, fallback)}
      end
    end

    defp variables(layers, design) do
      declared = design |> Map.get(:vars, %{}) |> Map.keys()
      used = layers |> Chart.free_vars() |> Enum.map(& &1.name)
      (declared ++ used) |> Enum.uniq() |> Enum.sort() |> Enum.map(&to_string/1)
    end

    defp open_style(%{path: [:styles, name]}), do: name
    defp open_style(_entry), do: nil

    defp root(label), do: label |> String.split(~r/[.\[]/, parts: 2) |> hd()

    defp leaf(label, root) do
      label |> String.replace_prefix(root, "") |> String.replace_prefix(".", "")
    end

    defp at(container, []), do: container

    defp at(list, [index | rest]) when is_list(list) and is_integer(index),
      do: at(Enum.at(list, index), rest)

    defp at(map, [key | rest]) when is_map(map), do: at(Map.get(map, key), rest)
    defp at(_other, _path), do: nil

    defp first_under(fragment, root) when is_map(fragment) do
      fragment
      |> Editor.nodes()
      |> Enum.find(&(root(&1.label) == root))
      |> case do
        nil -> nil
        node -> node.label
      end
    end

    defp first_under(_other, _root), do: nil

    defp first_under_nodes(nodes, root) do
      case Enum.find(nodes, &(root(&1.label) == root)) do
        nil -> nil
        node -> node.label
      end
    end

    # -- writes --------------------------------------------------------------------------

    # A position arrives as a string from a `phx-value-index` and as a number from the hook.
    defp position(index) when is_integer(index), do: index

    defp position(index) when is_binary(index) do
      case Integer.parse(index) do
        {value, ""} -> value
        _other -> -1
      end
    end

    defp position(_index), do: -1

    # Selecting a layer closes an opened entry: the two are one editing target.
    defp select(socket, index) do
      case Enum.at(socket.assigns.uses, index) do
        nil ->
          socket

        use ->
          # Selecting a site opens the site's context (spec/14 §19.10).
          assign(socket,
            selected: use.id,
            node_label: "design",
            facet: nil,
            style_entry: nil,
            field: nil,
            context: :inspect
          )
      end
    end

    defp shift(list, from, to) do
      {value, rest} = List.pop_at(list, from)
      List.insert_at(rest, to, value)
    end

    # The node of the chart that owns a path: the deepest whose label is a prefix of it,
    # and the root where none is (spec/14 §18.9, §18.15).
    defp opened(socket, path) do
      label =
        socket.assigns
        |> editing()
        |> Map.fetch!(:design)
        |> Editor.nodes()
        |> Enum.filter(&owns?(&1.label, path))
        |> Enum.max_by(&String.length(&1.label), fn -> %{label: "design"} end)
        |> Map.fetch!(:label)

      assign(socket, node_label: label, facet: nil, field: nil, context: :inspect)
    end

    defp owns?("design", _path), do: false

    defp owns?(label, path) do
      path == label or String.starts_with?(path, label <> ".") or
        String.starts_with?(path, label <> "[")
    end

    # Opening an entry opens it as a new chart — a composite's sites, or the body as one
    # inline site — selected, the entry recorded on it so Save as writes the entry
    # (spec/14 §19.9).
    defp opened_entry(socket, entry) do
      {uses, labels, vars, signals} = Stack.open(entry, names(socket.assigns.store))
      n = socket.assigns.next_chart

      socket
      |> park()
      |> assign(
        open: %{id: entry.id, name: entry.name, kind: entry.kind},
        uses: uses,
        labels: labels,
        stack_vars: vars,
        signals: signals,
        selected: uses |> List.first() |> then(&(&1 && &1.id)),
        node_label: "design",
        facet: nil,
        style_entry: nil,
        field: nil,
        context: :inspect,
        added: nil,
        notice: nil
      )
      |> added_chart(entry.name || "new #{entry.kind}", "chart #{n}")
    end

    # -- the workspace of charts (spec/14 §19.9) ------------------------------------------

    # The live assigns are the selected chart's; parking writes them back to its row.
    @chart_state [:uses, :labels, :stack_vars, :selected, :open, :signals]

    defp park(%{assigns: %{chart: nil}} = socket), do: socket

    defp park(%{assigns: assigns} = socket) do
      state = Map.take(assigns, @chart_state)

      update(socket, :charts, fn charts ->
        Enum.map(charts, &if(&1.id == assigns.chart, do: Map.merge(&1, state), else: &1))
      end)
    end

    defp load(socket, id) do
      case Enum.find(socket.assigns.charts, &(&1.id == id)) do
        nil ->
          socket

        chart ->
          socket
          |> assign(Map.take(chart, @chart_state))
          |> assign(chart: id, node_label: "design", facet: nil, style_entry: nil, field: nil)
          |> update(:charts, fn charts ->
            Enum.map(charts, &if(&1.id == id, do: %{&1 | expanded: true}, else: &1))
          end)
      end
    end

    # The live assigns become a new, selected, expanded chart of the workspace.
    defp added_chart(socket, name, fallback \\ nil) do
      %{next_chart: id} = socket.assigns
      state = Map.take(socket.assigns, @chart_state)
      chart = Map.merge(state, %{id: id, name: name || fallback, expanded: true})

      assign(socket,
        charts: socket.assigns.charts ++ [chart],
        chart: id,
        next_chart: id + 1
      )
    end

    # The store's names, for the labels of an opened composite's sites.
    defp names(nil), do: fn _id -> nil end

    defp names(store) do
      fn id ->
        case Store.get(store, id) do
          {:ok, entry} -> entry.name
          :error -> nil
        end
      end
    end

    defp drifted(kind, nil) do
      "this was opened as a #{kind} and is now many things at once; a saved #{kind} must still be one"
    end

    defp drifted(kind, other) do
      "this was opened as a #{kind} and is now a #{other}; a saved #{kind} must still be one"
    end

    # The fill group's controls (spec/14 §18.6): `fill_style` writes the fill and may declare
    # the gradient named for the style; the `fill.…` controls edit that gradient where it is
    # declared. `write` is how this form writes the fill itself — the node's or the panel's.
    defp filled(socket, target, submitted, write) do
      %{entry: entry, editing: node, design: design} = editing(socket.assigns)
      value = if(is_map(node), do: Map.get(node, :fill))
      defs = Map.get(design, :defs, %{})
      name = Fills.name(entry.path)

      target
      |> Fills.writes(submitted, value, defs, name, nil)
      |> Enum.reduce(socket, fn
        {:fill, parsed}, acc -> write.(acc, {:fill, parsed})
        {:declare, name, gradient}, acc -> declare_gradient(acc, name, gradient)
        {:gradient, name, fun}, acc -> update_gradient(acc, name, fun)
      end)
      |> assign(:notice, nil)
    end

    # A gradient is declared where the selected site can hold it: under the site's own
    # `defs` when the site is a design-level layer, else as a gradient site of its own,
    # keyed by name, just below (spec/14 §18.6, §19.3).
    defp declare_gradient(socket, name, gradient) do
      %{uses: uses, labels: labels, selected: selected} = socket.assigns

      case Stack.get(uses, selected) do
        nil ->
          socket

        %Use{local: local} = use ->
          cond do
            declares_gradient?(use, name) ->
              update_gradient(socket, name, fn _old -> gradient end)

            is_map(local) and Fragment.wrapped(local) == nil ->
              update_layer(socket, [:defs], name, {:ok, gradient})

            true ->
              site = %{Use.new(nil, uses) | ref: nil, local: %{gradient: gradient}, key: name}
              at = (Stack.index_of(uses, selected) || length(uses) - 1) + 1

              assign(socket,
                uses: List.insert_at(uses, at, site),
                labels: Map.put(labels, site.id, "gradient #{name}")
              )
          end
      end
    end

    # The gradient is edited in the site that declares it — as a keyed gradient site, or
    # under a layer's `defs`; one declared only through a library reference is left alone.
    defp update_gradient(socket, name, fun) do
      %{uses: uses} = socket.assigns

      case Enum.find(uses, &declares_gradient?(&1, name)) do
        nil ->
          assign(socket, :notice, "gradient #{name} is not declared in this stack")

        %Use{ref: ref} = use when ref != nil ->
          assign(socket, :notice, locked_notice(socket.assigns, use))

        %Use{id: id, local: %{gradient: body}} ->
          assign(socket, :uses, Stack.update(uses, id, &%{&1 | local: %{gradient: fun.(body)}}))

        %Use{id: id} ->
          assign(
            socket,
            :uses,
            Stack.update(uses, id, fn use ->
              Stack.write(use, [:defs], name, {:ok, fun.(get_in(use.local, [:defs, name]))})
            end)
          )
      end
    end

    defp declares_gradient?(%Use{local: %{gradient: body}, key: key}, name) when is_map(body),
      do: key == name

    defp declares_gradient?(%Use{local: local}, name) when is_map(local),
      do: is_map(local[:defs]) and Map.has_key?(local[:defs], name)

    defp declares_gradient?(_use, _name), do: false

    # A source chosen from the pool takes the pool's fields when it declares none (§19.10).
    defp filled(%{source: body} = local, key, pool) when is_map(body) and key != nil do
      case {Map.get(body, :fields, []), Map.get(pool, key)} do
        {[], rows} when rows != nil ->
          case Visualize.Data.Table.rows(rows) do
            [first | _] when is_map(first) ->
              %{local | source: Map.put(body, :fields, first |> Map.keys() |> Enum.sort())}

            _none ->
              local
          end

        _other ->
          local
      end
    end

    defp filled(local, _key, _pool), do: local

    # A signal added is a source of the chart (spec/14 §19.10): declared under its name in
    # the selected layer with the signal's fields, unless the chart declares one already.
    defp declared_source(socket, name, %{fields: fields}) do
      %{design: design} = editing(socket.assigns)

      if Map.has_key?(Map.get(design, :sources, %{}), name) do
        socket
      else
        update_layer(socket, [:sources], name, {:ok, %{fields: fields}})
      end
    end

    # The tick goes to the host's process, which forwards it (spec/14 §18.2).
    defp schedule(socket) do
      Process.send_after(
        self(),
        {:visualize_chart_tick, socket.assigns.id},
        socket.assigns.tick_ms
      )

      socket
    end

    # An event from a form on a page aims at the form's node (spec/14 §18.15): the node is
    # selected first, so everything that reads the entry reads that node.
    defp aimed(socket, params) do
      case Map.get(params, "_node") || Map.get(params, "node") do
        label when is_binary(label) and label != "" ->
          if label == socket.assigns.node_label,
            do: socket,
            else: assign(socket, node_label: label, facet: nil, style_entry: nil)

        _none ->
          socket
      end
    end

    # The inspect tab's page (spec/14 §18.15): the nodes at the top of the open root — the
    # root itself when it is one node, else its members — each a page of sections; the
    # frame's opens with the design's meta.
    defp page(nodes, entry, layer, errors, owned, %{uses: uses, labels: labels} = assigns) do
      open_root = root(entry.label)
      under = Enum.filter(nodes, &(root(&1.label) == open_root and &1.label != "design"))
      needs = needs(errors)

      owners =
        Map.new(owned, fn {path, id} -> {path, Stack.label(labels, Stack.get(uses, id))} end)

      selected = Stack.get(uses, assigns.selected)
      layer_label = selected && Stack.label(labels, selected)
      # The labels of the library's layers: read-only in the chart (§18.8, §18.15).
      locked =
        for use <- uses, Stack.locked?(use), into: MapSet.new(), do: Stack.label(labels, use)

      tops =
        case Enum.find(under, &(length(&1.path) == 1)) do
          nil -> Enum.filter(under, &(length(&1.path) == 2))
          single -> [single]
        end

      tops =
        for node <- tops do
          name = leaf(node.label, open_root)

          %{
            kind: node.kind,
            node: at(layer, node.path) || %{},
            path: node.path,
            label: node.label,
            name: if(name == "", do: node.label, else: name),
            slug: node.label |> String.replace(~r/[^A-Za-z0-9]+/, "-") |> String.trim("-"),
            needs: Map.get(needs, node.label, 0),
            layer: Map.get(owners, node.path),
            other?: Map.get(owners, node.path) not in [nil, layer_label],
            before: if(node.kind == :frame, do: [meta_form(layer)], else: [])
          }
        end

      page = %{owners: owners, layer: layer_label, locked: locked}

      case tops do
        [one] when length(one.path) == 1 ->
          Map.merge(page, %{sections?: false, single: one, tops: []})

        many ->
          Map.merge(page, %{sections?: true, single: nil, tops: many})
      end
    end

    # Which layer gave every value of the design and which owns every node (spec/14
    # §18.15): the provenance of the placed layers (§17.1), and for a node the highest
    # enabled layer with a value under its path — the one whose word the cascade keeps.
    defp owned(%{uses: uses}, fetch, nodes) do
      placed = Stack.placed(uses, fetch)
      leaves = Chart.explain(placed)
      by_leaf = Map.new(leaves, &{&1.path, &1.layer})

      Enum.reduce(nodes, by_leaf, fn %{path: path}, acc ->
        case owner_of(leaves, placed, uses, path) do
          nil -> acc
          id -> Map.put(acc, path, id)
        end
      end)
    end

    # The provenance is of values, so a node with none yet — a site just keyed, a `%{}` —
    # is owned by the highest layer that carries it; a path through a list is a value's.
    defp owner_of(_leaves, _placed, _uses, []), do: nil

    defp owner_of(leaves, placed, uses, path) do
      order = uses |> Enum.map(& &1.id) |> Enum.with_index() |> Map.new()

      carried =
        if Enum.all?(path, &is_atom/1),
          do: for({id, fragment} <- placed, at(fragment, path) != nil, do: id),
          else: []

      leaves
      |> Enum.filter(&List.starts_with?(&1.path, path))
      |> Enum.map(& &1.layer)
      |> Kernel.++(carried)
      |> Enum.max_by(&Map.get(order, &1, -1), fn -> nil end)
    end

    # A list ticked from the columns the rows have (spec/14 §18.6): the ticked names in
    # the list's order, the variable items kept.
    defp picked(socket, entry, field, params) do
      %{editing: node} = editing(socket.assigns)

      case Enum.find(Schema.describe(entry.kind), &(to_string(&1.key) == field)) do
        %{key: key, type: {:list, _}} ->
          ticked =
            params |> Map.get(field <> ".pick", []) |> List.wrap() |> Enum.map(&String.to_atom/1)

          vars = for %Var{} = v <- (is_map(node) && Map.get(node, key, [])) || [], do: v
          parsed = if ticked ++ vars == [], do: :error, else: {:ok, ticked ++ vars}
          socket |> update_layer(entry.path, key, parsed) |> assign(:notice, nil)

        _other ->
          socket
      end
    end

    # The columns the pool's rows have, by name (spec/14 §18.6): the first row's keys.
    defp columns(pool) do
      Map.new(pool, fn {name, rows} ->
        case Visualize.Data.Table.rows(rows) do
          [first | _] when is_map(first) ->
            {name, first |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort()}

          _none ->
            {name, []}
        end
      end)
    end

    # The name a keyed source site is declared under, for its fields' columns.
    defp source_name(%{uses: uses, selected: selected}, _fetch) do
      case Stack.get(uses, selected) do
        %Use{local: %{source: _}, key: key} -> key
        _other -> nil
      end
    end

    # The design's name and description open the frame's page (spec/14 §18.15).
    defp meta_form(layer) do
      %{kind: :meta, node: Map.get(layer, :meta) || %{}, path: [:meta], label: "meta", only: nil}
    end

    defp edit_field(socket, entry, target, params) do
      if Fills.control?(target) do
        {:noreply, filled(socket, target, params[target], &edited(&1, entry, &2))}
      else
        {:noreply,
         Enum.reduce(Editor.changes(entry.kind, params), socket, &edited(&2, entry, &1))}
      end
    end

    defp edited(socket, _entry, nil), do: socket

    defp edited(socket, entry, {key, parsed}),
      do: socket |> update_layer(entry.path, key, parsed) |> unguessed(entry, key)

    # An edited field is no longer a guess; a mark's data changed clears its channels' (§18.16).
    defp unguessed(socket, entry, key) do
      prefix = if key == :data and entry.kind == :mark, do: entry.label <> ".channels.", else: nil
      own = entry.label <> "." <> to_string(key)

      update(socket, :guessed, fn guessed ->
        guessed
        |> MapSet.delete(own)
        |> MapSet.reject(&(prefix != nil and String.starts_with?(&1, prefix)))
      end)
    end

    # A write goes to the use that owns what it writes — the one surface that writes
    # `Use.local` (spec/14 §19.3): the layer that gives the key's value, else the node's
    # owner, else the selected layer, which is where anything new is made (§18.15). A
    # declaration under a root — a source, a style, a def — is new unless a layer has it.
    defp update_layer(socket, path, key, parsed) do
      %{uses: uses, selected: selected, store: store} = socket.assigns
      fetch = Stack.fetch(store)

      case owner_for(uses, fetch, path, key) || Stack.get(uses, selected) do
        nil ->
          socket

        # A referenced site is the library's word: nothing is written here (§18.15).
        %Use{ref: ref} = use when ref != nil ->
          assign(socket, :notice, locked_notice(socket.assigns, use))

        use ->
          local = Stack.local_path(use, fetch, path)
          assign(socket, :uses, Stack.update(uses, use.id, &Stack.write(&1, local, key, parsed)))
      end
    end

    # -- placing a component (spec/14 §18.16) ------------------------------------------------

    # The region a drop names: its point classified against the frame the preview drew, or
    # the region given outright; absent both, the component's home.
    defp where(socket, params, component) do
      point = {number(Map.get(params, "x")), number(Map.get(params, "y"))}

      region =
        case Map.get(params, "region") do
          given when given in ~w(plot top bottom left right) ->
            String.to_existing_atom(given)

          _none when is_map_key(params, "x") ->
            Place.region(point, Place.geometry(composed(socket)))

          _none ->
            if component, do: Place.home(component), else: :plot
        end

      {region, point}
    end

    defp number(value) when is_number(value), do: value

    defp number(value) when is_binary(value) do
      case Float.parse(value) do
        {n, _} -> n
        :error -> 0
      end
    end

    defp number(_none), do: 0

    # The composed design, or `%{}` where the stack does not compose.
    defp composed(socket) do
      %{uses: uses, store: store, stack_vars: vars} = socket.assigns

      case Stack.design(uses, vars, Stack.fetch(store)) do
        {:ok, design, _keyless} -> design
        {:error, _cycle} -> %{}
      end
    end

    # A component placed: its sites inserted above the selected layer — or above the layer
    # whose axis of the same identity it replaces, so the drop is what draws (§8.2) —
    # lowest first, the last one selected and its node opened; a legend written through
    # the ownership rule.
    defp placed(socket, component, region, point) do
      design = composed(socket)

      case Place.node(component, region, design, point) do
        {:sites, sites} ->
          %{uses: uses, labels: labels, selected: selected} = socket.assigns
          above_selected = (Stack.index_of(uses, selected) || length(uses) - 1) + 1
          at = max(above_selected, above_replaced(socket, design, sites))

          {issued, _} =
            Enum.map_reduce(sites, uses, fn site, among ->
              use = %{
                Use.new(nil, among)
                | ref: nil,
                  local: %{site.kind => site.body},
                  key: site.key
              }

              {use, among ++ [use]}
            end)

          last = List.last(issued)

          socket
          |> assign(
            uses: List.flatten(List.insert_at(uses, at, issued)),
            labels: Enum.reduce(issued, labels, &Map.put(&2, &1.id, "new #{site_kind(&1)}")),
            selected: last.id,
            adding: false,
            notice: nil
          )
          |> opened_placed(component, last)

        {:legend, node} ->
          socket
          |> update_layer([:frame], :legend, {:ok, node})
          |> assign(adding: false, notice: nil)
          |> opened("frame.legend")

        {:error, :no_scale} ->
          assign(socket, notice: "a legend needs a colour scale", adding: false)
      end
    end

    defp site_kind(%Use{local: local}), do: local |> Map.keys() |> List.first()

    # The gap above the layer that owns an axis the placed one replaces — its `{scale,
    # side}` is an axis's identity in the cascade — or 0 when nothing is replaced.
    defp above_replaced(socket, design, sites) do
      %{uses: uses, store: store} = socket.assigns
      axes = design |> Editor.nodes() |> Enum.filter(&(&1.kind == :axis))
      owners = owned(socket.assigns, Stack.fetch(store), axes)

      sites
      |> Enum.filter(&(&1.kind == :axis))
      |> Enum.flat_map(fn %{body: %{scale: scale, side: side}} ->
        for node <- axes,
            match?(%{scale: ^scale, side: ^side}, at(design, node.path)),
            owner = Map.get(owners, node.path),
            index = Stack.index_of(uses, owner),
            do: index + 1
      end)
      |> Enum.max(fn -> 0 end)
    end

    # The placed node opened: the composed design's node of the site's kind that the site
    # owns (§18.15) — an axis that replaced one of its identity owns that one's node.
    defp opened_placed(socket, _component, %Use{id: id, local: local}) do
      [{kind, body}] = Map.to_list(local)
      design = composed(socket)
      nodes = design |> Editor.nodes() |> Enum.filter(&(&1.kind == kind))
      owners = owned(socket.assigns, Stack.fetch(socket.assigns.store), nodes)

      label =
        case Enum.find(nodes, &(Map.get(owners, &1.path) == id)) do
          nil -> root_of(kind)
          node -> node.label
        end

      socket |> guessed(label, kind, body) |> opened(label)
    end

    # A placed mark's guessed channels are marked as guesses (§18.16) until edited.
    defp guessed(socket, label, :mark, %{channels: channels}) when map_size(channels) > 0 do
      update(socket, :guessed, fn set ->
        Enum.reduce(channels, set, fn {key, _}, acc ->
          MapSet.put(acc, "#{label}.channels.#{key}")
        end)
      end)
    end

    defp guessed(socket, _label, _kind, _body), do: socket

    defp root_of(:axis), do: "frame"
    defp root_of(:mark), do: "marks"
    defp root_of(:label), do: "labels"
    defp root_of(:scale), do: "frame"
    defp root_of(_kind), do: "design"

    # A library entry copied onto the graph takes its placement from the region (§18.16):
    # the copy's sites are the ones just inserted at `at`.
    defp snapped(socket, entry, at, region) do
      {sites, _vars, _signals} =
        Stack.copies(entry, Stack.fetch(socket.assigns.store), names(socket.assigns.store))

      count = length(sites)

      update(socket, :uses, fn uses ->
        uses
        |> Enum.with_index()
        |> Enum.map(fn {use, i} ->
          if i >= at and i < at + count and use.ref == nil,
            do: %{use | local: Place.placed(use.local, region)},
            else: use
        end)
      end)
    end

    defp locked_notice(%{labels: labels}, use),
      do: "#{Stack.label(labels, use)} is from the library — open it to edit"

    @declaring [[:sources], [:styles], [:defs], [:vars]]

    defp owner_for(uses, fetch, path, key) do
      placed = Stack.placed(uses, fetch)
      leaves = Chart.explain(placed)
      candidates = if path in @declaring, do: [path ++ [key]], else: [path ++ [key], path]

      Enum.find_value(candidates, fn at ->
        case owner_of(leaves, placed, uses, at) do
          nil -> nil
          id -> Stack.get(uses, id)
        end
      end)
    end

    defp styled(socket, nil), do: socket
    defp styled(socket, {key, parsed}), do: restacked(socket, &local(&1, key, parsed))

    defp local(stack, key, parsed) do
      case List.last(stack) do
        node when is_map(node) -> List.replace_at(stack, -1, write_key(node, key, parsed))
        _none -> stack ++ [write_key(%{}, key, parsed)]
      end
    end

    defp write_key(node, key, {:ok, value}), do: Map.put(node, key, value)
    defp write_key(node, key, :error), do: Map.delete(node, key)

    # A change to the open node's stack, written back in whatever shape it came in: a stack
    # of one that names a style stays a bare reference (spec/14 §3.6).
    defp restacked(socket, change) do
      %{entry: entry, editing: node} = editing(socket.assigns)

      case Schema.key(entry.kind, :style) do
        nil ->
          socket

        %{default: fallback} ->
          current = current_stack(is_map(node) && Map.get(node, :style), fallback)

          socket
          |> update_layer(entry.path, :style, {:ok, shaped(change.(current))})
          |> assign(:style_entry, nil)
      end
    end

    defp current_stack(nil, nil), do: []
    defp current_stack(nil, fallback), do: [fallback]
    defp current_stack(false, fallback), do: current_stack(nil, fallback)
    defp current_stack(value, _fallback) when is_list(value), do: value
    defp current_stack(value, _fallback), do: [value]

    defp shaped(stack) do
      case Enum.reject(stack, &(is_map(&1) and map_size(&1) == 0)) do
        [only] when not is_map(only) -> only
        pruned -> pruned
      end
    end

    defp clamp(at, list), do: at |> max(0) |> min(length(list))

    # A variable takes the type of its first use (spec/14 §18.11); a blank control removes
    # the binding and the default returns.
    defp bound(socket, nil, _value), do: socket

    defp bound(socket, free, value) do
      case Editor.submitted(Params.expects(free), value) do
        {:ok, parsed} -> update(socket, :bindings, &Map.put(&1, free.name, parsed))
        :error -> update(socket, :bindings, &Map.delete(&1, free.name))
      end
    end

    # A document is a whole design, so it replaces the stack rather than joining it (D-88),
    # as its sites: one kind each, keyed where the document keyed them (spec/14 §18.12).
    defp imported(socket, design) do
      {uses, labels} = Composite.decompose(design)

      assign(socket,
        uses: uses,
        labels: labels,
        selected: uses |> List.first() |> then(&(&1 && &1.id)),
        open: nil,
        stash: nil,
        stack_vars: %{},
        bindings: %{},
        node_label: "design",
        facet: nil,
        notice: nil
      )
    end

    # A use referring to the entry, at the position it was dropped at; the label is the
    # entry's name (spec/14 §19.3).
    # A link: the reference site of §19.3, for a layer that is to follow the library.
    defp linked(socket, entry, at) do
      %{uses: uses, labels: labels} = socket.assigns
      use = Use.new(entry.id, uses)

      assign(socket,
        uses: List.insert_at(uses, clamp(at, uses), use),
        labels: Map.put(labels, use.id, entry.name),
        selected: socket.assigns.selected || use.id,
        added: entry.id,
        notice: nil
      )
    end

    # A copy: the entry's body as inline sites — a composite as its sites — each issued an
    # id among the stack it joins, inserted in order at the gap; the composite's vars and
    # signals join the chart's where it does not declare them (spec/14 §18.17).
    defp copied(socket, entry, at) do
      %{uses: uses, labels: labels, store: store, stack_vars: vars, signals: signals} =
        socket.assigns

      {sites, entry_vars, entry_signals} = Stack.copies(entry, Stack.fetch(store), names(store))

      {issued, _} =
        Enum.map_reduce(sites, uses, fn {use, name}, among ->
          issued = %{use | id: Use.new(nil, among).id}
          {{issued, name}, among ++ [issued]}
        end)

      inserted = Enum.map(issued, &elem(&1, 0))

      assign(socket,
        uses: List.flatten(List.insert_at(uses, clamp(at, uses), inserted)),
        labels:
          Enum.reduce(issued, labels, fn {use, name}, acc -> Map.put(acc, use.id, name) end),
        stack_vars: Map.merge(entry_vars, vars),
        signals: Map.merge(entry_signals, signals),
        selected: socket.assigns.selected || (List.first(inserted) && List.first(inserted).id),
        added: entry.id,
        notice: nil
      )
    end

    # The highest layer whose fragment declares a style of that name, or `nil`.
    defp declaring(layers, name) do
      layers
      |> Enum.with_index()
      |> Enum.filter(fn {{_label, fragment}, _index} ->
        fragment
        |> Map.get(:styles)
        |> then(&(is_map(&1) and Enum.any?(Map.keys(&1), fn key -> to_string(key) == name end)))
      end)
      |> List.last()
      |> case do
        {_layer, index} -> index
        nil -> nil
      end
    end

    defp notice(reason), do: Enum.join(Document.faults(reason), "; ")

    defp saved(socket, {:ok, id}, then), do: socket |> assign(:notice, nil) |> then.(id)

    defp saved(socket, {:error, reason}, _then),
      do: assign(socket, :notice, "the store refused the design: #{inspect(reason)}")

    defp fetch(nil, _submitted), do: :error

    defp fetch(store, submitted) do
      case Store.decode_id(submitted) do
        {:ok, id} -> Store.get(store, id)
        :error -> :error
      end
    end

    defp class(base, nil), do: base
    defp class(base, extra), do: base <> " " <> extra

    # The stack as a composite: what saving sends (spec/14 §19.6).
    defp structure(%{uses: uses, stack_vars: vars} = assigns),
      do: Stack.structure(uses, vars, Map.get(assigns, :signals, %{}))

    # The pool a chart binds while designed (spec/14 §19.10): the host's under the chart's
    # signals at the tick.
    defp pool(%{sources: sources} = assigns) do
      Map.merge(
        sources,
        Signals.pool(Map.get(assigns, :signals, %{}), Map.get(assigns, :tick, 0))
      )
    end

    @doc """
    The host's one line for the signals' tick (spec/14 §18.2): forwards the message the
    builder scheduled to itself, `{:visualize_chart_tick, id}`, as an update.

        def handle_info({:visualize_chart_tick, id}, socket),
          do: {:noreply, Visualize.Chart.Builder.tick(id, socket)}
    """
    @spec tick(String.t(), Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
    def tick(id, socket) do
      send_update(__MODULE__, id: id, tick: :next)
      socket
    end
  end
end
