defmodule Examples.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: Examples.PubSub},
      ExamplesWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Examples.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    ExamplesWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
