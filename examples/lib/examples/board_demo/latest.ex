defmodule Examples.BoardDemo.Latest do
  @moduledoc """
  Each service's newest request rate, a row per service, under the field `name`: a feed
  that names the services differently from `Examples.BoardDemo.Services`, which the board's
  `links: %{name: :service}` reconciles (spec/15 §13.2).
  """
  @behaviour Visualize.Feed

  alias Examples.BoardDemo.Services
  alias Visualize.Data.{Delivery, Schema}

  defstruct [:schema]

  def new do
    %__MODULE__{
      schema:
        Schema.new!(%{
          name: %{type: :category, label: "Service", identity: true},
          value: %{type: :number}
        })
    }
  end

  @impl true
  def describe(%__MODULE__{schema: schema}), do: {Schema.version(schema), schema, []}

  @impl true
  def fetch(%__MODULE__{schema: schema}, _window, _budget) do
    now = DateTime.utc_now()

    rows =
      for service <- Services.services(),
          do: %{name: service, value: Services.value(1, service, now)}

    {:ok, Delivery.new(rows, schema: Schema.version(schema))}
  end
end
