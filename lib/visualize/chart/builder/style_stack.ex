if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.StyleStack do
    @moduledoc """
    The stack of styles at one site (spec/14 §18.18).

    §3.6 gives every style site a stack — a reference, an inline node, or a list of either.
    This is the control over it: one row per entry in **resolution order**, the first applied
    first and the last winning, because that is the order the cascade is defined in and a
    panel that reversed it would teach the opposite of the specification.

    A row is the control, as a layer row is (§18.17): it carries the click and the drag
    itself, because a `<button>` spanning a draggable row defeats both gestures. Each row can
    be selected, removed, and dragged to a position.

    An inline entry is drawn as `local`: it is where an edit at the site lands, there is at
    most one, and it is created on first edit rather than sitting empty in every document
    (D-98).

    This module compiles only when `Phoenix.Component` is loaded (spec/10 §1.1, D-45, D-85).
    """

    use Phoenix.Component

    alias Visualize.Chart.{Schema, Style}

    @typedoc "One row of the stack: what it is, what to call it, and where it sits."
    @type entry :: %{
            index: non_neg_integer(),
            name: String.t(),
            local: boolean(),
            default: boolean()
          }

    @doc """
    A `style` value as the rows to draw (spec/14 §18.18).

    Total over the three shapes of §3.6, and over a site that carries no `style` key at all:
    the schema's default for that site is shown as the row it will resolve as, marked
    `default: true` so the panel can say it is not something the design states.

        iex> Visualize.Chart.Builder.StyleStack.entries(:series, nil)
        [%{index: 0, name: "series", local: false, default: false}]

        iex> Visualize.Chart.Builder.StyleStack.entries([:series, %{stroke_width: 5}], nil)
        [
          %{index: 0, name: "series", local: false, default: false},
          %{index: 1, name: "local", local: true, default: false}
        ]

        iex> Visualize.Chart.Builder.StyleStack.entries(nil, :label)
        [%{index: 0, name: "label", local: false, default: true}]

        iex> Visualize.Chart.Builder.StyleStack.entries(nil, nil)
        []
    """
    @spec entries(term(), atom() | nil) :: [entry()]
    def entries(nil, nil), do: []
    def entries(nil, fallback), do: [row(fallback, 0, true)]

    def entries(value, _fallback) when is_list(value) do
      for {one, index} <- Enum.with_index(value), do: row(one, index, false)
    end

    def entries(value, _fallback), do: [row(value, 0, false)]

    defp row(one, index, default?) when is_map(one) do
      %{index: index, name: "local", local: true, default: default?}
    end

    defp row(one, index, default?) do
      %{index: index, name: to_string(one), local: false, default: default?}
    end

    @doc """
    The names a style entry may take: what the stacked design declares, and the built-in
    four (spec/14 §3.3, §18.14).

        iex> Visualize.Chart.Builder.StyleStack.choices(%{styles: %{series: %{}}})
        [:axis, :grid, :label, :series, :title]
    """
    @spec choices(map()) :: [atom()]
    def choices(design) do
      declared =
        case Map.get(design, :styles) do
          map when is_map(map) -> Map.keys(map)
          _absent -> []
        end

      (declared ++ Schema.builtin_styles()) |> Enum.uniq() |> Enum.sort()
    end

    @doc """
    The site's stack cascaded, as the panel shows it (spec/14 §18.19).

    The design's declared styles over the built-in four, then the entries resolved left to
    right by §3.6 — which is `Visualize.Chart.Style`'s own rule, asked here for one site.

        iex> design = %{styles: %{series: %{stroke_width: 2}}}
        iex> Visualize.Chart.Builder.StyleStack.resolved(design, [:series, %{stroke_width: 5}])
        %{stroke_width: 5}
    """
    @spec resolved(map(), term()) :: map()
    def resolved(design, value) do
      design |> Map.get(:styles, %{}) |> Style.all() |> Style.node(value)
    end

    @doc """
    Which entry supplied each key of the resolved style (spec/14 §18.19).

    A resolved style is a cascade, so a value belongs to the last entry that set it. This is
    `Visualize.Chart.explain/1`'s question asked at a site: which style said this.

        iex> design = %{styles: %{series: %{stroke: "#111", stroke_width: 2}}}
        iex> Visualize.Chart.Builder.StyleStack.origins(design, [:series, %{stroke_width: 5}])
        %{stroke: "series", stroke_width: "local"}
    """
    @spec origins(map(), term()) :: %{atom() => String.t()}
    def origins(design, value) do
      styles = design |> Map.get(:styles, %{}) |> Style.all()

      value
      |> List.wrap()
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {one, index}, origins ->
        name = one |> row(index, false) |> Map.fetch!(:name)

        styles
        |> Style.node(one)
        |> Map.keys()
        |> Enum.reduce(origins, &Map.put(&2, &1, name))
      end)
    end

    attr(:id, :string, required: true, doc: "the hook element's id")
    attr(:value, :any, default: nil, doc: "the site's `style` value, in any shape of §3.6")
    attr(:fallback, :atom, default: nil, doc: "the schema's default for this site")
    attr(:design, :map, default: %{}, doc: "the stacked design, for the names on offer")
    attr(:open, :integer, default: nil, doc: "the entry the context panel is on")
    attr(:target, :any, default: nil, doc: "the `phx-target` of the panel's events")
    attr(:class, :string, default: nil, doc: "appended to the panel's class")

    @doc """
    Renders the stack at a site (spec/10 §15.3).

    An `<ol class="vis-builder-style-stack">` carrying `BuilderHook` at scope `style`, with
    one `<li class="vis-builder-style-entry">` per entry at its zero-based position.
    """
    def panel(assigns) do
      assigns =
        assigns
        |> assign(:entries, entries(assigns.value, assigns.fallback))
        |> assign(:choices, choices(assigns.design))

      ~H"""
      <div class={class(@class)}>
        <h3 class="vis-builder-style-title">Style</h3>
        <ol
          id={@id}
          class="vis-builder-style-entries"
          phx-hook="BuilderHook"
          data-builder-target={@target}
          data-builder-stack="true"
          data-builder-scope="style"
        >
          <li
            :for={entry <- @entries}
            class={entry_class(entry, @open)}
            data-builder-layer={entry.index}
            data-builder-end={entry.index + 1}
            draggable={not entry.default}
            title={title(entry)}
            phx-click="select_style_entry"
            phx-value-index={entry.index}
            phx-target={@target}
          >
            <span class="vis-builder-style-name">{entry.name}</span>
            <button
              :if={not entry.default}
              type="button"
              draggable="false"
              class="vis-builder-style-remove"
              title={"Remove " <> entry.name}
              aria-label={"Remove " <> entry.name}
              phx-click="remove_style_entry"
              phx-value-index={entry.index}
              phx-target={@target}
            ><span class="vis-builder-action-label">Remove</span></button>
          </li>
        </ol>
        <form id={@id <> "-add"} class="vis-builder-style-add" phx-submit="add_style_entry" phx-target={@target}>
          <select name="name" class="vis-builder-style-choice">
            <option :for={name <- @choices} value={name}>{name}</option>
          </select>
          <button type="submit" class="vis-builder-style-append">Add style</button>
        </form>
      </div>
      """
    end

    defp class(nil), do: "vis-builder-style-stack"
    defp class(extra), do: "vis-builder-style-stack " <> extra

    defp entry_class(entry, open) do
      ["vis-builder-style-entry"]
      |> then(&if entry.local, do: &1 ++ ["vis-builder-style-entry-local"], else: &1)
      |> then(&if entry.default, do: &1 ++ ["vis-builder-style-entry-default"], else: &1)
      |> then(&if entry.index == open, do: &1 ++ ["vis-builder-style-entry-open"], else: &1)
      |> Enum.join(" ")
    end

    defp title(%{default: true, name: name}),
      do: "#{name} — the default for this site, which the design does not state"

    defp title(%{local: true}), do: "the local style: edits at this site land here"
    defp title(%{name: name}), do: "#{name} — click to inspect, drag to reorder"
  end
end
