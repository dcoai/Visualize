defmodule Examples.BoardDemo.Links do
  @moduledoc """
  Each network link's newest throughput (#781, work item #821): a row per host and
  interface, the four hosts of `Examples.BoardDemo.Hosts` with two interfaces each. A link
  is named by **two** fields together, so the schema declares both `host` and `iface` as
  identity (spec/08 §10.1, D-167), and a pick of a bar is the composite identity
  `%{"host" => …, "iface" => …}` the board selects (spec/15 §13.2).
  """
  @behaviour Visualize.Feed

  alias Visualize.Data.{Delivery, Schema}

  @hosts ["h1", "h2", "h3", "h4"]
  @ifaces ["eth0", "eth1"]

  defstruct [:schema]

  @doc "The interfaces each host has."
  def ifaces, do: @ifaces

  def new do
    %__MODULE__{
      schema:
        Schema.new!(%{
          host: %{type: :category, label: "Host", identity: true},
          iface: %{type: :category, label: "Interface", identity: true},
          link: %{type: :category, label: "Link"},
          mbps: %{type: :number, label: "Throughput", unit: "Mbit/s"}
        })
    }
  end

  @impl true
  def describe(%__MODULE__{schema: schema}), do: {Schema.version(schema), schema, []}

  @impl true
  def fetch(%__MODULE__{schema: schema}, _window, _budget) do
    s = DateTime.to_unix(DateTime.utc_now())

    rows =
      for {host, i} <- Enum.with_index(@hosts), {iface, j} <- Enum.with_index(@ifaces) do
        level = 300 + 150 * i - 200 * j
        mbps = Float.round(level + 120 * :math.sin(s / (60 + 17 * i) + j), 1)
        %{host: host, iface: iface, link: "#{host}/#{iface}", mbps: max(mbps, 5.0)}
      end

    {:ok, Delivery.new(rows, schema: Schema.version(schema))}
  end
end
