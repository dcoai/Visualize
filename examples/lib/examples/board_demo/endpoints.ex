defmodule Examples.BoardDemo.Endpoints do
  @moduledoc """
  Each service's requests by endpoint over the last minute (spec/08 §11, spec/15 §10): the
  detail board's share of traffic. Endpoints are named as routes are, long — the reason the
  design's legend cuts its labels (`max_label`, spec/14 §4.5, D-169).
  """
  @behaviour Visualize.Feed

  alias Examples.BoardDemo.Services
  alias Visualize.Data.{Delivery, Schema}

  @endpoints %{
    "api" => [
      "/api/v2/customers/{id}/invoices",
      "/api/v2/customers/{id}/payment-methods",
      "/api/v2/orders/{id}/shipments",
      "/api/v2/health"
    ],
    "web" => [
      "/checkout/review-and-confirm-order",
      "/account/notification-preferences",
      "/search?q={query}&sort=relevance",
      "/"
    ],
    "db" => [
      "SELECT orders JOIN customers (by customer_id)",
      "UPDATE inventory_reservations SET released",
      "INSERT INTO audit_log",
      "VACUUM"
    ]
  }

  defstruct [:schema]

  def new do
    %__MODULE__{
      schema:
        Schema.new!(%{
          service: %{type: :category, label: "Service"},
          endpoint: %{type: :category, label: "Endpoint", identity: true},
          requests: %{type: :number, label: "Requests", unit: "{request}"}
        })
    }
  end

  @doc "A service's endpoints, as the service names them."
  def endpoints(service), do: Map.fetch!(@endpoints, service)

  @impl true
  def describe(%__MODULE__{schema: schema}), do: {Schema.version(schema), schema, []}

  @impl true
  def fetch(%__MODULE__{schema: schema}, _window, _budget) do
    now = DateTime.utc_now()

    rows =
      for service <- Services.services(),
          {endpoint, i} <- Enum.with_index(endpoints(service)),
          do: %{
            service: service,
            endpoint: endpoint,
            requests: round(Services.value(1, service, now) * 60 / (i + 1.5))
          }

    {:ok, Delivery.new(rows, schema: Schema.version(schema))}
  end
end
