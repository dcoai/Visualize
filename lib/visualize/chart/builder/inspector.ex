if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Inspector do
    @moduledoc """
    The builder's inspector: `Visualize.Chart.explain/1` rendered (spec/14 §18.9).

    One row per leaf path of the stack, ordered by path, with the value, the layer that set
    it and the layers it overrode. It is a view of one function, so what it shows and what
    `Visualize.Chart.stack/1` produces cannot drift (D-83). A row carries its path and the
    position of the layer that set it, so a click gets a person from a value they can see to
    the layer they must edit (D-87).

    Its two limits are `Visualize.Chart.explain/1`'s own: a value a higher layer discarded
    whole has no path in the result and so no row, and `overrode` names only the layers that
    wrote a value at the same path.

    This module compiles only when `Phoenix.Component` is loaded (spec/10 §1.1, D-45, D-85).
    """

    use Phoenix.Component

    alias Visualize.Chart

    attr(:id, :string, required: true, doc: "the hook element's id")

    attr(:layers, :list,
      required: true,
      doc: "the layers, as `Visualize.Chart.stack/1` takes them"
    )

    attr(:target, :any, default: nil, doc: "the `phx-target` of the panel's events")
    attr(:class, :string, default: nil, doc: "appended to the panel's class")

    @doc """
    Renders the inspector (spec/10 §15.3).

    A `<table class="vis-builder-inspector">` carrying `BuilderHook`, with one
    `<tr class="vis-builder-entry">` per entry of `Visualize.Chart.explain/1`.
    """
    def panel(assigns) do
      assigns = assign(assigns, :entries, entries(assigns.layers))

      ~H"""
      <table id={@id} class={class(@class)} phx-hook="BuilderHook" data-builder-target={@target}>
        <tbody>
          <tr
            :for={entry <- @entries}
            class="vis-builder-entry"
            data-builder-path={entry.path}
            data-builder-layer={entry.index}
          >
            <td class="vis-builder-entry-path">{entry.path}</td>
            <td class="vis-builder-entry-value">{entry.value}</td>
            <td class="vis-builder-entry-layer">{entry.layer}</td>
            <td class="vis-builder-entry-overrode">{entry.overrode}</td>
          </tr>
        </tbody>
      </table>
      """
    end

    defp class(nil), do: "vis-builder-inspector"
    defp class(extra), do: "vis-builder-inspector " <> extra

    # The provenance of the stack, with each entry's layer resolved back to its position so
    # a click can select it (spec/14 §18.9).
    defp entries(layers) do
      positions = positions(layers)

      for entry <- Chart.explain(layers) do
        %{
          path: label(entry.path),
          value: inspect(entry.value),
          layer: to_string(entry.layer),
          index: Map.get(positions, entry.layer),
          overrode: Enum.map_join(entry.overrode, ", ", &to_string/1)
        }
      end
    end

    # A layer is named by its `{name, layer}` pair and by its position otherwise, exactly as
    # `Visualize.Chart.explain/1` names it.
    defp positions(layers) do
      layers
      |> Enum.with_index()
      |> Map.new(fn
        {{name, _layer}, index} -> {name, index}
        {_layer, index} -> {index, index}
      end)
    end

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
