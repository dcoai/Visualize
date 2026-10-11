if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Selection do
    @moduledoc false
    # What is selected (spec/14 §18.8, §18.15): a row of the layer tree by its flat position,
    # the node of the chart a path opens, and the node a form's event aims at.
    #
    # Split from `Visualize.Chart.Builder` by area (#568); compiled only with
    # `Phoenix.Component`, as the builder is (spec/10 §1.1, D-45, D-85).

    import Phoenix.Component, only: [assign: 2]

    alias Visualize.Chart.Builder.{Editing, Editor, Stack}

    @doc false
    def row_name(%{assigns: %{uses: uses, labels: labels}}, index) do
      case row_use(uses, index) do
        nil -> "the row"
        use -> Stack.label(labels, use)
      end
    end

    # The site at a flat position of the tree (spec/14 §18.8, #380), or nil.
    @doc false
    def row_use(uses, index) do
      case Enum.at(Stack.all(uses), position(index)) do
        nil -> nil
        row -> row.use
      end
    end

    # A position arrives as a string from a `phx-value-index` and as a number from the hook.
    @doc false
    def position(index) when is_integer(index), do: index

    def position(index) when is_binary(index) do
      case Integer.parse(index) do
        {value, ""} -> value
        _other -> -1
      end
    end

    def position(_index), do: -1

    # Selecting a layer closes an opened entry: the two are one editing target.
    @doc false
    def select(socket, index) do
      case row_use(socket.assigns.uses, index) do
        nil ->
          socket

        use ->
          # Selecting a site opens the site's context (spec/14 §19.10).
          assign(socket,
            selected: use.id,
            selection: MapSet.new(),
            reverting: nil,
            node_label: "design",
            facet: nil,
            style_entry: nil,
            field: nil,
            context: :inspect
          )
      end
    end

    # The node of the chart that owns a path: the deepest whose label is a prefix of it,
    # and the root where none is (spec/14 §18.9, §18.15).
    @doc false
    def opened(socket, path) do
      label =
        socket.assigns
        |> Editing.editing()
        |> Map.fetch!(:design)
        |> Editor.nodes()
        |> Enum.filter(&owns?(&1.label, path))
        |> Enum.max_by(&String.length(&1.label), fn -> %{label: "design"} end)
        |> Map.fetch!(:label)

      assign(socket, node_label: label, facet: nil, field: nil, context: :inspect)
    end

    defp owns?("design", _path), do: false

    defp owns?(label, path) do
      path == label or String.starts_with?(path, label <> ".") or
        String.starts_with?(path, label <> "[")
    end

    # An event from a form on a page aims at the form's node (spec/14 §18.15): the node is
    # selected first, so everything that reads the entry reads that node.
    @doc false
    def aimed(socket, params) do
      case Map.get(params, "_node") || Map.get(params, "node") do
        label when is_binary(label) and label != "" ->
          if label == socket.assigns.node_label,
            do: socket,
            else: assign(socket, node_label: label, facet: nil, style_entry: nil)

        _none ->
          socket
      end
    end

    @doc false
    def decode_id(value) when is_binary(value) do
      case Integer.parse(value) do
        {n, ""} -> {:use, n}
        _other -> nil
      end
    end

    def decode_id(_other), do: nil
  end
end
