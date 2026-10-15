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
    * `catalog` - the connector catalog of the board mode: each feed the host offers to its
      `Visualize.Data.Schema`, or `nil` to bind a board's slots to the sample pool
      (spec/14 §22.8)
    * `board_bindings` - a `Visualize.Board.Binding` the host holds, by the board entry's id
    * `on_bind` - the tag of the binding message, `{on_bind, id, board_id, binding}`, sent
      on every change of a board's binding; the binding is never stored in the board
      (default `:visualize_board_bound`)
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

    import Visualize.Chart.Builder.Editing, only: [editing: 1, root: 1]

    import Visualize.Chart.Builder.Workspace,
      only: [added_chart: 2, load: 2, park: 1, schedule: 1, selection: 2]

    alias Visualize.Chart.Builder.{
      Axes,
      BoardGrid,
      Boards,
      Document,
      Editor,
      Events,
      Fonts,
      Glyphs,
      Inspector,
      Layers,
      Library,
      Masks,
      Modes,
      Page,
      Palette,
      Picker,
      Preview,
      Sources,
      Stack,
      Store,
      Styles,
      StyleStack,
      Themes,
      ThemeSheet,
      Variables
    }

    # Every event is handled by the module of its area, and a mode's by the mode's module
    # (spec/14 §18, §20): `handle_event/3` below is the one entry, and routes by the event's
    # name. An event two modules claim is a compile error, never a silent shadowing.
    @handlers [
                Events.Library,
                Events.Charts,
                Events.Inspect,
                Events.Data,
                Events.Tree,
                Events.Form,
                Events.Variables,
                Events.Color,
                Events.Graph
              ] ++ Modes.all()

    @routes Enum.reduce(@handlers, %{}, fn module, routes ->
              Enum.reduce(module.events(), routes, fn event, routes ->
                if Map.has_key?(routes, event),
                  do: raise(CompileError, description: "#{event} is handled twice"),
                  else: Map.put(routes, event, module)
              end)
            end)

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
        generators: [],
        source_defaults: true,
        tick_ms: 500,
        catalog: nil,
        board_bindings: %{},
        on_bind: :visualize_board_bound,
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

    attr(:catalog, :map,
      default: nil,
      doc:
        "the connector catalog: each feed the host offers to its `Visualize.Data.Schema`;" <>
          " `nil` binds a board's slots to the sample pool (spec/14 §22.8)"
    )

    attr(:board_bindings, :map,
      default: %{},
      doc: "a `Visualize.Board.Binding` the host holds, by the board entry's id (spec/14 §22.8)"
    )

    attr(:on_bind, :any,
      default: :visualize_board_bound,
      doc: "the tag of the binding message, `{on_bind, id, board_id, binding}`"
    )

    attr(:styles, :boolean,
      default: true,
      doc: "render the stylesheet, `false` if the host ships it"
    )

    attr(:class, :string, default: nil, doc: "appended to the builder's root class")

    attr(:library_folded, :any,
      doc:
        "the library's top-level headers folded at the start, a set of names; a person's" <>
          " folds are the builder's own after that (spec/14 §18.16, #355)"
    )

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
         palette_chosen: nil,
         field: nil,
         menu: nil,
         reverting: nil,
         selection: MapSet.new(),
         context: :inspect,
         library_open: true,
         context_width: 400,
         graph_size: nil,
         collapsed: MapSet.new(),
         guessed: MapSet.new(),
         expanded_layers: MapSet.new(),
         expanded_sites: MapSet.new(),
         mask_layers: MapSet.new(),
         expanded: MapSet.new(),
         find: "",
         node_label: "design",
         theme_designs: [],
         vision: :none,
         board: nil,
         board_cell: nil,
         binding: nil,
         board_view: :wide,
         return_to: nil
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
        |> assign(Map.drop(assigns, [:layers, :library_folded]))
        |> assign_new(:library_folded, fn -> Map.get(assigns, :library_folded, MapSet.new()) end)
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

    defp default({key, value}, socket), do: assign_new(socket, key, fn -> value end)

    # The style stack and, with an entry open, the style editor of the selected node
    # (spec/14 §18.18, #378): rendered where the node is — in its section, or after a
    # page that is the node — never at the column's foot.
    attr(:id, :string, required: true)
    attr(:style_site, :any, required: true)
    attr(:style_entry, :any, required: true)
    attr(:design, :map, required: true)
    attr(:refs, :map, required: true)
    attr(:theme, :any, required: true)
    attr(:defs, :map, required: true)
    attr(:target, :any, required: true)

    defp style_panels(assigns) do
      ~H"""
      <StyleStack.panel
        :if={@style_site}
        id={@id <> "-style-stack"}
        value={@style_site.value}
        fallback={@style_site.fallback}
        design={@design}
        theme={@theme}
        columns={@style_site.columns}
        generators={@style_site.generators}
        open={@style_entry}
        target={@target}
      />
      <Editor.panel
        :if={@style_site && @style_entry}
        id={@id <> "-style-editor"}
        class="vis-builder-style-panel"
        kind={:style}
        node={StyleStack.resolved(@design, @style_site.stack, @theme)}
        origins={StyleStack.origins(@design, @style_site.stack, @theme)}
        strip={false}
        event="edit_style"
        drawn_by={@style_site.drawn_by}
        refs={@refs}
        theme={@theme}
        defs={@defs}
        target={@target}
      />
      """
    end

    @impl true
    def render(assigns) do
      assigns = assign(assigns, editing(assigns))

      ~H"""
      <div id={@id} class={class("vis-builder", @class)}>
        <Styles.styles :if={@styles} />
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
            folded={@library_folded}
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
            <form :if={@store} id={@id <> "-new-form"} class="vis-builder-new" phx-submit="new_fragment" phx-target={@myself}>
              <label class="vis-builder-control-label" for={@id <> "-new-kind"}>New</label>
              <select id={@id <> "-new-kind"} name="kind" class="vis-builder-new-kind">
                <option :for={kind <- Stack.kinds()} value={kind}>{kind}</option>
              </select>
              <button type="submit" class="vis-builder-new-submit">New</button>
            </form>
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
                    :if={row.selected? and row.kind != :board}
                    type="button"
                    class="vis-builder-add"
                    title="add an empty layer: drag objects into it from the library"
                    aria-label="add a layer"
                    phx-click="new_layer"
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
                <Layers.panel
                  :if={row.selected? and row.expanded}
                  id={@id <> "-layers"}
                  rows={@tree_rows}
                  hidden={@hidden_index}
                  selected={@selected_index}
                  chosen={@chosen_index}
                  disabled={@disabled}
                  expanded={@expanded_index}
                  placed={@placed_layers}
                  masks={@layer_masks}
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
            <div class="vis-builder-chart-bar">
              <form :if={@store} id={@id <> "-keep-form"} class="vis-builder-keep" phx-submit="put_design" phx-target={@myself}>
                <input
                  id={@id <> "-keep"}
                  type="text"
                  name="name"
                  class="vis-builder-name"
                  value={(@open && @open.name) || ""}
                  placeholder="Group:sub-group:name"
                  aria-label={if @open, do: "save as", else: "save the chart as"}
                />
                <button type="submit" class="vis-builder-put">Save to library</button>
              </form>
              <button
                :if={@return_to}
                type="button"
                class="vis-builder-board-return"
                phx-click="board_return"
                phx-target={@myself}
                title="back to the board this component was opened from (spec/14 §22.7)"
              >
                Back to board
              </button>
              <button :if={@preview?} type="button" class="vis-builder-save" phx-click="save" phx-target={@myself}>
                Save
              </button>
              <button
                :if={@preview?}
                type="button"
                class="vis-builder-theme-open"
                phx-click="open_theme"
                phx-target={@myself}
                title="the theme mode: edit and preview this chart's theme"
              >
                Theme
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
            <BoardGrid.grid :if={@board_mode} id={@id <> "-board"} mode={@board_mode} target={@myself} />
            <div
              :if={!@board_mode}
              id={@id <> "-graph"}
              class="vis-builder-graph"
              tabindex="0"
              phx-hook="BuilderHook"
              data-builder-target={@myself}
              data-builder-scope="graph"
            >
              <Preview.panel
                :if={@preview?}
                design={@design}
                sources={@bound_pool}
                catalog={@catalog}
                vars={@bindings}
                theme={@preview_theme}
                generators={@generators}
                selected={@entry.label}
                steps={@steps}
                target={@myself}
                size={@graph_size}
                box={@id <> "-box"}
              />
              <ThemeSheet.sheet
                :if={@theme_mode}
                id={@id <> "-theme-sheet"}
                theme={@theme_mode.theme}
                designs={@theme_mode.designs}
                choices={@theme_mode.choices}
                vision={@vision}
                sources={@bound_pool}
                vars={@bindings}
                target={@myself}
              />
              <p :if={!@preview? and !@theme_mode} class="vis-builder-context-note">
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
                aria-label={tab.word}
                data-builder-bind-root={tab.label}
                phx-click="select_root"
                phx-value-root={tab.label}
                phx-target={@myself}
              >{Phoenix.HTML.raw(Glyphs.icon(tab.label))}<span :if={tab.needs > 0} class="vis-builder-node-badge">{tab.needs}</span></button>
              <button
                type="button"
                class={@variables_tab.class}
                title={@variables_tab.title}
                aria-label="variables"
                aria-pressed={to_string(@variables_tab.open)}
                data-builder-promote-target="true"
                phx-click="context"
                phx-value-panel="variables"
                phx-target={@myself}
              >{Phoenix.HTML.raw(Glyphs.icon(:variables))}<span :if={@variables_tab.needs > 0} class="vis-builder-node-badge">{@variables_tab.needs}</span></button>
              <button
                type="button"
                class={"vis-builder-node vis-builder-node-color" <> if(@context == :color, do: " vis-builder-node-open", else: "")}
                title={if(@context == :color, do: "colour — back to the node's form", else: "colour — the picker for the selected node")}
                aria-label="color"
                aria-pressed={to_string(@context == :color)}
                phx-click="context"
                phx-value-panel={if(@context == :color, do: "inspect", else: "color")}
                phx-target={@myself}
              >{Phoenix.HTML.raw(Glyphs.icon(:color))}</button>
            </nav>
            <Themes.panel
              :if={@context == :inspect and @theme_mode}
              id={@id <> "-theme"}
              node={@theme_mode.node}
              theme={@theme_mode.theme}
              faults={@theme_mode.faults}
              derive={@theme_mode.derive}
              vision={@vision}
              target={@myself}
            />
            <Boards.panel
              :if={@context == :inspect and @board_mode}
              id={@id <> "-board-panel"}
              mode={@board_mode}
              target={@myself}
            />
            <div :if={@context == :inspect and !@theme_mode and !@board_mode} class="vis-builder-inspect">
              <button
                :if={@preview? and root(@entry.label) == "frames"}
                type="button"
                class="vis-builder-add-frame"
                title="a new frame, a quarter of the graph at its centre; drag it into place"
                phx-click="add_frame"
                phx-target={@myself}
              >+ frame</button>
              <details
                :for={top <- @page.tops}
                :if={@page.sections? and not @data_page?}
                class={"vis-builder-section vis-builder-section-top" <> if(top.needs > 0, do: " vis-builder-section-needs", else: "") <> if(top.other?, do: " vis-builder-section-other", else: "") <> if(top.label == @entry.label, do: " vis-builder-section-selected", else: "")}
                open={not MapSet.member?(@collapsed, top.label)}
              >
                <summary
                  class="vis-builder-section-title"
                  title={if(top.layer, do: "#{top.label} — in #{top.layer}", else: top.label)}
                  phx-click="toggle_section"
                  phx-value-section={top.label}
                  phx-target={@myself}
                >{top.name}<span :if={top.layer} class="vis-builder-section-layer">{top.layer}</span></summary>
                <div :if={Page.styled?(top.kind)} class="vis-builder-section-select">
                  <span :if={top.label == @entry.label} class="vis-builder-section-selected-word">selected</span>
                  <button :if={top.layer && Map.has_key?(@page.locked, top.layer)} type="button" class="vis-builder-section-select-button" phx-click="copy_node" phx-value-node={top.label} phx-target={@myself}>copy</button>
                  <button :if={top.layer && Map.has_key?(@page.locked, top.layer)} type="button" class="vis-builder-section-select-button" phx-click="override_node" phx-value-node={top.label} phx-target={@myself}>override</button>
                  <button
                    :if={top.label != @entry.label}
                    type="button"
                    class="vis-builder-section-select-button"
                    title={"open #{top.label} — its form and its style"}
                    phx-click="select_node"
                    phx-value-node={top.label}
                    phx-target={@myself}
                  >select — edit its style</button>
                </div>
                <div :if={top.kind == :frame} class="vis-builder-section-select">
                  <span :if={top.label == @entry.label} class="vis-builder-section-selected-word">selected — drag it on the graph</span>
                  <button
                    :if={top.label != @entry.label}
                    type="button"
                    class="vis-builder-section-select-button"
                    title={"open #{top.label} — its outline and handles on the graph"}
                    phx-click="select_node"
                    phx-value-node={top.label}
                    phx-target={@myself}
                  >select — place it on the graph</button>
                </div>
                <Axes.section :if={top[:axes] not in [nil, []]} rows={top.axes} target={@myself} />
                <ul :if={top[:draws] not in [nil, []]} class="vis-builder-draws" title="what this frame draws">
                  <li :for={drawn <- top.draws}>
                    <button
                      type="button"
                      class="vis-builder-draws-item"
                      phx-click="select_node"
                      phx-value-node={drawn.label}
                      phx-target={@myself}
                    >{drawn.word}</button>
                  </li>
                </ul>
                <Page.page
                  id={@id <> "-page-" <> top.slug}
                  kind={top.kind}
                  node={top.node}
                  path={top.path}
                  label={top.label}
                  before={top.before}
                  design_defaults={top[:design_defaults]}
                  collapsed={@collapsed}
                  errors={@errors}
                  refs={@refs}
                  selected={@field}
                  selected_node={@entry.label}
                  found={@find_hit}
                  theme={@color.theme}
                  defs={@defs}
                  pool={@pool}
                  hidden={if(@source_defaults, do: [], else: [:default])}
                  columns={@columns}
                  source_name={@source_name}
                  channel_columns={@channel_columns}
                  owners={@page.owners}
                  layer={@page.layer}
                  locked={@page.locked}
                  guessed={@guessed}
                  target={@myself}
                  layout={Map.get(@design, :layout)}
                >
                  <:style_for :let={_label}>
                    <.style_panels
                      id={@id}
                      style_site={@style_site}
                      style_entry={@style_entry}
                      design={@design}
                      refs={@refs}
                      theme={@palette_theme}
                      defs={@defs}
                      target={@myself}
                    />
                  </:style_for>
                </Page.page>
                <.style_panels
                  :if={Page.styled?(top.kind) and top.label == @entry.label}
                  id={@id}
                  style_site={@style_site}
                  style_entry={@style_entry}
                  design={@design}
                  refs={@refs}
                  theme={@palette_theme}
                  defs={@defs}
                  target={@myself}
                />
              </details>
              <div
                :if={not @page.sections? and not @data_page? and @page.single.layer}
                class={"vis-builder-page-head" <> if(@page.single.other?, do: " vis-builder-section-other", else: "") <> if(Map.has_key?(@page.locked, @page.single.layer), do: " vis-builder-page-locked", else: "")}
                title={"#{@page.single.label} — in #{@page.single.layer}"}
              >
                <span class="vis-builder-section-layer">{@page.single.layer}</span>
              </div>
              <Page.page
                :if={not @page.sections? and not @data_page?}
                id={@id <> "-page"}
                kind={@page.single.kind}
                node={@page.single.node}
                path={@page.single.path}
                label={@page.single.label}
                before={@page.single.before}
                design_defaults={@page.single[:design_defaults]}
                collapsed={@collapsed}
                errors={@errors}
                refs={@refs}
                selected={@field}
                selected_node={@entry.label}
                found={@find_hit}
                theme={@color.theme}
                defs={@defs}
                pool={@pool}
                hidden={if(@source_defaults, do: [], else: [:default])}
                columns={@columns}
                source_name={@source_name}
                channel_columns={@channel_columns}
                owners={@page.owners}
                layer={@page.layer}
                locked={@page.locked}
                guessed={@guessed}
                target={@myself}
                layout={Map.get(@design, :layout)}
              >
                <:style_for :let={_label}>
                  <.style_panels
                    id={@id}
                    style_site={@style_site}
                    style_entry={@style_entry}
                    design={@design}
                    refs={@refs}
                    theme={@palette_theme}
                    defs={@defs}
                    target={@myself}
                  />
                </:style_for>
              </Page.page>
              <.style_panels
                :if={not @page.sections? and not @data_page? and @page.single.label == @entry.label}
                id={@id}
                style_site={@style_site}
                style_entry={@style_entry}
                design={@design}
                refs={@refs}
                theme={@palette_theme}
                defs={@defs}
                target={@myself}
              />
            </div>
            <Axes.section :if={@context == :inspect and @axes_rows != []} rows={@axes_rows} target={@myself} />
            <Sources.panel
              :if={@context == :inspect and @data_page?}
              id={@id <> "-sources"}
              rows={@data_rows}
              tick={@tick}
              playing={@playing}
              tick_ms={@tick_ms}
              pool={@pool}
              defaults?={@source_defaults}
              target={@myself}
            />
            <Picker.panel
              :if={@context == :color}
              id={@id <> "-picker"}
              key={@color.key}
              spec={@color.spec}
              value={@color.value}
              groups={@color.groups}
              theme={@color.theme}
              recent={@color.recent}
              target={@myself}
            />
            <Fonts.panel
              :if={@context == :inspect and root(@entry.label) == "styles"}
              id={@id <> "-fonts"}
              kind={@entry.kind}
              node={@editing}
              target={@myself}
            />
            <Masks.panel
              :if={@context == :inspect && @site && !(@style_site && @style_entry) && !@theme_mode && !@board_mode}
              id={@id <> "-masks"}
              use={@site.use}
              label={@site.label}
              fragment={@site.fragment}
              free={@site.free}
              keyless={@site.use.id in @keyless}
              pool={@pool}
              index={@selected_index}
              reverting={@reverting == @site.use.id}
              store?={@store != nil}
              target={@myself}
            />
            <section
              :if={@context == :inspect && @site && Stack.group?(@site.use) && !(@style_site && @style_entry) && !@theme_mode && !@board_mode}
              class="vis-builder-site-defaults"
            >
              <h3 class="vis-builder-context-title">defaults</h3>
              <p class="vis-builder-context-note">what everything in {@site.label} inherits under its styles (spec/14 §3.8)</p>
              <Editor.form_body
                id={@id <> "-site-defaults"}
                kind={:defaults}
                node={get_in(@site.use.local, [:composite, :defaults]) || %{}}
                event="edit_defaults"
                refs={@refs}
                theme={@color.theme}
                defs={@defs}
                target={@myself}
              />
            </section>
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
        <menu
          :if={@menu}
          id={@id <> "-menu"}
          class="vis-builder-menu"
          style={"left: #{@menu.x}px; top: #{@menu.y}px"}
          phx-click-away="menu_close"
          phx-window-keydown="menu_close"
          phx-key="Escape"
          phx-target={@myself}
        >
          <li :if={@menu[:site] && @menu.site.items != []} class="vis-builder-menu-site">
            <button :for={{event, word} <- @menu.site.items} type="button" class="vis-builder-menu-item" phx-click={event} phx-value-index={@menu.site.index} phx-target={@myself}>{word}</button>
          </li>
          <li :for={label <- @menu.nodes} class="vis-builder-menu-node">
            <span :if={length(@menu.nodes) > 1} class="vis-builder-menu-label">{label}</span>
            <button type="button" class="vis-builder-menu-item" phx-click="copy_node" phx-value-node={label} phx-target={@myself}>Copy</button>
            <button type="button" class="vis-builder-menu-item" phx-click="override_node" phx-value-node={label} phx-target={@myself}>Override</button>
            <button type="button" class="vis-builder-menu-item" phx-click="pick" phx-value-node={label} phx-target={@myself}>Open</button>
          </li>
        </menu>
        <div class="vis-builder-tray">
          <Palette.panel id={@id <> "-palette"} design={@design} theme={@palette_theme} open={@open_style} chosen={@palette_chosen} target={@myself} />
          <Inspector.look :if={@look} id={@id <> "-look"} look={@look} label={@entry.label} />
          <Inspector.panel id={@id <> "-inspector"} layers={@layers} target={@myself} />
          <Document.panel id={@id <> "-document"} design={@design} kind={@kind} target={@myself} />
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

    # Every event the builder's markup sends, routed to the module of its area; an event no
    # module handles is a `FunctionClauseError` here, as a missing clause always was.
    @impl true
    def handle_event(event, params, socket) when is_map_key(@routes, event),
      do: Map.fetch!(@routes, event).handle_event(event, params, socket)

    defp class(base, nil), do: base
    defp class(base, extra), do: base <> " " <> extra

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
