if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder do
    @moduledoc """
    An embeddable editor for a stack of design fragments (spec/14 §18).

    A `Phoenix.LiveComponent`, not a `Phoenix.LiveView`: a LiveView owns a route and a
    session, and this embeds in whatever page a host already has.

        <.live_component module={Visualize.Chart.Builder} id="builder"
                         layers={@layers} sources={@sources} on_save={:design_saved} />

    The host owns the route, the layers the builder starts with, the pool of sample sources
    the preview binds to, the library of saved fragments (`Visualize.Chart.Builder.Store`)
    and what saving means. The builder owns the editing state alone — which layers are
    disabled, which is selected, what the toolbar last reported — and the one thing that
    leaves it is a message: saving sends `{on_save, id, design}` to the host LiveView
    process, where `design` is `Visualize.Chart.stack/1` of the enabled layers, the same map
    the preview drew. It pushes no event and patches no URL (D-85).

    ## Assigns

    * `id` - the component id (required)
    * `layers` - the fragments in precedence order, the higher later, exactly as
      `Visualize.Chart.stack/1` reads them: a design map, a `Visualize.Chart` or a
      `{name, layer}` pair (default `[]`)
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

        def handle_info({:design_saved, "builder", design}, socket) do
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
      Inspector,
      Layers,
      Library,
      Palette,
      Params,
      Preview,
      Store,
      Styles,
      StyleStack
    }

    alias Visualize.Chart.{Fragment, Schema}

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
        styles: true,
        class: nil
      ]
    end

    attr(:id, :string, required: true, doc: "the component id")
    attr(:layers, :list, default: [], doc: "the fragments in precedence order, the higher later")
    attr(:sources, :map, default: %{}, doc: "the pool the preview binds the design's slots to")
    attr(:vars, :map, default: %{}, doc: "the values the preview applies the variables with")
    attr(:theme, :any, default: nil, doc: "a `Visualize.Theme` for the preview")

    attr(:store, :any,
      default: nil,
      doc: "a `Visualize.Chart.Builder.Store`, or `{module, context}`"
    )

    attr(:on_save, :any, default: :visualize_chart_saved, doc: "the tag of the save message")

    attr(:styles, :boolean,
      default: true,
      doc: "render the stylesheet, `false` if the host ships it"
    )

    attr(:class, :string, default: nil, doc: "appended to the builder's root class")

    @impl true
    def mount(socket) do
      {:ok,
       assign(socket,
         disabled: MapSet.new(),
         selected: 0,
         notice: nil,
         facet: nil,
         added: nil,
         style_entry: nil,
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

    # `layers` is seeded and not controlled, because it is the assign the builder writes to:
    # adopting the host's list on every parent render would discard the edit that render was
    # caused by. A list that differs from the one the host last gave is a host deliberately
    # replacing the stack and is taken; an equal one is a host re-rendering for its own
    # reasons and leaves the editing session alone (spec/14 §18.1, D-95).
    defp seed(socket, %{layers: layers}) do
      if Map.get(socket.assigns, :host_layers, :unseeded) == layers,
        do: socket,
        else: assign(socket, layers: layers, host_layers: layers)
    end

    defp seed(socket, _assigns), do: socket

    defp default({key, value}, socket), do: assign_new(socket, key, fn -> value end)

    @impl true
    def render(assigns) do
      assigns = assign(assigns, editing(assigns))

      ~H"""
      <div id={@id} class={class("vis-builder", @class)}>
        <Styles.styles :if={@styles} />
        <div class="vis-builder-toolbar">
          <span class="vis-builder-layer-count">{length(@layers)}</span>
          <form :if={@store} class="vis-builder-keep" phx-submit="put_design" phx-target={@myself}>
            <label class="vis-builder-control-label" for={@id <> "-keep"}>Save the stack as</label>
            <input
              id={@id <> "-keep"}
              type="text"
              name="name"
              class="vis-builder-name"
              value=""
              placeholder="Category:sub-category:name"
            />
            <button type="submit" class="vis-builder-put">Save to library</button>
          </form>
          <button type="button" class="vis-builder-save" phx-click="save" phx-target={@myself}>
            Save
          </button>
        </div>
        <p :if={@notice} class="vis-builder-notice">{@notice}</p>
        <div class={class("vis-builder-panels", if(@store, do: "vis-builder-panels-library"))}>
          <Library.panel
            :if={@store}
            id={@id <> "-library"}
            entries={Store.list(@store)}
            open={@added}
            target={@myself}
          />
          <aside class="vis-builder-sidebar">
            <h2 class="vis-builder-sidebar-title">Layers</h2>
            <Layers.panel
              id={@id <> "-layers"}
              layers={@layers}
              selected={@selected}
              disabled={@disabled}
              target={@myself}
            />
          </aside>
          <main class="vis-builder-main">
            <nav class="vis-builder-nodes">
              <button
                :for={tab <- @tabs}
                type="button"
                class={tab.class}
                title={tab.title}
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
                node={@editing}
                path={@entry.path}
                facet={@facet}
                errors={@errors}
                refs={%{style: Palette.names(@design)}}
                variables={@variables}
                strip={false}
                target={@myself}
              />
              <Preview.panel design={@design} sources={@sources} vars={@bindings} theme={@theme} />
            </div>
          </main>
          <aside class="vis-builder-context">
            <h2 class="vis-builder-sidebar-title">Context</h2>
            <StyleStack.panel
              :if={@style_site}
              id={@id <> "-style-stack"}
              value={@style_site.value}
              fallback={@style_site.fallback}
              design={@design}
              open={@style_entry}
              target={@myself}
            />
            <Editor.panel
              :if={@style_site && @style_entry}
              id={@id <> "-style-editor"}
              class="vis-builder-style-panel"
              kind={:style}
              node={StyleStack.resolved(@design, @style_site.stack)}
              origins={StyleStack.origins(@design, @style_site.stack)}
              strip={false}
              event="edit_style"
              refs={%{style: Palette.names(@design)}}
              variables={@variables}
              target={@myself}
            />
            <p :if={!@style_site} class="vis-builder-context-empty">
              Open a node with a style to see its stack.
            </p>
          </aside>
        </div>
        <div class="vis-builder-tray">
          <Palette.panel design={@design} open={@open_style} target={@myself} />
          <Params.panel layers={@layers} vars={@bindings} target={@myself} />
          <Inspector.panel id={@id <> "-inspector"} layers={@layers} target={@myself} />
          <Document.panel design={@design} target={@myself} />
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

    @impl true
    def handle_event("save", _params, socket) do
      %{on_save: tag, id: id} = socket.assigns
      send(self(), {tag, id, design(socket.assigns)})
      {:noreply, assign(socket, :notice, nil)}
    end

    def handle_event("add_layer", %{"name" => submitted}, socket) do
      case fetch(socket.assigns.store, submitted) do
        {:ok, entry} -> {:noreply, added(socket, entry.name, entry.fragment)}
        :error -> {:noreply, assign(socket, :notice, "no fragment is stored under #{submitted}")}
      end
    end

    # Saving names the entry, never the body: the stack's result is stored under a fresh id
    # (spec/14 §19.7). Until #178 the body is still the stacked design; structure comes there.
    def handle_event("put_design", %{"name" => name}, socket) do
      %{store: store} = socket.assigns
      fragment = design(socket.assigns)

      entry = %{id: nil, name: name, kind: Fragment.kind(fragment), fragment: fragment}
      {:noreply, assign(socket, :notice, kept(store && Store.put(store, entry)))}
    end

    def handle_event("select_node", %{"node" => label}, socket) do
      {:noreply, assign(socket, node_label: label, facet: nil)}
    end

    # A root the selected layer declares opens there; one it does not takes the person to
    # the highest layer that declares it, which is what the inspector and the palette
    # already do (spec/14 §18.13, §18.9, §18.14).
    def handle_event("select_root", %{"root" => root}, socket) do
      %{layers: layers, selected: selected} = socket.assigns

      case first_under(Enum.at(layers, selected), root) do
        nil ->
          case Enum.find(Enum.reverse(Enum.with_index(layers)), fn {layer, _index} ->
                 first_under(layer, root)
               end) do
            nil ->
              {:noreply, socket}

            {layer, index} ->
              {:noreply, socket |> select(index) |> opened(first_under(layer, root))}
          end

        label ->
          {:noreply, assign(socket, node_label: label, facet: nil)}
      end
    end

    def handle_event("select_layer", %{"index" => index}, socket) do
      {:noreply, select(socket, position(index))}
    end

    def handle_event("toggle_layer", %{"index" => index}, socket) do
      {:noreply, update(socket, :disabled, &toggle(&1, position(index)))}
    end

    def handle_event("reorder", %{"scope" => "style", "from" => from, "to" => to}, socket) do
      {:noreply, restacked(socket, &shift(&1, position(from), position(to)))}
    end

    def handle_event("reorder", %{"from" => from, "to" => to}, socket) do
      {:noreply, moved(socket, position(from), position(to))}
    end

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

    # Every edit at a site lands in its local style, never in a named entry: editing a mark
    # that references `:series` must not restyle every other mark that references the same
    # name (spec/14 §18.19, D-98). The local entry is created when there is none.
    def handle_event("edit_style", params, socket) do
      {:noreply, styled(socket, Editor.change(:style, params))}
    end

    # A style fragment dropped on a site's stack is the answer to "which style did you
    # mean": the drop said where it goes, so no name has to be bound (spec/14 §18.20).
    def handle_event("insert", %{"scope" => "style", "name" => submitted, "at" => at}, socket) do
      with {:ok, entry} <- fetch(socket.assigns.store, submitted),
           [style] <- declared_styles(entry.fragment) do
        {:noreply, dropped(socket, entry.name, entry.fragment, style, position(at))}
      else
        :error -> {:noreply, assign(socket, :notice, "no fragment is stored under #{submitted}")}
        [] -> {:noreply, assign(socket, :notice, "#{named(socket, submitted)} declares no style")}
        many -> {:noreply, assign(socket, :notice, refusal(named(socket, submitted), many))}
      end
    end

    # A fragment dragged out of the library lands at the position it was dropped at, so
    # precedence is chosen in the gesture rather than fixed afterwards (spec/14 §18.17).
    def handle_event("insert", %{"name" => submitted, "at" => at}, socket) do
      case fetch(socket.assigns.store, submitted) do
        {:ok, entry} ->
          {:noreply, inserted(socket, entry.name, entry.fragment, position(at))}

        :error ->
          {:noreply, assign(socket, :notice, "no fragment is stored under #{submitted}")}
      end
    end

    def handle_event("inspect", %{"path" => path, "layer" => layer}, socket) do
      {:noreply, socket |> select(position(layer)) |> opened(path)}
    end

    def handle_event("set_var", %{"_target" => [name]} = params, socket) do
      free = Enum.find(Chart.free_vars(socket.assigns.layers), &(to_string(&1.name) == name))
      {:noreply, bound(socket, free, params[name])}
    end

    def handle_event("import", %{"document" => document}, socket) do
      case Chart.from_json(document) do
        {:ok, chart} -> {:noreply, imported(socket, Chart.to_map(chart))}
        {:error, reason} -> {:noreply, assign(socket, :notice, notice(reason))}
      end
    end

    # A style is created in the selected layer, because that is where every edit goes, and
    # the editor opens on it: creating a style and not being taken to it would be half a
    # gesture (spec/14 §18.14).
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

    # The palette is a view of the stack, so the style a person picks may be declared by a
    # layer other than the selected one; the highest that declares it is the one that owns
    # the value, which is the same rule the inspector follows (§18.9).
    def handle_event("select_style", %{"name" => submitted}, socket) do
      path = "styles." <> submitted

      case declaring(socket.assigns.layers, submitted) do
        nil -> {:noreply, socket}
        index -> {:noreply, socket |> select(index) |> opened(path)}
      end
    end

    def handle_event("facet", %{"facet" => facet}, socket) do
      %{entry: entry} = editing(socket.assigns)
      facets = Enum.map(Schema.describe(entry.kind), & &1.facet)
      {:noreply, assign(socket, :facet, Enum.find(facets, &(to_string(&1) == facet)))}
    end

    def handle_event("edit", params, socket) do
      %{entry: entry} = editing(socket.assigns)
      {:noreply, edited(socket, entry, Editor.change(entry.kind, params))}
    end

    # A position arrives as a string from a `phx-value-index` and as a number from the hook.
    defp position(index) when is_integer(index), do: index

    defp position(index) when is_binary(index) do
      case Integer.parse(index) do
        {value, ""} -> value
        _other -> -1
      end
    end

    defp position(_index), do: -1

    defp select(socket, index) do
      if index in positions(socket),
        do: assign(socket, selected: index, node_label: "design", facet: nil),
        else: socket
    end

    defp toggle(disabled, index) do
      if index in disabled, do: MapSet.delete(disabled, index), else: MapSet.put(disabled, index)
    end

    defp positions(socket), do: 0..(length(socket.assigns.layers) - 1)//1

    # A move is list surgery, and the selection and the disabled set follow their layers:
    # both are positions, and every position after the move is a different layer.
    defp moved(socket, from, to) do
      if from != to and from in positions(socket) and to in positions(socket) do
        order = socket |> positions() |> Enum.to_list() |> shift(from, to)
        moved = Map.new(Enum.with_index(order))

        socket
        |> assign(:layers, Enum.map(order, &Enum.at(socket.assigns.layers, &1)))
        |> assign(:selected, Map.get(moved, socket.assigns.selected, socket.assigns.selected))
        |> assign(:disabled, MapSet.new(socket.assigns.disabled, &Map.get(moved, &1, &1)))
      else
        socket
      end
    end

    defp shift(list, from, to) do
      {value, rest} = List.pop_at(list, from)
      List.insert_at(rest, to, value)
    end

    # The node of the selected layer that owns a path: the deepest whose label is a prefix
    # of it, and the layer's root where none is (spec/14 §18.9).
    defp opened(socket, path) do
      layer = fragment(Enum.at(socket.assigns.layers, socket.assigns.selected) || %{})

      label =
        layer
        |> Editor.nodes()
        |> Enum.filter(&owns?(&1.label, path))
        |> Enum.max_by(&String.length(&1.label), fn -> %{label: "design"} end)
        |> Map.fetch!(:label)

      assign(socket, node_label: label, facet: nil)
    end

    defp owns?("design", _path), do: false

    defp owns?(label, path) do
      path == label or String.starts_with?(path, label <> ".") or
        String.starts_with?(path, label <> "[")
    end

    defp edited(socket, _entry, nil), do: socket
    defp edited(socket, entry, {key, parsed}), do: update_layer(socket, entry.path, key, parsed)

    defp update_layer(socket, path, key, parsed) do
      %{layers: layers, selected: selected} = socket.assigns

      assign(socket, :layers, List.update_at(layers, selected, &write(&1, path, key, parsed)))
    end

    # A layer keeps its name; a chart layer becomes the map it is, which is the same design.
    defp write({name, layer}, path, key, parsed), do: {name, write(layer, path, key, parsed)}

    defp write(%Chart{} = chart, path, key, parsed),
      do: write(Chart.to_map(chart), path, key, parsed)

    defp write(fragment, path, key, {:ok, value}),
      do: update_node(fragment, path, &Map.put(&1, key, value))

    defp write(fragment, path, key, :error),
      do: update_node(fragment, path, &Map.delete(&1, key))

    defp update_node(nil, [], fun), do: fun.(%{})
    defp update_node(container, [], fun), do: fun.(container)

    # A fragment need not already carry the key a node is being added under: `styles` is
    # absent until the first style is declared, and adding one is adding the key (§18.5).
    defp update_node(nil, [key | _rest] = path, fun) when is_atom(key),
      do: update_node(%{}, path, fun)

    defp update_node(list, [index | rest], fun) when is_list(list) and is_integer(index),
      do: List.update_at(list, index, &update_node(&1, rest, fun))

    defp update_node(map, [key | rest], fun) when is_map(map),
      do: Map.put(map, key, update_node(Map.get(map, key), rest, fun))

    # What the editor is looking at: the selected layer, its nodes, the open one and its
    # value, the stacked design and the faults application reports of it (spec/14 §18.7).
    defp editing(assigns) do
      layer = fragment(Enum.at(assigns.layers, assigns.selected) || %{})
      nodes = Editor.nodes(layer)
      entry = Enum.find(nodes, &(&1.label == assigns.node_label)) || hd(nodes)
      design = design(assigns)

      {tabs, children} = strip(nodes, entry, design)

      %{
        design: design,
        nodes: nodes,
        entry: entry,
        tabs: tabs,
        chips: chips(children, entry, assigns.facet),
        style_site: style_site(entry, at(layer, entry.path)),
        open_style: open_style(entry),
        variables: variables(assigns.layers, design),
        editing: at(layer, entry.path),
        errors: faults(design, assigns)
      }
    end

    # A fragment is a tree and its labels say so — `frame`, `frame.size`, `frame.margin` —
    # so the strip is two rows rather than one long line of dotted paths (spec/14 §18.13).
    # The top row is one tab per root segment, in the order the walk reached it; the second
    # is the nodes under whichever root the open node sits in, labelled by what they add to
    # it. A root that is not itself a node — `styles`, which exists only as the map its
    # members live in — opens its first member instead.
    defp strip(nodes, entry, design) do
      open_root = root(entry.label)
      here = nodes |> Enum.map(&root(&1.label)) |> Enum.uniq()

      # Every root the *stacked design* declares, in the schema's order, so the whole
      # vocabulary of the chart is on screen whatever layer is selected (spec/14 §18.13).
      tabs =
        for root <- roots(design, here) do
          %{
            label: root,
            open: root == open_root,
            elsewhere: root not in here,
            class: tab_class(root == open_root, root in here),
            title: tab_title(root, root in here)
          }
        end

      children =
        for node <- nodes, root(node.label) == open_root, node.label != open_root do
          %{label: leaf(node.label, open_root), node: node.label, open: node.label == entry.label}
        end

      {tabs, children}
    end

    # The design's roots in the schema's order, with any the selected layer has and the
    # design somehow does not — a layer the host gave that the stack drops — kept at the end
    # rather than made unreachable.
    defp roots(design, here) do
      declared = design |> Editor.nodes() |> Enum.map(&root(&1.label)) |> Enum.uniq()
      declared ++ Enum.reject(here, &(&1 in declared))
    end

    defp tab_class(open?, here?) do
      ["vis-builder-node"]
      |> then(&if open?, do: &1 ++ ["vis-builder-node-open"], else: &1)
      |> then(&if here?, do: &1, else: &1 ++ ["vis-builder-node-elsewhere"])
      |> Enum.join(" ")
    end

    defp tab_title(root, true), do: "#{root} of this layer"

    defp tab_title(root, false),
      do: "#{root} — this layer declares none; opens the layer that does"

    # The second row is one strip of one kind of control: the children of the open root, then
    # the facets of the open node, which are two things to choose between and were two rows
    # that looked and behaved differently. A node with one facet and no children has nothing
    # to choose, so no strip is rendered rather than a lone chip that appears to do nothing
    # (spec/14 §18.15).
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
            class: chip(child.open, nil)
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

    # A node whose kind declares a `style` key is a style site (spec/14 §3.6), and the panel
    # needs the value it carries and the default it resolves as when it carries none.
    defp style_site(entry, node) do
      case Schema.key(entry.kind, :style) do
        nil ->
          nil

        %{default: fallback} ->
          value = is_map(node) && Map.get(node, :style)
          %{value: value, fallback: fallback, stack: current_stack(value || nil, fallback)}
      end
    end

    # The names a variable may take here: those the stack declares under `vars`, and those
    # any layer already uses, so the datalist offers what exists before a new one is typed.
    defp variables(layers, design) do
      declared = design |> Map.get(:vars, %{}) |> Map.keys()
      used = layers |> Chart.free_vars() |> Enum.map(& &1.name)
      (declared ++ used) |> Enum.uniq() |> Enum.sort() |> Enum.map(&to_string/1)
    end

    defp open_style(%{path: [:styles, name]}), do: name
    defp open_style(_entry), do: nil

    defp styled(socket, nil), do: socket
    defp styled(socket, {key, parsed}), do: restacked(socket, &local(&1, key, parsed))

    # The local entry is the last one when it is inline, and a new one otherwise.
    defp local(stack, key, parsed) do
      case List.last(stack) do
        node when is_map(node) -> List.replace_at(stack, -1, write_key(node, key, parsed))
        _none -> stack ++ [write_key(%{}, key, parsed)]
      end
    end

    defp write_key(node, key, {:ok, value}), do: Map.put(node, key, value)
    defp write_key(node, key, :error), do: Map.delete(node, key)

    # A change to the open node's stack, written back in whatever shape it came in: a stack
    # of one that names a style stays a bare reference, so an edit elsewhere does not rewrite
    # a document's shape (spec/14 §3.6).
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

    # The stack a value stands for: a site carrying nothing stands for its default, so
    # adding to it keeps what it already resolved as rather than silently dropping it.
    defp current_stack(nil, nil), do: []
    defp current_stack(nil, fallback), do: [fallback]
    defp current_stack(value, _fallback) when is_list(value), do: value
    defp current_stack(value, _fallback), do: [value]

    defp shaped(stack) do
      case Enum.reject(stack, &(is_map(&1) and map_size(&1) == 0)) do
        [only] when not is_map(only) -> only
        pruned -> pruned
      end
    end

    # The first segment of a label: `frame.scales.x` is under `frame`, `marks[0]` under
    # `marks`, and `design` is its own root.
    defp root(label), do: label |> String.split(~r/[.\[]/, parts: 2) |> hd()

    defp leaf(label, root) do
      label |> String.replace_prefix(root, "") |> String.replace_prefix(".", "")
    end

    defp fragment({_name, layer}), do: fragment(layer)
    defp fragment(%Chart{} = chart), do: Chart.to_map(chart)
    defp fragment(layer) when is_map(layer), do: layer

    defp at(container, []), do: container

    defp at(list, [index | rest]) when is_list(list) and is_integer(index),
      do: at(Enum.at(list, index), rest)

    defp at(map, [key | rest]) when is_map(map), do: at(Map.get(map, key), rest)

    # A variable takes the type of its first use, as its control was chosen from it
    # (spec/14 §18.11); a blank control removes the binding and the default returns.
    defp bound(socket, nil, _value), do: socket

    defp bound(socket, free, value) do
      type = Params.expects(free)

      case Editor.submitted(type, value) do
        {:ok, parsed} -> update(socket, :bindings, &Map.put(&1, free.name, parsed))
        :error -> update(socket, :bindings, &Map.delete(&1, free.name))
      end
    end

    # A document is a whole design, so it replaces the stack rather than joining it (D-88).
    defp imported(socket, design) do
      assign(socket,
        layers: [{:imported, design}],
        selected: 0,
        disabled: MapSet.new(),
        bindings: %{},
        node_label: "design",
        facet: nil,
        notice: nil
      )
    end

    # The label of the first node of a layer under a root, or `nil`.
    defp first_under(nil, _root), do: nil

    defp first_under(layer, root) do
      layer
      |> fragment()
      |> Editor.nodes()
      |> Enum.find(&(root(&1.label) == root))
      |> case do
        nil -> nil
        node -> node.label
      end
    end

    # The style names a fragment declares, in name order.
    defp declared_styles(fragment) do
      case Map.get(fragment, :styles) do
        map when is_map(map) -> map |> Map.keys() |> Enum.sort()
        _absent -> []
      end
    end

    defp refusal(submitted, many) do
      "#{submitted} declares #{length(many)} styles — #{Enum.map_join(many, ", ", &to_string/1)}" <>
        " — so which one this site means is the question the drop was meant to answer"
    end

    # The two writes of one gesture: the fragment joins the stack as a layer, so the style
    # stays declared once and reusable, and a reference to it goes into the site's stack at
    # the position it was dropped at (spec/14 §18.20).
    defp dropped(socket, name, fragment, style, at) do
      socket
      |> assign(:layers, socket.assigns.layers ++ [{name, fragment}])
      |> assign(:added, to_string(name))
      |> restacked(fn stack -> List.insert_at(stack, clamp(at, stack), style) end)
      |> assign(:notice, nil)
    end

    defp clamp(at, stack), do: at |> max(0) |> min(length(stack))

    # The highest layer whose fragment declares a style of that name, or `nil`.
    defp declaring(layers, name) do
      layers
      |> Enum.with_index()
      |> Enum.filter(fn {layer, _index} ->
        layer
        |> fragment()
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

    defp faults(design, %{sources: sources, bindings: vars, theme: theme}) do
      case Chart.apply(design, sources: sources, vars: vars, theme: theme) do
        {:ok, _applied} -> []
        {:error, errors} -> errors
      end
    end

    # The selection and the disabled set are positions, so both follow an insert below them.
    defp inserted(socket, name, fragment, at) do
      %{layers: layers, selected: selected, disabled: disabled} = socket.assigns
      at = at |> max(0) |> min(length(layers))

      socket
      |> assign(:layers, List.insert_at(layers, at, {name, fragment}))
      |> assign(:selected, if(selected >= at, do: selected + 1, else: selected))
      |> assign(:disabled, MapSet.new(disabled, &if(&1 >= at, do: &1 + 1, else: &1)))
      |> assign(:added, to_string(name))
      |> assign(:notice, nil)
    end

    defp added(socket, name, fragment) do
      socket
      |> assign(:layers, socket.assigns.layers ++ [{name, fragment}])
      |> assign(:added, to_string(name))
      |> assign(:notice, nil)
    end

    defp kept({:ok, _id}), do: nil
    defp kept({:error, reason}), do: "the store refused the design: #{inspect(reason)}"
    defp kept(nil), do: "no store is configured"

    # The name a notice calls an entry by: the entry's own, or the id string when the
    # store no longer holds it.
    defp named(socket, submitted) do
      case fetch(socket.assigns.store, submitted) do
        {:ok, entry} -> entry.name
        :error -> submitted
      end
    end

    # An entry by the id a client sent as a string; no store means no entry, as does a
    # string that is not an id, so no atom is created from a client's string.
    defp fetch(nil, _submitted), do: :error

    defp fetch(store, submitted) do
      case Store.decode_id(submitted) do
        {:ok, id} -> Store.get(store, id)
        :error -> :error
      end
    end

    # A `nil` class assign leaves the element's own class alone, with no trailing space.
    defp class(base, nil), do: base
    defp class(base, extra), do: base <> " " <> extra

    # The design the preview draws and saving sends: the enabled layers cascaded (§8.2).
    defp design(%{layers: layers, disabled: disabled}) do
      layers
      |> Enum.with_index()
      |> Enum.reject(fn {_layer, index} -> index in disabled end)
      |> Enum.map(fn {layer, _index} -> layer end)
      |> Chart.stack()
    end
  end
end
