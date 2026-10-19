defmodule Examples.BoardDemo.Generators do
  @moduledoc """
  The board demo's host function (spec/14 §3.13): each service's color, as a host's
  palette service would answer it, called by the board's cell when it draws.

  A host function that raises takes only its cell down (spec/15 §8.3): the cell is shown
  *Crashed, restarting* and started again with a backoff, while its siblings draw on. The
  `/board` page can make this one raise for a while (`Examples.BoardDemo.Chaos`), so that
  state is on the page for anyone to see.
  """
  use Visualize.Generators

  import Visualize.Color, only: [color: 1]

  @colors %{"api" => :blue, "web" => :amber, "db" => :green}

  defgenerator service_color(service, _ctx) do
    if Examples.BoardDemo.Chaos.failing?(),
      do: raise("the palette service is unreachable"),
      else: color(Map.get(@colors, service, :gray))
  end
end

defmodule Examples.BoardDemo.Chaos do
  @moduledoc """
  Whether the board demo's host function fails, until when (spec/15 §10): a deadline in
  `:persistent_term`, set by the `/board` page's button and read by the generator.
  """

  @key {__MODULE__, :until}

  @doc "The host function fails for `ms` milliseconds from now."
  @spec fail_for(pos_integer()) :: :ok
  def fail_for(ms), do: :persistent_term.put(@key, System.monotonic_time(:millisecond) + ms)

  @doc "Whether the host function fails now."
  @spec failing?() :: boolean()
  def failing? do
    case :persistent_term.get(@key, nil) do
      nil -> false
      until -> System.monotonic_time(:millisecond) < until
    end
  end

  @doc "The host function works again."
  @spec recover() :: :ok
  def recover do
    :persistent_term.erase(@key)
    :ok
  end
end
