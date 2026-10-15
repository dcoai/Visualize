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

    alias Visualize.Chart.Builder.{Palette, Store}
    alias Visualize.Chart.Style
    alias Visualize.Theme

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
        [%{index: 0, name: "series", kind: :name, local: false, default: false}]

        iex> Visualize.Chart.Builder.StyleStack.entries([:series, {:field, :health}, {:generate, :tenant_style, [{:field, :tenant}]}, %{stroke: %{width: 5}}], nil)
        [
          %{index: 0, name: "series", kind: :name, local: false, default: false},
          %{index: 1, name: "field health", kind: :field, local: false, default: false},
          %{index: 2, name: "generate tenant_style(field tenant)", kind: :generator, local: false, default: false},
          %{index: 3, name: "local", kind: :local, local: true, default: false}
        ]

        iex> Visualize.Chart.Builder.StyleStack.entries(nil, :label)
        [%{index: 0, name: "label", kind: :name, local: false, default: true}]

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
      %{index: index, name: "local", kind: :local, local: true, default: default?}
    end

    # A style named by data shows the field whose value names it (spec/14 §3.6, #644).
    defp row({:field, field}, index, default?) do
      %{index: index, name: "field #{field}", kind: :field, local: false, default: default?}
    end

    # A generator entry shows its call, a field argument as the field (§3.13, #686).
    defp row({:generate, name, args}, index, default?) do
      call = "generate #{name}(#{Enum.map_join(List.wrap(args), ", ", &argument/1)})"
      %{index: index, name: call, kind: :generator, local: false, default: default?}
    end

    defp row({kind, n} = id, index, default?) when is_atom(kind) and is_integer(n) do
      %{index: index, name: Store.encode_id(id), kind: :name, local: false, default: default?}
    end

    defp row(one, index, default?) do
      %{index: index, name: to_string(one), kind: :name, local: false, default: default?}
    end

    defp argument({:field, field}), do: "field #{field}"
    defp argument(value), do: inspect(value)

    @doc """
    The columns a site's data has, offered by + field (spec/14 §18.18, #686): the declared
    `fields` of the source the node's `data` names, and the columns of `pool`'s rows for it,
    sorted; none where the node binds no source.

        iex> design = %{sources: %{load: %{fields: [:t, :v]}}}
        iex> Visualize.Chart.Builder.StyleStack.columns(design, %{data: :load}, %{load: [%{t: 0, v: 1, host: "a"}]})
        [:host, :t, :v]

        iex> Visualize.Chart.Builder.StyleStack.columns(%{}, %{}, %{})
        []
    """
    @spec columns(map(), term(), map()) :: [atom()]
    def columns(design, node, pool) do
      case source_of(node) do
        nil ->
          []

        source ->
          declared = get_in(design, [:sources, source, :fields]) || []

          rows =
            case Visualize.Data.Table.rows(Map.get(pool, source, [])) do
              [first | _] when is_map(first) -> Map.keys(first)
              _none -> []
            end

          (declared ++ rows)
          |> Enum.filter(&is_atom/1)
          |> Enum.uniq()
          |> Enum.sort()
      end
    end

    defp source_of(%{data: source}) when is_atom(source) and source != nil, do: source
    defp source_of(%{data: %{source: source}}) when is_atom(source), do: source
    defp source_of(_node), do: nil

    @doc """
    The generators a builder knows, offered by + generator (spec/14 §18.18, #686): the
    registry of `modules` and the host's configuration, each as `{name, arguments}` — its
    arity less the context — by name.
    """
    @spec generators([module()]) :: [{atom(), non_neg_integer()}]
    def generators(modules) do
      modules
      |> Visualize.Generators.registry()
      |> Map.keys()
      |> Enum.map(fn {name, arity} -> {name, arity - 1} end)
      |> Enum.sort()
    end

    @doc """
    The names a style entry may take, grouped (spec/14 §18.14, §18.18, #685): what the
    stacked design declares, then the theme's palette group by group — the built-in four
    are its furniture.

        iex> choices = Visualize.Chart.Builder.StyleStack.choices(%{styles: %{series: %{}}}, Visualize.Theme.default())
        iex> hd(choices)
        {"design", [:series]}
        iex> {"furniture", furniture} = List.keyfind(choices, "furniture", 0)
        iex> Enum.all?([:axis, :grid, :label, :title], &(&1 in furniture))
        true
    """
    @spec choices(map(), Theme.t()) :: [{String.t(), [atom()]}]
    def choices(design, %Theme{} = theme), do: Palette.groups(design, theme)

    @doc """
    The site's stack cascaded in its parts, as the panel shows it (spec/14 §18.19, D-178).

    The design's declared styles over the palette of `theme` — the design's own, the one
    its chart is drawn with (#685) — then the entries resolved left
    to right by §3.6 and merged part by part by §3.5 — `Visualize.Chart.Style`'s own rule,
    asked here for one site, before any projection onto the element keys. A field entry
    and a generator lay nothing, since the panel has no datum to read.

        iex> design = %{styles: %{series: %{stroke: "#111", stroke_width: 2}}}
        iex> Visualize.Chart.Builder.StyleStack.resolved(design, [:series, %{stroke: %{width: 5}}], Visualize.Theme.default())
        %{stroke: %{type: :solid, color: "#111", width: 5}}
    """
    @spec resolved(map(), term(), Theme.t()) :: map()
    def resolved(design, value, %Theme{} = theme) do
      design
      |> Map.get(:styles, %{})
      |> Style.all(theme)
      |> Style.compound(value, fn _entry -> nil end)
    end

    @doc """
    Which entry supplied each key of the resolved style (spec/14 §18.19), by its path: a
    whole element's key by its key, a part's by `part.key` — one part is often several
    entries' (a stroke's colour from `series`, its width from `local`).

    A resolved style is a cascade, so a value belongs to the last entry that set it. This is
    `Visualize.Chart.explain/1`'s question asked at a site: which style said this.

        iex> design = %{styles: %{series: %{stroke: "#111", stroke_width: 2}, faded: %{opacity: 0.5}}}
        iex> Visualize.Chart.Builder.StyleStack.origins(design, [:series, :faded, %{stroke: %{width: 5}}], Visualize.Theme.default())
        %{:opacity => "faded", "stroke.color" => "series", "stroke.type" => "series", "stroke.width" => "local"}
    """
    @spec origins(map(), term(), Theme.t()) :: %{(atom() | String.t()) => String.t()}
    def origins(design, value, %Theme{} = theme) do
      styles = design |> Map.get(:styles, %{}) |> Style.all(theme)

      value
      |> List.wrap()
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {one, index}, origins ->
        name = one |> row(index, false) |> Map.fetch!(:name)

        styles
        |> Style.compound(one, fn _entry -> nil end)
        |> leaves([])
        |> Enum.reduce(origins, &Map.put(&2, &1, name))
      end)
    end

    # The paths a node in its parts sets: a whole element's key as itself, a part's keys —
    # and a nested node's, a transition's per property — joined by `.`.
    defp leaves(node, prefix) do
      Enum.flat_map(node, fn
        {key, value} when is_map(value) and not is_struct(value) -> leaves(value, prefix ++ [key])
        {key, _value} when prefix == [] -> [key]
        {key, _value} -> [Enum.map_join(prefix ++ [key], ".", &to_string/1)]
      end)
    end

    attr(:id, :string, required: true, doc: "the hook element's id")
    attr(:value, :any, default: nil, doc: "the site's `style` value, in any shape of §3.6")
    attr(:fallback, :atom, default: nil, doc: "the schema's default for this site")
    attr(:design, :map, default: %{}, doc: "the stacked design, for the names on offer")

    attr(:theme, :any,
      default: nil,
      doc: "the theme whose palette is on offer; the default's when nil"
    )

    attr(:columns, :list, default: [], doc: "the columns the site's data has, for + field")

    attr(:generators, :list,
      default: [],
      doc: "the generators the builder knows, `{name, arguments}`, for + generator"
    )

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
        |> assign(:choices, choices(assigns.design, assigns.theme || Theme.default()))

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
            tabindex={if(entry.default, do: nil, else: "0")}
            phx-click="select_style_entry"
            phx-keydown={if(entry.default, do: nil, else: "style_entry_key")}
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
            <optgroup :for={{group, names} <- @choices} label={group}>
              <option :for={name <- names} value={name}>{name}</option>
            </optgroup>
          </select>
          <button type="submit" class="vis-builder-style-append">Add style</button>
        </form>
        <form
          :if={@columns != []}
          id={@id <> "-add-field"}
          class="vis-builder-style-add"
          phx-submit="add_style_entry"
          phx-target={@target}
        >
          <select name="field" class="vis-builder-style-choice" aria-label="a column whose value names the style">
            <option :for={column <- @columns} value={column}>{column}</option>
          </select>
          <button type="submit" class="vis-builder-style-append">+ field</button>
        </form>
        <form
          :if={@generators != []}
          id={@id <> "-add-generator"}
          class="vis-builder-style-add"
          phx-submit="add_style_entry"
          phx-target={@target}
        >
          <select name="generator" class="vis-builder-style-choice" aria-label="a generator">
            <option :for={{name, arguments} <- @generators} value={"#{name}/#{arguments}"}>{name}/{arguments}</option>
          </select>
          <input type="text" name="args" class="vis-builder-style-args" placeholder="[{:field, :tenant}]" aria-label="the generator's arguments, a list" />
          <button type="submit" class="vis-builder-style-append">+ generator</button>
        </form>
      </div>
      """
    end

    defp class(nil), do: "vis-builder-style-stack"
    defp class(extra), do: "vis-builder-style-stack " <> extra

    defp entry_class(entry, open) do
      ["vis-builder-style-entry"]
      |> Kernel.++(["vis-builder-style-entry-#{entry.kind}"])
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
