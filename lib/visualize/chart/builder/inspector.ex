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

    attr(:id, :string, required: true, doc: "the section's id")

    attr(:look, :map,
      required: true,
      doc: "what `Visualize.Chart.explain/2` answers for the element"
    )

    attr(:label, :string, default: nil, doc: "the node's label, as its heading")

    @doc """
    Renders an element's look explained (spec/14 §18.9, §17.3, #686): one block per part of
    its resolved style — its value in brief, whether its kind draws it — and the part's
    chain of contributions, lowest first, each its layer of the precedence order, its
    container, its style and the names it was reached through, the field that chose it,
    the generators it was computed with, and the keys it set.
    """
    def look(assigns) do
      assigns = assign(assigns, :parts, look_parts(assigns.look))

      ~H"""
      <section id={@id} class="vis-builder-look">
        <h3 class="vis-builder-context-title">why {@label} looks as it does</h3>
        <div :for={part <- @parts} class={"vis-builder-look-part" <> if(part.drawn, do: "", else: " vis-builder-look-undrawn")}>
          <h4 class="vis-builder-look-name">
            {part.name}<span :if={!part.drawn} class="vis-builder-look-note"> · not drawn</span>
          </h4>
          <p class="vis-builder-look-value">{part.value}</p>
          <ol class="vis-builder-look-chain">
            <li :for={link <- part.chain} class={"vis-builder-look-link vis-builder-look-" <> link.layer}>
              <span class="vis-builder-look-layer">{link.layer}</span>
              <span :if={link.from} class="vis-builder-look-from">{link.from}</span>
              <span :if={link.field} class="vis-builder-look-field">{link.field}</span>
              <span :for={generator <- link.generators} class="vis-builder-look-generator">{generator}</span>
              <span class="vis-builder-look-set">{link.set}</span>
            </li>
          </ol>
        </div>
      </section>
      """
    end

    # The parts of an element's look in §3.1's order, each with its chain as words.
    defp look_parts(%{parts: parts}) do
      order = [:fill, :stroke, :font, :text, :effect, :opacity, :blend, :marker, :curve, :class]

      named =
        Enum.sort_by(parts, fn {part, _} -> Enum.find_index(order ++ [part], &(&1 == part)) end)

      for {part, %{value: value, drawn: drawn, chain: chain}} <- named do
        %{
          name: to_string(part),
          drawn: drawn,
          value: brief(value),
          chain: Enum.map(chain, &contribution/1)
        }
      end
    end

    defp contribution(link) do
      %{
        layer: to_string(link.layer),
        from: from(link),
        field: field(link),
        generators: Enum.map(Map.get(link, :generators, []), &generator/1),
        set: brief(link.set)
      }
    end

    # Where a contribution came from: its container, its style and the names it was reached
    # through.
    defp from(link) do
      words =
        [container(Map.get(link, :container)), link.style && to_string(link.style)] ++
          Enum.map(Map.get(link, :via, []), &"via #{&1}")

      case Enum.reject(words, &is_nil/1) do
        [] -> nil
        some -> Enum.join(some, " · ")
      end
    end

    defp container(nil), do: nil
    defp container({:frame, name}), do: "frame #{name}"
    defp container(other), do: to_string(other)

    defp field(%{field: {:field, f}, value: value}), do: "field #{f} = #{brief(value)}"
    defp field(_link), do: nil

    defp generator(%{name: name, args: args, result: result}),
      do: "generate #{name}(#{Enum.map_join(args, ", ", &brief/1)}) → #{brief(result)}"

    defp brief(value), do: inspect(value, limit: 6, printable_limit: 40)

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
