defmodule Visualize.Feed.Combine do
  @moduledoc """
  One feed over several, routed by window: live data and its history in one slot
  (spec/08 §11.5, D-140).

  The feeds are listed freshest first — say an in-process `:telemetry` feed holding the
  last hour, then a metresis feed holding everything. A fetch asks the first for the
  window; what it served starts at its delivery's `window` (else its earliest row), and
  the part of the window before that goes to the next feed, and so on. Each later feed's
  rows are trimmed to the half-open window it was asked for, `[from, served)`, so a row
  at a seam comes from the fresher feed alone. Every feed must describe the same schema,
  since a delivery names one version, and the schema must have a time field to route by;
  choosing the feeds and making their schemas agree is the connector's.

  A combination honours `:window`, and pushes when its first feed does: its pushes name
  the shared version and pass through unchanged. A budget is passed to every part as a
  request and left to the monitor.

  ## Examples

      iex> alias Visualize.Feed.Signals
      iex> signal = Visualize.Signals.new(:discrete, [:t, :n])
      iex> live = Signals.new(signal, tick: 9, limit: 3)
      iex> history = Signals.new(signal, tick: 9)
      iex> {:ok, delivery} = Visualize.Feed.fetch(Visualize.Feed.Combine.new([live, history]), [2, 9], nil)
      iex> {Enum.map(delivery.rows, & &1.t), delivery.window, delivery.capped}
      {[2, 3, 4, 5, 6, 7, 8, 9], [2, 9], false}

  """

  @behaviour Visualize.Feed

  alias Visualize.Data.{Delivery, Table}
  alias Visualize.Feed
  alias Visualize.Feed.Window

  @enforce_keys [:feeds]
  defstruct [:feeds]

  @type t :: %__MODULE__{feeds: [Feed.t(), ...]}

  @doc "One feed over several, freshest first."
  @spec new([Feed.t(), ...]) :: t()
  def new([_ | _] = feeds), do: %__MODULE__{feeds: feeds}

  @doc """
  The shared `{version, schema, supports}`: `{:error, {:combine_schema, versions}}` when
  the feeds describe different schemas, `{:error, :combine_time_field}` when the schema
  has no time field, and the first error of a feed that cannot describe.
  """
  @impl Feed
  def describe(%__MODULE__{feeds: feeds}) do
    with {:ok, [{version, schema, supports} | _] = described} <- describe_all(feeds, []),
         :ok <- one_version(described),
         :ok <- has_time(schema) do
      {version, schema, [:window | Enum.filter(supports, &(&1 == :push))]}
    end
  end

  defp describe_all([], acc), do: {:ok, Enum.reverse(acc)}

  defp describe_all([feed | rest], acc) do
    case Feed.describe(feed) do
      {:error, reason} -> {:error, reason}
      described -> describe_all(rest, [described | acc])
    end
  end

  defp one_version(described) do
    case Enum.uniq(for {version, _schema, _supports} <- described, do: version) do
      [_one] -> :ok
      versions -> {:error, {:combine_schema, versions}}
    end
  end

  defp has_time(schema),
    do: if(Feed.time_field(schema), do: :ok, else: {:error, :combine_time_field})

  @impl Feed
  def fetch(%__MODULE__{feeds: feeds} = combine, window, budget) do
    with {version, schema, _supports} <- describe(combine) do
      [from, to] = window || [nil, nil]
      route(feeds, Feed.time_field(schema), from, to, budget, [], true, version)
    end
  end

  # Each feed is asked for `[from, upper]`, `upper` what the fresher feeds served (the
  # window's `to` for the first). `parts` is built oldest first, since the route goes back
  # in time.
  defp route([], _time, from, _upper, _budget, parts, _first?, version),
    do: combined(parts, from, version)

  defp route([feed | rest], time, from, upper, budget, parts, first?, version) do
    case Feed.fetch(feed, [from, upper], budget) do
      {:error, reason} ->
        {:error, reason}

      {:ok, delivery} ->
        rows = delivery |> Table.rows() |> seam(time, from, upper, first?)
        served = served_from(delivery, rows, time)
        parts = [%{rows: rows, delivery: delivery, from: served} | parts]

        if covered?(served, from),
          do: combined(parts, from, version),
          else: route(rest, time, from, served || upper, budget, parts, false, version)
    end
  end

  # The freshest feed keeps its own end; every later part is strictly before what the
  # fresher ones served.
  defp seam(rows, time, from, upper, true), do: Window.trim(rows, time, [from, upper])
  defp seam(rows, time, from, upper, false), do: Window.before(rows, time, from, upper)

  defp served_from(%Delivery{window: [served, _to]}, _rows, _time) when served != nil,
    do: served

  defp served_from(_delivery, rows, time),
    do: Enum.reduce(rows, nil, &Window.earliest(&2, Table.get(&1, time)))

  defp covered?(nil, _from), do: false
  defp covered?(_served, nil), do: false
  defp covered?(served, from), do: Window.compare(served, from) != :gt

  defp combined([oldest | _] = parts, from, version) do
    freshest = List.last(parts)

    capped =
      if from == nil, do: oldest.delivery.capped, else: not covered?(oldest.from, from)

    {:ok,
     Delivery.new(Enum.flat_map(parts, & &1.rows),
       window: [Window.latest(oldest.from, from), window_to(freshest.delivery)],
       resolution: freshest.delivery.resolution,
       capped: capped,
       schema: version
     )}
  end

  defp window_to(%Delivery{window: [_from, to]}), do: to
  defp window_to(_delivery), do: nil

  @impl Feed
  def subscribe(%__MODULE__{feeds: [first | _]}, pid), do: Feed.subscribe(first, pid)

  @impl Feed
  def unsubscribe(%__MODULE__{feeds: [first | _]}, ref), do: Feed.unsubscribe(first, ref)
end
