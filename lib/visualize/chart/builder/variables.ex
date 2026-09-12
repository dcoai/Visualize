if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Variables do
    @moduledoc """
    The variable panel (spec/14 §19.10): the composition's variables as chips, and what a
    person does with them.

    Every variable the stack declares or uses is listed alphabetically as a **chip** — the
    thing dragged onto a control to bind it (§19.9). A chip expands to its details: the
    type it took from its first use (§17.2), every use as a link to the node, its declared
    default, the value the preview binds it to, and the per-site rows of §19.4. A find box
    filters the list and names the variable whose fields the form highlights; a create
    form declares a new one as a `var` site of the stack.

    This module compiles only when `Phoenix.Component` is loaded (spec/10 §1.1, D-45, D-85).
    """

    use Phoenix.Component

    alias Visualize.Chart
    alias Visualize.Chart.Builder.Editor

    attr(:id, :string, required: true, doc: "the panel's id")

    attr(:layers, :list,
      required: true,
      doc: "the resolved layers, `{label, fragment}` in stack order"
    )

    attr(:design, :map, required: true, doc: "the stacked design, for what is declared")
    attr(:bindings, :map, default: %{}, doc: "the values the preview binds variables to")
    attr(:sites, :list, default: [], doc: "the per-site rows, as `Stack.sites/3` gives them")
    attr(:expanded, :any, default: nil, doc: "the names expanded, a `MapSet`")
    attr(:find, :string, default: "", doc: "the find box's text")
    attr(:target, :any, default: nil, doc: "the `phx-target` of the panel's events")

    @doc """
    Renders the variable panel: the chips, the find box, the create form, and each
    expanded chip's details.
    """
    def panel(assigns) do
      assigns = assign(assigns, :rows, rows(assigns))

      ~H"""
      <div
        id={@id}
        class="vis-builder-variables"
        phx-hook="BuilderHook"
        data-builder-target={@target}
        data-builder-scope="variables"
      >
        <form class="vis-builder-find" phx-change="find_variable" phx-target={@target}>
          <input
            type="search"
            name="find"
            value={@find}
            placeholder="find a variable"
            aria-label="find a variable"
            phx-debounce="150"
          />
        </form>
        <ul class="vis-builder-chips-list">
          <li :for={row <- @rows} class={"vis-builder-variable" <> if(row.expanded?, do: " vis-builder-variable-open", else: "")}>
            <div class="vis-builder-variable-row">
              <span
                class={"vis-builder-var-chip" <> if(row.found?, do: " vis-builder-var-chip-found", else: "")}
                draggable="true"
                data-builder-variable={row.name}
                title={"var(:#{row.name}) — drag onto a field to bind it"}
              >var(:{row.name})</span>
              <span class="vis-builder-variable-type">{row.type_word}</span>
              <button
                type="button"
                class="vis-builder-variable-expand"
                phx-click="expand_variable"
                phx-value-name={row.name}
                phx-target={@target}
                aria-expanded={to_string(row.expanded?)}
                aria-label={"details of #{row.name}"}
              >{if row.expanded?, do: "▾", else: "▸"}</button>
            </div>
            <div :if={row.expanded?} class="vis-builder-variable-details">
              <p :if={row.uses == []} class="vis-builder-context-note">declared, used nowhere yet</p>
              <ul :if={row.uses != []} class="vis-builder-variable-uses">
                <li :for={use <- row.uses}>
                  <button
                    type="button"
                    class="vis-builder-variable-use"
                    phx-click="inspect"
                    phx-value-path={use.path}
                    phx-value-layer={use.layer}
                    phx-target={@target}
                    title={"open #{use.path} in #{use.label}"}
                  >{use.label} → {use.path}</button>
                </li>
              </ul>
              <form class="vis-builder-variable-value" phx-change="set_var" phx-target={@target}>
                <label class="vis-builder-picker-row">
                  <span class="vis-builder-control-label">
                    value{if row.default != nil, do: " (default #{row.default})", else: ""}
                  </span>
                  <input type="text" name={row.name} value={row.value} placeholder={row.default} />
                </label>
              </form>
              <form
                :for={site <- row.sites}
                class="vis-builder-site"
                phx-change="bind_site"
                phx-target={@target}
              >
                <h4 class="vis-builder-site-name">{site.label}</h4>
                <input type="hidden" name="site" value={site.index} />
                <div class={"vis-builder-site-var vis-builder-site-var-" <> to_string(site.state)}>
                  <span class="vis-builder-site-state">{site.reads}</span>
                  <input
                    type="text"
                    name={row.name}
                    class="vis-builder-site-literal"
                    value={site.literal}
                    placeholder="a value here"
                    aria-label={"#{row.name} as a value at #{site.label}"}
                  />
                  <input
                    type="text"
                    name={row.name <> ".var"}
                    class="vis-builder-site-variable"
                    value={site.variable}
                    placeholder="or another variable"
                    aria-label={"#{row.name} as a variable at #{site.label}"}
                  />
                </div>
              </form>
            </div>
          </li>
        </ul>
        <p :if={@rows == []} class="vis-builder-context-note">no variables yet</p>
        <form
          class="vis-builder-create"
          phx-submit="create_variable"
          phx-target={@target}
          data-builder-promote-target="true"
        >
          <input type="text" name="name" placeholder="new variable" aria-label="new variable's name" />
          <input type="text" name="default" placeholder="default" aria-label="its default" />
          <button type="submit">Create</button>
          <p class="vis-builder-context-note">or drop a field's handle here to make a variable of its value</p>
        </form>
      </div>
      """
    end

    @doc """
    Every variable of the composition, alphabetically: what the stack still needs
    (`Visualize.Chart.free_vars/1`) and what it declares, each with the type its first use
    expects, or `nil` for one used nowhere.

        iex> layers = [{"a", %{vars: %{unit: %{default: "%"}}, labels: [%{anchor: :title, text: ["u ", Visualize.Chart.var(:unit)]}]}}]
        iex> [unit] = Visualize.Chart.Builder.Variables.list(layers, Visualize.Chart.stack(layers))
        iex> {unit.name, unit.type, unit.default, length(unit.uses)}
        {:unit, :text, "%", 1}
    """
    @spec list([{term(), map()}], map()) :: [map()]
    def list(layers, design) do
      free = layers |> Chart.free_vars() |> Map.new(&{&1.name, &1})
      declared = design |> Map.get(:vars, %{}) |> Map.new(fn {k, v} -> {k, v} end)

      (Map.keys(free) ++ Map.keys(declared))
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.map(fn name ->
        var = Map.get(free, name, %{uses: [], default: nil})
        decl = Map.get(declared, name)

        %{
          name: name,
          type: type_of(var.uses),
          default: var.default || (is_map(decl) && Map.get(decl, :default)) || nil,
          uses: var.uses
        }
      end)
    end

    @doc "The type a variable took from its first use (spec/14 §17.2), or `nil` for none."
    @spec type_of([map()]) :: term() | nil
    def type_of([%{expects: type} | _rest]), do: type
    def type_of([]), do: nil

    defp rows(%{layers: layers, design: design} = assigns) do
      expanded = assigns.expanded || MapSet.new()
      find = String.trim(assigns.find || "")

      indexes =
        layers |> Enum.with_index() |> Map.new(fn {{label, _}, i} -> {to_string(label), i} end)

      for var <- list(layers, design),
          find == "" or String.contains?(to_string(var.name), find) do
        name = to_string(var.name)

        %{
          name: name,
          type_word: type_word(var.type),
          default: default_word(var.default),
          value: shown(Map.fetch(assigns.bindings, var.name)),
          expanded?: MapSet.member?(expanded, name),
          found?: find != "" and name == find,
          uses:
            Enum.map(var.uses, fn use ->
              label = to_string(use.layer)
              %{path: Editor.label(use.path), layer: Map.get(indexes, label, 0), label: label}
            end),
          sites: site_rows(assigns.sites, var.name)
        }
      end
    end

    defp site_rows(sites, name) do
      for site <- sites, Enum.any?(site.free, &(&1.name == name)) do
        {state, literal, variable} = bound_as(Map.get(site.vars, name))

        %{
          index: site.index,
          label: site.label,
          state: state,
          reads: reads(state, name, literal, variable),
          literal: literal,
          variable: variable
        }
      end
    end

    defp bound_as(nil), do: {:up, nil, nil}
    defp bound_as(%Chart.Var{name: name}), do: {:variable, nil, to_string(name)}
    defp bound_as(value) when is_binary(value), do: {:literal, value, nil}
    defp bound_as(value), do: {:literal, inspect(value), nil}

    defp reads(:up, name, _literal, _variable), do: "flows up as :#{name}"
    defp reads(:literal, _name, literal, _variable), do: "= #{literal}"
    defp reads(:variable, _name, _literal, variable), do: "= var(:#{variable})"

    defp type_word(nil), do: "untyped"
    defp type_word({:enum, _}), do: "a choice"
    defp type_word({:ref, kind}), do: "a #{kind}"
    defp type_word({:one_of, [first | _]}), do: type_word(first)
    defp type_word(type) when is_atom(type), do: "a #{type}"
    defp type_word(type), do: inspect(type)

    defp default_word(nil), do: nil
    defp default_word(value) when is_binary(value), do: value
    defp default_word(value), do: inspect(value)

    defp shown(:error), do: nil
    defp shown({:ok, value}) when is_binary(value), do: value
    defp shown({:ok, value}), do: inspect(value)
  end
end
