if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Palette do
    @moduledoc """
    The builder's style palette: the styles the stack declares, and how one is made
    (spec/14 §18.14).

    A design's `styles` is a map of name to style node (§3), and a mark refers to one by
    name. Before this panel there was no way to *add* a name — §18.5 says "adding a node is
    adding the key, which is the same edit as any other", but no control added one — so a
    style could only be edited where some layer had already declared it, and a mark's style
    was a name typed into a text box and checked by the error list.

    The palette is a view of the **stacked** design, because that is what a mark's reference
    resolves against: a style the house layer declares is available to a mark in the panel
    layer, and the palette says so. Creating one writes into the **selected** layer, because
    that is where every other edit goes.

    This module compiles only when `Phoenix.Component` is loaded (spec/10 §1.1, D-45, D-85).
    """

    use Phoenix.Component

    attr(:design, :map, required: true, doc: "the stacked design whose styles are the palette")
    attr(:open, :atom, default: nil, doc: "the style the editor is on, marked in the list")
    attr(:target, :any, default: nil, doc: "the `phx-target` of the palette's events")
    attr(:class, :string, default: nil, doc: "appended to the palette's class")

    @doc """
    Renders the palette (spec/10 §15.3).

    A `<div class="vis-builder-palette">` with one
    `<li class="vis-builder-palette-entry">` per declared style and a form that adds one.
    """
    def panel(assigns) do
      assigns = assign(assigns, :styles, styles(assigns.design))

      ~H"""
      <div class={class(@class)}>
        <h2 class="vis-builder-tray-title">Styles</h2>
        <ul :if={@styles != []} class="vis-builder-palette-list">
          <li :for={style <- @styles} class={entry(style.name == @open)}>
            <button
              type="button"
              class="vis-builder-palette-style"
              phx-click="select_style"
              phx-value-name={style.name}
              phx-target={@target}
            >
              <span class="vis-builder-swatch" style={style.swatch}></span>
              <span class="vis-builder-palette-name">{style.name}</span>
              <span class="vis-builder-palette-summary">{style.summary}</span>
            </button>
          </li>
        </ul>
        <p :if={@styles == []} class="vis-builder-palette-empty">
          No layer declares a style yet.
        </p>
        <form class="vis-builder-palette-new" phx-submit="add_style" phx-target={@target}>
          <input
            type="text"
            name="name"
            value=""
            class="vis-builder-palette-input"
            placeholder="new style"
          />
          <button type="submit" class="vis-builder-palette-add">Add style</button>
        </form>
      </div>
      """
    end

    @doc """
    The names the stacked design declares, in name order (spec/14 §18.14).

    This is what a `{:ref, :style}` is a choice among, and it is read from the design rather
    than kept anywhere: a style a layer stops declaring stops being offered.

        iex> Visualize.Chart.Builder.Palette.names(%{styles: %{series: %{}, axis: %{}}})
        [:axis, :series]

        iex> Visualize.Chart.Builder.Palette.names(%{marks: []})
        []
    """
    @spec names(map()) :: [atom()]
    def names(design) do
      case Map.get(design, :styles) do
        map when is_map(map) -> map |> Map.keys() |> Enum.sort()
        _absent -> []
      end
    end

    defp class(nil), do: "vis-builder-palette"
    defp class(extra), do: "vis-builder-palette " <> extra

    defp entry(true), do: "vis-builder-palette-entry vis-builder-palette-entry-open"
    defp entry(false), do: "vis-builder-palette-entry"

    # One row per declared style: what it is called, what it declares, and a swatch where the
    # style names a colour outright. A stroke given as a theme slot — `:series_1` — has no
    # colour until the theme resolves it, so the swatch is left to the stylesheet rather than
    # guessed at here.
    defp styles(design) do
      declared = Map.get(design, :styles) || %{}

      for name <- names(design) do
        style = Map.get(declared, name) || %{}
        %{name: name, swatch: swatch(style), summary: summary(style)}
      end
    end

    defp swatch(style) do
      case Enum.find_value([:fill, :stroke], &literal(Map.get(style, &1))) do
        nil -> nil
        colour -> "background: " <> colour
      end
    end

    defp literal("#" <> _rest = colour), do: colour
    defp literal(_other), do: nil

    defp summary(style) when map_size(style) == 0, do: "empty"
    defp summary(style), do: style |> Map.keys() |> Enum.sort() |> Enum.join(", ")
  end
end
