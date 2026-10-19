if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.BoardGrid do
    @moduledoc """
    The board mode's grid (spec/14 §22.3, D-152): every cell of the board placed on the
    12-column grid with its handles and its preview, or the board as it reflows below its
    breakpoint.

    The grid is a CSS grid with the board's own arithmetic (spec/15 §1.6): 12 equal
    columns, rows `row_height` high and `gap` apart. `BuilderHook` in scope `board` drags a
    cell by its body and resizes it by a handle, and pushes the rectangle; the server
    places it (`Visualize.Chart.Builder.Boards.place/3`) or refuses it, and the next render
    is where the cell is.

    This module compiles only when `Phoenix.Component` is loaded (spec/10 §1.1, D-45, D-85).
    """

    use Phoenix.Component

    attr(:id, :string, required: true, doc: "the grid's id")

    attr(:mode, :map,
      required: true,
      doc:
        "the board mode's assigns, as the builder derives them for the open board (spec/14 §22)"
    )

    attr(:target, :any, default: nil, doc: "the `phx-target` of the hook and every control")

    @doc """
    The grid of the board mode (spec/14 §22.3): `<div class="vis-builder-board-grid">`
    holding one `<article class="vis-builder-board-cell">` per cell, placed by
    `grid-column` and `grid-row` and carrying `data-board-cell` and its rectangle, with its
    title, its component, its preview and its three handles; or, in the narrow view, the
    cells stacked as `Visualize.Board.arrange/2` places them below the breakpoint, with no
    handles.
    """
    def grid(assigns) do
      ~H"""
      <div class="vis-builder-board-view">
        <div class="vis-builder-board-bar" role="group" aria-label="the board's view">
          <button
            :for={{view, word} <- [wide: "wide", narrow: "narrow"]}
            type="button"
            class={"vis-builder-board-view-button" <> if(view == @mode.view, do: " vis-builder-board-view-on", else: "")}
            aria-pressed={to_string(view == @mode.view)}
            phx-click="board_view"
            phx-value-view={word}
            phx-target={@target}
          >{word}</button>
          <span class="vis-builder-board-measure">
            12 columns · rows {@mode.layout.row_height} px · gap {@mode.layout.gap} px · stacks below {@mode.layout.breakpoint} px
          </span>
        </div>
        <p :if={@mode.cells == []} class="vis-builder-context-note">
          this board has no cells yet; add one in the inspector
        </p>
        <div
          :if={@mode.view == :wide}
          id={@id}
          class="vis-builder-board-grid"
          style={track(@mode.layout)}
          phx-hook="BuilderHook"
          data-builder-target={@target}
          data-builder-scope="board"
          data-board-gap={@mode.layout.gap}
          data-board-row-height={@mode.layout.row_height}
        >
          <article
            :for={cell <- @mode.cells}
            class={cell_class(cell)}
            style={place(cell)}
            tabindex="0"
            aria-label={"#{cell.title}, columns #{cell.x + 1} to #{cell.x + cell.w}, rows #{cell.y + 1} to #{cell.y + cell.h}"}
            data-board-cell={cell.name}
            data-board-x={cell.x}
            data-board-y={cell.y}
            data-board-w={cell.w}
            data-board-h={cell.h}
            phx-click="board_select"
            phx-value-cell={cell.name}
            phx-target={@target}
          >
            <.face cell={cell} />
            <span :for={edge <- ~w(e s se)} class={"vis-builder-board-handle vis-builder-board-handle-" <> edge} data-board-handle={edge} aria-hidden="true"></span>
          </article>
        </div>
        <div
          :if={@mode.view == :narrow}
          id={@id <> "-narrow"}
          class="vis-builder-board-grid vis-builder-board-grid-narrow"
          style={track(@mode.layout)}
        >
          <article
            :for={cell <- @mode.stacked}
            class={cell_class(cell)}
            style={place(cell)}
            data-board-cell={cell.name}
          >
            <.face cell={cell} />
          </article>
        </div>
        <p :if={@mode.view == :narrow} class="vis-builder-board-note">
          below {@mode.layout.breakpoint} px the cells stack in reading order; placement is edited in the wide view
        </p>
      </div>
      """
    end

    attr(:cell, :map, required: true)

    defp face(assigns) do
      ~H"""
      <header class="vis-builder-board-cell-head">
        <span class="vis-builder-board-cell-title">{@cell.title}</span>
        <span class="vis-builder-board-cell-component">{@cell.component}</span>
      </header>
      <div class="vis-builder-board-cell-body">
        {preview(@cell.preview)}
      </div>
      """
    end

    # The cell's chart, raw markup the library rendered, its fault panel, or its faults one
    # per line.
    defp preview({:ok, svg}), do: Phoenix.HTML.raw(svg)

    # A binding of the wrong type: the cell-state panel and its faults (§22.6, D-153).
    defp preview({:fault, svg, lines}) do
      assigns = %{svg: svg, lines: lines}

      ~H"""
      <div class="vis-builder-fault">{Phoenix.HTML.raw(@svg)}</div>
      <ul class="vis-builder-errors"><li :for={line <- @lines} class="vis-builder-error">{line}</li></ul>
      """
    end

    defp preview({:error, lines}) do
      assigns = %{lines: lines}

      ~H"""
      <ul class="vis-builder-errors"><li :for={line <- @lines} class="vis-builder-error">{line}</li></ul>
      """
    end

    defp track(layout) do
      "grid-template-columns: repeat(12, minmax(0, 1fr)); grid-auto-rows: #{layout.row_height}px; gap: #{layout.gap}px"
    end

    defp place(cell),
      do: "grid-column: #{cell.x + 1} / span #{cell.w}; grid-row: #{cell.y + 1} / span #{cell.h}"

    defp cell_class(cell) do
      ["vis-builder-board-cell"]
      |> then(&if cell.selected?, do: &1 ++ ["vis-builder-board-cell-selected"], else: &1)
      |> then(&if cell.faulty?, do: &1 ++ ["vis-builder-board-cell-faulty"], else: &1)
      |> Enum.join(" ")
    end

    @doc false
    # The grid's rules, appended to the builder's stylesheet (spec/14 §18.13): every rule
    # under `.vis-builder`, every color one of its properties.
    def css do
      """

      .vis-builder .vis-builder-board-view {
        display: flex;
        flex-direction: column;
        gap: var(--vis-builder-gap);
        padding: var(--vis-builder-gap);
        overflow: auto;
      }

      .vis-builder .vis-builder-board-bar {
        display: flex;
        align-items: center;
        gap: 6px;
        flex-wrap: wrap;
      }

      .vis-builder .vis-builder-board-view-button {
        border: 1px solid var(--vis-builder-line);
        border-radius: var(--vis-builder-radius);
        background: var(--vis-builder-panel);
        color: var(--vis-builder-ink);
        padding: 2px 10px;
        cursor: pointer;
      }

      .vis-builder .vis-builder-board-view-on {
        background: var(--vis-builder-accent);
        border-color: var(--vis-builder-accent);
        color: var(--vis-builder-accent-ink);
      }

      .vis-builder .vis-builder-board-measure,
      .vis-builder .vis-builder-board-note {
        color: var(--vis-builder-muted);
        font-size: 12px;
      }

      .vis-builder .vis-builder-board-grid {
        display: grid;
        position: relative;
        min-width: 600px;
        touch-action: none;
      }

      .vis-builder .vis-builder-board-grid-narrow {
        min-width: 0;
        max-width: 360px;
      }

      .vis-builder .vis-builder-board-cell {
        position: relative;
        display: flex;
        flex-direction: column;
        min-width: 0;
        min-height: 0;
        border: 1px solid var(--vis-builder-line);
        border-radius: var(--vis-builder-radius);
        background: var(--vis-builder-panel);
        cursor: grab;
        overflow: hidden;
        user-select: none;
      }

      .vis-builder .vis-builder-board-cell-selected {
        border-color: var(--vis-builder-accent);
        box-shadow: 0 0 0 1px var(--vis-builder-accent);
      }

      .vis-builder .vis-builder-board-cell-faulty {
        border-color: var(--vis-builder-warn);
      }

      .vis-builder .vis-builder-board-dragging {
        opacity: 0.85;
        cursor: grabbing;
        z-index: 2;
      }

      .vis-builder .vis-builder-board-cell-head {
        display: flex;
        justify-content: space-between;
        gap: 6px;
        padding: 2px 6px;
        font-size: 12px;
        border-bottom: 1px solid var(--vis-builder-line);
      }

      .vis-builder .vis-builder-board-cell-component {
        color: var(--vis-builder-muted);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .vis-builder .vis-builder-board-cell-body {
        flex: 1 1 auto;
        min-height: 0;
        overflow: hidden;
        pointer-events: none;
      }

      .vis-builder .vis-builder-board-cell-body svg {
        width: 100%;
        height: 100%;
      }

      .vis-builder .vis-builder-board-handle {
        position: absolute;
        background: transparent;
      }

      .vis-builder .vis-builder-board-handle-e {
        top: 0;
        right: 0;
        width: 8px;
        height: 100%;
        cursor: ew-resize;
      }

      .vis-builder .vis-builder-board-handle-s {
        left: 0;
        bottom: 0;
        width: 100%;
        height: 8px;
        cursor: ns-resize;
      }

      .vis-builder .vis-builder-board-handle-se {
        right: 0;
        bottom: 0;
        width: 14px;
        height: 14px;
        cursor: nwse-resize;
        background: linear-gradient(135deg, transparent 50%, var(--vis-builder-muted) 50%);
      }

      .vis-builder .vis-builder-board-panel {
        display: flex;
        flex-direction: column;
        gap: var(--vis-builder-gap);
        padding: var(--vis-builder-gap);
        overflow-y: auto;
      }

      .vis-builder .vis-builder-board-section {
        display: flex;
        flex-direction: column;
        gap: 6px;
        border: 1px solid var(--vis-builder-line);
        border-radius: var(--vis-builder-radius);
      }

      .vis-builder .vis-builder-board-row {
        display: flex;
        align-items: center;
        gap: 6px;
        flex-wrap: wrap;
      }

      .vis-builder .vis-builder-board-row-stale {
        color: var(--vis-builder-muted);
      }

      .vis-builder .vis-builder-board-actions {
        display: flex;
        gap: 6px;
      }

      .vis-builder .vis-builder-board-valid {
        color: var(--vis-builder-muted);
      }

      .vis-builder .vis-builder-board-source-text {
        box-sizing: border-box;
        width: 100%;
        min-height: 7em;
        font-family: ui-monospace, monospace;
        font-size: 12px;
        white-space: pre-wrap;
      }

      .vis-builder .vis-builder-board-source-rows {
        border-collapse: collapse;
        font-size: 12px;
      }

      .vis-builder .vis-builder-board-source-rows th,
      .vis-builder .vis-builder-board-source-rows td {
        padding: 1px 6px;
        text-align: left;
      }
      """
    end
  end
end
