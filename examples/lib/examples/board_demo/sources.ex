defmodule Examples.BoardDemo.Sources do
  @moduledoc """
  The host's own virtual-source function (spec/08 §10.5.8, D-194): trusted Elixir, tested
  as any function, captured with its source when this module compiles and run by the board
  through the same bounded runner as a stored one.
  """
  use Visualize.VirtualSources

  @doc "A host's direction over its readings: the newest against the oldest, 5 points either way."
  defsource trend(rows) do
    cpu = Enum.map(rows, & &1.cpu)
    delta = List.last(cpu) - List.first(cpu)

    trend =
      cond do
        delta > 5 -> :increasing
        delta < -5 -> :decreasing
        true -> :neutral
      end

    %{trend: trend}
  end
end
