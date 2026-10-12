defmodule Visualize.Feed do
  @moduledoc """
  The feed behaviour: what fills a chart's source slot, asked for rows (spec/08 §11,
  D-140).

  A feed is a struct whose module implements this behaviour. `describe/1` answers the
  feed's schema, its version and `supports`, the capabilities it honours among
  `[:window, :budget, :push]`; `fetch/3` answers a `Visualize.Data.Delivery` for a window
  and a budget; `subscribe/2` and `unsubscribe/2` are for a feed that pushes. **Only rows
  are required.** A window and a budget are requests: where a feed does not honour one,
  `finish/3` trims and reduces for it and the delivery records `reduced_by: :visualize`.
  Every callback answers `{:error, reason}` rather than raising, so a feed that is down is
  a value a cell shows.

  A push feed sends `{:visualize_feed, ref, {:schema, version, schema}}` before the first
  delivery naming `version`, then `{:visualize_feed, ref, {:delivery, delivery}}`, each a
  delivery of the rows new since the last (spec/08 §11.3). `Visualize.Feed.Monitor` runs
  the loop over many feeds; `Visualize.Feed.Combine` makes one feed of several by window.

  ## Examples

      iex> alias Visualize.Data.{Delivery, Schema}
      iex> schema = Schema.new!(%{t: %{type: :number, window: true}, v: %{type: :number}, s: %{type: :category}})
      iex> rows = for t <- 1..10, s <- ["a", "b"], do: %{t: t, v: rem(t * 7, 5), s: s}
      iex> delivery = Visualize.Feed.finish(Delivery.new(rows), schema, supports: [], budget: 8)
      iex> {length(delivery.rows), delivery.reduced_by}
      {8, :visualize}

  """

  alias Visualize.Data
  alias Visualize.Data.{Delivery, Schema, Table}
  alias Visualize.Feed.Window

  @capabilities [:window, :budget, :push]

  @typedoc "A feed: a struct whose module implements `Visualize.Feed`."
  @type t :: struct()

  @typedoc "What a feed honours (spec/08 §11.1)."
  @type capability :: :window | :budget | :push

  @typedoc "`nil`, or `[from, to]` over the feed's window field, either bound `nil` for open."
  @type window :: Window.t()

  @typedoc "`nil`, or the most rows a cell wants."
  @type budget :: pos_integer() | nil

  @doc "The feed's present schema, its version and the capabilities it honours."
  @callback describe(feed :: t()) ::
              {String.t(), Schema.t(), [capability()]} | {:error, term()}

  @doc "The rows for a window and a budget, both requests."
  @callback fetch(feed :: t(), window(), budget()) :: {:ok, Delivery.t()} | {:error, term()}

  @doc "The feed's pushes sent to `pid`, tagged with the answered reference."
  @callback subscribe(feed :: t(), pid()) :: {:ok, reference()} | {:error, term()}

  @doc "A subscription stopped."
  @callback unsubscribe(feed :: t(), reference()) :: :ok

  @optional_callbacks subscribe: 2, unsubscribe: 2

  @doc "The three capabilities a feed may honour, in the order of spec/08 §11.1."
  @spec capabilities() :: [capability(), ...]
  def capabilities, do: @capabilities

  @doc "The feed's `{version, schema, supports}`, or `{:error, reason}`."
  @spec describe(t()) :: {String.t(), Schema.t(), [capability()]} | {:error, term()}
  def describe(%module{} = feed), do: module.describe(feed)

  @doc "`fetch(feed, window, budget)`: `{:ok, delivery}` or `{:error, reason}`."
  @spec fetch(t(), window(), budget()) :: {:ok, Delivery.t()} | {:error, term()}
  def fetch(%module{} = feed, window, budget), do: module.fetch(feed, window, budget)

  @doc """
  The feed's pushes sent to `pid` (spec/08 §11.3): `{:ok, ref}`, or `{:error, :no_push}`
  for a feed whose module does not implement `subscribe/2`.
  """
  @spec subscribe(t(), pid()) :: {:ok, reference()} | {:error, term()}
  def subscribe(%module{} = feed, pid) when is_pid(pid) do
    if push?(module),
      do: module.subscribe(feed, pid),
      else: {:error, :no_push}
  end

  @doc "A subscription stopped; `:ok` for a feed that does not push."
  @spec unsubscribe(t(), reference()) :: :ok
  def unsubscribe(%module{} = feed, ref) when is_reference(ref) do
    if push?(module), do: module.unsubscribe(feed, ref), else: :ok
  end

  # A struct literal does not load its module, so it is loaded before it is asked.
  defp push?(module),
    do: Code.ensure_loaded?(module) and function_exported?(module, :subscribe, 2)

  @doc """
  A map of feeds by name as the describe function of spec/08 §10.3, for
  `Visualize.Data.Schema.Cache.resolve/4` and `Visualize.Chart.apply/2`'s `describe:`.
  A name not in the map is `{:error, :no_feed}`.
  """
  @spec describer(%{term() => t()}) :: (term() -> {:ok, Schema.t()} | {:error, term()})
  def describer(feeds) when is_map(feeds) do
    fn name ->
      with {:ok, feed} <- Map.fetch(feeds, name) |> no_feed(),
           {_version, schema, _supports} <- describe(feed) do
        {:ok, schema}
      end
    end
  end

  defp no_feed(:error), do: {:error, :no_feed}
  defp no_feed(found), do: found

  @doc """
  The schema's window field (spec/08 §10.1, §11.2, D-154): the field a window is over, by
  which rows are ordered, trimmed and routed. It is the field described `window: true`,
  else the schema's one `:time` field when it does not say `window: false`; `nil` when
  there is neither.

      iex> alias Visualize.Data.Schema
      iex> Visualize.Feed.window_field(Schema.new!(%{t: %{type: :time}, v: %{type: :number}}))
      :t
      iex> Visualize.Feed.window_field(Schema.new!(%{tick: %{type: :number, window: true}, v: %{type: :number}}))
      :tick
      iex> Visualize.Feed.window_field(Schema.new!(%{a: %{type: :time}, b: %{type: :time}}))
      nil
  """
  @spec window_field(Schema.t()) :: Schema.name() | nil
  def window_field(%Schema{fields: fields}) do
    case for({name, %{window: true}} <- fields, do: name) do
      [name] -> name
      [] -> the_time_field(fields)
    end
  end

  defp the_time_field(fields) do
    case for({name, %{type: :time} = d} <- fields, Map.get(d, :window) != false, do: name) do
      [name] -> name
      _none_or_several -> nil
    end
  end

  @doc """
  The type of the schema's window field, `:time` or `:number`, or `nil` when it has none:
  the kind of window that applies to it (`Visualize.Feed.Window.applies?/2`).
  """
  @spec window_type(Schema.t()) :: :time | :number | nil
  def window_type(%Schema{} = schema) do
    case window_field(schema) do
      nil -> nil
      field -> schema |> Schema.fetch(field, :type) |> elem(1)
    end
  end

  @doc """
  A delivery finished for a request (spec/08 §11.2): trimmed to `window:` when
  `supports:` lacks `:window` and the schema has a window field, and reduced to `budget:`
  by `reduce:` (`:lttb` or `:m4`) when `supports:` lacks `:budget` and there are more
  rows than the budget, recording `reduced_by: :visualize`. A delivery that needs
  neither comes back as it is.
  """
  @spec finish(Delivery.t(), Schema.t(), keyword()) :: Delivery.t()
  def finish(%Delivery{} = delivery, %Schema{} = schema, opts) do
    opts = Keyword.validate!(opts, supports: [], window: nil, budget: nil, reduce: :lttb)

    delivery
    |> trim(schema, opts[:window], :window in opts[:supports])
    |> reduce(schema, opts[:budget], opts[:reduce], :budget in opts[:supports])
  end

  defp trim(delivery, _schema, nil, _honoured), do: delivery
  defp trim(delivery, _schema, _window, true), do: delivery

  # A window of the other kind than the window field asks for the feed's own span, so it
  # trims nothing (spec/08 §11.2).
  defp trim(delivery, schema, window, false) do
    field = window_field(schema)

    if field != nil and Window.applies?(window, window_type(schema)) do
      rows = delivery |> Table.rows() |> Window.trim(field, window)
      %{delivery | rows: rows, window: Window.intersect(delivery.window, window)}
    else
      delivery
    end
  end

  defp reduce(delivery, _schema, nil, _method, _honoured), do: delivery
  defp reduce(delivery, _schema, _budget, _method, true), do: delivery

  defp reduce(delivery, schema, budget, method, false)
       when is_integer(budget) and budget > 0 and method in [:lttb, :m4] do
    rows = Table.rows(delivery)
    clock = window_field(schema)
    numbers = for {name, %{type: :number}} <- schema.fields, name != clock, do: name

    if length(rows) <= budget or numbers == [] do
      delivery
    else
      rows = reduced(rows, schema, Enum.sort(numbers), budget, method)
      %{delivery | rows: rows, reduced_by: :visualize}
    end
  end

  # Each series — the rows sharing the values of every `:category` field — reduced field by
  # field against the window field (or the row's place), and the union of the kept rows
  # returned in their order: whole rows, every field's peaks kept.
  defp reduced(rows, schema, numbers, budget, method) do
    categories = Enum.sort(for {name, %{type: :category}} <- schema.fields, do: name)
    time = window_field(schema)

    groups =
      rows
      |> Enum.with_index()
      |> Enum.group_by(fn {row, _i} -> Enum.map(categories, &Table.get(row, &1)) end)
      |> Map.values()

    share = length(groups) * length(numbers)

    kept =
      for group <- groups, field <- numbers, reduce: MapSet.new() do
        kept ->
          group
          |> Enum.with_index()
          |> pick(time, field, share, budget, method)
          |> Enum.reduce(kept, fn {{_row, i}, _place}, acc -> MapSet.put(acc, i) end)
      end

    for {row, i} <- Enum.with_index(rows), MapSet.member?(kept, i), do: row
  end

  defp pick(points, time, field, share, budget, :lttb),
    do: Data.lttb(points, max(3, div(budget, share)), xy(time, field))

  defp pick(points, time, field, share, budget, :m4),
    do: Data.m4(points, max(1, div(budget, 4 * share)), xy(time, field))

  defp xy(nil, field), do: fn {{row, _i}, place} -> {place, Table.get(row, field)} end

  defp xy(time, field),
    do: fn {{row, _i}, _place} ->
      {Window.position(Table.get(row, time)), Table.get(row, field)}
    end
end
