if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Events.Color do
    @moduledoc false
    # A color's chain in the chooser (spec/14 §19.10, D-178): a step added at the end, an
    # amount changed, a step removed, a blend's operand added or removed — each an edit of
    # the selected color field's value by `Visualize.Chart.Builder.Chain.edit/3`, written as
    # any write of the field is.
    #
    # Compiled only with `Phoenix.Component`, as the builder is (spec/10 §1.1, D-45, D-85).

    import Phoenix.Component, only: [assign: 3]
    import Visualize.Chart.Builder.Editing, only: [editing: 1]
    import Visualize.Chart.Builder.Writes, only: [update_node: 3]

    alias Visualize.Chart.Builder.{Chain, Editor}

    # The events this module handles: `Visualize.Chart.Builder.handle_event/3` routes
    # each here.
    @events ~w(color_chain)

    @doc false
    def events, do: @events

    @doc false
    # The chain's form: an amount typed or dragged, a step picked from + step — the chain's
    # own, or the first step of a plain color (`<field>.step`).
    def handle_event("color_chain", %{"_target" => [target]} = params, socket) do
      field = Map.get(params, "field")

      case String.split(target, "|") do
        ["amount", path, index] ->
          with {i, ""} <- Integer.parse(index),
               {:ok, n} <- Editor.parse(:number, Map.get(params, target, "")) do
            {:noreply, chained(socket, field, path, {:amount, i, n})}
          else
            _other -> {:noreply, socket}
          end

        ["add", path] ->
          {:noreply, added(socket, field, path, Map.get(params, target))}

        [_other] ->
          # The first step of a plain color, from the chooser's own form.
          case String.split(target, ".step") do
            [field, ""] -> {:noreply, added(socket, field, "", Map.get(params, target))}
            _none -> {:noreply, socket}
          end

        _other ->
          {:noreply, socket}
      end
    end

    # A row's × and a blend's operands.
    def handle_event("color_chain", %{"field" => field, "op" => op} = params, socket) do
      path = Map.get(params, "path", "")
      index = Integer.parse(Map.get(params, "index", ""))

      change =
        case {op, index} do
          {"remove", {i, ""}} -> {:remove, i}
          {"operand_add", _index} -> {:operand, :add}
          {"operand_remove", {i, ""}} -> {:operand, {:remove, i}}
          _other -> nil
        end

      {:noreply, if(change, do: chained(socket, field, path, change), else: socket)}
    end

    def handle_event("color_chain", _params, socket), do: {:noreply, socket}

    defp added(socket, field, path, step) do
      case Enum.find(Chain.steps(), &(to_string(&1) == step)) do
        nil -> socket
        op -> chained(socket, field, path, {:add, op})
      end
    end

    # The field's value edited at the chain's operand path and written back (§18.7).
    defp chained(socket, field, path, change) when is_binary(field) do
      %{entry: entry, editing: node} = editing(socket.assigns)

      with %{path: at, spec: %{type: :color}} <- Editor.locate(entry.kind, field),
           {:ok, path} <- operand_path(path),
           current when current != nil <- Editor.value_at(entry.kind, node, at) do
        written = Chain.edit(current, path, change)

        socket
        |> update_node(entry.path, Editor.write(entry.kind, node, at, {:ok, written}))
        |> assign(:notice, nil)
      else
        _other -> socket
      end
    end

    defp chained(socket, _field, _path, _change), do: socket

    defp operand_path(""), do: {:ok, []}

    defp operand_path(path) do
      path
      |> String.split(".")
      |> Enum.reduce_while({:ok, []}, fn segment, {:ok, acc} ->
        case Integer.parse(segment) do
          {i, ""} when i >= 0 -> {:cont, {:ok, acc ++ [i]}}
          _other -> {:halt, :error}
        end
      end)
    end
  end
end
