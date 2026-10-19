defmodule Examples.BoardDemo.Probe do
  @moduledoc """
  Emits the demo's `:telemetry` event, `[:examples, :vm]`, every half second: the memory
  in use in megabytes and the run queue's length, which the collector turns into two
  feeds (spec/08 §11.6).
  """
  use GenServer

  @every 500

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    send(self(), :probe)
    {:ok, nil}
  end

  @impl true
  def handle_info(:probe, state) do
    :telemetry.execute(
      [:examples, :vm],
      %{
        memory: Float.round(:erlang.memory(:total) / 1_048_576, 2),
        run_queue: :erlang.statistics(:total_run_queue_lengths_all)
      },
      %{}
    )

    Process.send_after(self(), :probe, @every)
    {:noreply, state}
  end
end
