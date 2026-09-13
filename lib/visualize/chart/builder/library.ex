if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Library do
    @moduledoc """
    The builder's library: the store's fragments as a tree (spec/14 §18.16).

    A `Visualize.Chart.Builder.Store` is a flat map of name to fragment (§18.3), and a
    library of any size is unusable as a dropdown. The tree groups by what the **name**
    carries:

        <category>:<sub-category>:<fragment name>

    `Frame:axes:dense ticks` is `dense ticks`, under `axes`, under `Frame`. Nothing is
    classified anywhere else — no metadata beside the fragment, nothing derived from the keys
    it happens to set — so a category exists because some item names it, and inventing one is
    typing it (D-97).

    The parse is total and forgiving, because a store populated before this existed must keep
    working: two parts is a category and a name, one part is a name under `Uncategorised`, and
    an empty sub-category and the literal `none` are the same absent thing.

    This module compiles only when `Phoenix.Component` is loaded (spec/10 §1.1, D-45, D-85).
    """

    use Phoenix.Component

    alias Visualize.Chart.Builder.Store

    @separator ":"
    @uncategorised "Uncategorised"

    @typedoc "A stored name pulled apart: its category, its sub-category and its own name."
    @type place :: {String.t(), String.t() | nil, String.t()}

    @doc """
    A stored name as `{category, sub_category, name}` (spec/14 §18.16).

    The split takes the **first** two separators, so a fragment's own name may contain one.
    An absent sub-category is `nil`, which both an empty part and the literal `none` mean.

        iex> Visualize.Chart.Builder.Library.parse("Frame:axes:dense ticks")
        {"Frame", "axes", "dense ticks"}

        iex> Visualize.Chart.Builder.Library.parse("Styles::thick line")
        {"Styles", nil, "thick line"}

        iex> Visualize.Chart.Builder.Library.parse("Theme:none:dark")
        {"Theme", nil, "dark"}

        iex> Visualize.Chart.Builder.Library.parse("Frame:dense ticks")
        {"Frame", nil, "dense ticks"}

        iex> Visualize.Chart.Builder.Library.parse("dark")
        {"Uncategorised", nil, "dark"}

        iex> Visualize.Chart.Builder.Library.parse("Frame:aspect:2:1 aspect")
        {"Frame", "aspect", "2:1 aspect"}
    """
    @spec parse(String.t() | atom()) :: place()
    def parse(stored) do
      case stored |> to_string() |> String.split(@separator, parts: 3) do
        [category, sub, name] -> {blank(category, @uncategorised), absent(sub), name}
        [category, name] -> {blank(category, @uncategorised), nil, name}
        [name] -> {@uncategorised, nil, name}
      end
    end

    @doc """
    A category, sub-category and name as the name to store it under (spec/14 §18.16).

    The inverse of `parse/1` for every name this builds; `nil`, `""` and `"none"` are all
    written as the empty sub-category, so one absent sub-category has one spelling on disk.

        iex> Visualize.Chart.Builder.Library.name("Frame", "axes", "dense ticks")
        "Frame:axes:dense ticks"

        iex> Visualize.Chart.Builder.Library.name("Styles", nil, "thick line")
        "Styles::thick line"

        iex> Visualize.Chart.Builder.Library.name("Styles", "none", "thick line")
        "Styles::thick line"
    """
    @spec name(String.t(), String.t() | nil, String.t()) :: String.t()
    def name(category, sub_category, name) do
      Enum.join(
        [String.trim(category), absent(sub_category) || "", String.trim(name)],
        @separator
      )
    end

    @doc """
    Stored names as the tree the panel draws (spec/14 §18.16).

    One entry per category in name order; within it one group per sub-category, the unnamed
    group first and the rest in name order, because a fragment sitting directly under its
    category is the general case and the sub-categories refine it.

        iex> entries = [
        ...>   %{id: {:theme, 32}, name: "Theme::dark", kind: :theme},
        ...>   %{id: {:axis, 2}, name: "Frame:axes:dense", kind: :axis},
        ...>   %{id: {:size, 1}, name: "Frame::wide", kind: :size}
        ...> ]
        iex> Visualize.Chart.Builder.Library.tree(entries)
        [
          %{category: "Frame", groups: [
            %{sub_category: nil, items: [%{id: {:size, 1}, stored: "Frame::wide", name: "wide", kind: :size}]},
            %{sub_category: "axes", items: [%{id: {:axis, 2}, stored: "Frame:axes:dense", name: "dense", kind: :axis}]}
          ]},
          %{category: "Theme", groups: [
            %{sub_category: nil, items: [%{id: {:theme, 32}, stored: "Theme::dark", name: "dark", kind: :theme}]}
          ]}
        ]
    """
    @spec tree([map()]) :: [map()]
    def tree(entries) do
      entries
      |> Enum.map(fn entry -> {entry, parse(entry.name)} end)
      |> Enum.group_by(fn {_entry, {category, _sub, _name}} -> category end)
      |> Enum.sort_by(fn {category, _entries} -> category end)
      |> Enum.map(fn {category, entries} -> %{category: category, groups: groups(entries)} end)
    end

    @doc """
    The categories a set of stored names names, in name order.

        iex> Visualize.Chart.Builder.Library.categories(["Theme::dark", "Frame::wide"])
        ["Frame", "Theme"]
    """
    @spec categories([String.t() | atom()]) :: [String.t()]
    def categories(stored) do
      stored
      |> Enum.map(fn entry -> entry |> stored_name() |> parse() |> elem(0) end)
      |> Enum.uniq()
      |> Enum.sort()
    end

    @doc """
    The sub-categories one category has, in name order, without the unnamed group.

        iex> names = ["Frame:axes:dense", "Frame::wide", "Theme:mood:dark"]
        iex> Visualize.Chart.Builder.Library.sub_categories(names, "Frame")
        ["axes"]
    """
    @spec sub_categories([String.t() | atom()], String.t()) :: [String.t()]
    def sub_categories(stored, category) do
      stored
      |> Enum.map(&(&1 |> stored_name() |> parse()))
      |> Enum.filter(fn {named, sub, _name} -> named == category and is_binary(sub) end)
      |> Enum.map(fn {_category, sub, _name} -> sub end)
      |> Enum.uniq()
      |> Enum.sort()
    end

    # The kinds always shown by kind, empty or not: a `Scale` heading with nothing under it
    # says the library holds no scale yet, where an absent heading is indistinguishable
    # from a bug (spec/14 §19.8). Any other kind appears only when an entry has it.
    @shown_kinds [
      :composite,
      :theme,
      :style,
      :frame,
      :scale,
      :axis,
      :source,
      :var,
      :mark,
      :label
    ]

    @doc """
    Entries as the kind tree (spec/14 §19.8): one group per kind, the kinds a library item
    is usually one of always present, empty or not, and any other kind when an entry has
    it. Items within a kind sort by name; each carries its group as a second line.

        iex> entries = [
        ...>   %{id: {:style, 1}, name: "Styles::thick", kind: :style},
        ...>   %{id: {:size, 1}, name: "Frame:size:wide", kind: :size}
        ...> ]
        iex> tree = Visualize.Chart.Builder.Library.by_kind(entries)
        iex> Enum.map(tree, &{&1.kind, length(&1.items)})
        [composite: 0, theme: 0, style: 1, frame: 0, scale: 0, axis: 0, source: 0, var: 0, mark: 0, label: 0, size: 1]
    """
    @spec by_kind([map()]) :: [%{kind: atom(), items: [map()]}]
    def by_kind(entries) do
      present = entries |> Enum.map(& &1.kind) |> Enum.uniq()
      kinds = @shown_kinds ++ Enum.sort(present -- @shown_kinds)

      for kind <- kinds do
        items =
          entries
          |> Enum.filter(&(&1.kind == kind))
          |> Enum.map(fn entry ->
            {category, sub, name} = parse(entry.name)

            %{
              id: entry.id,
              stored: entry.name,
              name: name,
              kind: entry.kind,
              where: Enum.join(Enum.reject([category, sub], &is_nil/1), " / ")
            }
          end)
          |> Enum.sort_by(& &1.name)

        %{kind: kind, items: items}
      end
    end

    attr(:entries, :list,
      required: true,
      doc: "the store's entries, as `Store.list/1` returns them"
    )

    attr(:view, :atom, default: :group, doc: "`:group`, the default, or `:kind` (spec/14 §19.8)")

    attr(:open, :any, default: nil, doc: "the id last acted on, marked in the tree")
    attr(:target, :any, default: nil, doc: "the `phx-target` of the library's events")
    attr(:id, :string, required: true, doc: "the hook element's id")
    attr(:class, :string, default: nil, doc: "appended to the library's class")

    @doc """
    Renders the library (spec/10 §15.3).

    An `<aside class="vis-builder-library-pane">` holding one section per category, each with
    one list per sub-category, each item draggable by its stored name.
    """
    def panel(assigns) do
      assigns =
        assigns
        |> assign(:tree, tree(assigns.entries))
        |> assign(:kinds, by_kind(assigns.entries))

      ~H"""
      <aside id={@id} class={class(@class)} phx-hook="BuilderHook" data-builder-target={@target}>
        <h2 class="vis-builder-sidebar-title vis-builder-sidebar-title-row">
          Library
          <button
            type="button"
            class="vis-builder-library-fold"
            title="hide the library"
            aria-label="hide the library"
            aria-expanded="true"
            phx-click="library_fold"
            phx-target={@target}
          >◂</button>
        </h2>
        <nav class="vis-builder-views">
          <button
            type="button"
            class={view_class(@view == :group)}
            phx-click="library_view"
            phx-value-view="group"
            phx-target={@target}
          >group</button>
          <button
            type="button"
            class={view_class(@view == :kind)}
            phx-click="library_view"
            phx-value-view="kind"
            phx-target={@target}
          >kind</button>
        </nav>
        <p :if={@tree == [] and @view == :group} class="vis-builder-library-empty">
          The store holds nothing yet.
        </p>
        <section :for={group <- @kinds} :if={@view == :kind} class="vis-builder-category">
          <h3 class={kind_class(group.items == [])}>{group.kind}</h3>
          <p :if={group.items == []} class="vis-builder-kind-empty">none yet</p>
          <ul :if={group.items != []} class="vis-builder-group-items">
            <li
              :for={item <- group.items}
              class={item_class(item.id == @open)}
              draggable="true"
              data-builder-fragment={Store.encode_id(item.id)}
              title={says(item)}
              aria-label={says(item)}
              role="button"
              tabindex="0"
              phx-click="add_layer"
              phx-keydown="fragment_key"
              phx-value-name={Store.encode_id(item.id)}
              phx-target={@target}
            >
              <span class="vis-builder-fragment">{item.name}</span>
              <span :if={item.where != ""} class="vis-builder-fragment-where">{item.where}</span>
            </li>
          </ul>
        </section>
        <section :for={category <- @tree} :if={@view == :group} class="vis-builder-category">
          <h3 class="vis-builder-category-name">{category.category}</h3>
          <div :for={group <- category.groups} class="vis-builder-group">
            <h4 :if={group.sub_category} class="vis-builder-group-name">{group.sub_category}</h4>
            <ul class="vis-builder-group-items">
              <li
                :for={item <- group.items}
                class={item_class(item.id == @open)}
                draggable="true"
                data-builder-fragment={Store.encode_id(item.id)}
                title={says(item)}
                aria-label={says(item)}
                role="button"
                tabindex="0"
                phx-click="add_layer"
                phx-keydown="fragment_key"
                phx-value-name={Store.encode_id(item.id)}
                phx-target={@target}
              >
                <span class="vis-builder-fragment">{item.name}</span>
              </li>
            </ul>
          </div>
        </section>
      </aside>
      """
    end

    defp class(nil), do: "vis-builder-library-pane"
    defp class(extra), do: "vis-builder-library-pane " <> extra

    defp item_class(true), do: "vis-builder-item vis-builder-item-open"
    defp item_class(false), do: "vis-builder-item"

    defp view_class(true), do: "vis-builder-view vis-builder-view-on"
    defp view_class(false), do: "vis-builder-view"

    # What the item is and what its keys do, for hover and for what is announced (§18.17).
    defp says(item) do
      "#{item.stored} · #{Store.encode_id(item.id)}: Enter to open, Insert to add above the " <>
        "selected layer, drag into the stack"
    end

    defp kind_class(true), do: "vis-builder-category-name vis-builder-category-empty"
    defp kind_class(false), do: "vis-builder-category-name"

    # The sub-categories of one category's entries: the unnamed group first, the rest by name.
    defp groups(entries) do
      entries
      |> Enum.group_by(fn {_entry, {_category, sub, _name}} -> sub end)
      |> Enum.sort_by(fn {sub, _entries} -> {sub != nil, sub} end)
      |> Enum.map(fn {sub, group} ->
        %{
          sub_category: sub,
          items:
            group
            |> Enum.map(fn {entry, {_category, _sub, name}} ->
              %{id: entry.id, stored: entry.name, name: name, kind: entry.kind}
            end)
            |> Enum.sort_by(& &1.name)
        }
      end)
    end

    # A bare name, or an entry carrying one.
    defp stored_name(%{name: name}), do: name
    defp stored_name(name), do: name

    defp blank("", fallback), do: fallback
    defp blank(value, _fallback), do: value

    defp absent(nil), do: nil
    defp absent(""), do: nil
    defp absent("none"), do: nil
    defp absent(value), do: value
  end
end
