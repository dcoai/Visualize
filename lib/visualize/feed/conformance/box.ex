defmodule Visualize.Feed.Conformance.Box do
  @moduledoc false
  # The supports check's clauses for a box (spec/08 §12.3, D-168): a `:region` feed's rows
  # within every range, and a `:latest` feed's one row per identity, the last within the
  # box. `fetch` is the kit's probe — a request to `{:ok, delivery, rows}` or its findings
  # — so these clauses run as isolated as every other.

  alias Visualize.Data.{Schema, Table}
  alias Visualize.Feed
  alias Visualize.Feed.Window

  # Of every box, each row's value of each field ranged but the window field within its
  # range (spec/08 §12.3, D-168).
  @doc false
  def region(fetch, supports, schema, o) do
    time = Feed.window_field(schema)
    boxes = for %{} = box <- o.windows, region(box, time) != [], valid?(box, schema), do: box

    cond do
      :region not in supports ->
        []

      boxes == [] ->
        [{:no_probe, :region}]

      true ->
        for box <- boxes, budget <- o.budgets do
          case fetch.({box, budget}) do
            {:ok, _delivery, rows} -> region_kept(rows, {box, budget}, region(box, time))
            _faults -> []
          end
        end
        |> List.flatten()
    end
  end

  defp region(box, time) do
    for {field, range} <- Map.get(box, :ranges, %{}),
        time == nil or to_string(field) != to_string(time),
        do: {field, range}
  end

  defp valid?(box, schema), do: Window.check(box, schema) == :ok

  defp region_kept(rows, request, ranges) do
    for {field, range} <- ranges,
        row = Enum.find(rows, &(not Window.within?(Table.get(&1, field), range))),
        row != nil,
        do: {:region_row, request, field, Table.get(row, field)}
  end

  @doc false
  # Of every box asking `latest`, at most one row per identity, and none older than the
  # same box's last row of it without `latest` (spec/08 §12.3, #622's acceptance).
  def latest(fetch, supports, schema, o) do
    boxes = for %{latest: true} = box <- o.windows, valid?(box, schema), do: box

    cond do
      :latest not in supports ->
        []

      boxes == [] ->
        [{:no_probe, :latest}]

      true ->
        for box <- boxes, budget <- o.budgets do
          latest_kept(fetch, {box, budget}, schema)
        end
        |> List.flatten()
    end
  end

  defp latest_kept(fetch, {box, _budget} = request, schema) do
    time = Feed.window_field(schema)

    with {:ok, _delivery, rows} <- fetch.(request),
         {:ok, _whole, all} <- fetch.({%{box | latest: false}, nil}) do
      by_id = Enum.group_by(rows, &Schema.identity(schema, &1))
      twice = for {id, [_, _ | _]} <- by_id, id != nil, do: {:latest_twice, request, id}

      last =
        all
        |> Window.latest_rows(&place(&1, time), &Schema.identity(schema, &1))
        |> Map.new(&{Schema.identity(schema, &1), place(&1, time)})

      older =
        for {id, [row]} <- by_id,
            id != nil,
            newest = Map.get(last, id),
            newest != nil and (place(row, time) == nil or place(row, time) < newest),
            do: {:not_latest, request, id}

      twice ++ older
    else
      _unanswered -> []
    end
  end

  defp place(row, time) do
    value = Table.get(row, time)
    if Window.time?(value), do: Window.position(value)
  end
end
