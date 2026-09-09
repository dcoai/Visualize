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

        iex> Visualize.Chart.Builder.Library.tree(["Theme::dark", "Frame:axes:dense", "Frame::wide"])
        [
          %{category: "Frame", groups: [
            %{sub_category: nil, items: [%{stored: "Frame::wide", name: "wide"}]},
            %{sub_category: "axes", items: [%{stored: "Frame:axes:dense", name: "dense"}]}
          ]},
          %{category: "Theme", groups: [
            %{sub_category: nil, items: [%{stored: "Theme::dark", name: "dark"}]}
          ]}
        ]
    """
    @spec tree([String.t() | atom()]) :: [map()]
    def tree(stored_names) do
      stored_names
      |> Enum.map(fn stored -> {to_string(stored), parse(stored)} end)
      |> Enum.group_by(fn {_stored, {category, _sub, _name}} -> category end)
      |> Enum.sort_by(fn {category, _entries} -> category end)
      |> Enum.map(fn {category, entries} -> %{category: category, groups: groups(entries)} end)
    end

    @doc """
    The categories a set of stored names names, in name order.

        iex> Visualize.Chart.Builder.Library.categories(["Theme::dark", "Frame::wide"])
        ["Frame", "Theme"]
    """
    @spec categories([String.t() | atom()]) :: [String.t()]
    def categories(stored_names) do
      stored_names
      |> Enum.map(fn stored -> stored |> parse() |> elem(0) end)
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
    def sub_categories(stored_names, category) do
      stored_names
      |> Enum.map(&parse/1)
      |> Enum.filter(fn {named, sub, _name} -> named == category and is_binary(sub) end)
      |> Enum.map(fn {_category, sub, _name} -> sub end)
      |> Enum.uniq()
      |> Enum.sort()
    end

    attr(:names, :list, required: true, doc: "the store's names, as `Store.list/0` returns them")
    attr(:open, :string, default: nil, doc: "the stored name last acted on, marked in the tree")
    attr(:target, :any, default: nil, doc: "the `phx-target` of the library's events")
    attr(:id, :string, required: true, doc: "the hook element's id")
    attr(:class, :string, default: nil, doc: "appended to the library's class")

    @doc """
    Renders the library (spec/10 §15.3).

    An `<aside class="vis-builder-library-pane">` holding one section per category, each with
    one list per sub-category, each item draggable by its stored name.
    """
    def panel(assigns) do
      assigns = assign(assigns, :tree, tree(assigns.names))

      ~H"""
      <aside id={@id} class={class(@class)} phx-hook="BuilderHook" data-builder-target={@target}>
        <h2 class="vis-builder-sidebar-title">Library</h2>
        <p :if={@tree == []} class="vis-builder-library-empty">The store holds nothing yet.</p>
        <section :for={category <- @tree} class="vis-builder-category">
          <h3 class="vis-builder-category-name">{category.category}</h3>
          <div :for={group <- category.groups} class="vis-builder-group">
            <h4 :if={group.sub_category} class="vis-builder-group-name">{group.sub_category}</h4>
            <ul class="vis-builder-group-items">
              <li
                :for={item <- group.items}
                class={item_class(item.stored == @open)}
                draggable="true"
                data-builder-fragment={item.stored}
                title={"Drag " <> item.stored <> " into the layers, or click to add it on top"}
                role="button"
                tabindex="0"
                phx-click="add_layer"
                phx-value-name={item.stored}
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

    # The sub-categories of one category's entries: the unnamed group first, the rest by name.
    defp groups(entries) do
      entries
      |> Enum.group_by(fn {_stored, {_category, sub, _name}} -> sub end)
      |> Enum.sort_by(fn {sub, _entries} -> {sub != nil, sub} end)
      |> Enum.map(fn {sub, group} ->
        %{
          sub_category: sub,
          items:
            group
            |> Enum.map(fn {stored, {_category, _sub, name}} -> %{stored: stored, name: name} end)
            |> Enum.sort_by(& &1.name)
        }
      end)
    end

    defp blank("", fallback), do: fallback
    defp blank(value, _fallback), do: value

    defp absent(nil), do: nil
    defp absent(""), do: nil
    defp absent("none"), do: nil
    defp absent(value), do: value
  end
end
