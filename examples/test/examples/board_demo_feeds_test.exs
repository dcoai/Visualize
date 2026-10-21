defmodule Examples.BoardDemo.FeedsTest do
  @moduledoc """
  The board demo's feeds held to the feed contract (spec/08 §12, D-145): each module here
  is what a host writes for its own feeds — `use Visualize.Feed.Conformance` inside an
  `ExUnit.Case`, the feed and the windows it is asked for, and six tests come of it.

  A board's window is over instants (spec/15 §1.5), so each wall-clock feed is asked for
  no window and for five minutes. Their clocks are pinned (`clock:`, read through
  `Examples.BoardDemo.Clock`) at an instant whose sub-second phase is the one that matters:
  the window's start lies a fraction of a second after a reading, so a feed that rounds the
  start down to the second serves a row outside the window it says it served, every run.
  The signal under `Wave` counts ticks on the wall clock, and its wrapper is held to
  answering in instants over the last five minutes.
  """

  # Five minutes after a whole ten seconds, and 0.865612 s on: the window's start is
  # 00:05:00.865612, just after the 00:05:00 reading.
  @now ~U[2026-01-01 00:10:00.865612Z]

  @doc "The pinned now."
  def now, do: @now

  @doc "The pinned clock a feed reads."
  def clock, do: fn -> @now end

  @doc "The five minutes up to the pinned now."
  def window, do: [DateTime.add(@now, -300), @now]

  # The last five minutes on the wall clock, as a board asks for them: evaluated in each test.
  defmacro last_five_minutes do
    quote do
      now = DateTime.utc_now()
      [DateTime.add(now, -300), now]
    end
  end
end

defmodule Examples.BoardDemo.FeedsTest.Wave do
  use ExUnit.Case, async: true
  require Examples.BoardDemo.FeedsTest, as: Feeds

  use Visualize.Feed.Conformance,
    name: "Wave",
    feed:
      Examples.BoardDemo.Wave.new(
        Visualize.Signals.new(:sine, [:t, :v], period: 90, min: 0.4, max: 3.2)
      ),
    windows: [nil, Feeds.last_five_minutes()]
end

defmodule Examples.BoardDemo.FeedsTest.Latest do
  use ExUnit.Case, async: true

  use Visualize.Feed.Conformance, name: "Latest", feed: Examples.BoardDemo.Latest.new()
end

defmodule Examples.BoardDemo.FeedsTest.Services do
  use ExUnit.Case, async: true
  require Examples.BoardDemo.FeedsTest, as: Feeds

  use Visualize.Feed.Conformance,
    name: "Services",
    feed: Examples.BoardDemo.Services.new(1, clock: Feeds.clock()),
    windows: [nil, Feeds.window()]
end

defmodule Examples.BoardDemo.FeedsTest.Hosts do
  use ExUnit.Case, async: true
  require Examples.BoardDemo.FeedsTest, as: Feeds

  use Visualize.Feed.Conformance,
    name: "Hosts",
    feed: Examples.BoardDemo.Hosts.new(clock: Feeds.clock()),
    windows: [nil, Feeds.window()]
end

defmodule Examples.BoardDemo.FeedsTest.Weather do
  use ExUnit.Case, async: true
  require Examples.BoardDemo.FeedsTest, as: Feeds

  use Visualize.Feed.Conformance,
    name: "Weather",
    feed: Examples.BoardDemo.Weather.new(clock: Feeds.clock()),
    windows: [nil, Feeds.window()]
end

defmodule Examples.BoardDemo.FeedsTest.Latency do
  use ExUnit.Case, async: true
  require Examples.BoardDemo.FeedsTest, as: Feeds

  use Visualize.Feed.Conformance,
    name: "Latency",
    feed: Examples.BoardDemo.Latency.new(clock: Feeds.clock()),
    windows: [nil, Feeds.window()]
end

