defmodule Visualize.Board.Server.Budgets do
  @moduledoc false
  # The board process's budgets (spec/15 §8.2, #864, #865, #873, D-226, D-227, D-230):
  # every bound slot's, a feed's or a virtual source's, and every feed's, recomputed when
  # the width or the variables move, a slot's delivery or a source's output reduced to its
  # own, and a slot over the ceiling handed without its rows. The arithmetic is
  # `Visualize.Board.Budget`'s; this is the state it is held in.

  alias Visualize.Board
  alias Visualize.Board.Budget
  alias Visualize.Data.Table
  alias Visualize.Feed
  alias Visualize.Feed.Monitor
  alias Visualize.VirtualSource.Engine

  # Every bound slot's budget and every feed's, the largest of its slots' (spec/15 §8.2).
  @doc false
  def budgets(state, components, width, ceiling) do
    boxes = Board.boxes(state.board, width)
    budgets = Budget.slots(components, state.needs, state.slot_refs, boxes, ceiling)
    feeds = Map.keys(state.feeds)
    read = Engine.feeds_read(state.engine)
    {budgets, Budget.feeds(feeds, budgets, state.slot_refs, read, ceiling)}
  end

  # The budgets recomputed for the board's present width and components, and the monitor
  # given the feeds' (spec/15 §8.2): a `:budget` feed whose budget changed is refetched.
  @doc false
  def budgeted(state) do
    {budgets, asked} = budgets(state, state.components, state.width, state.ceiling)

    %{state | budgets: budgets, asked: asked, monitor: Monitor.budget(state.monitor, asked)}
  end

  # A slot's delivery at its own budget (spec/15 §8.2, D-226): reduced when the budget is
  # below the one its feed was asked, else as the monitor finished it, so a budget-honoring
  # feed is not reduced again to the budget it honored.
  @doc false
  def own(_state, _key, _feed, nil, _schema), do: nil
  def own(_state, _key, _feed, delivery, nil), do: delivery

  def own(state, key, feed, delivery, schema) do
    budget = Map.get(state.budgets, key)
    asked = Map.get(state.asked, feed)

    if budget != nil and (asked == nil or budget < asked),
      do: Feed.reduce(delivery, schema, budget, state.monitor.reduce),
      else: delivery
  end

  # A virtual source's output at a slot's budget (spec/15 §8.2, #873, D-230): reduced as a
  # feed's that does not name `:budget` is, `reduced_by: :visualize`, by the monitor's
  # method. A source promises no budget and its output is never pre-reduced, so it is
  # reduced whenever it holds more rows than the slot's budget; `Feed.reduce/4` hands back
  # as it is an output within the budget, or with no `:number` field besides the window
  # field, which `over_budget/2` then holds to the ceiling.
  @doc false
  def source(_state, _key, nil, _schema), do: nil
  def source(_state, _key, delivery, nil), do: delivery

  def source(state, key, delivery, schema),
    do: Feed.reduce(delivery, schema, Map.get(state.budgets, key), state.monitor.reduce)

  # A slot whose delivery, at its own budget, still holds more rows than the ceiling
  # (spec/15 §8.2, D-227): handed with no delivery, so its cell never holds the rows, and
  # the status `{:over_budget, rows, ceiling}` — unless its feed is down, which says more.
  # `nil` for a slot within the ceiling, and for every slot of a board with none.
  @doc false
  def over_budget(%{delivery: nil}, _ceiling), do: nil
  def over_budget(_data, nil), do: nil

  def over_budget(%{delivery: delivery, status: status} = data, ceiling) do
    rows = length(Table.rows(delivery))

    cond do
      rows <= ceiling -> nil
      match?({:down, _reason}, status) -> %{data | delivery: nil}
      true -> %{data | delivery: nil, status: {:over_budget, rows, ceiling}}
    end
  end
end
