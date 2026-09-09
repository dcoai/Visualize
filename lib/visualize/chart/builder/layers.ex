if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Layers do
    @moduledoc """
    The builder's stack panel: the layers in precedence order (spec/14 §18.8).

    The layers are listed in the order `Visualize.Chart.stack/1` reads them — the higher
    layer last — because that is the order the cascade is defined in, and a panel that
    reversed it would teach the opposite of the specification. Each layer offers three
    things: select it, disable it, and drag it into place through `Visualize.Hooks.Builder`.

    **The row is the control.** Clicking anywhere on it selects the layer and dragging it
    reorders it, because a row that can only be selected through a 22px icon reads as a row
    that cannot be selected at all. The one button left is the toggle, and it says
    `draggable="false"`: a control inside a draggable row is itself a drag source unless it
    says otherwise, and a mousedown that moves a pixel becomes a drag whose click never
    fires.

    Disabling is not deleting: a disabled layer stays in the list and is dropped from the
    stack, so "what does this look like without the house theme" is one click and one click
    back (D-87).

    Moving is dragging and nothing else. The panel carried up and down buttons beside every
    layer, which is two more controls per row to say what one gesture already says, and a
    stack of any depth is not reordered a step at a time. `Visualize.Hooks.Builder` is the
    one way a layer moves (§18.10, §18.17).

    This module compiles only when `Phoenix.Component` is loaded (spec/10 §1.1, D-45, D-85).
    """

    use Phoenix.Component

    attr(:id, :string, required: true, doc: "the hook element's id")
    attr(:layers, :list, required: true, doc: "the layers in precedence order, the higher last")
    attr(:selected, :integer, default: 0, doc: "the position of the layer being edited")
    attr(:disabled, :any, default: nil, doc: "the positions dropped from the stack, a `MapSet`")
    attr(:target, :any, default: nil, doc: "the `phx-target` of the panel's events")
    attr(:class, :string, default: nil, doc: "appended to the panel's class")

    @doc """
    Renders the stack panel (spec/10 §15.3).

    An `<ol class="vis-builder-layers">` carrying `BuilderHook`, with one
    `<li class="vis-builder-layer">` per layer at its zero-based position.
    """
    def panel(assigns) do
      assigns = assign(assigns, :entries, entries(assigns))

      ~H"""
      <ol
        id={@id}
        class={class(@class)}
        phx-hook="BuilderHook"
        data-builder-target={@target}
        data-builder-stack="true"
      >
        <li
          :for={entry <- @entries}
          class={entry.class}
          data-builder-layer={entry.index}
          draggable="true"
          title={"Click to edit " <> entry.name <> ", drag to reorder it"}
          phx-click="select_layer"
          phx-value-index={entry.index}
          phx-target={@target}
        >
          <span class="vis-builder-layer-name">{entry.name}</span>
          <button
            type="button"
            draggable="false"
            class="vis-builder-layer-toggle"
            title={entry.toggle <> " " <> entry.name}
            aria-label={entry.toggle <> " " <> entry.name}
            phx-click="toggle_layer"
            phx-value-index={entry.index}
            phx-target={@target}
          ><span class="vis-builder-action-label">{entry.toggle}</span></button>
        </li>
      </ol>
      """
    end

    defp class(nil), do: "vis-builder-layers"
    defp class(extra), do: "vis-builder-layers " <> extra

    # One entry per layer: its name as `Visualize.Chart.explain/1` names it, its classes and
    # what its toggle now offers.
    defp entries(%{layers: layers, selected: selected, disabled: disabled}) do
      off = disabled || MapSet.new()

      for {layer, index} <- Enum.with_index(layers) do
        %{
          index: index,
          name: name(layer, index),
          class: classes(index == selected, index in off),
          toggle: if(index in off, do: "Enable", else: "Disable")
        }
      end
    end

    defp name({name, _layer}, _index), do: to_string(name)
    defp name(_layer, index), do: to_string(index)

    defp classes(selected?, disabled?) do
      ["vis-builder-layer"]
      |> then(&if selected?, do: &1 ++ ["vis-builder-layer-selected"], else: &1)
      |> then(&if disabled?, do: &1 ++ ["vis-builder-layer-disabled"], else: &1)
      |> Enum.join(" ")
    end
  end
end
