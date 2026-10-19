defmodule Examples.BoardDemo.Hosts do
  @moduledoc """
  A synthetic feed of four hosts' CPU readings (spec/08 §11): a reading every ten seconds
  for each of `h1`…`h4`, each its own wave, so their health (`Examples.BoardDemo`'s
  virtual sources) moves between good, warning and bad. `host` is the declared identity
  (D-167) the virtual sources run per.
  """
  @behaviour Visualize.Feed

  alias Examples.BoardDemo.Clock
  alias Visualize.Data.{Delivery, Schema}

  @hosts ["h1", "h2", "h3", "h4"]
  @every 10
  @most 200

  defstruct [:schema]

  def new do
    %__MODULE__{
      schema:
        Schema.new!(%{
          t: %{type: :time, label: "Time"},
          host: %{type: :category, label: "Host", identity: true},
          cpu: %{type: :number, label: "CPU", unit: "%", continuity: 3 * @every}
        })
    }
  end

  @doc "A host's reading at an instant: a slow wave around its own level."
  def cpu(host, %DateTime{} = t) do
    i = Enum.find_index(@hosts, &(&1 == host))
    s = DateTime.to_unix(t)
    base = Enum.at([35, 55, 70, 50], i)

    Float.round(
      base + 30 * :math.sin(2 * :math.pi() * s / Enum.at([120, 200, 260, 90], i) + i),
      1
    )
  end

  @impl true
  def describe(%__MODULE__{schema: schema}), do: {Schema.version(schema), schema, [:window]}

  @impl true
  def fetch(%__MODULE__{schema: schema}, window, _budget) do
    with {:ok, from, to} <- Clock.window(window) do
      {ticks, served, capped} = Clock.ticks(from, to, @every, @most)

      rows =
        for tick <- ticks,
            t = DateTime.from_unix!(tick * @every),
            host <- @hosts,
            do: %{t: t, host: host, cpu: cpu(host, t)}

      {:ok, Delivery.new(rows, window: served, capped: capped, schema: Schema.version(schema))}
    end
  end
end
