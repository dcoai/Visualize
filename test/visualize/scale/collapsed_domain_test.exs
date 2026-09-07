defmodule Visualize.Scale.CollapsedDomainTest do
  @moduledoc "D-49: a collapsed domain maps to the range midpoint; nothing raises."
  use ExUnit.Case, async: true

  alias Visualize.Scale

  @t ~U[2024-01-01 00:00:00Z]

  defp continuous do
    [
      {"linear", Scale.linear() |> Scale.domain([5, 5]) |> Scale.range([0, 100]), 5, 7},
      {"log", Scale.log() |> Scale.domain([10, 10]) |> Scale.range([0, 100]), 10, 3},
      {"power", Scale.power() |> Scale.domain([5, 5]) |> Scale.range([0, 100]), 5, 7},
      {"symlog", Scale.symlog() |> Scale.domain([5, 5]) |> Scale.range([0, 100]), 5, 7},
      {"time", Scale.time() |> Scale.domain([@t, @t]) |> Scale.range([0, 100]), @t,
       DateTime.add(@t, 3600, :second)}
    ]
  end

  test "apply/2 returns the range midpoint for the domain value and for any other" do
    for {name, scale, at, elsewhere} <- continuous() do
      assert Scale.apply(scale, at) == 50.0, name
      assert Scale.apply(scale, elsewhere) == 50.0, name
    end
  end

  test "invert/2 on a collapsed domain returns d0" do
    for {name, scale, at, _} <- continuous() do
      assert Scale.invert(scale, 30) == at, name
    end
  end

  test "invert/2 on a collapsed range returns the domain midpoint" do
    scale = Scale.linear() |> Scale.domain([0, 10]) |> Scale.range([40, 40])
    assert Scale.invert(scale, 40) == 5.0
  end

  test "normalize/3 is d3's normalize" do
    assert Visualize.Scale.Behaviour.normalize(3, 1, 5) == 0.5
    assert Visualize.Scale.Behaviour.normalize(1, 1, 5) == 0.0
    assert Visualize.Scale.Behaviour.normalize(9, 4, 4) == 0.5
  end
end
