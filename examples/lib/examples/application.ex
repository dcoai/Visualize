defmodule Examples.Application do
  use Application

  @impl true
  def start(_type, _args) do
    # The gallery's preview cache lives for the application (#397).
    Examples.Previews.table()

    children = [
      {Phoenix.PubSub, name: Examples.PubSub},
      # A performance run's frames render here, off the view's process (#323)
      {Task.Supervisor, name: Examples.TaskSupervisor},
      # One renderer per run, for as long as the run lasts (#413)
      {DynamicSupervisor, name: Examples.RendererSupervisor, strategy: :one_for_one},
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
