if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Palette do
    @moduledoc """
    The builder's style palette: the styles the stack declares, how one is made, and the
    theme's palette beneath them (spec/14 §18.14).

    A design's `styles` is a map of name to style node (§3), and a mark refers to one by
    name. Before this panel there was no way to *add* a name — §18.5 says "adding a node is
    adding the key, which is the same edit as any other", but no control added one — so a
    style could only be edited where some layer had already declared it, and a mark's style
    was a name typed into a text box and checked by the error list.

    The palette is a view of the **stacked** design, because that is what a mark's reference
    resolves against: a style the house layer declares is available to a mark in the panel
    layer, and the palette says so. Creating one declares it **in the design**, as a style
    site keyed by its name — never in a layer (§18.14, §19.11, D-178).

    A reference resolves against the **theme's palette** too (spec/08 §7.7, #637), so the
    panel lists it beneath the design's styles in its five groups (#685, the redo of #639):
    each entry in its parts drawn as a sample shape and a label in the theme's own looks, a
    state or a modifier laid over a neutral sample, a name the design declares marked as
    overridden. Choosing an entry offers to override it, which declares the theme's entry
    in the design as a style site of that name.

    This module compiles only when `Phoenix.Component` is loaded (spec/10 §1.1, D-45, D-85).
    """

    use Phoenix.Component

    alias Visualize.Chart.Style
    alias Visualize.IR.Path
    alias Visualize.SVG.Renderer
    alias Visualize.Theme
    alias Visualize.Theme.Palette, as: Entries

    # The sample a state or a modifier is laid over: an object whose look means nothing,
    # in the theme's `:neutral` role, so the preview shows only what the entry changes.
    @neutral %{
      fill: %{type: :solid, color: {:color, :neutral}, opacity: 0.35},
      stroke: %{type: :solid, color: {:color, :neutral}, width: 1}
    }
    # What the sample shape and the label draw of a resolved entry, in the order written.
    @shape_keys [
      :fill,
      :fill_opacity,
      :stroke,
      :stroke_width,
      :stroke_opacity,
      :stroke_dasharray,
      :opacity
    ]
    @line_keys [:stroke, :stroke_width, :stroke_opacity, :stroke_dasharray, :opacity]
    @label_keys [:fill, :font_family, :font_size, :font_weight, :font_style, :opacity]

    @typedoc "A preview's three pictures, each a list of SVG attribute names and their text."
    @type preview :: %{
            shape: [{String.t(), String.t()}],
            line: [{String.t(), String.t()}],
            label: [{String.t(), String.t()}]
          }

    attr(:id, :string,
      default: "vis-builder-palette",
      doc: "the palette's id, and the stem of its add form's"
    )

    attr(:design, :map, required: true, doc: "the stacked design whose styles are the palette")

    attr(:theme, :any,
      default: nil,
      doc: "the theme whose palette is listed; the default's when nil"
    )

    attr(:open, :atom, default: nil, doc: "the style the editor is on, marked in the list")
    attr(:chosen, :atom, default: nil, doc: "the theme entry chosen, offered for override")
    attr(:target, :any, default: nil, doc: "the `phx-target` of the palette's events")
    attr(:class, :string, default: nil, doc: "appended to the palette's class")

    @doc """
    Renders the palette (spec/10 §15.3).

    A `<div class="vis-builder-palette">` with one
    `<li class="vis-builder-palette-entry">` per declared style, a form that adds one, and
    a `<section class="vis-builder-palette-group">` per group of the theme's palette.
    """
    def panel(assigns) do
      theme = assigns.theme || Theme.default()

      assigns =
        assigns
        |> assign(:styles, styles(assigns.design, theme))
        |> assign(:groups, theme_groups(assigns.design, theme))
        # The previews sit on the theme's own background, as the chart's marks do.
        |> assign(:background, Theme.resolve(theme, :background, :literal))

      ~H"""
      <div id={@id} class={class(@class)}>
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
              <span :if={style.shadows} class="vis-builder-palette-summary">shadows the theme's</span>
            </button>
          </li>
        </ul>
        <p :if={@styles == []} class="vis-builder-palette-empty">
          No layer declares a style yet.
        </p>
        <form id={@id <> "-new"} class="vis-builder-palette-new" phx-submit="add_style" phx-target={@target}>
          <input
            type="text"
            name="name"
            value=""
            class="vis-builder-palette-input"
            placeholder="new style"
          />
          <button type="submit" class="vis-builder-palette-add">Add style</button>
        </form>
        <h3 class="vis-builder-palette-theme">The theme's palette</h3>
        <section :for={{group, rows} <- @groups} class="vis-builder-palette-group">
          <h4 class="vis-builder-palette-group-title">{group}</h4>
          <ul class="vis-builder-palette-list">
            <li :for={row <- rows} class={theme_entry(row, @open, @chosen)}>
              <button
                type="button"
                class="vis-builder-palette-style"
                title={theme_title(row)}
                phx-click={if row.shadowed, do: "select_style", else: "choose_palette_style"}
                phx-value-name={row.name}
                phx-target={@target}
              >
                <svg
                  class="vis-builder-palette-preview"
                  width="76"
                  height="22"
                  viewBox="0 0 76 22"
                  aria-hidden="true"
                >
                  <rect width="76" height="22" fill={@background} />
                  <rect x="2" y="4" width="20" height="14" rx="2" {row.preview.shape} />
                  <line x1="26" y1="11" x2="46" y2="11" {row.preview.line} />
                  <text x="50" y="16" {row.preview.label}>Aa</text>
                </svg>
                <span class="vis-builder-palette-name">{row.name}</span>
                <span :if={row.shadowed} class="vis-builder-palette-summary">overridden by the design</span>
              </button>
              <button
                :if={row.name == @chosen and not row.shadowed}
                type="button"
                class="vis-builder-palette-override"
                phx-click="override_style"
                phx-value-name={row.name}
                phx-target={@target}
              >Override in the design</button>
            </li>
          </ul>
        </section>
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

    @doc """
    The style names a reference may take, grouped (spec/14 §18.14, #685): the design's
    own, then the theme's palette in spec/08 §7.7's five groups. A name the design declares
    is listed under the design only, since that is the entry a reference to it draws; a
    group left empty is left out.

        iex> theme = Visualize.Theme.default()
        iex> groups = Visualize.Chart.Builder.Palette.groups(%{styles: %{warning: %{}}}, theme)
        iex> Enum.map(groups, &elem(&1, 0))
        ["design", "style series", "roles", "states", "furniture", "modifiers"]
        iex> groups |> List.keyfind("roles", 0) |> elem(1)
        [:good, :bad, :info, :neutral]
    """
    @spec groups(map(), Theme.t()) :: [{String.t(), [atom()]}]
    def groups(design, %Theme{} = theme) do
      declared = names(design)

      [{"design", declared} | palette_groups(theme)]
      |> Enum.map(fn
        {"design", names} -> {"design", names}
        {group, names} -> {group, names -- declared}
      end)
      |> Enum.reject(&match?({_group, []}, &1))
    end

    # The theme's names in spec/08 §7.7's five groups, in its order.
    defp palette_groups(theme) do
      names = Theme.style_names(theme)
      roles = Entries.roles()
      states = Entries.states()
      furniture = Entries.furniture()
      modifiers = Entries.modifiers()

      [
        {"style series", names -- (roles ++ states ++ furniture ++ modifiers)},
        {"roles", Enum.filter(names, &(&1 in roles))},
        {"states", Enum.filter(names, &(&1 in states))},
        {"furniture", Enum.filter(names, &(&1 in furniture))},
        {"modifiers", Enum.filter(names, &(&1 in modifiers))}
      ]
    end

    @doc """
    A palette entry's preview (spec/14 §18.14, #685): the SVG attributes of its sample shape,
    a rectangle, of the stroke drawn beside it, and of its `Aa` label — the entry in its parts
    resolved through `theme` in `:literal` mode and projected onto what the picture draws.

    A whole style has no single color, so it is drawn rather than swatched; the stroke is
    drawn on its own as well as round the shape, because a dash round a shape filled in the
    stroke's own color cannot be seen. A key the
    entry leaves unset is the sample's own — no fill on the shape; the theme's text color,
    font and label size on the label — and a **state** entry, which says only what changes,
    is laid over a neutral sample first, and so is a **modifier**. A value the preview cannot
    draw, a binding or a paint, is left out.

        iex> theme = Visualize.Theme.default()
        iex> Visualize.Chart.Builder.Palette.preview(theme, :grid, %{stroke: %{type: :solid, color: {:color, :grid}}}).shape
        [{"fill", "none"}, {"stroke", "#e0e0e0"}]
        iex> Visualize.Chart.Builder.Palette.preview(theme, :selected, %{stroke: %{width: 2}}).shape
        [{"fill", "#6f7480"}, {"fill-opacity", "0.35"}, {"stroke", "#6f7480"}, {"stroke-width", "2"}]
        iex> Visualize.Chart.Builder.Palette.preview(theme, :thick, Visualize.Theme.style(theme, :thick)).line
        [{"stroke", "#6f7480"}, {"stroke-width", "3"}]
    """
    @spec preview(Theme.t(), atom(), map()) :: preview()
    def preview(%Theme{} = theme, name, entry) when is_map(entry) do
      node = if neutral?(name), do: Style.merge(@neutral, entry), else: entry
      style = Style.resolve(node, theme, :literal)

      label_base = %{
        fill: Theme.resolve(theme, :text, :literal),
        font_family: Theme.resolve(theme, :font_family, :literal),
        font_size: Theme.resolve(theme, :label_size, :literal)
      }

      %{
        shape: attributes(Map.merge(%{fill: "none"}, style), @shape_keys),
        line: attributes(style, @line_keys),
        label: attributes(Map.merge(label_base, style), @label_keys)
      }
    end

    defp neutral?(name), do: name in Entries.states() or name in Entries.modifiers()

    defp attributes(style, keys) do
      for key <- keys,
          text = text(Map.get(style, key)),
          text != nil,
          do: {Renderer.attribute_name(key), text}
    end

    defp text(value) when is_binary(value), do: value
    defp text(value) when is_number(value), do: Path.format_number(value)

    defp text(value) when is_atom(value) and value not in [nil, true, false],
      do: Atom.to_string(value)

    defp text(_absent_binding_or_paint), do: nil

    defp class(nil), do: "vis-builder-palette"
    defp class(extra), do: "vis-builder-palette " <> extra

    defp entry(true), do: "vis-builder-palette-entry vis-builder-palette-entry-open"
    defp entry(false), do: "vis-builder-palette-entry"

    defp theme_entry(row, open, chosen) do
      ["vis-builder-palette-entry"]
      |> then(&if row.shadowed, do: &1 ++ ["vis-builder-palette-entry-shadowed"], else: &1)
      |> then(
        &if (row.shadowed and row.name == open) or (not row.shadowed and row.name == chosen),
          do: &1 ++ ["vis-builder-palette-entry-open"],
          else: &1
      )
      |> Enum.join(" ")
    end

    defp theme_title(%{shadowed: true, name: name}),
      do: "#{name} — the design declares its own; click to open it"

    defp theme_title(%{name: name}), do: "#{name} — the theme's; click to override it"

    # One row per declared style: what it is called, what it declares, and a swatch where the
    # style names a color outright. A stroke given as a theme slot — `:series_1` — has no
    # color until the theme resolves it, so the swatch is left to the stylesheet rather than
    # guessed at here.
    defp styles(design, theme) do
      declared = Map.get(design, :styles) || %{}

      for name <- names(design) do
        style = Map.get(declared, name) || %{}

        %{
          name: name,
          swatch: swatch(style),
          summary: summary(style),
          shadows: name in Theme.style_names(theme)
        }
      end
    end

    # The theme's palette as rows, group by group: every entry of the theme, a name the
    # design declares kept in its group and marked, so the groups stay whole.
    defp theme_groups(design, theme) do
      declared = names(design)

      for {group, names} <- palette_groups(theme), names != [] do
        rows =
          for name <- names do
            %{
              name: name,
              shadowed: name in declared,
              preview: preview(theme, name, Theme.style(theme, name))
            }
          end

        {group, rows}
      end
    end

    defp swatch(style) do
      style = if is_map(style), do: Style.normalize(style), else: %{}

      case Enum.find_value([:fill, :stroke], &literal(get_in(style, [&1, :color]))) do
        nil -> nil
        color -> "background: " <> color
      end
    end

    defp literal("#" <> _rest = color), do: color
    defp literal(_other), do: nil

    defp summary(style) when map_size(style) == 0, do: "empty"
    defp summary(style), do: style |> Map.keys() |> Enum.sort() |> Enum.join(", ")
  end
end
