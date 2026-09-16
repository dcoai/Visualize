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

    alias Visualize.Chart.Builder.{Editor, Glyphs}

    attr(:id, :string, required: true, doc: "the hook element's id")
    attr(:layers, :list, required: true, doc: "the layers in precedence order, the higher last")
    attr(:selected, :integer, default: 0, doc: "the position of the layer being edited")
    attr(:disabled, :any, default: nil, doc: "the positions dropped from the stack, a `MapSet`")

    attr(:locked, :any,
      default: nil,
      doc: "the positions whose site references a library entry, a `MapSet` (spec/14 §18.8)"
    )

    attr(:expanded, :any,
      default: nil,
      doc: "the positions whose rows are open on what the layer declares, a `MapSet` (§18.8)"
    )

    attr(:placed, :list,
      default: [],
      doc: "each layer placed where the design keeps its kind, by position, for `declared/1`"
    )

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
          id={@id <> "-row-" <> to_string(entry.index)}
          class={entry.class}
          data-builder-layer={entry.index}
          draggable="true"
          role="button"
          tabindex="0"
          title={entry.says}
          aria-label={entry.says}
          phx-click="select_layer"
          phx-keydown="layer_key"
          phx-value-index={entry.index}
          phx-target={@target}
        >
          <button
            type="button"
            draggable="false"
            class="vis-builder-layer-expand"
            title={(entry.expanded? && "hide what " <> entry.name <> " declares") || "show what " <> entry.name <> " declares"}
            aria-label={(entry.expanded? && "hide what " <> entry.name <> " declares") || "show what " <> entry.name <> " declares"}
            aria-expanded={to_string(entry.expanded?)}
            phx-click="toggle_layer_detail"
            phx-value-index={entry.index}
            phx-target={@target}
          >{if entry.expanded?, do: "⌄", else: "›"}</button>
          <span class="vis-builder-layer-name">{entry.name}</span>
          <button
            :if={entry.locked?}
            type="button"
            draggable="false"
            class="vis-builder-layer-lock"
            title={"Open " <> entry.name <> " — from the library, edited by opening it"}
            aria-label={"Open " <> entry.name}
            phx-click="open_layer"
            phx-value-index={entry.index}
            phx-target={@target}
          >{Phoenix.HTML.raw(Glyphs.icon(:lock))}</button>
          <button
            type="button"
            draggable="false"
            class="vis-builder-layer-toggle"
            title={entry.toggle <> " " <> entry.name}
            aria-label={entry.toggle <> " " <> entry.name}
            phx-click="toggle_layer"
            phx-value-index={entry.index}
            phx-target={@target}
          >{Phoenix.HTML.raw(Glyphs.icon(entry.eye))}<span class="vis-builder-action-label">{entry.toggle}</span></button>
          <dl :if={entry.expanded? and entry.declared != []} class="vis-builder-layer-detail">
            <%= for {root, members} <- entry.declared do %>
              <dt class="vis-builder-declared-root">{root}</dt>
              <dd class="vis-builder-declared-members">
                <button
                  :for={{name, path} <- members}
                  type="button"
                  draggable="false"
                  class="vis-builder-declared"
                  title={"open " <> name <> " in " <> entry.name}
                  phx-click="open_declared"
                  phx-value-index={entry.index}
                  phx-value-path={Editor.label(path)}
                  phx-target={@target}
                >{name}</button>
              </dd>
            <% end %>
          </dl>
          <p :if={entry.expanded? and entry.declared == []} class="vis-builder-layer-detail vis-builder-declared-none">
            declares nothing yet
          </p>
        </li>
      </ol>
      """
    end

    @roots [
      :meta,
      :theme,
      :sources,
      :vars,
      :styles,
      :defs,
      :frame,
      :scales,
      :axes,
      :marks,
      :labels
    ]
    @frame_parts [:size, :margin, :legend, :projection, :facet, :viewport]

    @doc """
    What a placed fragment declares (spec/14 §18.8): `[{root, [{name, path}]}]` in the
    schema's order — `meta`, `theme`, `sources`, `vars`, `styles`, `defs`, `frame` (its
    parts), `scales`, `axes`, `marks`, `labels` — only the roots it declares, each member
    named as the strip names it: a keyed node by its key, an axis by `scale · side`, a mark
    by its `id` or its `type`, a label by its anchor.

        iex> Visualize.Chart.Builder.Layers.declared(%{styles: %{series: %{stroke: :red}}, frame: %{size: %{width: 1}, scales: %{x: %{kind: :linear}}, axes: [%{scale: :x, side: :bottom}]}})
        [styles: [{"series", [:styles, :series]}], frame: [{"size", [:frame, :size]}], scales: [{"x", [:frame, :scales, :x]}], axes: [{"x · bottom", [:frame, :axes, 0]}]]
        iex> Visualize.Chart.Builder.Layers.declared(%{})
        []
    """
    @spec declared(map()) :: [{atom(), [{String.t(), [atom() | non_neg_integer()]}]}]
    def declared(fragment) when is_map(fragment) do
      frame = node_or_empty(Map.get(fragment, :frame))

      for root <- @roots,
          members = members(root, fragment, frame),
          members != [],
          do: {root, members}
    end

    defp members(:meta, fragment, _frame) do
      case Map.get(fragment, :meta) do
        %{} = meta when map_size(meta) > 0 -> [{Map.get(meta, :name) || "meta", [:meta]}]
        _none -> []
      end
    end

    defp members(:theme, fragment, _frame) do
      case Map.get(fragment, :theme) do
        nil -> []
        name when is_atom(name) -> [{to_string(name), [:theme]}]
        _node -> [{"theme", [:theme]}]
      end
    end

    defp members(root, fragment, _frame) when root in [:sources, :vars, :styles, :defs],
      do: keyed(Map.get(fragment, root), [root])

    defp members(:frame, _fragment, frame) do
      for part <- @frame_parts,
          is_map(Map.get(frame, part)),
          do: {to_string(part), [:frame, part]}
    end

    defp members(:scales, _fragment, frame), do: keyed(Map.get(frame, :scales), [:frame, :scales])

    defp members(:axes, _fragment, frame) do
      listed(Map.get(frame, :axes), [:frame, :axes], fn axis ->
        "#{Map.get(axis, :scale, "?")} · #{Map.get(axis, :side, "?")}"
      end)
    end

    defp members(:marks, fragment, _frame) do
      listed(Map.get(fragment, :marks), [:marks], fn mark ->
        to_string(Map.get(mark, :id) || Map.get(mark, :type) || "mark")
      end)
    end

    defp members(:labels, fragment, _frame) do
      listed(Map.get(fragment, :labels), [:labels], fn label ->
        case Map.get(label, :anchor) do
          nil -> "label"
          {kind, at} -> "#{kind} #{at}"
          anchor -> to_string(anchor)
        end
      end)
    end

    defp keyed(map, path) when is_map(map),
      do: for({key, _node} <- Enum.sort(map), do: {to_string(key), path ++ [key]})

    defp keyed(_other, _path), do: []

    defp listed(list, path, name) when is_list(list) do
      list
      |> Enum.with_index()
      |> Enum.map(fn {node, i} -> {if(is_map(node), do: name.(node), else: "?"), path ++ [i]} end)
    end

    defp listed(_other, _path, _name), do: []

    defp node_or_empty(node) when is_map(node) and not is_struct(node), do: node
    defp node_or_empty(_other), do: %{}

    defp class(nil), do: "vis-builder-layers"
    defp class(extra), do: "vis-builder-layers " <> extra

    # One entry per layer: its name as `Visualize.Chart.explain/1` names it, its classes and
    # what its toggle now offers.
    defp entries(%{layers: layers, selected: selected, disabled: disabled} = assigns) do
      off = disabled || MapSet.new()
      held = assigns.locked || MapSet.new()
      open = assigns.expanded || MapSet.new()
      placed = assigns.placed || []

      count = length(layers)

      for {layer, index} <- Enum.with_index(layers) do
        name = name(layer, index)

        %{
          index: index,
          name: name,
          class: classes(index == selected, index in off, index in held),
          toggle: if(index in off, do: "Enable", else: "Disable"),
          eye: if(index in off, do: :eye_off, else: :eye),
          locked?: index in held,
          expanded?: index in open,
          declared: if(index in open, do: declared(Enum.at(placed, index) || %{}), else: []),
          says: says(name, index, count, index == selected, index in off, index in held)
        }
      end
    end

    # What the row is and what its keys do, for hover and for what is announced (§18.17);
    # a library layer says it is one, and that `o` opens it (§18.8).
    defp says(name, index, count, selected?, disabled?, locked?) do
      state =
        [selected? && "selected", disabled? && "disabled"]
        |> Enum.filter(& &1)
        |> Enum.join(", ")

      "#{name}, layer #{index + 1} of #{count}" <>
        if(state == "", do: "", else: ", " <> state) <>
        ": Enter to edit, arrows to move, Right to show what it declares, drag to reorder" <>
        if(locked?, do: ", from the library: o to open", else: "")
    end

    defp name({name, _layer}, _index), do: to_string(name)
    defp name(_layer, index), do: to_string(index)

    defp classes(selected?, disabled?, locked?) do
      ["vis-builder-layer"]
      |> then(&if selected?, do: &1 ++ ["vis-builder-layer-selected"], else: &1)
      |> then(&if disabled?, do: &1 ++ ["vis-builder-layer-disabled"], else: &1)
      |> then(&if locked?, do: &1 ++ ["vis-builder-layer-locked"], else: &1)
      |> Enum.join(" ")
    end
  end
end
