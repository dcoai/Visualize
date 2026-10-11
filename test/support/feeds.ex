defmodule Visualize.Test.Feeds do
  @moduledoc """
  Feeds for the feed behaviour's tests (spec/08 §11): a feed whose every answer comes
  from an `Agent` the test holds, so a test can change what it says between ticks and
  count how often it was asked.

  The agent holds `schema`, `supports`, `rows` (or a function of the window and the
  budget answering a delivery's rows), `error` (answered by every call when set), `ref`
  (the subscription reference it answers) and `calls`, a count by callback.
  """

  alias Visualize.Data.{Delivery, Schema}

  defmodule Scripted do
    @moduledoc "A feed answering whatever its agent holds (`Visualize.Test.Feeds`)."
    @behaviour Visualize.Feed

    alias Visualize.Data.{Delivery, Schema}

    @enforce_keys [:agent]
    defstruct [:agent]

    @impl true
    def describe(%__MODULE__{agent: agent}) do
      state = counted(agent, :describe)

      case state.error do
        nil -> {Schema.version(state.schema), state.schema, state.supports}
        error -> {:error, error}
      end
    end

    @impl true
    def fetch(%__MODULE__{agent: agent}, window, budget) do
      state = counted(agent, :fetch)

      case state.error do
        nil -> {:ok, delivery(state, window, budget)}
        error -> {:error, error}
      end
    end

    @impl true
    def subscribe(%__MODULE__{agent: agent}, pid) do
      state = counted(agent, :subscribe)
      ref = state.ref || make_ref()
      Agent.update(agent, &%{&1 | ref: ref})
      send(pid, {:visualize_feed, ref, {:schema, Schema.version(state.schema), state.schema}})
      {:ok, ref}
    end

    @impl true
    def unsubscribe(%__MODULE__{agent: agent}, _ref) do
      counted(agent, :unsubscribe)
      :ok
    end

    defp delivery(%{rows: rows} = state, window, budget) when is_function(rows, 2) do
      {rows, facts} = rows.(window, budget)
      Delivery.new(rows, Keyword.put_new(facts, :schema, Schema.version(state.schema)))
    end

    defp delivery(state, _window, _budget),
      do: Delivery.new(state.rows, schema: Schema.version(state.schema))

    defp counted(agent, call) do
      Agent.get_and_update(agent, fn state ->
        state = update_in(state.calls[call], &((&1 || 0) + 1))
        {state, state}
      end)
    end
  end

  @doc "A scripted feed and its agent, linked to the test."
  @spec scripted(keyword()) :: {Scripted.t(), pid()}
  def scripted(opts) do
    state = %{
      schema: Keyword.fetch!(opts, :schema),
      supports: Keyword.get(opts, :supports, []),
      rows: Keyword.get(opts, :rows, []),
      error: Keyword.get(opts, :error),
      ref: nil,
      calls: %{}
    }

    {:ok, agent} = Agent.start_link(fn -> state end)
    {%Scripted{agent: agent}, agent}
  end

  @doc "How many times a scripted feed's callback ran."
  @spec calls(pid(), atom()) :: non_neg_integer()
  def calls(agent, call), do: Agent.get(agent, &Map.get(&1.calls, call, 0))

  @doc "A scripted feed's agent changed."
  @spec set(pid(), keyword()) :: :ok
  def set(agent, changes), do: Agent.update(agent, &Map.merge(&1, Map.new(changes)))

  @doc "The subscription reference a scripted feed answered."
  @spec ref(pid()) :: reference() | nil
  def ref(agent), do: Agent.get(agent, & &1.ref)

  @doc "A delivery pushed to `pid` under a scripted feed's subscription."
  @spec push(pid(), pid(), Delivery.t()) :: :ok
  def push(agent, pid, %Delivery{} = delivery) do
    send(pid, {:visualize_feed, ref(agent), {:delivery, delivery}})
    :ok
  end

  @doc "A schema pushed to `pid` under a scripted feed's subscription."
  @spec push_schema(pid(), pid(), Schema.t()) :: :ok
  def push_schema(agent, pid, %Schema{} = schema) do
    send(pid, {:visualize_feed, ref(agent), {:schema, Schema.version(schema), schema}})
    :ok
  end

  @doc """
  Every feed message in the mailbox handed to the monitor, in arrival order; any other
  message is left where it is.
  """
  @spec drain(Visualize.Feed.Monitor.t()) :: Visualize.Feed.Monitor.t()
  def drain(monitor) do
    receive do
      {:visualize_feed, _ref, _message} = message ->
        {:ok, monitor} = Visualize.Feed.Monitor.handle_message(monitor, message)
        drain(monitor)
    after
      0 -> monitor
    end
  end
end
