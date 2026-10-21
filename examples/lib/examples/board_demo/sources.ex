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

  @doc """
  The wave's values in ten bins (metresis #505, D-228, D-229): over the cell's variable
  `bin_domain` when it is a pair of numbers, the panel's own bounds, else over the data's
  extent. A function of two arguments, so the board gives it its context, and a change to
  the variable re-runs it; the cell's `x` scale reads the same variable, so the bins and
  the axis agree either way.
  """
  defsource wave_bins(inputs, context) do
    values = Enum.map(inputs["wave"], & &1.y)

    domain =
      case context["vars"]["bin_domain"] do
        [lo, hi] when is_number(lo) and is_number(hi) and lo < hi -> [lo, hi]
        _unset -> nil
      end

    for bin <- Visualize.Data.bin(values, thresholds: 10, domain: domain),
        do: %{lo: bin.x0, hi: bin.x1, count: length(bin.values)}
  end
end
