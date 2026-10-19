defmodule Examples.BoardDemo.Status do
  @moduledoc """
  A synthetic feed of each service's state over time (spec/08 §11, spec/15 §10): a row per
  stretch a service spent in one state, `since` to `until`, the shape a state timeline
  draws. A service's state is decided every thirty seconds, mostly `ok`.

  The schema says what each state *means* — `status: %{"ok" => :good, …}` — so a design
  colors the stretches by the feed's own word (`fact(:status, :state, :status)`) and every
  theme draws that meaning in its own tones (#565, D-143). A stretch has two instants;
  `until` is the window field, so a stretch still running when a window opens is kept, and
  the connector clips each stretch to the window it was asked for.
  """
  @behaviour Visualize.Feed

  alias Examples.BoardDemo.{Clock, Services}
  alias Visualize.Data.{Delivery, Schema}

  @slot 30
  @states ["ok", "degraded", "down"]

  defstruct [:schema]

  def new do
    %__MODULE__{
      schema:
        Schema.new!(%{
          service: %{type: :category, label: "Service", identity: true},
          since: %{type: :time, label: "Since", window: false},
          until: %{type: :time, label: "Until", window: true},
          state: %{
            type: :category,
            label: "State",
            values: @states,
            status: %{"ok" => :good, "degraded" => :warning, "down" => :bad}
          }
        })
    }
  end

  @doc "A service's state over the thirty seconds a slot holds: a hash of the two, mostly `ok`."
  def state(service, slot) do
    case :erlang.phash2({service, slot}, 20) do
      n when n < 15 -> "ok"
      n when n < 19 -> "degraded"
      _ -> "down"
    end
  end

  @impl true
  def describe(%__MODULE__{schema: schema}), do: {Schema.version(schema), schema, [:window]}

  @impl true
  def fetch(%__MODULE__{schema: schema}, window, _budget) do
    with {:ok, from, to} <- Clock.window(window) do
      {from_s, to_s} = {DateTime.to_unix(from), DateTime.to_unix(to)}

      rows =
        for service <- Services.services(),
            {state, since, until} <- stretches(service, from_s, to_s),
            do: %{
              service: service,
              state: state,
              since: DateTime.from_unix!(since),
              until: DateTime.from_unix!(until)
            }

      {:ok, Delivery.new(rows, window: [from, to], schema: Schema.version(schema))}
    end
  end

  # The slots from `from` to `to` merged where a state runs on, each clipped to the two.
  defp stretches(_service, from, to) when from >= to, do: []

  defp stretches(service, from, to) do
    div(from, @slot)..div(to - 1, @slot)
    |> Enum.map(fn slot ->
      {state(service, slot), max(slot * @slot, from), min((slot + 1) * @slot, to)}
    end)
    |> Enum.chunk_by(&elem(&1, 0))
    |> Enum.map(fn [{state, since, _} | _] = run ->
      {state, since, run |> List.last() |> elem(2)}
    end)
  end
end
