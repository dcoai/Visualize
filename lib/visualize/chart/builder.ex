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
      Fonts,
      Inspector,
      Layers,
      Library,
      Masks,
      Palette,
      Params,
      Picker,
      Preview,
      Stack,
      Store,
      Styles,
      StyleStack,
      Variables
    }

    alias Visualize.Chart.{Composite, Fragment, Schema, Use, Validator}
    alias Visualize.Theme

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
         stash: nil,
         stack_vars: %{},
         notice: nil,
         facet: nil,
         added: nil,
         library_view: :group,
         style_entry: nil,
         field: nil,
         adding: false,
         context: :layer,
         expanded: MapSet.new(),
         find: "",
         node_label: "design"
       )}
    end

    @impl true
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

        assign(socket,
          uses: uses,
          labels: labels,
          selected: selection(socket.assigns.selected, uses),
          host_layers: layers
        )
      end
    end

    defp seed(socket, _assigns), do: socket

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
          <span :if={@open} class="vis-builder-opened">
            editing {@open.kind} <strong>{@open.name || "(unsaved)"}</strong>
            <button type="button" class="vis-builder-close" phx-click="close" phx-target={@myself}>
              back to the stack
            </button>
          </span>
          <form :if={@store} class="vis-builder-keep" phx-submit="put_design" phx-target={@myself}>
            <label class="vis-builder-control-label" for={@id <> "-keep"}>
              {if @open, do: "Save as", else: "Save the stack as"}
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
        <div class={class("vis-builder-panels", if(@store, do: "vis-builder-panels-library"))}>
          <Library.panel
            :if={@store}
            id={@id <> "-library"}
            entries={Store.list(@store)}
            view={@library_view}
            open={(@open && @open.id) || @added}
            target={@myself}
          />
          <aside class="vis-builder-sidebar">
            <h2 class="vis-builder-sidebar-title vis-builder-sidebar-title-row">
              {@stack_title}
              <button
                type="button"
                class="vis-builder-add"
                title="add an empty site below the selected layer"
                aria-label="add a site"
                aria-expanded={to_string(@adding)}
                phx-click="adding"
                phx-target={@myself}
              >+</button>
            </h2>
            <div :if={@adding} class="vis-builder-add-menu" role="menu" aria-label="a kind to add">
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
              id={@id <> "-layers"}
              layers={@layers}
              selected={@selected_index}
              disabled={@disabled}
              target={@myself}
            />
            <p :if={@missing != []} class="vis-builder-missing">
              {length(@missing)} {if length(@missing) == 1, do: "reference", else: "references"} no longer exist — showing through
            </p>
            <p :if={@unplaced != []} class="vis-builder-missing">
              not placed: {Enum.join(@unplaced, ", ")} — a style, scale, source or var needs a name to be declared under
            </p>
          </aside>
          <main class="vis-builder-main">
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
            <nav :if={@chips != []} class="vis-builder-chips">
              <button
                :for={chip <- @chips}
                type="button"
                class={chip.class}
                phx-click={chip.event}
                phx-value-node={chip.node}
                phx-value-facet={chip.facet}
                phx-target={@myself}
              >{chip.label}</button>
            </nav>
            <div class="vis-builder-workspace">
              <Editor.panel
                id={@id <> "-editor"}
                kind={@entry.kind}
                selected={@field}
                found={@find_hit}
                node={@editing}
                path={@entry.path}
                facet={@facet}
                errors={@errors}
                refs={@refs}
                theme={@colour.theme}
                strip={false}
                target={@myself}
              />
              <Preview.panel
                :if={@preview?}
                design={@design}
                sources={@sources}
                vars={@bindings}
                theme={@theme}
              />
            </div>
          </main>
          <aside class="vis-builder-context">
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
            <StyleStack.panel
              :if={@context == :layer and @style_site}
              id={@id <> "-style-stack"}
              value={@style_site.value}
              fallback={@style_site.fallback}
              design={@design}
              open={@style_entry}
              target={@myself}
            />
            <Editor.panel
              :if={@context == :layer && @style_site && @style_entry}
              id={@id <> "-style-editor"}
              class="vis-builder-style-panel"
              kind={:style}
              node={StyleStack.resolved(@design, @style_site.stack)}
              origins={StyleStack.origins(@design, @style_site.stack)}
              strip={false}
              event="edit_style"
              refs={@refs}
              theme={@colour.theme}
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
              :if={@context == :layer && @site && !(@style_site && @style_entry)}
              id={@id <> "-masks"}
              use={@site.use}
              label={@site.label}
              fragment={@site.fragment}
              free={@site.free}
              keyless={@site.use.id in @keyless}
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

    # Closing an entry is the way back to the stack it was opened over (spec/14 §19.9).
    def handle_event("close", _params, socket) do
      {:noreply, closed(socket)}
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
      {:noreply, assign(socket, node_label: label, facet: nil, field: nil)}
    end

    # Clicking into a field selects it, and the context panel becomes its picker
    # (spec/14 §19.10); the same click on the field already selected leaves it.
    def handle_event("select_field", %{"field" => key}, socket) do
      {:noreply, assign(socket, field: key, context: context_for(socket, key))}
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

    # A root the editing target declares opens there; one it does not takes the person to
    # the highest layer that declares it — what the inspector and the palette already do
    # (spec/14 §18.13, §18.9, §18.14).
    def handle_event("select_root", %{"root" => root}, socket) do
      case first_under(target_fragment(socket.assigns), root) do
        nil ->
          %{layers: layers} = editing(socket.assigns)

          layers
          |> Enum.with_index()
          |> Enum.reverse()
          |> Enum.find(fn {{_label, fragment}, _index} -> first_under(fragment, root) end)
          |> case do
            nil ->
              {:noreply, socket}

            {{_label, fragment}, index} ->
              {:noreply, socket |> select(index) |> opened(first_under(fragment, root))}
          end

        label ->
          {:noreply, assign(socket, node_label: label, facet: nil)}
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

        _other ->
          {:noreply, socket}
      end
    end

    # A library item from the keyboard: Enter opens, Insert adds above the selected layer.
    def handle_event("fragment_key", %{"key" => key, "name" => name}, socket) do
      case key do
        enter when enter in ["Enter", " "] ->
          handle_event("add_layer", %{"name" => name}, socket)

        insert when insert in ["Insert", "i"] ->
          above = (Stack.index_of(socket.assigns.uses, socket.assigns.selected) || -1) + 1
          handle_event("insert", %{"name" => name, "at" => above}, socket)

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
    def handle_event("insert", %{"scope" => "ref", "field" => field, "name" => submitted}, socket) do
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
    def handle_event("insert", %{"name" => submitted, "at" => at}, socket) do
      case fetch(socket.assigns.store, submitted) do
        {:ok, entry} ->
          case admits(socket.assigns.open, entry) do
            :ok -> {:noreply, inserted(socket, entry, position(at))}
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
    def handle_event("edit_style", params, socket) do
      {:noreply, Enum.reduce(Editor.changes(:style, params), socket, &styled(&2, &1))}
    end

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

    def handle_event("edit", params, socket) do
      %{entry: entry} = editing(socket.assigns)

      {:noreply, Enum.reduce(Editor.changes(entry.kind, params), socket, &edited(&2, entry, &1))}
    end

    def handle_event("set_var", %{"_target" => [name]} = params, socket) do
      %{layers: layers} = editing(socket.assigns)
      free = Enum.find(Chart.free_vars(layers), &(to_string(&1.name) == name))
      {:noreply, bound(socket, free, params[name])}
    end

    # The key a name-keyed site is declared under, from the context panel (spec/14 §19.3):
    # the one surface that writes `Use.key`; blank removes it.
    def handle_event("set_key", %{"key" => submitted}, socket) do
      %{selected: selected} = socket.assigns

      key =
        case Editor.parse(:name, submitted) do
          {:ok, name} -> name
          :error -> nil
        end

      {:noreply, update(socket, :uses, &Stack.update(&1, selected, fn u -> %{u | key: key} end))}
    end

    # A list of scalars as items (spec/14 §18.6): Enter in the + box appends one read by the
    # element's type; × removes by index. Both write the whole list, as the schema says.
    def handle_event("list_add", %{"field" => field} = params, socket) do
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

    def handle_event("list_remove", %{"field" => field, "index" => index}, socket) do
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
             adding: false,
             notice: nil
           )}
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
    def handle_event("bind_field", %{"field" => field, "name" => name}, socket) do
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

    def handle_event("unbind_field", %{"field" => field}, socket) do
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
      edit = if Map.get(params, "edit") == "edit_style", do: "edit_style", else: "edit"
      kind = if edit == "edit_style", do: :style, else: editing(socket.assigns).entry.kind

      case Enum.find(Schema.describe(kind), &(to_string(&1.key) == field)) do
        %{type: :colour} ->
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
    def handle_event("promote", %{"field" => field}, socket) do
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

    # The editing target: the selected use, resolved.
    defp target_fragment(%{uses: uses, labels: labels, selected: selected, store: store}) do
      case Stack.get(uses, selected) do
        nil ->
          %{}

        use ->
          {[{_label, fragment}], _missing} = Stack.resolve([use], labels, Stack.fetch(store))
          fragment
      end
    end

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
      layer = target_fragment(assigns)
      nodes = Editor.nodes(layer)

      # The design root itself is not a place to edit: its keys are Deploy's (`version`)
      # or sites of their own (§19.8), so a layer opens on its first real node.
      entry =
        case assigns.node_label do
          "design" -> first_node(nodes)
          label -> Enum.find(nodes, &(&1.label == label)) || first_node(nodes)
        end

      errors = faults(kind, design, assigns, cycle)
      {tabs, children} = strip(nodes, entry, design, errors)

      %{
        layers: layers,
        missing: missing,
        design: design,
        nodes: nodes,
        entry: entry,
        tabs: tabs,
        chips: chips(children, entry, assigns.facet),
        needs: needs(errors),
        style_site: style_site(entry, at(layer, entry.path)),
        open_style: open_style(entry),
        variables: variables(layers, design),
        sites: Stack.sites(assigns.uses, assigns.labels, fetch),
        find_hit: find_hit(assigns.find),
        site: site(assigns, fetch),
        refs: refs(design, assigns.store),
        colour: colour(assigns, entry, at(layer, entry.path), design),
        editing: at(layer, entry.path),
        errors: errors,
        keyless: keyless,
        unplaced: Enum.map(keyless, &Stack.label(assigns.labels, Stack.get(assigns.uses, &1))),
        kind: kind,
        preview?: kind == :composite,
        stack_title: stack_title(kind),
        selected_index: Stack.index_of(assigns.uses, assigns.selected),
        disabled: disabled(assigns.uses)
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

      %{
        theme: theme,
        key: spec && spec.key,
        spec: spec || %{type: :colour, range: nil},
        value: if(spec && is_map(node), do: Map.get(node, spec.key)),
        swatches:
          Enum.map(
            Theme.colour_slots(theme),
            &{to_string(&1), Theme.resolve(theme, &1, :literal)}
          ),
        recent: recent_colours(design)
      }
    end

    # A colour field opens the colour panel and a font key the font panel; any other field
    # leaves the panel where it is.
    defp context_for(socket, key) do
      %{entry: entry} = editing(socket.assigns)

      case Enum.find(Schema.describe(entry.kind), &(to_string(&1.key) == key)) do
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
        {:layer,
         ~s|<svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 8 L12 4 L20 8 L12 12 Z"/><path d="M4 12 L12 16 L20 12"/><path d="M4 16 L12 20 L20 16"/></svg>|,
         "layer"},
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

    defp stack_title(:composite), do: "Layers"
    defp stack_title(kind), do: "#{kind} stack"

    defp disabled(uses) do
      uses
      |> Enum.with_index()
      |> Enum.reject(fn {use, _index} -> Stack.enabled?(use) end)
      |> MapSet.new(fn {_use, index} -> index end)
    end

    # A composite or a design is applied, so its faults are the design's; any other kind is
    # validated as that kind — per-kind validity (spec/14 §19.8).
    defp faults(_kind, _design, _assigns, [_ | _] = chain), do: [{[], {:cycle, chain}}]

    defp faults(:composite, design, %{sources: sources, bindings: vars, theme: theme}, nil) do
      case Chart.apply(design, sources: sources, vars: vars, theme: theme) do
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
    defp strip(nodes, entry, design, errors) do
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
            title: tab_title(root, root in here, count)
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

    # Every root but the design's own: design is the deployed tier, not a node to edit.
    defp roots(design, here) do
      declared = design |> Editor.nodes() |> Enum.map(&root(&1.label)) |> Enum.uniq()
      # Neither the design's own root nor `vars` is a tab: a declaration is the variable
      # panel's (§19.10), where it is made, defaulted and bound in one place.
      Enum.reject(declared ++ Enum.reject(here, &(&1 in declared)), &(&1 in ["design", "vars"]))
    end

    defp first_node(nodes) do
      Enum.find(nodes, &(&1.label != "design")) || hd(nodes)
    end

    defp tab_class(open?, here?, count) do
      ["vis-builder-node"]
      |> then(&if open?, do: &1 ++ ["vis-builder-node-open"], else: &1)
      |> then(&if here?, do: &1, else: &1 ++ ["vis-builder-node-elsewhere"])
      |> then(&if count > 0, do: &1 ++ ["vis-builder-node-needs"], else: &1)
      |> Enum.join(" ")
    end

    defp tab_title(root, here?, count) do
      base =
        if here?,
          do: "#{root} of this layer",
          else: "#{root} — this layer declares none; opens the layer that does"

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
          assign(socket,
            selected: use.id,
            node_label: "design",
            facet: nil,
            style_entry: nil,
            field: nil
          )
      end
    end

    defp shift(list, from, to) do
      {value, rest} = List.pop_at(list, from)
      List.insert_at(rest, to, value)
    end

    # The node of the target that owns a path: the deepest whose label is a prefix of it,
    # and the root where none is (spec/14 §18.9).
    defp opened(socket, path) do
      label =
        socket.assigns
        |> target_fragment()
        |> Editor.nodes()
        |> Enum.filter(&owns?(&1.label, path))
        |> Enum.max_by(&String.length(&1.label), fn -> %{label: "design"} end)
        |> Map.fetch!(:label)

      assign(socket, node_label: label, facet: nil, field: nil)
    end

    defp owns?("design", _path), do: false

    defp owns?(label, path) do
      path == label or String.starts_with?(path, label <> ".") or
        String.starts_with?(path, label <> "[")
    end

    # Opening an entry makes it the stack — a composite's sites, or the body as one inline
    # site — and the field forms then write to a site in it. The stack it was opened over
    # is stashed once and comes back on close (spec/14 §19.9).
    defp opened_entry(socket, entry) do
      {uses, labels, vars} = Stack.open(entry, names(socket.assigns.store))

      socket
      |> stashed()
      |> assign(
        open: %{id: entry.id, name: entry.name, kind: entry.kind},
        uses: uses,
        labels: labels,
        stack_vars: vars,
        selected: uses |> List.first() |> then(&(&1 && &1.id)),
        node_label: "design",
        facet: nil,
        style_entry: nil,
        added: nil,
        notice: nil
      )
    end

    defp stashed(%{assigns: %{open: nil} = assigns} = socket) do
      assign(socket, :stash, Map.take(assigns, [:uses, :labels, :stack_vars, :selected]))
    end

    defp stashed(socket), do: socket

    defp closed(%{assigns: %{stash: nil}} = socket), do: assign(socket, :open, nil)

    defp closed(%{assigns: %{stash: stash}} = socket) do
      socket
      |> assign(stash)
      |> assign(open: nil, stash: nil, node_label: "design", facet: nil, style_entry: nil)
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

    defp edited(socket, _entry, nil), do: socket
    defp edited(socket, entry, {key, parsed}), do: update_layer(socket, entry.path, key, parsed)

    # A write goes to the selected use's local — the one surface that writes `Use.local`
    # (spec/14 §19.3).
    defp update_layer(socket, path, key, parsed) do
      %{uses: uses, selected: selected} = socket.assigns

      case Stack.get(uses, selected) do
        nil ->
          socket

        _use ->
          assign(socket, :uses, Stack.update(uses, selected, &Stack.write(&1, path, key, parsed)))
      end
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
    defp inserted(socket, entry, at) do
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
    defp structure(%{uses: uses, stack_vars: vars}), do: Stack.structure(uses, vars)
  end
end
