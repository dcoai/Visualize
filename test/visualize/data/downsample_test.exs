defmodule Visualize.Data.DownsampleTest do
  @moduledoc """
  `Visualize.Data.lttb/3` and `m4/3` (spec/08 §5.2, #448): the canonical
  Largest-Triangle-Three-Buckets selection on vectors worked by hand, M4's per-column
  guarantee, gaps kept as gaps, and the edges of both.
  """
  use ExUnit.Case, async: true

  alias Visualize.Data

  doctest Visualize.Data

  defp indexed(ys), do: ys |> Enum.with_index() |> Enum.map(fn {y, x} -> {x, y} end)
  defp xs(points), do: Enum.map(points, &elem(&1, 0))

  # A deterministic noisy series with spikes, so a uniform sample would lose them.
  defp series(count, seed) do
    :rand.seed(:exsss, {seed, seed * 7, seed * 13})

    for i <- 0..(count - 1) do
      spike = if :rand.uniform() < 0.002, do: (:rand.uniform() - 0.5) * 400, else: 0
      {i, :math.sin(i / 300) * 50 + (:rand.uniform() - 0.5) * 20 + spike}
    end
  end

  describe "lttb/3 — the canonical selection" do
    # x = 0..6, n = 4: every = 5/2. Bucket 0 is indices 1..2 against a = (0, 0) and the
    # mean of 3..5, (4, 2): doubled areas |−4y + 2x| are 2 and 4, so index 2. Bucket 1 is
    # 3..5 against a = (2, 0) and the last point (6, 0): areas 4|y| are 20, 0, 4, so 3.
    test "a seven-point vector worked by hand" do
      points = indexed([0, 1, 0, 5, 0, 1, 0])
      assert points |> Data.lttb(4) |> xs() == [0, 2, 3, 6]
    end

    # x = 0..9, n = 5: every = 8/3.
    #   bucket 0 = 1..2,  a = (0, 0), mean of 3..5 = (4, 14/3): |−4y + 14x/3| = 11.3, 5.3 → 1
    #   bucket 1 = 3..5,  a = (1, 4), mean of 6..8 = (7, 10/3): 4.7, 32.0, 9.3           → 4
    #   bucket 2 = 6..8,  a = (4, 9), last point (9, 5):         27, 7, 29                → 8
    test "a ten-point vector worked by hand" do
      points = indexed([0, 4, 1, 3, 9, 2, 2, 8, 0, 5])
      assert points |> Data.lttb(5) |> xs() == [0, 1, 4, 8, 9]
    end

    test "a tie keeps the earliest point of the bucket" do
      # Bucket 0 is 1..3 with the last point (4, 0) after it: 1 and 2 both stand 1 above
      # the base line, so their triangles tie.
      points = [{0, 0}, {1, 1}, {2, 1}, {3, 0}, {4, 0}]
      assert points |> Data.lttb(3) |> xs() |> Enum.take(2) == [0, 1]
    end

    test "without gaps: exactly n, the ends kept, one point per bucket, in order" do
      points = series(5_000, 1)
      n = 137
      kept = Data.lttb(points, n)
      indices = xs(kept)

      assert length(kept) == n
      assert hd(indices) == 0 and List.last(indices) == 4_999
      assert indices == Enum.sort(Enum.uniq(indices))

      every = (5_000 - 2) / (n - 2)

      for {index, i} <- indices |> Enum.slice(1..(n - 2)) |> Enum.with_index() do
        assert index >= floor(i * every) + 1 and index < floor((i + 1) * every) + 1
      end
    end

    test "keeps whole elements through the accessor" do
      rows = for i <- 0..99, do: %{t: i, v: rem(i * 37, 11), tag: "r#{i}"}
      kept = Data.lttb(rows, 10, &{&1.t, &1.v})

      assert length(kept) == 10
      assert Enum.all?(kept, &(&1 in rows))
    end
  end

  describe "lttb/3 — edges" do
    test "n at or above the length is the input unchanged, gaps and all" do
      points = [{0, 1}, {1, nil}, {2, 3}]
      assert Data.lttb(points, 3) == points
      assert Data.lttb(points, 50) == points
      assert Data.lttb([], 3) == []
    end

    test "n below 3 is refused" do
      assert_raise FunctionClauseError, fn -> Data.lttb(indexed([1, 2, 3, 4]), 2) end
    end
  end

  describe "m4/3" do
    test "every column keeps its first, last, least and greatest element" do
      points = series(20_000, 2)
      width = 173
      kept = Data.m4(points, width)

      assert Enum.all?(kept, &(&1 in points))
      assert xs(kept) == Enum.sort(xs(kept))
      assert length(kept) <= 4 * width

      column = fn {x, _y} -> min(width - 1, floor(x / 19_999 * width)) end

      by_column = fn ps -> Enum.group_by(ps, column) end
      whole = by_column.(points)
      reduced = by_column.(kept)

      assert Map.keys(whole) == Map.keys(reduced)

      for {c, column_points} <- whole do
        ys = Enum.map(column_points, &elem(&1, 1))
        kept_ys = Enum.map(reduced[c], &elem(&1, 1))

        assert Enum.min(kept_ys) == Enum.min(ys)
        assert Enum.max(kept_ys) == Enum.max(ys)
        assert hd(reduced[c]) == hd(column_points)
        assert List.last(reduced[c]) == List.last(column_points)
      end
    end

    test "a column of four or fewer is kept whole, and ties keep the earliest" do
      assert Data.m4([{0, 1}, {1, 1}, {2, 1}], 1) == [{0, 1}, {2, 1}]
      assert Data.m4([{0, 3}, {1, 1}, {2, 1}, {3, 3}, {4, 2}], 1) == [{0, 3}, {1, 1}, {4, 2}]
      assert Data.m4([{0, 1}, {1, 2}], 600) == [{0, 1}, {1, 2}]
    end

    test "one x everywhere is one column, and width below 1 is refused" do
      assert Data.m4([{5, 1}, {5, 9}, {5, 0}, {5, 4}, {5, 7}], 10) ==
               [{5, 1}, {5, 9}, {5, 0}, {5, 7}]

      assert Data.m4([], 4) == []
      assert_raise FunctionClauseError, fn -> Data.m4([{0, 1}], 0) end
    end
  end

  describe "gaps" do
    # Two runs of defined points with a run of three gaps between them, and a leading gap.
    defp gapped do
      [{-1, nil}] ++
        for(i <- 0..499, do: {i, :math.sin(i / 20)}) ++
        [{500, nil}, {501, nil}, {502, nil}] ++ for(i <- 503..999, do: {i, :math.cos(i / 20)})
    end

    test "lttb keeps each run of gaps as its first element, in place, and both run ends" do
      kept = Data.lttb(gapped(), 100)

      assert Enum.filter(kept, &is_nil(elem(&1, 1))) == [{-1, nil}, {500, nil}]
      assert hd(kept) == {-1, nil}

      {before, [{500, nil} | after_gap]} = Enum.split_while(kept, &(&1 != {500, nil}))
      assert List.last(before) == {499, :math.sin(499 / 20)}
      assert hd(after_gap) == {503, :math.cos(503 / 20)}
      assert List.last(after_gap) == {999, :math.cos(999 / 20)}

      # Each run's budget is its share of n: 500 of 997 defined points, floor(100·500/997).
      assert length(before) - 1 == 50
      assert length(after_gap) == 49
    end

    test "m4 keeps each run of gaps as its first element and reduces each run apart" do
      kept = Data.m4(gapped(), 20)

      assert Enum.filter(kept, &is_nil(elem(&1, 1))) == [{-1, nil}, {500, nil}]
      {before, [{500, nil} | after_gap]} = Enum.split_while(tl(kept), &(&1 != {500, nil}))
      assert elem(List.last(before), 0) == 499
      assert elem(hd(after_gap), 0) == 503
    end

    test "a non-number reading is a gap; nothing but gaps is one element per run" do
      assert Data.lttb([{0, nil}, {1, :na}, {2, nil}, {3, nil}], 3) == [{0, nil}]
      assert Data.m4([{nil, 1}, {nil, 2}, {0, 1}, {1, 2}], 1) == [{nil, 1}, {0, 1}, {1, 2}]
    end
  end

  # The proposal's benchmark (#448): stated, not gated — run with `mix test --only benchmark`.
  @tag :benchmark
  test "1M points reduce well inside a frame budget on this machine" do
    points = for i <- 0..999_999, do: {i, :math.sin(i / 1_000) + rem(i * 7919, 101) / 100}

    {lttb_us, kept} = :timer.tc(fn -> Data.lttb(points, 1_000) end)
    {m4_us, columns} = :timer.tc(fn -> Data.m4(points, 1_000) end)

    IO.puts(
      "\n1M points: lttb to 1000 in #{div(lttb_us, 1000)} ms, m4 to 1000 px in #{div(m4_us, 1000)} ms"
    )

    assert length(kept) == 1_000
    assert length(columns) <= 4_000
  end
end
