if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Page do
    @moduledoc """
    A root tab as one page of sections (spec/14 §18.15, #249).

    A node's keys are grouped by facet into collapsible sections; a key that holds a node
    — one, a map of them or a list — is not a textarea in its facet's section but a
    **sub-section** inside it, titled by the node's label, itself a page, so the whole
    subtree under a root reads as one page and nothing is listed twice. The frame's page
    reads as a frame: kind, then the design's name and description (the `meta` node),
    then *size* — the `size` and `margin` nodes together — then *binding*, then its parts.
    Every form on the page carries its node's label, so an edit anywhere aims at its node.

    This module compiles only when `Phoenix.Component` is loaded (spec/10 §1.1, D-45, D-85).
    """

    use Phoenix.Component

    alias Visualize.Chart.Builder.Editor
    alias Visualize.Chart.{Schema, Var}

    @facets [:binding, :channel, :geometry, :style, :content]

    attr(:id, :string, required: true, doc: "the page's id; sub-sections extend it")
    attr(:kind, :atom, required: true, doc: "the node kind")
    attr(:node, :map, required: true, doc: "the node's value")
    attr(:path, :list, required: true, doc: "where the node sits in the design")
    attr(:label, :string, required: true, doc: "the node's label, as `Editor.label/1` spells it")

    attr(:before, :list,
      default: [],
      doc: "forms shown first: `%{kind, node, path, label}` (the frame's meta)"
    )

    attr(:collapsed, :any,
      default: MapSet.new(),
      doc: "the section keys folded shut (`toggle_section`)"
    )

    attr(:errors, :list, default: [], doc: "the design's faults")
    attr(:refs, :map, default: %{})
    attr(:selected, :string, default: nil, doc: "the selected field's key")

    attr(:selected_node, :string,
      default: nil,
      doc: "the label of the node the selected field is in"
    )

    attr(:found, :string, default: nil)
    attr(:theme, :any, default: nil)
    attr(:defs, :map, default: %{})
    attr(:pool, :list, default: [])
    attr(:hidden, :list, default: [])
    attr(:columns, :map, default: %{})
    attr(:source_name, :any, default: nil)
    attr(:origins, :map, default: %{})
    attr(:target, :any, default: nil)
    attr(:depth, :integer, default: 0)

    @doc "Renders a node as a page of sections, its sub-nodes as sub-sections."
    def page(assigns) do
      assigns = assign(assigns, sections: sections(assigns))

      ~H"""
      <div class={"vis-builder-page vis-builder-page-#{@depth}"}>
        <.form_for :for={extra <- @before} page={assigns} kind={extra.kind} node={extra.node} path={extra.path} label={extra.label} only={extra[:only]} suffix="before" />
        <%= for section <- @sections do %>
          <.form_for :if={section.bare} page={assigns} kind={@kind} node={@node} path={@path} label={@label} only={section.keys} suffix={section.name} />
          <details :if={not section.bare} class={section_class(section)} open={not MapSet.member?(@collapsed, section.key)}>
            <summary
              class="vis-builder-section-title"
              title={section.title}
              phx-click="toggle_section"
              phx-value-section={section.key}
              phx-target={@target}
            >{section.name}</summary>
            <.form_for :if={section.keys != []} page={assigns} kind={@kind} node={@node} path={@path} label={@label} only={section.keys} suffix={section.name} />
            <.form_for :for={form <- section.forms} page={assigns} kind={form.kind} node={form.node} path={form.path} label={form.label} />
            <details :for={child <- section.children} class={child_class(child)} open={not MapSet.member?(@collapsed, child.label)}>
              <summary
                class="vis-builder-section-title vis-builder-subsection-title"
                title={child.title}
                phx-click="toggle_section"
                phx-value-section={child.label}
                phx-target={@target}
              >{child.name}</summary>
              <.page
                id={@id <> "-" <> slug(child.label)}
                kind={child.kind}
                node={child.node}
                path={child.path}
                label={child.label}
                collapsed={@collapsed}
                errors={@errors}
                refs={@refs}
                selected={@selected}
                selected_node={@selected_node}
                found={@found}
                theme={@theme}
                defs={@defs}
                pool={@pool}
                hidden={@hidden}
                columns={@columns}
                source_name={@source_name}
                origins={@origins}
                target={@target}
                depth={@depth + 1}
              />
            </details>
          </details>
        <% end %>
      </div>
      """
    end

    attr(:page, :map, required: true)
    attr(:kind, :atom, required: true)
    attr(:node, :any, required: true)
    attr(:path, :list, required: true)
    attr(:label, :string, required: true)
    attr(:only, :any, default: nil)

    attr(:suffix, :string,
      default: "form",
      doc: "what tells this form's id from the node's others"
    )

    # One form of the page, with the page's context; a node that is a variable shows as one.
    defp form_for(assigns) do
      ~H"""
      <p :if={is_struct(@node, Var)} class="vis-builder-context-note">
        {@label} = var(:{@node.name})
      </p>
      <Editor.form_body
        :if={not is_struct(@node, Var)}
        id={@page.id <> "-" <> slug(@label) <> "-" <> @suffix}
        kind={@kind}
        node={@node || %{}}
        path={@path}
        label={@label}
        only={@only}
        errors={@page.errors}
        refs={@page.refs}
        selected={if(@page.selected_node == @label, do: @page.selected)}
        found={@page.found}
        theme={@page.theme}
        defs={@page.defs}
        pool={@page.pool}
        hidden={@page.hidden}
        columns={@page.columns}
        source_name={@page.source_name}
        origins={@page.origins}
        target={@page.target}
      />
      """
    end

    # -- the sections (spec/14 §18.15) ----------------------------------------------------

    @doc """
    The sections of a node's page: for each facet, the keys that are values and the child
    nodes the facet's node keys hold; a frame's are its own — kind first, bare, then *size*
    (the size and margin nodes together), *binding*, then the parts.

        iex> page = %{kind: :mark, node: %{type: :line, data: :p, channels: %{x: :t}, options: %{}}, path: [:marks, 0], label: "marks[0]", errors: []}
        iex> for s <- Enum.take(Visualize.Chart.Builder.Page.sections(page), 3), do: {s.name, s.keys, Enum.map(s.children, & &1.label)}
        [{"binding", [:data], []}, {"channel", [:type, :scales], ["marks[0].channels"]}, {"geometry", [:render], ["marks[0].options"]}]

    A node key the node does not carry yet — the mark's `scales` above — stays a field, so
    the node can be given there; once it is, it is a sub-section.
    """
    @spec sections(map()) :: [map()]
    def sections(%{kind: :frame} = page) do
      node = page.node
      specs = Schema.describe(:frame)

      parts =
        for spec <- specs,
            spec.key not in [:kind, :size, :margin, :facet],
            node?(spec.type),
            Map.has_key?(node, spec.key),
            do: spec

      [
        %{
          key: "#{page.label}:kind",
          name: "frame",
          title: "the frame's kind",
          bare: true,
          keys: [:kind],
          forms: [],
          children: [],
          needs: 0
        },
        %{
          key: "#{page.label}:size",
          name: "size",
          title: "the frame's size and margins",
          bare: false,
          keys: [],
          forms:
            for key <- [:size, :margin] do
              %{
                kind: key,
                node: Map.get(node, key, %{}),
                path: page.path ++ [key],
                label: Editor.label(page.path ++ [key])
              }
            end,
          children: [],
          needs: needs(page.errors, [page.path ++ [:size], page.path ++ [:margin]])
        },
        %{
          key: "#{page.label}:binding",
          name: "binding",
          title: "the frame's binding — a facet frame's panels",
          bare: false,
          keys: [],
          forms: [],
          children: children(Enum.find(specs, &(&1.key == :facet)), node, page),
          needs: needs(page.errors, [page.path ++ [:facet]])
        }
      ] ++
        for spec <- parts do
          kids = children(spec, node, page)

          %{
            key: "#{page.label}:#{spec.key}",
            name: to_string(spec.key),
            title: "the frame's #{spec.key}",
            bare: false,
            keys: [],
            forms: [],
            children: kids,
            needs: needs(page.errors, [page.path ++ [spec.key]])
          }
        end
    end

    def sections(page) do
      specs = Schema.describe(page.kind)
      node = page.node || %{}

      for facet <- @facets, own = Enum.filter(specs, &(&1.facet == facet)), own != [] do
        {nodes, values} = Enum.split_with(own, &(node?(&1.type) and holds_node?(node, &1)))
        keys = Enum.map(values, & &1.key)
        kids = Enum.flat_map(nodes, &children(&1, node, page))

        %{
          key: "#{page.label}:#{facet}",
          name: to_string(facet),
          title: "the #{page.kind}'s #{facet} keys",
          bare: false,
          keys: keys,
          forms: [],
          children: kids,
          needs: needs(page.errors, Enum.map(own, &(page.path ++ [&1.key])))
        }
      end
      |> Enum.reject(&(&1.keys == [] and &1.children == []))
    end

    # A key whose type admits a node.
    defp node?({:node, _}), do: true
    defp node?({:map, {:node, _}}), do: true
    defp node?({:list, {:node, _}}), do: true
    defp node?({:one_of, alts}), do: Enum.any?(alts, &node?/1)
    defp node?(_type), do: false

    # Whether the node's value under the key is a node (or nodes) rather than a value — a
    # style key holding a reference is a field, holding an inline style a sub-section.
    defp holds_node?(node, %{key: key, type: type}) do
      case {type, Map.get(node, key)} do
        {_type, nil} -> false
        {{:one_of, _}, value} -> is_map(value) and not is_struct(value)
        {_type, _value} -> true
      end
    end

    # The child nodes a key holds, each with its kind, path and label.
    defp children(nil, _node, _page), do: []

    defp children(%{key: key, type: type}, node, page) do
      case Map.get(node, key) do
        nil -> []
        value -> descend(type, value, page.path ++ [key])
      end
    end

    defp descend({:node, kind}, value, path) when is_map(value) and not is_struct(value),
      do: [child(kind, value, path)]

    defp descend({:map, {:node, kind}}, value, path)
         when is_map(value) and not is_struct(value) do
      value
      |> Enum.sort_by(fn {name, _} -> to_string(name) end)
      |> Enum.map(fn {name, node} -> child(kind, node, path ++ [name]) end)
    end

    defp descend({:list, {:node, kind}}, value, path) when is_list(value) do
      value |> Enum.with_index() |> Enum.map(fn {node, i} -> child(kind, node, path ++ [i]) end)
    end

    defp descend({:one_of, alts}, value, path) when is_map(value) and not is_struct(value) do
      case Enum.find(alts, &match?({:node, _}, &1)) do
        nil -> []
        inner -> descend(inner, value, path)
      end
    end

    defp descend(_type, _value, _path), do: []

    defp child(kind, node, path) do
      label = Editor.label(path)

      %{
        kind: kind,
        node: node,
        path: path,
        label: label,
        name: List.last(path) |> to_string(),
        title: label
      }
    end

    defp needs(errors, prefixes) do
      Enum.count(errors, fn {at, _reason} -> Enum.any?(prefixes, &List.starts_with?(at, &1)) end)
    end

    defp section_class(%{needs: n}) when n > 0,
      do: "vis-builder-section vis-builder-section-needs"

    defp section_class(_section), do: "vis-builder-section"

    defp child_class(_child), do: "vis-builder-section vis-builder-subsection"

    defp slug(label), do: label |> String.replace(~r/[^A-Za-z0-9]+/, "-") |> String.trim("-")
  end
end
