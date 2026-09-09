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
    alias Visualize.Chart.Builder.Preview

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
      {:ok, assign(socket, disabled: MapSet.new(), selected: 0, notice: nil)}
    end

    @impl true
    def update(assigns, socket) do
      {:ok, Enum.reduce(defaults(), assign(socket, assigns), &default/2)}
    end

    defp default({key, value}, socket), do: assign_new(socket, key, fn -> value end)

    @impl true
    def render(assigns) do
      assigns = assign(assigns, :design, design(assigns))

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
        <Preview.panel design={@design} sources={@sources} vars={@vars} theme={@theme} />
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
