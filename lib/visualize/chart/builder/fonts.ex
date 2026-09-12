if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Fonts do
    @moduledoc """
    The font picker (spec/14 §19.10): family, size, weight and anchor of the node being
    edited, together, the way a drawing tool keeps them beside the canvas.

    It acts on the node the form is editing when that node's kind carries the font keys —
    a style, a theme — and writes through the same `edit` the form does, under the same
    names, so it is a bigger view of four fields and never a second form. On a node with
    no font keys it says which node to open.

    This module compiles only when `Phoenix.Component` is loaded (spec/10 §1.1, D-45, D-85).
    """

    use Phoenix.Component

    alias Visualize.Chart.Builder.Glyphs
    alias Visualize.Chart.{Schema, Var}

    @faces [
      "system-ui",
      "sans-serif",
      "serif",
      "monospace",
      "Helvetica",
      "Arial",
      "Verdana",
      "Georgia",
      "Times New Roman",
      "Courier New"
    ]

    @keys [:font_family, :font_size, :font_weight, :text_anchor]

    attr(:id, :string, required: true, doc: "the panel's id")
    attr(:kind, :atom, required: true, doc: "the kind of the node being edited")
    attr(:node, :any, default: nil, doc: "the node being edited, or nil")
    attr(:target, :any, default: nil, doc: "the `phx-target` of the panel's events")

    @doc """
    Renders the font picker: `<form class="vis-builder-fonts">` over the node's font keys,
    or a note when the node has none.
    """
    def panel(assigns) do
      assigns = assign(assigns, keys: keys(assigns.kind), node: assigns.node || %{})

      ~H"""
      <div id={@id} class="vis-builder-fonts-panel">
        <p :if={@keys == []} class="vis-builder-context-note">
          open a style — a mark's, a label's, or the theme — to set its font
        </p>
        <form :if={@keys != []} class="vis-builder-fonts" phx-change="edit" phx-target={@target}>
          <div :if={:font_family in @keys} class="vis-builder-faces" role="radiogroup" aria-label="font family">
            <label
              :for={family <- faces(Map.get(@node, :font_family))}
              class={"vis-builder-face" <> if(Map.get(@node, :font_family) == family, do: " vis-builder-face-on", else: "")}
              style={"font-family: #{family}"}
            >
              <input
                type="radio"
                name="font_family"
                value={family}
                checked={Map.get(@node, :font_family) == family}
                aria-label={family}
              />
              {family}
            </label>
          </div>
          <label :if={:font_size in @keys} class="vis-builder-picker-row">
            <span class="vis-builder-control-label">size</span>
            <input
              type="range"
              name="font_size.range"
              class="vis-builder-range"
              min="6"
              max="72"
              step="1"
              value={number(Map.get(@node, :font_size), 12)}
              aria-label="font size, dragged"
            />
            <input type="text" name="font_size" value={shown(Map.get(@node, :font_size))} placeholder="12" />
          </label>
          <div :if={:font_weight in @keys} class="vis-builder-words" role="radiogroup" aria-label="font weight">
            <label
              :for={weight <- [:normal, :bold]}
              class={"vis-builder-word" <> if(Map.get(@node, :font_weight) == weight, do: " vis-builder-word-on", else: "")}
              style={"font-weight: #{weight}"}
            >
              <input type="radio" name="font_weight" value={weight} checked={Map.get(@node, :font_weight) == weight} />
              {weight}
            </label>
          </div>
          <div :if={:text_anchor in @keys} class="vis-builder-glyphs" role="radiogroup" aria-label="text anchor">
            <label
              :for={anchor <- [:start, :middle, :end]}
              class={"vis-builder-glyph" <> if(Map.get(@node, :text_anchor) == anchor, do: " vis-builder-glyph-on", else: "")}
              title={anchor}
            >
              <input
                type="radio"
                name="text_anchor"
                value={anchor}
                checked={Map.get(@node, :text_anchor) == anchor}
                aria-label={anchor}
              />
              {Phoenix.HTML.raw(Glyphs.glyph(:text_anchor, anchor))}
            </label>
          </div>
        </form>
      </div>
      """
    end

    @doc """
    The font keys a node kind carries, of `font_family`, `font_size`, `font_weight` and
    `text_anchor`; `[]` for a kind with none.

        iex> Visualize.Chart.Builder.Fonts.keys(:style)
        [:font_family, :font_size, :font_weight, :text_anchor]

        iex> Visualize.Chart.Builder.Fonts.keys(:frame)
        []
    """
    @spec keys(atom()) :: [atom()]
    def keys(kind) do
      declared = Enum.map(Schema.describe(kind), & &1.key)
      Enum.filter(@keys, &(&1 in declared))
    end

    defp faces(value) when is_binary(value) and value not in @faces, do: [value | @faces]
    defp faces(_value), do: @faces

    defp number(n, _default) when is_number(n), do: n
    defp number(_other, default), do: default

    defp shown(nil), do: nil
    defp shown(%Var{}), do: nil
    defp shown(value) when is_binary(value), do: value
    defp shown(value), do: to_string(value)
  end
end
