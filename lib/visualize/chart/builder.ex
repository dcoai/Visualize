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
    * `store` - a module implementing `Visualize.Chart.Builder.Store`, or `nil` for no
      library (default `nil`)
    * `on_save` - the tag of the message saving sends (default `:visualize_chart_saved`)
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
    alias Visualize.Chart.Builder.{Editor, Preview}
    alias Visualize.Chart.Schema

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
        class: nil
      ]
    end

    attr(:id, :string, required: true, doc: "the component id")
    attr(:layers, :list, default: [], doc: "the fragments in precedence order, the higher later")
    attr(:sources, :map, default: %{}, doc: "the pool the preview binds the design's slots to")
    attr(:vars, :map, default: %{}, doc: "the values the preview applies the variables with")
    attr(:theme, :any, default: nil, doc: "a `Visualize.Theme` for the preview")
    attr(:store, :atom, default: nil, doc: "a `Visualize.Chart.Builder.Store` implementation")
    attr(:on_save, :any, default: :visualize_chart_saved, doc: "the tag of the save message")
    attr(:class, :string, default: nil, doc: "appended to the builder's root class")

    @impl true
    def mount(socket) do
      {:ok,
       assign(socket,
         disabled: MapSet.new(),
         selected: 0,
         notice: nil,
         facet: nil,
         node_label: "design"
       )}
    end

    @impl true
    def update(assigns, socket) do
      {:ok, Enum.reduce(defaults(), assign(socket, assigns), &default/2)}
    end

    defp default({key, value}, socket), do: assign_new(socket, key, fn -> value end)

    @impl true
    def render(assigns) do
      assigns = assign(assigns, editing(assigns))

      ~H"""
      <div id={@id} class={class("vis-builder", @class)}>
        <div class="vis-builder-toolbar">
          <span class="vis-builder-layer-count">{length(@layers)}</span>
          <form :if={@store} class="vis-builder-library" phx-submit="add_layer" phx-target={@myself}>
            <select name="name" class="vis-builder-store">
              <option :for={name <- stored(@store)} value={name}>{name}</option>
            </select>
            <button type="submit" class="vis-builder-add">Add layer</button>
          </form>
          <form :if={@store} class="vis-builder-keep" phx-submit="put_design" phx-target={@myself}>
            <input type="text" name="name" class="vis-builder-name" value="" />
            <button type="submit" class="vis-builder-put">Save to library</button>
          </form>
          <button type="button" class="vis-builder-save" phx-click="save" phx-target={@myself}>
            Save
          </button>
        </div>
        <p :if={@notice} class="vis-builder-notice">{@notice}</p>
        <div class="vis-builder-panels">
          <nav class="vis-builder-nodes">
            <button
              :for={entry <- @nodes}
              type="button"
              class={class("vis-builder-node", open(entry, @entry))}
              phx-click="select_node"
              phx-value-node={entry.label}
              phx-target={@myself}
            >{entry.label}</button>
          </nav>
          <Editor.panel
            kind={@entry.kind}
            node={@editing}
            path={@entry.path}
            facet={@facet}
            errors={@errors}
            target={@myself}
          />
          <Preview.panel design={@design} sources={@sources} vars={@vars} theme={@theme} />
        </div>
      </div>
      """
    end

    @impl true
    def handle_event("save", _params, socket) do
      %{on_save: tag, id: id} = socket.assigns
      send(self(), {tag, id, design(socket.assigns)})
      {:noreply, assign(socket, :notice, nil)}
    end

    def handle_event("add_layer", %{"name" => submitted}, socket) do
      %{store: store} = socket.assigns

      case store && Enum.find(store.list(), &(to_string(&1) == submitted)) do
        nil ->
          {:noreply, assign(socket, :notice, "no fragment is stored under #{submitted}")}

        name ->
          {:noreply, added(socket, name, store.get(name))}
      end
    end

    def handle_event("put_design", %{"name" => name}, socket) do
      %{store: store} = socket.assigns
      {:noreply, assign(socket, :notice, kept(store && store.put(name, design(socket.assigns))))}
    end

    def handle_event("select_node", %{"node" => label}, socket) do
      {:noreply, assign(socket, node_label: label, facet: nil)}
    end

    def handle_event("facet", %{"facet" => facet}, socket) do
      %{entry: entry} = editing(socket.assigns)
      facets = Enum.map(Schema.describe(entry.kind), & &1.facet)
      {:noreply, assign(socket, :facet, Enum.find(facets, &(to_string(&1) == facet)))}
    end

    def handle_event("edit", %{"_target" => [submitted]} = params, socket) do
      %{entry: entry} = editing(socket.assigns)
      {:noreply, edited(socket, entry, spec(entry.kind, submitted), params)}
    end

    # A key the node kind does not carry changes nothing: a submitted name is a string, and
    # only a key the schema already declares is looked up by it — no atom is created here.
    defp spec(kind, submitted) do
      Enum.find(Schema.describe(kind), &(to_string(&1.key) == submitted))
    end

    defp edited(socket, _entry, nil, _params), do: socket

    defp edited(socket, entry, spec, params) do
      value = params[to_string(spec.key)]
      update_layer(socket, entry.path, spec.key, read(Editor.widget(spec.type), spec.type, value))
    end

    # An unchecked checkbox submits nothing, which is `false` and not a removal; every other
    # control's blank string removes the key (spec/14 §18.6).
    defp read(:checkbox, _type, nil), do: {:ok, false}
    defp read(_widget, _type, nil), do: :error
    defp read(_widget, type, string), do: Editor.parse(type, string)

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

    defp update_node(container, [], fun), do: fun.(container)

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

      %{
        design: design,
        nodes: nodes,
        entry: entry,
        editing: at(layer, entry.path),
        errors: faults(design, assigns)
      }
    end

    defp fragment({_name, layer}), do: fragment(layer)
    defp fragment(%Chart{} = chart), do: Chart.to_map(chart)
    defp fragment(layer) when is_map(layer), do: layer

    defp at(container, []), do: container

    defp at(list, [index | rest]) when is_list(list) and is_integer(index),
      do: at(Enum.at(list, index), rest)

    defp at(map, [key | rest]) when is_map(map), do: at(Map.get(map, key), rest)

    defp faults(design, %{sources: sources, vars: vars, theme: theme}) do
      case Chart.apply(design, sources: sources, vars: vars, theme: theme) do
        {:ok, _applied} -> []
        {:error, errors} -> errors
      end
    end

    defp open(entry, entry), do: "vis-builder-node-open"
    defp open(_entry, _open), do: nil

    defp added(socket, name, {:ok, fragment}) do
      socket
      |> assign(:layers, socket.assigns.layers ++ [{name, fragment}])
      |> assign(:notice, nil)
    end

    defp added(socket, name, :error),
      do: assign(socket, :notice, "no fragment is stored under #{name}")

    defp kept(:ok), do: nil
    defp kept({:error, reason}), do: "the store refused the design: #{inspect(reason)}"
    defp kept(nil), do: "no store is configured"

    defp stored(store), do: Enum.map(store.list(), &to_string/1)

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
