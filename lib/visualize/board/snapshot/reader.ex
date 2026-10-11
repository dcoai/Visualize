defmodule Visualize.Board.Snapshot.Reader do
  @moduledoc false
  # A snapshot's map read back (spec/15 §12.3): every key checked, every fault reported
  # by path in the shape of spec/14 §10.1, and the snapshot built only when there is none.
  # The documents inside it are read by their own readers — the board by
  # `Visualize.Board.from_map/2`, the theme by `Visualize.Chart.Theme.from_map/2`, a cell's
  # component by `Visualize.Chart.from_map/2`, a schema by `Visualize.Data.Schema.new/1` —
  # with their faults under their own paths.

  alias Visualize.Board
  alias Visualize.Board.Snapshot
  alias Visualize.Board.Snapshot.Codec
  alias Visualize.Chart
  alias Visualize.Chart.Theme, as: ChartTheme
  alias Visualize.Data.{Delivery, Schema}

  @required [:board, :cells]
  @reductions [nil, :feed, :visualize]

  @doc false
  def done([]), do: :ok
  def done(errors), do: {:error, Enum.sort_by(errors, &elem(&1, 0))}

  @doc false
  def read(map, limits) when is_map(map) and not is_struct(map) do
    limits = Map.to_list(limits)

    errors =
      unknown(map, [:version | Codec.keys()], []) ++
        for(key <- @required, not Map.has_key?(map, key), do: {[key], :required})

    {board, board_errors} = board(Map.get(map, :board), limits)
    {theme, theme_errors} = theme(Map.get(map, :theme), limits)
    {cells, cell_errors} = cells(Map.get(map, :cells, %{}), board, limits)

    errors =
      errors ++
        board_errors ++
        theme_errors ++
        cell_errors ++
        now(Map.get(map, :now)) ++
        window(Map.get(map, :window)) ++
        width(Map.get(map, :width, 1200))

    with :ok <- done(errors) do
      {:ok,
       %Snapshot{
         version: Map.get(map, :version, Chart.Migration.current()),
         board: board,
         now: Map.get(map, :now),
         window: with(%{from: from, to: to} <- Map.get(map, :window), do: {from, to}),
         width: Map.get(map, :width, 1200),
         theme: theme,
         cells: cells
       }}
    end
  end

  def read(_other, _limits), do: {:error, [{[], {:type, :snapshot}}]}

  defp unknown(map, keys, path) do
    for key <- Map.keys(map), key not in keys, do: {path ++ [key], :unknown_key}
  end

  defp board(nil, _limits), do: {nil, []}

  defp board(map, limits) do
    case Board.from_map(map, limits: limits) do
      {:ok, board} -> {board, []}
      {:error, errors} -> {nil, under([:board], errors)}
    end
  end

  defp theme(nil, _limits), do: {Visualize.Theme.default(), []}

  defp theme(node, limits) do
    case ChartTheme.from_map(%{theme: node}, limits: limits) do
      {:ok, theme} -> {theme, []}
      {:error, errors} -> {nil, errors}
    end
  end

  defp now(nil), do: []
  defp now(value), do: utc(value, [:now])

  defp window(nil), do: []

  defp window(%{from: from, to: to} = window) when map_size(window) == 2 do
    case utc(from, [:window, :from]) ++ utc(to, [:window, :to]) do
      [] ->
        if DateTime.compare(from, to) == :gt, do: [{[:window], {:window, :inverted}}], else: []

      errors ->
        errors
    end
  end

  defp window(_window), do: [{[:window], {:type, :window}}]

  defp utc(%DateTime{time_zone: "Etc/UTC"}, _path), do: []
  defp utc(_value, path), do: [{path, {:type, :utc_datetime}}]

  defp width(w) when is_number(w) and w > 0, do: []
  defp width(_w), do: [{[:width], {:type, :positive}}]

  # -- cells ---------------------------------------------------------------------------------

  defp cells(cells, board, limits) when is_map(cells) and not is_struct(cells) do
    on_board = if board, do: Map.keys(board.cells), else: Map.keys(cells)

    missing = for name <- on_board, not Map.has_key?(cells, name), do: {[:cells, name], :required}

    Enum.reduce(cells, {%{}, missing}, fn {name, cell}, {read, errors} ->
      path = [:cells, name]

      if name in on_board do
        case cell(cell, path, limits) do
          {:ok, cell} -> {Map.put(read, name, cell), errors}
          {:error, faults} -> {read, faults ++ errors}
        end
      else
        {read, [{path, :not_on_board} | errors]}
      end
    end)
  end

  defp cells(_cells, _board, _limits), do: {%{}, [{[:cells], {:type, {:map, {:node, :cell}}}}]}

  defp cell(cell, path, limits) when is_map(cell) and not is_struct(cell) do
    errors =
      unknown(cell, Codec.cell_keys(), path) ++
        if(Map.has_key?(cell, :chart), do: [], else: [{path ++ [:chart], :required}])

    {chart, chart_errors} =
      case Map.fetch(cell, :chart) do
        {:ok, map} ->
          case Chart.from_map(map, limits: limits) do
            {:ok, chart} -> {chart, []}
            {:error, faults} -> {nil, under(path ++ [:chart], faults)}
          end

        :error ->
          {nil, []}
      end

    vars = Map.get(cell, :vars, %{})
    {slots, slot_errors} = slots(Map.get(cell, :slots), path ++ [:slots])
    crashed = Map.get(cell, :crashed)

    errors =
      errors ++
        chart_errors ++
        slot_errors ++
        vars(vars, path ++ [:vars]) ++
        if(is_nil(crashed) or is_binary(crashed),
          do: [],
          else: [{path ++ [:crashed], {:type, :string}}]
        )

    case errors do
      [] -> {:ok, %{chart: chart, vars: vars, slots: slots, crashed: crashed}}
      errors -> {:error, errors}
    end
  end

  defp cell(_cell, path, _limits), do: {:error, [{path, {:type, {:node, :cell}}}]}

  defp vars(vars, path) when is_map(vars) and not is_struct(vars) do
    for {name, _value} <- vars, not is_atom(name), do: {path ++ [name], {:type, :name}}
  end

  defp vars(_vars, path), do: [{path, {:type, {:map, :term}}}]

  defp slots(nil, _path), do: {nil, []}

  defp slots(slots, path) when is_map(slots) and not is_struct(slots) do
    Enum.reduce(slots, {%{}, []}, fn {name, slot}, {read, errors} ->
      case slot(slot, path ++ [name]) do
        {:ok, slot} when is_atom(name) -> {Map.put(read, name, slot), errors}
        {:ok, _slot} -> {read, [{path ++ [name], {:type, :name}} | errors]}
        {:error, faults} -> {read, faults ++ errors}
      end
    end)
  end

  defp slots(_slots, path), do: {nil, [{path, {:type, {:map, {:node, :slot}}}}]}

  defp slot(slot, path) when is_map(slot) and not is_struct(slot) do
    rows = Map.get(slot, :rows)
    {schema, schema_errors} = schema(Map.get(slot, :schema), path ++ [:schema])

    errors =
      unknown(slot, Codec.slot_keys(), path) ++
        schema_errors ++
        rows(rows, path ++ [:rows]) ++
        facts(rows, slot, path) ++
        status(Map.get(slot, :status), path ++ [:status])

    case errors do
      [] -> {:ok, %{delivery: delivery(rows, slot), schema: schema, status: slot.status}}
      errors -> {:error, errors}
    end
  end

  defp slot(_slot, path), do: {:error, [{path, {:type, {:node, :slot}}}]}

  defp delivery(nil, _slot), do: nil

  defp delivery(rows, slot) do
    %Delivery{
      rows: rows,
      window: Map.get(slot, :window),
      resolution: Map.get(slot, :resolution),
      capped: Map.get(slot, :capped, false),
      reduced_by: Map.get(slot, :reduced_by),
      schema: Map.get(slot, :version)
    }
  end

  defp rows(nil, _path), do: []

  defp rows(rows, path) when is_list(rows) do
    rows
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {row, _i} when is_map(row) and not is_struct(row) -> []
      {_row, i} -> [{path ++ [i], {:type, :row}}]
    end)
  end

  defp rows(_rows, path), do: [{path, {:type, {:list, :row}}}]

  # A delivery's facts, checked only where there is a delivery.
  defp facts(nil, _slot, _path), do: []

  defp facts(_rows, slot, path) do
    capped = Map.get(slot, :capped, false)
    reduced = Map.get(slot, :reduced_by)
    version = Map.get(slot, :version)
    window = Map.get(slot, :window)

    if(is_boolean(capped), do: [], else: [{path ++ [:capped], {:type, :boolean}}]) ++
      if(reduced in @reductions,
        do: [],
        else: [{path ++ [:reduced_by], {:type, {:enum, [:feed, :visualize]}}}]
      ) ++
      if(is_nil(version) or is_binary(version),
        do: [],
        else: [{path ++ [:version], {:type, :string}}]
      ) ++
      if(is_nil(window) or is_list(window),
        do: [],
        else: [{path ++ [:window], {:type, {:list, :term}}}]
      )
  end

  defp schema(nil, _path), do: {nil, []}

  defp schema(fields, path) do
    case Schema.new(fields) do
      {:ok, schema} -> {schema, []}
      {:error, errors} -> {nil, under(path, errors)}
    end
  end

  defp status(status, _path) when status in [:loading, :live, :stale], do: []
  defp status({:down, reason}, _path) when is_binary(reason), do: []
  defp status(_status, path), do: [{path, {:type, :status}}]

  defp under(prefix, errors),
    do: Enum.map(errors, fn {path, reason} -> {prefix ++ path, reason} end)
end
