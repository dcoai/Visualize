if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Fonts do
    @moduledoc """
    The font picker (spec/14 §19.10): family, size, face and anchor of the node being
    edited, together, the way a drawing tool keeps them beside the canvas.

    It acts on the node the form is editing when that node's kind carries the font keys —
    a style, a theme — and writes through the same `edit` the form does, under the same
    names, so it is a bigger view of the font fields and never a second form. On a node with
    no font keys it says which node to open.

    This module compiles only when `Phoenix.Component` is loaded (spec/10 §1.1, D-45, D-85).
    """

    use Phoenix.Component

    alias Visualize.Chart.Builder.{Editor, Glyphs, StyleForm, Writes}
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

    # The font controls by the name they write under, and the path each reads (spec/14
    # §19.10): a style's are its parts' keys (§18.7, D-178), a theme's its own keys.
    @style [
      {"font.family", [:font, :family]},
      {"font.size", [:font, :size]},
      {"font.face", [:font]},
      {"text.anchor", [:text, :anchor]}
    ]
    @flat [{"font_family", [:font_family]}, {"font_size", [:font_size]}]

    attr(:id, :string, required: true, doc: "the panel's id")
    attr(:kind, :atom, required: true, doc: "the kind of the node being edited")
    attr(:node, :any, default: nil, doc: "the node being edited, or nil")
    attr(:target, :any, default: nil, doc: "the `phx-target` of the panel's events")

    @doc """
    Renders the font picker: `<form class="vis-builder-fonts">` over the node's font keys,
    or a note when the node has none.
    """
    def panel(assigns) do
      controls = controls(assigns.kind)
      node = shown(assigns.kind, assigns.node)
      at = fn name -> Map.get(controls, name) && Writes.at(node, Map.fetch!(controls, name)) end

      assigns =
        assign(assigns,
          keys: keys(assigns.kind),
          family: at.("font.family") || at.("font_family"),
          size: at.("font.size") || at.("font_size"),
          size_name: if(Map.has_key?(controls, "font.size"), do: "font.size", else: "font_size"),
          family_name:
            if(Map.has_key?(controls, "font.family"), do: "font.family", else: "font_family"),
          font: at.("font.face") || %{},
          anchor: at.("text.anchor")
        )

      ~H"""
      <div id={@id} class="vis-builder-fonts-panel">
        <p :if={@keys == []} class="vis-builder-context-note">
          open a style — a mark's, a label's, or the theme — to set its font
        </p>
        <form :if={@keys != []} id={@id <> "-form"} class="vis-builder-fonts" phx-change="edit" phx-target={@target} phx-submit="submitted">
          <div :if={@family_name in @keys} class="vis-builder-faces" role="radiogroup" aria-label="font family">
            <label
              :for={family <- faces(@family)}
              class={"vis-builder-face" <> if(@family == family, do: " vis-builder-face-on", else: "")}
              style={"font-family: #{family}"}
            >
              <input
                type="radio"
                name={@family_name}
                value={family}
                checked={@family == family}
                aria-label={family}
              />
              {family}
            </label>
          </div>
          <label :if={@size_name in @keys} class="vis-builder-picker-row">
            <span class="vis-builder-control-label">size</span>
            <input
              type="range"
              name={@size_name <> ".range"}
              class="vis-builder-range"
              min="6"
              max="72"
              step="1"
              value={number(@size, 12)}
              aria-label="font size, dragged"
            />
            <input type="text" name={@size_name} value={shown_value(@size)} placeholder="12" />
          </label>
          <div :if={"font.face" in @keys} class="vis-builder-face-list vis-builder-face-list-large" role="radiogroup" aria-label="face">
            <label
              :for={row <- face_rows(@font)}
              class={"vis-builder-face-row" <> if(row.on?, do: " vis-builder-face-row-on", else: "")}
              style={row.css}
            >
              <input type="radio" name="font.face" value={row.face} checked={row.on?} aria-label={row.label} />
              {row.label}
            </label>
          </div>
          <div :if={"text.anchor" in @keys} class="vis-builder-glyphs" role="radiogroup" aria-label="text anchor">
            <label
              :for={anchor <- [:start, :middle, :end]}
              class={"vis-builder-glyph" <> if(@anchor == anchor, do: " vis-builder-glyph-on", else: "")}
              title={anchor}
            >
              <input
                type="radio"
                name="text.anchor"
                value={anchor}
                checked={@anchor == anchor}
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
    The font controls a node kind has, by the name each writes under: a style's family,
    size, face and anchor in its parts, a theme's family and size; `[]` for a kind with
    none.

        iex> Visualize.Chart.Builder.Fonts.keys(:style)
        ["font.family", "font.size", "font.face", "text.anchor"]

        iex> Visualize.Chart.Builder.Fonts.keys(:theme)
        ["font_family", "font_size"]

        iex> Visualize.Chart.Builder.Fonts.keys(:frame)
        []
    """
    @spec keys(atom()) :: [String.t()]
    def keys(kind), do: kind |> table() |> Enum.map(&elem(&1, 0))

    defp controls(kind), do: Map.new(table(kind))

    defp table(kind) do
      if StyleForm.kind?(kind) do
        @style
      else
        declared = Enum.map(Schema.describe(kind), & &1.key)
        Enum.filter(@flat, fn {_name, [key]} -> key in declared end)
      end
    end

    # A style's node read in its parts, whatever spelling it is in.
    defp shown(kind, node) when is_map(node) do
      if StyleForm.kind?(kind), do: Visualize.Chart.Style.normalize(node), else: node
    end

    defp shown(_kind, _node), do: %{}

    # The face list, as the form draws it (spec/14 §18.6): the same eight, the font's marked.
    defp face_rows(font) do
      font = if is_map(font) and not is_struct(font), do: font, else: %{}
      shown = Editor.face(Map.get(font, :weight), Map.get(font, :style))

      for {face, weight, style} <- Editor.faces() do
        %{
          face: face,
          on?: face == shown,
          css:
            "font-weight: #{%{light: 300, normal: 400, medium: 500, bold: 700}[weight]}; font-style: #{style}",
          label: face |> to_string() |> String.replace("_", " ")
        }
      end
    end

    defp faces(value) when is_binary(value) and value not in @faces, do: [value | @faces]
    defp faces(_value), do: @faces

    defp number(n, _default) when is_number(n), do: n
    defp number(_other, default), do: default

    defp shown_value(nil), do: nil
    defp shown_value(%Var{}), do: nil
    defp shown_value(value) when is_binary(value), do: value
    defp shown_value(value) when is_atom(value) or is_number(value), do: to_string(value)
    defp shown_value(value), do: inspect(value)
  end
end
