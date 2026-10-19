defmodule Examples.BoardDemo.Services do
  @moduledoc """
  A synthetic feed of three services' rates over time (spec/08 §11): a reading every ten
  seconds for each of `api`, `web` and `db`, each its own slow wave, scaled by the feed's
  `scale` — so one module is the board's requests and, scaled down, its errors. The rows
  are a function of the instant, so every window asked is answered at once, and a brushed
  window is answered with exactly its readings (spec/15 §13.1).
  """
  @behaviour Visualize.Feed

  alias Examples.BoardDemo.Clock
  alias Visualize.Data.{Delivery, Schema}

  @services ["api", "web", "db"]
  @every 10
  # At most this many readings per service, however wide the window.
  @most 400

  defstruct [:scale, :schema]

  @doc "The services, in the order every design colors them."
  def services, do: @services

  @doc "A feed whose readings are the waves times `scale`."
  def new(scale) do
    schema =
      Schema.new!(%{
        t: %{type: :time, label: "Time"},
        service: %{type: :category, label: "Service", identity: true},
        value: %{type: :number, label: "Rate", continuity: 3 * @every}
      })

    %__MODULE__{scale: scale, schema: schema}
  end

  @doc "One service's reading at an instant, at a scale."
  def value(scale, service, %DateTime{} = t) do
    i = Enum.find_index(@services, &(&1 == service))
    s = DateTime.to_unix(t)
    base = Enum.at([40, 25, 12], i)
    wave = :math.sin(2 * :math.pi() * s / Enum.at([180, 240, 300], i) + i)
    Float.round(scale * (base + base * 0.5 * wave), 2)
  end

  @impl true
  def describe(%__MODULE__{schema: schema}), do: {Schema.version(schema), schema, [:window]}

  @impl true
  def fetch(%__MODULE__{} = feed, window, _budget) do
    with {:ok, from, to} <- Clock.window(window) do
      {ticks, served, capped} = Clock.ticks(from, to, @every, @most)

      rows =
        for tick <- ticks,
            t = DateTime.from_unix!(tick * @every),
            service <- @services,
            do: %{t: t, service: service, value: value(feed.scale, service, t)}

      {:ok,
       Delivery.new(rows, window: served, capped: capped, schema: Schema.version(feed.schema))}
    end
  end
end
