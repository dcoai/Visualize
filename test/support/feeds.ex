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

  defmodule Broken do
    @moduledoc """
    A feed that is honest unless given a flaw: the conformance kit's negatives (spec/08
    §12.4). Its rows are `%{t: 0..19, v: …}`, one series a tick apart, `t` its numeric
    window field (`window: true`, D-154); it honors a numeric window, a budget (every `k`-th row, `reduced_by: :feed`, the resolution `k`)
    and push, and `emit/1` pushes one new row under a new version of its schema, the
    schema first. Each flaw breaks one rule of the contract and nothing else.
    """
    @behaviour Visualize.Feed

    alias Visualize.Data.{Delivery, Schema}

    @enforce_keys [:agent]
    defstruct [:agent, :flaw]

    @flaws [
      nil,
      :down,
      :unstable_version,
      :wrong_version,
      :stale_version,
      :served_window_lie,
      :missing_row,
      :capped_lie,
      :uncapped_lie,
      :reduction_unrecorded,
      :resolution_lie,
      :window_overrun,
      :budget_overrun,
      :push_undeclared,
      :no_handshake,
      :data_before_schema,
      :keeps_pushing,
      :raises,
      :ticks_as_time,
      :no_window_field,
      :stamp_as_number,
      :misspelled_unit,
      :identified,
      :no_identity
    ]

    @last 19

    @doc "The feed with a flaw (`nil` for an honest one), its agent linked to the caller."
    def new(flaw \\ nil) when flaw in @flaws do
      {:ok, agent} = Agent.start_link(fn -> %{subscribers: %{}, generation: 0, describes: 0} end)
      %__MODULE__{agent: agent, flaw: flaw}
    end

    @doc "Every flaw the feed can be given."
    def flaws, do: tl(@flaws)

    @impl true
    def describe(%__MODULE__{flaw: :down}), do: {:error, :down}

    def describe(%__MODULE__{agent: agent, flaw: flaw} = feed) do
      n = Agent.get_and_update(agent, &{&1.describes, %{&1 | describes: &1.describes + 1}})

      schema =
        if flaw == :unstable_version,
          do: schema("call #{n}", flaw),
          else: schema(feed)

      version =
        if flaw == :wrong_version, do: String.duplicate("0", 64), else: Schema.version(schema)

      supports =
        if flaw == :push_undeclared, do: [:window, :budget], else: [:window, :budget, :push]

      {version, schema, supports}
    end

    @impl true
    def fetch(%__MODULE__{flaw: :down}, _window, _budget), do: {:error, :down}

    def fetch(%__MODULE__{flaw: flaw} = feed, window, budget) do
      case bounds(window) do
        {:ok, from, to} ->
          {:ok, served(feed, flaw, from, to, budget, window)}

        # One raise is the flaw; more would only add crash reports to the test log.
        :error when flaw == :raises and window == [:not, :a_time] ->
          raise ArgumentError, "unreadable window #{inspect(window)}"

        :error ->
          {:error, {:window, window}}
      end
    end

    @impl true
    def subscribe(%__MODULE__{flaw: :down}, _pid), do: {:error, :down}

    def subscribe(%__MODULE__{agent: agent, flaw: flaw} = feed, pid) do
      ref = make_ref()
      Agent.update(agent, &put_in(&1.subscribers[ref], pid))

      if flaw != :no_handshake do
        schema = schema(feed)
        send(pid, {:visualize_feed, ref, {:schema, Schema.version(schema), schema}})
      end

      {:ok, ref}
    end

    @impl true
    def unsubscribe(%__MODULE__{flaw: :keeps_pushing}, _ref), do: :ok

    def unsubscribe(%__MODULE__{agent: agent}, ref) do
      Agent.update(agent, &%{&1 | subscribers: Map.delete(&1.subscribers, ref)})
    end

    @doc "One new row pushed to every subscriber, under a new version of the schema."
    def emit(%__MODULE__{agent: agent, flaw: flaw}) do
      {generation, subscribers} =
        Agent.get_and_update(agent, fn state ->
          state = %{state | generation: state.generation + 1}
          {{state.generation, state.subscribers}, state}
        end)

      schema = schema("generation #{generation}", flaw)
      version = Schema.version(schema)
      t = 100 + generation
      delivery = Delivery.new([row(t, 1, flaw)], window: [t, t], schema: version)

      messages =
        if flaw == :data_before_schema,
          do: [{:delivery, delivery}, {:schema, version, schema}],
          else: [{:schema, version, schema}, {:delivery, delivery}]

      for {ref, pid} <- subscribers,
          message <- messages,
          do: send(pid, {:visualize_feed, ref, message})

      :ok
    end

    defp schema(%__MODULE__{agent: agent, flaw: flaw}) do
      case Agent.get(agent, & &1.generation) do
        0 -> schema("Value", flaw)
        n -> schema("generation #{n}", flaw)
      end
    end

    # The tick is a `:number` window field; three flaws misdescribe it (D-154): ticks
    # called `:time`, a window feed that names no window field, and a second `:time` field
    # written as numbers.
    defp schema(label, flaw) when is_binary(label) do
      t =
        case flaw do
          :ticks_as_time -> %{type: :time}
          :no_window_field -> %{type: :number}
          _honest -> %{type: :number, window: true}
        end

      fields = %{t: t, v: %{type: :number, label: label}}
      fields = if flaw == :stamp_as_number, do: Map.put(fields, :at, %{type: :time}), else: fields

      # Rows about two units, which `:identified` names in every row and `:no_identity`
      # leaves out of some (D-167).
      fields =
        if flaw in [:identified, :no_identity],
          do: Map.put(fields, :unit, %{type: :category, identity: true}),
          else: fields

      misspelled(Schema.new!(fields), flaw)
    end

    # A schema assembled around `Schema.new/1`, its value field in a unit visualize does
    # not read (D-157): the struct a provider could build by hand.
    defp misspelled(%Schema{fields: fields} = schema, :misspelled_unit),
      do: %{schema | fields: put_in(fields, [:v, :unit], "mss")}

    defp misspelled(schema, _flaw), do: schema

    defp row(t, v, :stamp_as_number), do: %{t: t, v: v, at: t}
    defp row(t, v, :identified), do: %{t: t, v: v, unit: if(rem(t, 2) == 0, do: "a", else: "b")}
    defp row(t, v, :no_identity) when rem(t, 3) == 0, do: %{t: t, v: v}
    defp row(t, v, :no_identity), do: row(t, v, :identified)
    defp row(t, v, _flaw), do: %{t: t, v: v}

    defp bounds(nil), do: {:ok, nil, nil}

    defp bounds([from, to] = window) do
      if Enum.all?(window, &(is_nil(&1) or is_number(&1))), do: {:ok, from, to}, else: :error
    end

    defp bounds(_window), do: :error

    # The honest answer, then the one rule a flaw breaks.
    defp served(feed, flaw, from, to, budget, window) do
      lo = max(from || 0, 0)
      hi = min(to || @last, @last)
      lo = if flaw == :uncapped_lie and from != nil, do: lo + 3, else: lo
      lo = if flaw == :window_overrun, do: 0, else: lo
      hi = if flaw == :window_overrun, do: @last, else: hi

      rows = for t <- lo..hi//1, do: row(t, rem(t * 7, 5), flaw)
      rows = if flaw == :missing_row and from != nil, do: List.delete_at(rows, 2), else: rows

      {rows, step} =
        if budget && flaw != :budget_overrun && length(rows) > budget do
          step = ceil(length(rows) / budget)
          {Enum.take_every(rows, step), step}
        else
          {rows, 1}
        end

      reduced_by = if step > 1 and flaw != :reduction_unrecorded, do: :feed

      Delivery.new(rows,
        window: [if(flaw == :served_window_lie, do: lo + 2, else: lo), hi],
        resolution: if(flaw == :resolution_lie, do: 2, else: step),
        capped: flaw == :capped_lie and window != nil and from != nil,
        reduced_by: reduced_by,
        schema:
          if(flaw == :stale_version,
            do: String.duplicate("0", 64),
            else: Schema.version(schema(feed))
          )
      )
    end
  end

  defmodule Fleet do
    @moduledoc """
    A fleet of cars as a feed, for the box window (spec/08 §11.1, D-168): rows
    `%{t, car, x, y}` over ticks `0..11`, three cars a tick, `t` its numeric window field
    and `car` its declared identity. Honoring (`honors: true`, the default), it names
    `[:window, :region, :latest]` and answers a box itself, by its own code rather than
    `Visualize.Feed.Window`'s, so the two can be held to the same rows; otherwise it names
    `[:window]` and leaves the region and `latest` to `Visualize.Feed.finish/3`. A flaw
    breaks one rule of an honoring feed: `:region_overrun` ignores the region,
    `:latest_twice` ignores `latest`, `:stale_latest` serves each car's first row.
    """
    @behaviour Visualize.Feed

    alias Visualize.Data.{Delivery, Schema}

    defstruct honors: true, flaw: nil

    @last 11
    @cars ["a", "b", "c"]

    @doc "The fleet's feed: `honors:` (`true`) and `flaw:` (`nil`)."
    def new(opts \\ []) do
      opts = Keyword.validate!(opts, honors: true, flaw: nil)
      true = opts[:flaw] in [nil, :region_overrun, :latest_twice, :stale_latest]
      struct!(__MODULE__, opts)
    end

    @doc "The fleet's schema."
    def schema do
      Schema.new!(%{
        t: %{type: :number, window: true},
        car: %{type: :category, identity: true},
        x: %{type: :number},
        y: %{type: :number}
      })
    end

    @doc "Every row the fleet holds, in tick order, the cars in order within a tick."
    def rows do
      for t <- 0..@last,
          {car, i} <- Enum.with_index(@cars),
          do: %{t: t, car: car, x: rem(t * 3 + i * 5, 10), y: rem(t * 7 + i * 2, 10)}
    end

    @impl true
    def describe(%__MODULE__{honors: honors}) do
      supports = if honors, do: [:window, :region, :latest], else: [:window]
      {Schema.version(schema()), schema(), supports}
    end

    @impl true
    def fetch(%__MODULE__{} = feed, window, _budget) do
      case span(window) do
        {:ok, from, to} ->
          lo = max(from || 0, 0)
          hi = min(to || @last, @last)
          rows = Enum.filter(rows(), &(&1.t >= lo and &1.t <= hi))
          rows = if feed.honors, do: honored(rows, window, feed.flaw), else: rows
          {:ok, Delivery.new(rows, window: [lo, hi], schema: Schema.version(schema()))}

        :error ->
          {:error, {:window, window}}
      end
    end

    defp span(nil), do: {:ok, nil, nil}

    defp span([from, to])
         when (is_number(from) or is_nil(from)) and (is_number(to) or is_nil(to)),
         do: {:ok, from, to}

    defp span(%{} = box) do
      case Map.get(box, :ranges, %{}) |> Enum.find(fn {f, _r} -> to_string(f) == "t" end) do
        nil -> {:ok, nil, nil}
        {_t, range} -> span(range)
      end
    end

    defp span(_window), do: :error

    defp honored(rows, %{} = box, flaw) do
      # A range over a field the fleet does not have keeps nothing.
      ranges =
        for {f, r} <- Map.get(box, :ranges, %{}), to_string(f) != "t", do: {to_string(f), r}

      rows =
        if flaw == :region_overrun, do: rows, else: Enum.filter(rows, &in_ranges?(&1, ranges))

      if Map.get(box, :latest, false) and flaw != :latest_twice,
        do: last_of_each(rows, flaw),
        else: rows
    end

    defp honored(rows, _window, _flaw), do: rows

    defp in_ranges?(row, ranges) do
      Enum.all?(ranges, fn {field, [from, to]} ->
        value = Enum.find_value(row, fn {k, v} -> if Atom.to_string(k) == field, do: v end)
        value != nil and (from == nil or value >= from) and (to == nil or value <= to)
      end)
    end

    defp last_of_each(rows, flaw) do
      pick =
        if flaw == :stale_latest,
          do: &Enum.min_by(&1, fn r -> r.t end),
          else: &Enum.max_by(&1, fn r -> r.t end)

      kept = rows |> Enum.group_by(& &1.car) |> Enum.map(fn {_car, rs} -> pick.(rs) end)
      Enum.filter(rows, &(&1 in kept))
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
