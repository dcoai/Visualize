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

    alias Visualize.Chart.Builder.Glyphs

    attr(:id, :string, required: true, doc: "the hook element's id")

    attr(:rows, :list,
      required: true,
      doc:
        "the tree's rows by flat position — name, depth, parent, group?, count, open?, kind, id, state (spec/14 §18.8, #380, #381)"
    )

    attr(:hidden, :any, default: nil, doc: "the positions under a closed group, a `MapSet`")
    attr(:selected, :integer, default: 0, doc: "the position of the layer being edited")

    attr(:chosen, :any,
      default: nil,
      doc: "the positions selected beside the anchor, a `MapSet` (spec/14 §18.8, #382)"
    )

    attr(:disabled, :any, default: nil, doc: "the positions dropped from the stack, a `MapSet`")

    attr(:expanded, :any,
      default: nil,
      doc: "the positions whose rows are open on what the layer declares, a `MapSet` (§18.8)"
    )

    attr(:placed, :list,
      default: [],
      doc: "each layer placed where the design keeps its kind, by position, for `declared/1`"
    )

    attr(:masks, :map,
      default: %{},
      doc:
        "by position, the mask of a layer whose › Mask item is open: `%{rows, all?}` from `Masks.rows/2` (§18.8, #316)"
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
          :if={not entry.hidden?}
          id={@id <> "-row-" <> to_string(entry.index)}
          class={entry.class}
          style={"--vis-builder-depth: #{entry.depth}"}
          data-builder-layer={entry.index}
          data-builder-parent={entry.parent}
          data-builder-into={entry.into}
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
            :if={entry.group?}
            type="button"
            draggable="false"
            class="vis-builder-site-toggle"
            title={(entry.open? && "collapse " <> entry.name) || "expand " <> entry.name}
            aria-label={(entry.open? && "collapse " <> entry.name) || "expand " <> entry.name}
            aria-expanded={to_string(entry.open?)}
            phx-click="toggle_site"
            phx-value-index={entry.index}
            phx-target={@target}
          >{if entry.open?, do: "▾", else: "▸"}</button>
          <span :if={not entry.group? and entry.kind} class="vis-builder-site-kind" title={to_string(entry.kind)}>{Phoenix.HTML.raw(Glyphs.icon(entry.kind))}</span>
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
          <span :if={entry.group?} class="vis-builder-site-count" title={"#{entry.count} inside"}>{entry.count}</span>
          <button
            :if={entry.locked?}
            type="button"
            draggable="false"
            class="vis-builder-layer-lock"
            title={"Open " <> entry.name <> " — from the library" <> if(entry.state == :edited, do: ", with local changes", else: "") <> ", edited by opening it"}
            aria-label={"Open " <> entry.name}
            phx-click="open_layer"
            phx-value-index={entry.index}
            phx-target={@target}
          >{Phoenix.HTML.raw(Glyphs.icon(:lock))}</button>
          <button
            :if={entry.state == :unlocked}
            type="button"
            draggable="false"
            class="vis-builder-layer-lock vis-builder-layer-lock-open"
            title={"Lock " <> entry.name <> " — link it to the library again, keeping its changes"}
            aria-label={"Lock " <> entry.name}
            phx-click="lock_site"
            phx-value-index={entry.index}
            phx-target={@target}
          >{Phoenix.HTML.raw(Glyphs.icon(:lock_open))}</button>
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
          <div :if={entry.expanded?} class="vis-builder-layer-mask">
            <button
              type="button"
              draggable="false"
              class="vis-builder-layer-mask-toggle"
              title={"which keys of " <> entry.name <> " the layers below show through"}
              aria-expanded={to_string(entry.mask != nil)}
              phx-click="toggle_layer_mask"
              phx-value-index={entry.index}
              phx-target={@target}
            >{if entry.mask, do: "⌄", else: "›"} Mask</button>
            <p :if={entry.mask && entry.mask.all?} class="vis-builder-context-note">
              disabled — every key is masked, so the layers below show through
            </p>
            <p :if={entry.mask && !entry.mask.all? && entry.mask.rows == []} class="vis-builder-context-note">
              this layer sets nothing yet
            </p>
            <form
              :if={entry.mask && !entry.mask.all? && entry.mask.rows != []}
              class="vis-builder-masks"
              phx-change="mask"
              phx-target={@target}
              phx-submit="submitted"
            >
              <input type="hidden" name="_index" value={entry.index} />
              <label :for={row <- entry.mask.rows} class={row.class} title={row.title}>
                <input type="checkbox" name={row.name} value="true" checked={row.masked} />
                <span class="vis-builder-mask-path">{row.name}</span>
              </label>
            </form>
          </div>
          <div :if={entry.expanded? and entry.declared != []} class="vis-builder-layer-detail">
            <button
              :for={kind <- entry.declared}
              type="button"
              draggable="false"
              class="vis-builder-declared"
              title={"open the " <> to_string(kind) <> " of " <> entry.name <> " in the inspector"}
              phx-click="open_declared"
              phx-value-index={entry.index}
              phx-value-kind={kind}
              phx-target={@target}
            >{kind}</button>
          </div>
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
    The kinds a placed fragment declares (spec/14 §18.8), in the schema's order — `meta`,
    `theme`, `sources`, `vars`, `styles`, `defs`, `frame`, `scales`, `axes`, `marks`,
    `labels` — only those it declares; the details are the inspector's.

        iex> Visualize.Chart.Builder.Layers.declared(%{styles: %{series: %{stroke: :red}}, frame: %{size: %{width: 1}, scales: %{x: %{kind: :linear}}, axes: [%{scale: :x, side: :bottom}]}})
        [:styles, :frame, :scales, :axes]
        iex> Visualize.Chart.Builder.Layers.declared(%{})
        []
    """
    @spec declared(map()) :: [atom()]
    def declared(fragment) when is_map(fragment) do
      frame = node_or_empty(Map.get(fragment, :frame))
      for kind <- @roots, declares?(kind, fragment, frame), do: kind
    end

    defp declares?(:meta, fragment, _frame), do: full?(Map.get(fragment, :meta))
    defp declares?(:theme, fragment, _frame), do: Map.get(fragment, :theme) != nil

    defp declares?(kind, fragment, _frame) when kind in [:sources, :vars, :styles, :defs],
      do: full?(Map.get(fragment, kind))

    defp declares?(:frame, _fragment, frame),
      do: Enum.any?(@frame_parts ++ [:kind], &(Map.get(frame, &1) != nil))

    defp declares?(:scales, _fragment, frame), do: full?(Map.get(frame, :scales))
    defp declares?(:axes, _fragment, frame), do: full?(Map.get(frame, :axes))
    defp declares?(:marks, fragment, _frame), do: full?(Map.get(fragment, :marks))
    defp declares?(:labels, fragment, _frame), do: full?(Map.get(fragment, :labels))

    defp full?(map) when is_map(map), do: map_size(map) > 0
    defp full?(list) when is_list(list), do: list != []
    defp full?(_other), do: false

    defp node_or_empty(node) when is_map(node) and not is_struct(node), do: node
    defp node_or_empty(_other), do: %{}

    defp class(nil), do: "vis-builder-layers"
    defp class(extra), do: "vis-builder-layers " <> extra

    # One entry per row of the tree (#380): its name, depth and role, its classes and what
    # its toggle now offers; a row under a closed group is not drawn.
    defp entries(%{rows: rows, selected: selected, disabled: disabled} = assigns) do
      off = disabled || MapSet.new()
      chosen = assigns.chosen || MapSet.new()
      open = assigns.expanded || MapSet.new()
      hidden = assigns.hidden || MapSet.new()
      placed = assigns.placed || []

      count = length(rows)

      for {row, index} <- Enum.with_index(rows) do
        name = row.name
        state = Map.get(row, :state, :inline)
        locked? = state in [:linked, :edited]

        %{
          index: index,
          name: name,
          depth: row.depth,
          parent: row.parent && encode_id(row.parent),
          group?: row.group?,
          count: row.count,
          open?: row.open?,
          kind: if(row.group?, do: nil, else: kind_word(row.kind)),
          into: if(row.group? and not locked?, do: encode_id(row.id)),
          hidden?: index in hidden,
          class: classes(index == selected, index in chosen, index in off, state, row.group?),
          toggle: if(index in off, do: "Enable", else: "Disable"),
          eye: if(index in off, do: :eye_off, else: :eye),
          locked?: locked?,
          state: state,
          expanded?: index in open,
          declared: if(index in open, do: declared(Enum.at(placed, index) || %{}), else: []),
          mask: Map.get(assigns.masks || %{}, index),
          says: says(name, row, index, count, index == selected, index in off, state)
        }
      end
    end

    defp encode_id({:use, n}), do: to_string(n)

    # An object's kind as the root word its glyph is drawn for (§18.13); a layer of several
    # roots (a host-seeded one) wears none.
    defp kind_word(:mark), do: "marks"
    defp kind_word(:style), do: "styles"
    defp kind_word(:label), do: "labels"
    defp kind_word(:source), do: "sources"
    defp kind_word(:gradient), do: "defs"
    defp kind_word(:scale), do: "scales"
    defp kind_word(:axis), do: "axes"
    defp kind_word(:var), do: "vars"
    defp kind_word(kind) when kind in [:theme, :frame], do: to_string(kind)
    defp kind_word(_other), do: nil

    # What the row is and what its keys do, for hover and for what is announced (§18.17);
    # a library layer says it is one, and that `o` opens it and `l` unlocks it; an unlocked
    # one that `l` locks it again (§18.8, #381).
    defp says(name, row, index, count, selected?, disabled?, state) do
      marks =
        [selected? && "selected", disabled? && "disabled"]
        |> Enum.filter(& &1)
        |> Enum.join(", ")

      role =
        cond do
          row.group? and row.depth == 0 -> "layer"
          row.group? -> "group"
          true -> "object"
        end

      "#{name}, #{role} #{index + 1} of #{count}" <>
        if(marks == "", do: "", else: ", " <> marks) <>
        ": Enter to edit, arrows to move, Right to show what it declares, drag to reorder" <>
        case state do
          :linked -> ", from the library: o to open, l to unlock"
          :edited -> ", from the library with local changes: o to open, l to unlock"
          :unlocked -> ", unlocked from the library: l to lock"
          :inline -> ""
        end
    end

    defp classes(selected?, chosen?, disabled?, state, group?) do
      ["vis-builder-layer"]
      |> then(&if selected?, do: &1 ++ ["vis-builder-layer-selected"], else: &1)
      |> then(&if chosen?, do: &1 ++ ["vis-builder-layer-chosen"], else: &1)
      |> then(&if disabled?, do: &1 ++ ["vis-builder-layer-disabled"], else: &1)
      |> then(&if state in [:linked, :edited], do: &1 ++ ["vis-builder-layer-locked"], else: &1)
      |> then(&if state == :edited, do: &1 ++ ["vis-builder-layer-edited"], else: &1)
      |> then(&if state == :unlocked, do: &1 ++ ["vis-builder-layer-unlocked"], else: &1)
      |> then(&if group?, do: &1 ++ ["vis-builder-layer-group"], else: &1)
      |> Enum.join(" ")
    end
  end
end
