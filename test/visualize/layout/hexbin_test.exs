defmodule Visualize.Layout.HexbinTest do
  @moduledoc "`Visualize.Layout.Hexbin` as spec/06 §9 says (#348)."
  use ExUnit.Case, async: true
  doctest Visualize.Layout.Hexbin

  alias Visualize.IR.Path
  alias Visualize.Layout.Hexbin

  @r 20
  @dx @r * 2 * :math.sin(:math.pi() / 3)
  @dy @r * 1.5

  test "a point at the origin bins to the cell at the origin, and counts sum" do
    assert [%{x: +0.0, y: +0.0, count: 3, points: [{0, 0}, {1, -1}, {-2, 3}]}] =
             Hexbin.bin([{0, 0}, {1, -1}, {-2, 3}], @r)
  end

  test "an odd row is offset by half a column, and cells come in lattice order" do
    cells = Hexbin.bin([{@dx, @dy}, {@dx / 2, @dy}, {0, 0}], @r)

    assert Enum.map(cells, &{&1.x, &1.y, &1.count}) == [
             {0.0, 0.0, 1},
             {@dx / 2, @dy, 1},
             {@dx * 1.5, @dy, 1}
           ]
  end

  test "the hexagon is six segments closed, at the circumradius from its centre" do
    path = Hexbin.hexagon(10, 20, @r)
    assert [{:M, _, _} | rest] = path.commands
    assert length(rest) == 6 and List.last(rest) == :Z

    for {:L, x, y} <- rest do
      assert_in_delta :math.sqrt((x - 10) * (x - 10) + (y - 20) * (y - 20)), @r, 1.0e-9
    end

    assert Path.to_string(path) =~ ~r/^M27\.3205,10L/
  end
end
