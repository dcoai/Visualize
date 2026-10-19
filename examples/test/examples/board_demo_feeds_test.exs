defmodule Examples.BoardDemo.FeedsTest do
  @moduledoc """
  The board demo's feeds held to the feed contract (spec/08 §12, D-145): each module here
  is what a host writes for its own feeds — `use Visualize.Feed.Conformance` inside an
  `ExUnit.Case`, the feed and the windows it is asked for, and six tests come of it.

  A board's window is over instants (spec/15 §1.5), so each wall-clock feed is asked for
  no window and for the last five minutes; the signal under `Wave` counts ticks, and its
  wrapper is held to answering in instants.
  """

  # The last five minutes, as a board asks for them: evaluated in each test.
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
    feed: Examples.BoardDemo.Services.new(1),
    windows: [nil, Feeds.last_five_minutes()]
end

defmodule Examples.BoardDemo.FeedsTest.Hosts do
  use ExUnit.Case, async: true
  require Examples.BoardDemo.FeedsTest, as: Feeds

  use Visualize.Feed.Conformance,
    name: "Hosts",
    feed: Examples.BoardDemo.Hosts.new(),
    windows: [nil, Feeds.last_five_minutes()]
end

defmodule Examples.BoardDemo.FeedsTest.Weather do
  use ExUnit.Case, async: true
  require Examples.BoardDemo.FeedsTest, as: Feeds

  use Visualize.Feed.Conformance,
    name: "Weather",
    feed: Examples.BoardDemo.Weather.new(),
    windows: [nil, Feeds.last_five_minutes()]
end

defmodule Examples.BoardDemo.FeedsTest.Latency do
  use ExUnit.Case, async: true
  require Examples.BoardDemo.FeedsTest, as: Feeds

  use Visualize.Feed.Conformance,
    name: "Latency",
    feed: Examples.BoardDemo.Latency.new(),
    windows: [nil, Feeds.last_five_minutes()]
end

defmodule Examples.BoardDemo.FeedsTest.Status do
  use ExUnit.Case, async: true
  require Examples.BoardDemo.FeedsTest, as: Feeds

  use Visualize.Feed.Conformance,
    name: "Status",
    feed: Examples.BoardDemo.Status.new(),
    windows: [nil, Feeds.last_five_minutes()]
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