defmodule Examples.BoardDemo.FeedsTest.Status do
  use ExUnit.Case, async: true
  require Examples.BoardDemo.FeedsTest, as: Feeds

  use Visualize.Feed.Conformance,
    name: "Status",
    feed: Examples.BoardDemo.Status.new(clock: Feeds.clock()),
    windows: [nil, Feeds.window()]
end

defmodule Examples.BoardDemo.FeedsTest.Memory do
  use ExUnit.Case, async: false
  require Examples.BoardDemo.FeedsTest, as: Feeds

  # The live telemetry feed with the store's history behind it, one Feed.Combine: it
  # pushes as the live feed does, so the kit is shown how to make it push.
  use Visualize.Feed.Conformance,
    name: "Memory (live and history)",
    feed: Map.fetch!(Examples.BoardDemo.feeds(), "examples.vm.memory"),
    windows: [Feeds.last_five_minutes()],
    push: fn _feed ->
      :telemetry.execute([:examples, :vm], %{memory: 64.0, run_queue: 0}, %{})
    end
end

defmodule Examples.BoardDemo.FeedsTest.Links do
  use ExUnit.Case, async: true

  use Visualize.Feed.Conformance, name: "Links", feed: Examples.BoardDemo.Links.new()
end

# A feed made to put its cell in one state (#781, work item #821), a well-behaved feed still.
defmodule Examples.BoardDemo.FeedsTest.StatesStale do
  use ExUnit.Case, async: true
  require Examples.BoardDemo.FeedsTest, as: Feeds

  use Visualize.Feed.Conformance,
    name: "States :stale",
    feed: Examples.BoardDemo.States.new(:stale, clock: Feeds.clock()),
    windows: [nil, Feeds.window()]
end

# A feed made to put its cell in one state (#781, work item #821), a well-behaved feed still.
defmodule Examples.BoardDemo.FeedsTest.StatesNoData do
  use ExUnit.Case, async: true
  require Examples.BoardDemo.FeedsTest, as: Feeds

  use Visualize.Feed.Conformance,
    name: "States :no_data",
    feed: Examples.BoardDemo.States.new(:no_data, clock: Feeds.clock()),
    windows: [nil, Feeds.window()]
end

# A feed made to put its cell in one state (#781, work item #821), a well-behaved feed still.
defmodule Examples.BoardDemo.FeedsTest.StatesCapped do
  use ExUnit.Case, async: true
  require Examples.BoardDemo.FeedsTest, as: Feeds

  use Visualize.Feed.Conformance,
    name: "States :capped",
    feed: Examples.BoardDemo.States.new(:capped, clock: Feeds.clock()),
    windows: [nil, Feeds.window()]
end

# A feed made to put its cell in one state (#781, work item #821), a well-behaved feed still.
defmodule Examples.BoardDemo.FeedsTest.StatesInvalid do
  use ExUnit.Case, async: true
  require Examples.BoardDemo.FeedsTest, as: Feeds

  use Visualize.Feed.Conformance,
    name: "States :invalid",
    feed: Examples.BoardDemo.States.new(:invalid, clock: Feeds.clock()),
    windows: [nil, Feeds.window()]
end

# A feed made to over-deliver on purpose (#865, D-227): it names :budget and serves more,
# so it is no conformance module of its own; the kit is shown to name its overrun.
defmodule Examples.BoardDemo.FeedsTest.StatesOverBudget do
  use ExUnit.Case, async: true
  require Examples.BoardDemo.FeedsTest, as: Feeds

  alias Visualize.Feed.Conformance

  test "the kit names the overrun, and the overrun only" do
    feed = Examples.BoardDemo.States.new(:over_budget, clock: Feeds.clock())
    findings = Conformance.check(feed, windows: [nil, Feeds.window()])

    assert [_ | _] = findings
    assert Enum.all?(findings, &match?({:supports, {:over_budget, {_window, 5}, 6000}}, &1))
  end
end
