if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Params do
    @moduledoc """
    The builder's parameters form: `Visualize.Chart.free_vars/1` rendered (spec/14 §18.11).

    One control per variable the stack still demands, ordered by name, with its default,
    whether it is required, and the paths it stands at. It is the second inspector —
    `Visualize.Chart.explain/1` says where a value came from and `Visualize.Chart.free_vars/1`
    says what is still open — and, like the first, it is a view of one function, so what it
    offers and what `Visualize.Chart.apply/2` will demand are the same set by construction.

    The control is `Visualize.Chart.Builder.Editor.widget/1` of the first use's `expects`,
    the schema's type at the path the variable stands at, so the parameters form and the
    fragment editor choose from one table and a schema addition reaches both (D-86, D-88).

    This module compiles only when `Phoenix.Component` is loaded (spec/10 §1.1, D-45, D-85).
    """

    use Phoenix.Component

    alias Visualize.Chart
    alias Visualize.Chart.Builder.Editor

    attr(:layers, :list,
      required: true,
      doc: "the layers, as `Visualize.Chart.stack/1` takes them"
    )

    attr(:vars, :map, default: %{}, doc: "the values now bound")

    attr(:id, :string,
      default: "vis-builder-params",
      doc: "the parameters form's id, and the stem of its site forms' and datalist's"
    )

    attr(:sites, :list,
      default: [],
      doc: "each site's own free variables and what it binds them to (spec/14 §19.10)"
    )

    attr(:names, :list, default: [], doc: "the variable names a site may bind to")
    attr(:target, :any, default: nil, doc: "the `phx-target` of the form's events")
    attr(:class, :string, default: nil, doc: "appended to the form's class")

    @doc """
    Renders the parameters form (spec/10 §15.3), and the per-site rows (spec/14 §19.10).

    A `<form class="vis-builder-params">` with one `<label class="vis-builder-param">` per
    free variable, each carrying the control its first use's type asks for; then one
    `<form class="vis-builder-site">` per site that carries variables, with a row per
    variable reading as one of three states — *flows up*, `= literal`, `= var(:name)`.
    """
    def panel(assigns) do
      assigns = assign(assigns, params: params(assigns), rows: rows(assigns.sites))

      ~H"""
      <div class="vis-builder-variables">
      <form id={@id} class={class(@class)} phx-change="set_var" phx-target={@target} phx-submit="submitted">
        <label :for={param <- @params} class={param.class}>
          <span class="vis-builder-param-name">{param.name}</span>
          <input
            :if={param.widget == :checkbox}
            type="checkbox"
            name={param.name}
            value="true"
            checked={param.checked}
          />
          <input
            :if={param.widget == :number}
            type="number"
            name={param.name}
            value={param.value}
            placeholder={param.placeholder}
          />
          <input
            :if={param.widget == :text}
            type="text"
            name={param.name}
            value={param.value}
            placeholder={param.placeholder}
          />
          <select :if={param.widget == :select} name={param.name}>
            <option value=""></option>
            <option
              :for={allowed <- param.options}
              value={allowed}
              selected={param.value == to_string(allowed)}
            >{allowed}</option>
          </select>
          <textarea
            :if={param.widget == :textarea}
            name={param.name}
            placeholder={param.placeholder}
          >{param.value}</textarea>
          <span class="vis-builder-param-uses">{param.uses}</span>
        </label>
      </form>
      <form
        :for={site <- @rows}
        id={"#{@id}-site-#{site.index}"}
        class="vis-builder-site"
        phx-change="bind_site"
        phx-target={@target}
       phx-submit="submitted">
        <h3 class="vis-builder-site-name">{site.label}</h3>
        <input type="hidden" name="site" value={site.index} />
        <div :for={row <- site.rows} class={"vis-builder-site-var vis-builder-site-var-" <> to_string(row.state)}>
          <span class="vis-builder-param-name">{row.name}</span>
          <span class="vis-builder-site-state">{row.reads}</span>
          <input
            type="text"
            name={row.name}
            class="vis-builder-site-literal"
            value={row.literal}
            placeholder="a value"
            aria-label={"#{row.name} as a value"}
          />
          <input
            type="text"
            name={row.name <> ".var"}
            class="vis-builder-site-variable"
            value={row.variable}
            placeholder="or a variable"
            list={@id <> "-names"}
            aria-label={"#{row.name} as a variable"}
          />
        </div>
      </form>
      <datalist id={@id <> "-names"}>
        <option :for={name <- @names} value={name}></option>
      </datalist>
      </div>
      """
    end

    # A site's rows: what its fragment asks for, and what the site says of each (§19.4).
    defp rows(sites) do
      for site <- sites do
        rows =
          for free <- site.free do
            {state, literal, variable} = bound_as(Map.get(site.vars, free.name))

            %{
              name: to_string(free.name),
              state: state,
              reads: reads(state, free.name, literal, variable),
              literal: literal,
              variable: variable
            }
          end

        %{index: site.index, label: site.label, rows: rows}
      end
    end

    defp bound_as(nil), do: {:up, nil, nil}
    defp bound_as(%Chart.Var{name: name}), do: {:variable, nil, to_string(name)}
    defp bound_as(value) when is_binary(value), do: {:literal, value, nil}
    defp bound_as(value), do: {:literal, inspect(value), nil}

    defp reads(:up, name, _literal, _variable), do: "flows up as :#{name}"
    defp reads(:literal, _name, literal, _variable), do: "= #{literal}"
    defp reads(:variable, _name, _literal, variable), do: "= var(:#{variable})"

    defp class(nil), do: "vis-builder-params"
    defp class(extra), do: "vis-builder-params " <> extra

    @doc false
    # The type a variable's control is chosen from and read back with: the schema's at the
    # first path it stands at (spec/14 §18.11). Public to the builder's edit event, which
    # must parse a submitted value with the same type the control was chosen from.
    @spec expects(Chart.free_var()) :: Visualize.Chart.Schema.type()
    def expects(%{uses: [%{expects: type} | _rest]}), do: type
    def expects(%{uses: []}), do: :term

    defp params(%{layers: layers, vars: vars}) do
      for free <- Chart.free_vars(layers) do
        widget = Editor.widget(expects(free))
        bound = Map.fetch(vars, free.name)

        %{
          name: free.name,
          class: classes(free.required),
          widget: shape(widget),
          options: options(widget),
          checked: Map.get(vars, free.name) == true,
          value: shown(widget, bound),
          placeholder: shown(widget, default(free.default)),
          uses: Enum.map_join(free.uses, ", ", &label(&1.path))
        }
      end
    end

    defp classes(true), do: "vis-builder-param vis-builder-param-required"
    defp classes(false), do: "vis-builder-param"

    defp shape({:select, _allowed}), do: :select
    defp shape(widget), do: widget

    defp options({:select, allowed}), do: allowed
    defp options(_widget), do: []

    defp default(nil), do: :error
    defp default(value), do: {:ok, value}

    defp shown(_widget, :error), do: nil
    defp shown(:textarea, {:ok, value}), do: inspect(value)
    defp shown(_widget, {:ok, value}), do: to_string(value)

    # The path as `Visualize.Chart.Validator.format/1` spells it.
    defp label([]), do: "design"

    defp label(path) do
      Enum.reduce(path, "", fn
        index, acc when is_integer(index) -> "#{acc}[#{index}]"
        key, "" -> "#{key}"
        key, acc -> "#{acc}.#{key}"
      end)
    end
  end
end
