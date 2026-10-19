defmodule Examples.BoardDemo.MemoryHistory do
  @moduledoc """
  The memory metric's history, as a store holds it (spec/08 §11.5, D-159): a reading every
  ten seconds back as far as asked, in the store's own words — fields spelled `"t"` and
  `"value"`, the value in kilobytes — where the live `:telemetry` feed says `:t`, `:value`
  and megabytes.

  `Examples.BoardDemo.feeds/0` puts it behind the live feed in one `Visualize.Feed.Combine`:
  the live feed serves what it has held since the node started, this store the part of the
  window before that, its rows read in the live schema's names and converted into its unit.
  The two schemas are compatible though not equal (`Visualize.Data.Schema.compatibility/2`),
  and the combination describes itself with the live feed's, whose facts — the target and
  the polarity the design's overlays read — the store does not know.
  """
  @behaviour Visualize.Feed

  alias Examples.BoardDemo.Clock
  alias Visualize.Data.{Delivery, Schema}

  @every 10
  @most 400

  defstruct [:schema]

  def new do
    %__MODULE__{
      schema:
        Schema.new!(%{
          "t" => %{type: :time, label: "Recorded at"},
          "value" => %{type: :number, label: "Memory", unit: "kBy", quantity: :information}
        })
    }
  end

  @doc "The recorded reading at an instant, in kilobytes: a slow drift around 90 MB."
  def reading(%DateTime{} = t) do
    s = DateTime.to_unix(t)
    %{"t" => t, "value" => round(90_000 + 12_000 * :math.sin(2 * :math.pi() * s / 1800))}
  end

  @impl true
  def describe(%__MODULE__{schema: schema}), do: {Schema.version(schema), schema, [:window]}

  @impl true
  def fetch(%__MODULE__{schema: schema}, window, _budget) do
    with {:ok, from, to} <- Clock.window(window) do
      {ticks, served, capped} = Clock.ticks(from, to, @every, @most)
      rows = for tick <- ticks, do: reading(DateTime.from_unix!(tick * @every))
      {:ok, Delivery.new(rows, window: served, capped: capped, schema: Schema.version(schema))}
    end
  end
end
