defmodule Visualize.Chart.Builder.BoardSources do
  @moduledoc false
  # A board's virtual sources in the board mode (spec/14 §22.9, D-194): run as the board
  # runs them, over the preview's data — the bindable feeds' sample rows under their catalog
  # schemas — with the same engine and one immediate pulse, no process. What a pass reads
  # of them: each cell's pool with the sources' answers and joined fields, each slot's
  # schema, each feed's schema with the fields joined into it at the board's scope (for the
  # binding check), and a view of every source for the inspector.

  alias Visualize.Board
  alias Visualize.Board.Binding
  alias Visualize.Chart.Names
  alias Visualize.Data.{Delivery, Schema}
  alias Visualize.VirtualSource
  alias Visualize.VirtualSource.{Engine, Join, Sandbox}
  alias Visualize.VirtualSources

  @rows 5

  @type t :: %{
          pools: map(),
          slot_schemas: map(),
          feed_schemas: map(),
          sources: [map()],
          errors: [String.t()]
        }

  @doc false
  # `run(board, binding, sources, catalog, modules)`: `sources` the bindable feeds' preview
  # data by feed, `catalog` their schemas or `nil`, `modules` the host's function modules.
  @spec run(Board.t(), Binding.t(), map(), map() | nil, [module()]) :: t()
  def run(%Board{} = board, %Binding{} = binding, sources, catalog, modules),
    do: board |> ran(sources, catalog, modules) |> answer(binding)

  @doc false
  # The board's sources run over the preview's data, whatever the binding (#838, D-219):
  # what `answer/2` reads for a binding, so a pass whose binding alone moved does not
  # check, compile and run the sources again.
  @spec ran(Board.t(), map(), map() | nil, [module()]) :: map()
  def ran(%Board{} = board, sources, catalog, modules) do
    table = Board.virtual_sources(board)
    schemas = catalog || %{}
    deliveries = Map.new(sources, fn {feed, source} -> {feed, delivery(source)} end)
    ran = %{table: table, sources: sources, schemas: schemas, deliveries: deliveries}

    if table == %{} do
      Map.put(ran, :engine, nil)
    else
      functions = VirtualSources.registry(modules)
      opts = [feeds: Map.keys(deliveries), functions: functions, debounce: 0]

      engine =
        with {:ok, engine} <- Engine.new(table, opts),
             do: {:ok, engine |> Engine.push(deliveries, schemas, 0) |> Engine.run(0)}

      Map.merge(ran, %{engine: engine, functions: functions})
    end
  end

  @doc false
  # What a pass reads of the sources' run for a binding.
  @spec answer(map(), Binding.t()) :: t()
  def answer(%{engine: {:ok, engine}} = ran, %Binding{} = binding),
    do: answered(engine, ran.table, binding, ran.deliveries, ran.schemas, ran.functions)

  def answer(ran, %Binding{} = binding) do
    plain = %{
      pools: Binding.pools(binding, ran.sources),
      slot_schemas: %{},
      feed_schemas: ran.schemas,
      sources: [],
      errors: []
    }

    case ran.engine do
      nil ->
        plain

      {:error, errors} ->
        %{
          plain
          | sources: views(ran.table, nil, ran.functions),
            errors: Enum.map(errors, &define_error/1)
        }
    end
  end

  defp delivery(%Delivery{} = delivery), do: delivery
  defp delivery(rows), do: Delivery.new(rows)

  defp answered(engine, table, binding, deliveries, schemas, functions) do
    outputs = Engine.outputs(engine)
    out_schemas = Engine.schemas(engine)

    slots =
      for {{cell, slot} = key, feed} <- binding.slots, into: %{} do
        case Engine.resolve(engine, [cell], feed) do
          {:source, path} ->
            {key, {cell, slot, Map.get(outputs, path), Map.fetch!(out_schemas, path)}}

          {:feed, name} ->
            joins = Join.joins(engine, [cell], {:feed, name})

            {delivery, schema} =
              Join.join(Map.get(deliveries, name), Map.get(schemas, name), joins, engine)

            {key, {cell, slot, delivery, schema}}

          :error ->
            {key, {cell, slot, nil, nil}}
        end
      end

    pools =
      for {_key, {cell, slot, delivery, _schema}} <- slots, delivery != nil, reduce: %{} do
        pools -> Map.update(pools, cell, %{slot => delivery}, &Map.put(&1, slot, delivery))
      end

    # Each feed's schema with the fields joined into it at the board's scope, and each
    # name a binding gives a source the source's output schema, for the binding check.
    feed_schemas =
      Map.new(schemas, fn {feed, schema} ->
        {feed, Join.schema(schema, Join.joins(engine, [], {:feed, feed}), engine)}
      end)

    feed_schemas =
      for {{cell, _slot}, name} <- binding.slots,
          {:source, path} <- [Engine.resolve(engine, [cell], name)],
          into: feed_schemas,
          do: {name, Map.fetch!(out_schemas, path)}

    %{
      pools: pools,
      slot_schemas:
        for(
          {key, {_cell, _slot, _delivery, %Schema{} = schema}} <- slots,
          into: %{},
          do: {key, schema}
        ),
      feed_schemas: feed_schemas,
      sources: views(table, engine, functions),
      errors: []
    }
  end

  defp define_error({path, at, reason}),
    do: VirtualSource.dotted(path) <> ": " <> VirtualSource.format_error({at, reason})

  # Each source as the inspector shows it, by path.
  defp views(table, engine, functions) do
    status = if engine, do: Engine.status(engine), else: %{}
    faults = if engine, do: Engine.faults(engine), else: %{}
    outputs = if engine, do: Engine.outputs(engine), else: %{}

    for {path, source} <- Enum.sort(table) do
      fault = Map.get(faults, path)

      %{
        path: VirtualSource.dotted(path),
        id: source.id,
        stored?: is_binary(source.elixir),
        text: source.elixir || host_text(source.function, functions),
        state: state(Map.get(status, path)),
        faults: check_lines(source) ++ fault_lines(fault),
        fields: source.schema.fields |> Map.keys() |> Enum.sort_by(&to_string/1),
        rows:
          outputs |> Map.get(path, %Delivery{rows: []}) |> Map.fetch!(:rows) |> Enum.take(@rows)
      }
    end
  end

  # A host function is named by its string and its registry read by spelling (D-195).
  defp host_text(name, functions) do
    with {:ok, module} <- Names.fetch(functions, name),
         {_name, _arity, text} <-
           Enum.find(module.__virtual_sources__(), fn {own, _arity, _text} ->
             Names.same?(own, name)
           end) do
      text
    else
      _none -> ""
    end
  end

  defp state(nil), do: "not run"
  defp state(:loading), do: "loading"
  defp state(:live), do: "live"
  defp state({:down, {:virtual_source, _id, kind}}), do: to_string(kind)

  defp check_lines(%{elixir: text}) when is_binary(text) do
    case Sandbox.check(text) do
      {:ok, _quoted} -> []
      {:error, faults} -> Enum.map(faults, &Sandbox.format_error/1)
    end
  end

  defp check_lines(_source), do: []

  defp fault_lines(nil), do: []

  defp fault_lines(%{kind: :restricted, detail: errors}) when is_list(errors),
    do: Enum.map(errors, &line/1)

  defp fault_lines(%{kind: kind, detail: detail}), do: ["#{kind}: #{inspect(detail)}"]

  @doc false
  # A source's function written from the page: `{:ok, board}` with the text in the board
  # when it holds — alone, and given its inputs' schemas where they are known — else
  # `{:error, lines}` with the faults at their lines (spec/14 §22.9).
  @spec write(Board.t(), String.t(), String.t(), map()) ::
          {:ok, Board.t()} | {:error, [String.t()]}
  def write(%Board{} = board, dotted, text, schemas) do
    case Enum.find(Board.virtual_sources(board), fn {path, _s} ->
           VirtualSource.dotted(path) == dotted
         end) do
      {path, source} ->
        map = source |> VirtualSource.to_map() |> Map.put(:elixir, text)

        with {:ok, edited} <- lines(VirtualSource.new(map)),
             :ok <- lines(VirtualSource.validate(edited, inputs: input_schemas(edited, schemas))) do
          {:ok, put(board, path, map |> Map.delete(:id))}
        end

      nil ->
        {:error, ["no virtual source " <> dotted]}
    end
  end

  defp lines({:ok, _value} = ok), do: ok
  defp lines(:ok), do: :ok
  defp lines({:error, errors}), do: {:error, Enum.map(errors, &line/1)}

  defp line({[:elixir], {:check, line, reason}}), do: Sandbox.format_error({line, reason})
  defp line(fault), do: VirtualSource.format_error(fault)

  defp input_schemas(source, schemas) do
    for {name, _window} <- source.from,
        {:ok, schema} <- [Map.fetch(schemas, name)],
        into: %{},
        do: {name, schema}
  end

  defp put(board, [id], map),
    do: %{board | virtual_sources: Map.put(board.virtual_sources, id, map)}

  defp put(board, [cell, id], map) do
    cells =
      Map.update!(board.cells, cell, fn c ->
        Map.update(c, :virtual_sources, %{id => map}, &Map.put(&1, id, map))
      end)

    %{board | cells: cells}
  end
end
