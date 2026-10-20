defmodule Examples.BoardDemo.Sources do
  @moduledoc """
  The host's own virtual-source function (spec/08 §10.5.8, D-194): trusted Elixir, tested
  as any function, captured with its source when this module compiles and run by the board
  through the same bounded runner as a stored one.
  """
  use Visualize.VirtualSources

  @doc """
  A host's direction over its readings: the least-squares slope of its CPU per reading
  (`Visualize.Data.slope/1`, #769), a point a reading either way; `nil` for a single
  reading is no direction.
  """
  defsource trend(rows) do
    slope = rows |> Enum.map(& &1.cpu) |> Visualize.Data.slope()

    trend =
      cond do
        slope == nil -> :neutral
        slope > 1 -> :increasing
        slope < -1 -> :decreasing
        true -> :neutral
      end

    %{trend: trend}
  end
end
