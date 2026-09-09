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
    attr(:target, :any, default: nil, doc: "the `phx-target` of the form's events")
    attr(:class, :string, default: nil, doc: "appended to the form's class")

    @doc """
    Renders the parameters form (spec/10 §15.3).

    A `<form class="vis-builder-params">` with one `<label class="vis-builder-param">` per
    free variable, each carrying the control its first use's type asks for.
    """
    def panel(assigns) do
      assigns = assign(assigns, :params, params(assigns))

      ~H"""
      <form class={class(@class)} phx-change="set_var" phx-target={@target}>
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
      """
    end

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
