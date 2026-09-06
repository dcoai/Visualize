defmodule Visualize.IR.PathTransformTest do
  @moduledoc "`IR.Path.transform/2` under the affine contract (spec/02 §2.2, D-35)."
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Visualize.IR.{Path, Transform}

  @path %Path{
    commands: [
      {:M, 1, 2},
      {:l, 3, 4},
      {:H, 9},
      {:h, 2},
      {:V, 5},
      {:v, -1},
      {:c, 1, 1, 2, 2, 3, 3},
      {:S, 4, 4, 5, 5},
      {:q, 1, 0, 2, 0},
      {:T, 7, 7},
      {:A, 20, 10, 0, 0, 1, 30, 30},
      {:a, 5, 5, 0, 1, 0, -2, -2},
      :Z,
      {:m, 1, 1},
      {:L, 0, 0}
    ]
  }

  test "a translation moves absolute points only and keeps every single-axis command" do
    translated = Path.transform(@path, {1, 0, 0, 1, 10, 20})

    assert translated.commands == [
             {:M, 11, 22},
             {:l, 3, 4},
             {:H, 19},
             {:h, 2},
             {:V, 25},
             {:v, -1},
             {:c, 1, 1, 2, 2, 3, 3},
             {:S, 14, 24, 15, 25},
             {:q, 1, 0, 2, 0},
             {:T, 17, 27},
             {:A, 20.0, 10.0, 0.0, 0, 1, 40, 50},
             {:a, 5.0, 5.0, 0.0, 1, 0, -2, -2},
             :Z,
             {:m, 1, 1},
             {:L, 10, 20}
           ]
  end

  test "a Transform struct is folded through to_matrix/1" do
    assert Path.transform(@path, Transform.translate(10, 20)) ==
             Path.transform(@path, {1, 0, 0, 1, 10, 20})
  end

  test "a leading relative move is absolute, as SVG reads it" do
    path = %Path{commands: [{:m, 1, 1}, {:l, 1, 1}]}
    assert Path.transform(path, {1, 0, 0, 1, 10, 20}).commands == [{:m, 11, 21}, {:l, 1, 1}]
  end

  test "H and V follow the current point and become L under a rotation" do
    path = %Path{commands: [{:M, 0, 0}, {:H, 10}, {:V, 5}, {:h, 2}, {:v, 1}]}
    rotated = Path.transform(path, Transform.rotate(90))

    assert [{:M, _, _}, {:L, x1, y1}, {:L, x2, y2}, {:l, dx, dy}, {:l, dx2, dy2}] =
             rotated.commands

    assert_in_delta x1, 0, 1.0e-9
    assert_in_delta y1, 10, 1.0e-9
    assert_in_delta x2, -5, 1.0e-9
    assert_in_delta y2, 10, 1.0e-9
    assert_in_delta dx, 0, 1.0e-9
    assert_in_delta dy, 2, 1.0e-9
    assert_in_delta dx2, -1, 1.0e-9
    assert_in_delta dy2, 0, 1.0e-9
  end

  test "a scale keeps H and V single-axis and scales them" do
    path = %Path{commands: [{:M, 1, 1}, {:H, 10}, {:v, 3}]}
    assert Path.transform(path, {2, 0, 0, 3, 0, 0}).commands == [{:M, 2, 3}, {:H, 20}, {:v, 9}]
  end

  test "an arc's ellipse is mapped exactly" do
    arc = %Path{commands: [{:M, 0, 0}, {:A, 20, 10, 0, 0, 1, 30, 30}]}

    [_, {:A, rx, ry, rot, 0, 1, _, _}] = Path.transform(arc, Transform.rotate(90)).commands
    assert_in_delta rx, 20, 1.0e-9
    assert_in_delta ry, 10, 1.0e-9
    assert_in_delta rot, 90, 1.0e-9

    circle = %Path{commands: [{:M, 0, 0}, {:A, 10, 10, 0, 0, 1, 30, 30}]}
    [_, {:A, rx, ry, rot, 0, 1, _, _}] = Path.transform(circle, Transform.scale(2, 1)).commands
    assert_in_delta rx, 20, 1.0e-9
    assert_in_delta ry, 10, 1.0e-9
    assert_in_delta rot, 0, 1.0e-9
  end

  test "a reflection flips the sweep flag" do
    arc = %Path{commands: [{:M, 0, 0}, {:A, 20, 10, 0, 0, 1, 30, 30}]}
    assert [_, {:A, _, _, _, 0, 0, 30, -30}] = Path.transform(arc, {1, 0, 0, -1, 0, 0}).commands
  end

  defp coord, do: float(min: -1000.0, max: 1000.0)

  defp command do
    one_of([
      tuple({constant(:M), coord(), coord()}),
      tuple({constant(:m), coord(), coord()}),
      tuple({constant(:L), coord(), coord()}),
      tuple({constant(:l), coord(), coord()}),
      tuple({constant(:H), coord()}),
      tuple({constant(:h), coord()}),
      tuple({constant(:V), coord()}),
      tuple({constant(:v), coord()}),
      tuple({constant(:C), coord(), coord(), coord(), coord(), coord(), coord()}),
      tuple({constant(:c), coord(), coord(), coord(), coord(), coord(), coord()}),
      tuple({constant(:S), coord(), coord(), coord(), coord()}),
      tuple({constant(:s), coord(), coord(), coord(), coord()}),
      tuple({constant(:Q), coord(), coord(), coord(), coord()}),
      tuple({constant(:q), coord(), coord(), coord(), coord()}),
      tuple({constant(:T), coord(), coord()}),
      tuple({constant(:t), coord(), coord()}),
      tuple(
        {constant(:A), float(min: 1.0, max: 50.0), float(min: 1.0, max: 50.0),
         float(min: 0.0, max: 180.0), member_of([0, 1]), member_of([0, 1]), coord(), coord()}
      ),
      tuple(
        {constant(:a), float(min: 1.0, max: 50.0), float(min: 1.0, max: 50.0),
         float(min: 0.0, max: 180.0), member_of([0, 1]), member_of([0, 1]), coord(), coord()}
      ),
      constant(:Z)
    ])
  end

  def path_gen, do: map(list_of(command(), max_length: 12), &%Path{commands: &1})

  # An arc's ellipse is the same under swapped radii with a quarter turn, and its rotation
  # is an axis angle defined modulo a half turn; compare the canonical form (D-35).
  defp numbers({tag, rx, ry, rot, large, sweep, x, y}) when tag in [:A, :a] do
    {rx, ry, rot} = if rx < ry, do: {ry, rx, rot + 90}, else: {rx, ry, rot}
    [rx, ry, :math.fmod(rot, 180.0), large, sweep, x, y]
  end

  defp numbers(cmd) when is_tuple(cmd), do: cmd |> Tuple.to_list() |> tl()
  defp numbers(:Z), do: []

  defp close?(p1, p2) do
    length(p1.commands) == length(p2.commands) and
      Enum.zip(p1.commands, p2.commands)
      |> Enum.all?(fn {c1, c2} ->
        tag = fn c -> if is_tuple(c), do: elem(c, 0), else: c end

        tag.(c1) == tag.(c2) and
          Enum.zip(numbers(c1), numbers(c2))
          |> Enum.all?(fn {a, b} ->
            abs(a - b) <= 1.0e-6 * max(1.0, abs(a)) or abs(abs(a - b) - 180) <= 1.0e-6
          end)
      end)
  end

  property "the identity leaves every path unchanged" do
    check all(path <- path_gen()) do
      assert close?(Path.transform(path, {1, 0, 0, 1, 0, 0}), path)
    end
  end

  property "translating and translating back is the identity" do
    check all(path <- path_gen(), tx <- coord(), ty <- coord()) do
      there = Path.transform(path, {1, 0, 0, 1, tx, ty})
      assert close?(Path.transform(there, {1, 0, 0, 1, -tx, -ty}), path)
    end
  end
end
