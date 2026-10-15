defmodule Visualize.Chart.DownsampleTest do
  @moduledoc """
  The `:lttb` and `:m4` data steps (spec/14 §5.4.1, #448): the step over the rows, its
  binding to the plot's width, its faults, gaps that still break the drawn path, and the
  proposal's acceptance — a 100,000-point line reduced by `:m4` to a 600 px plot draws the
  same pixel columns as the unreduced line.
  """
  # Not async: the acceptance reduces and draws 100,000 rows twice, and timing-sensitive
  # tests elsewhere (the viewport's cost ratio in CompiledTest) must not share the CPU with it.
  use ExUnit.Case, async: false

  import Visualize.Chart.Build

  alias Visualize.{Chart, Data, Scale}
  alias Visualize.Chart.{Frame, Mark, Transform, Validator}

  defp run(step, rows, opts \\ []), do: Transform.apply([step], rows, opts)

  defp wave(count) do
    for i <- 0..(count - 1), do: %{t: i, v: :math.sin(i / 40) * 10 + rem(i * 7919, 13), id: i}
  end

  describe "the steps over rows" do
    test ":lttb is Data.lttb/3 over the two columns, keeping whole rows" do
      rows = wave(1_000)
      kept = run(%{op: :lttb, fields: [:t, :v], n: 50}, rows)

      assert kept == Data.lttb(rows, 50, &{&1.t, &1.v})
      assert length(kept) == 50
      assert Enum.all?(kept, &(&1 in rows))
    end

    test ":m4 is Data.m4/3 over the two columns" do
      rows = wave(1_000)

      assert run(%{op: :m4, fields: [:t, :v], width: 30}, rows) ==
               Data.m4(rows, 30, &{&1.t, &1.v})
    end

    test "n: :plot and width: :plot read the plot's width, whole pixels up" do
      rows = wave(1_000)

      assert length(run(%{op: :lttb, fields: [:t, :v], n: :plot}, rows, size: [72.4, 50])) == 73

      assert run(%{op: :m4, fields: [:t, :v], width: :plot}, rows, size: [40, 50]) ==
               run(%{op: :m4, fields: [:t, :v], width: 40}, rows)
    end

    test "a time column reads in seconds, as :window reads one" do
      epoch = ~U[2026-01-01 00:00:00Z]
      timed = for %{t: t} = row <- wave(500), do: %{row | t: DateTime.add(epoch, t)}
      numbered = wave(500)

      ids = fn rows -> Enum.map(rows, & &1.id) end

      assert ids.(run(%{op: :lttb, fields: [:t, :v], n: 40}, timed)) ==
               ids.(run(%{op: :lttb, fields: [:t, :v], n: 40}, numbered))

      assert ids.(run(%{op: :m4, fields: [:t, :v], width: 25}, timed)) ==
               ids.(run(%{op: :m4, fields: [:t, :v], width: 25}, numbered))
    end

    test "n at or above the row count is the rows unchanged" do
      rows = wave(20)
      assert run(%{op: :lttb, fields: [:t, :v], n: 20}, rows) == rows
    end

    test "the faults are the step's" do
      rows = wave(20)

      assert_raise ArgumentError, ~r/:lttb .*n is at least 3, got 2/, fn ->
        run(%{op: :lttb, fields: [:t, :v], n: 2}, rows)
      end

      assert_raise ArgumentError, ~r/:m4 needs at least one pixel column/, fn ->
        run(%{op: :m4, fields: [:t, :v], width: 0}, rows)
      end

      assert_raise ArgumentError, ~r/:lttb: :n is an integer or :plot/, fn ->
        run(%{op: :lttb, fields: [:t, :v], n: "10"}, rows)
      end

      assert_raise ArgumentError, ~r/:m4: fields is \[x, y\]/, fn ->
        run(%{op: :m4, fields: [:t], width: 10}, rows)
      end

      assert_raise ArgumentError, ~r/:lttb: :v reads "x", which is not a number/, fn ->
        run(%{op: :lttb, fields: [:t, :v], n: 3}, [
          %{t: 0, v: 1},
          %{t: 1, v: "x"},
          %{t: 2, v: 1},
          %{t: 3, v: 0}
        ])
      end

      assert_raise ArgumentError, ~r/:m4: :t reads :soon, which is not a time/, fn ->
        run(%{op: :m4, fields: [:t, :v], width: 3}, [%{t: :soon, v: 1}])
      end

      assert_raise ArgumentError, ~r/transform :lttb needs :n/, fn ->
        run(%{op: :lttb, fields: [:t, :v]}, rows)
      end
    end
  end

  describe "the schema and the validator" do
    test "both ops are transform ops with their required keys" do
      assert :lttb in Chart.Schema.transform_ops()
      assert :m4 in Chart.Schema.transform_ops()
      assert Chart.Schema.transform_keys(:lttb) == %{required: [:fields, :n], optional: []}
      assert Chart.Schema.transform_keys(:m4) == %{required: [:fields, :width], optional: []}
    end

    test ":plot validates for :lttb and :m4 and not for :take; width is :m4's alone" do
      ok = fn step -> Validator.validate(design([step])) end

      assert ok.(%{op: :lttb, fields: [:t, :v], n: :plot}) == :ok
      assert ok.(%{op: :m4, fields: [:t, :v], width: :plot}) == :ok
      assert ok.(%{op: :m4, fields: [:t, :v], width: 600}) == :ok
      assert {:error, [_]} = ok.(%{op: :take, n: :plot})
      assert {:error, [_]} = ok.(%{op: :lttb, fields: [:t, :v], n: :wide})

      assert {:error, [{_path, {:invalid_for, :lttb}}]} =
               ok.(%{op: :lttb, fields: [:t, :v], n: 3, width: 3})

      assert {:error, [{_path, :required}]} = ok.(%{op: :m4, fields: [:t, :v]})
    end

    test "the builder appends both steps" do
      assert lttb(:s, [:t, :v], :plot) ==
               %{source: :s, transforms: [%{op: :lttb, fields: [:t, :v], n: :plot}]}

      assert m4(from(:s), [:t, :v], 600) ==
               %{source: :s, transforms: [%{op: :m4, fields: [:t, :v], width: 600}]}
    end
  end

  # A one-frame design whose line reads the source through `steps`, margins of 30 and 20
  # so a 650-wide render has a 600 px plot.
  defp design(steps) do
    %{
      version: 3,
      sources: %{s: %{fields: [:t, :v]}},
      frames: %{
        main: %{
          kind: :cartesian,
          margin: %{top: 10, right: 20, bottom: 10, left: 30},
          scales: %{x: %{kind: :linear}, y: %{kind: :linear}}
        }
      },
      marks: [%{type: :line, data: %{source: :s, transforms: steps}, channels: %{x: :t, y: :v}}]
    }
  end

  defp applied(steps, rows, size \\ {650, 300}) do
    {:ok, applied} = Chart.apply(design(steps), sources: %{s: rows}, size: size)
    applied
  end

  defp mark_rows(applied),
    do: Mark.rows(applied.frames.main, hd(applied.chart.marks), applied.sources)

  describe "through Visualize.Chart.apply/2" do
    test ":plot binds to the frame's plot width, and follows it when the size changes" do
      rows = wave(5_000)
      step = %{op: :lttb, fields: [:t, :v], n: :plot}

      assert applied([step], rows).frames.main.plot.width == 600
      assert length(mark_rows(applied([step], rows))) == 600
      assert length(mark_rows(applied([step], rows, {350, 300}))) == 300
    end

    test "a run of nil readings still breaks the drawn path, after either step" do
      rows =
        for i <- 0..2_999 do
          if i in 1_200..1_349, do: %{t: i, v: nil}, else: %{t: i, v: :math.sin(i / 50)}
        end

      for step <- [
            %{op: :lttb, fields: [:t, :v], n: 200},
            %{op: :m4, fields: [:t, :v], width: :plot}
          ] do
        reduced = mark_rows(applied([step], rows))
        assert Enum.count(reduced, &is_nil(&1.v)) == 1

        # The line's path: two subpaths, one per defined run, as the unreduced line draws.
        assert subpaths(applied([step], rows)) == 2
        assert subpaths(applied([], rows)) == 2
      end
    end
  end

  # The number of `M` commands in the line mark's drawn path — the longest `d` the
  # render holds, the axes having none of their own of that length.
  defp subpaths(applied) do
    ~r/<path[^>]*\sd="([^"]+)"/
    |> Regex.scan(Chart.render(applied), capture: :all_but_first)
    |> Enum.map(&hd/1)
    |> Enum.max_by(&String.length/1)
    |> String.graphemes()
    |> Enum.count(&(&1 == "M"))
  end

  describe "acceptance (#448): 100,000 points reduced by :m4 to a 600 px plot" do
    # A noisy wave with rare spikes, seeded so it is the same every run: the case a
    # uniform sample loses and an average flattens.
    defp spiky(count) do
      :rand.seed(:exsss, {448, 600, 100_000})

      for i <- 0..(count - 1) do
        spike = if :rand.uniform() < 0.0005, do: (:rand.uniform() - 0.5) * 300, else: 0
        %{t: i * 0.25, v: :math.sin(i / 2_000) * 40 + (:rand.uniform() - 0.5) * 12 + spike}
      end
    end

    test "every pixel column keeps its top, bottom, entry and exit" do
      rows = spiky(100_000)
      whole = applied([], rows)
      reduced = applied([%{op: :m4, fields: [:t, :v], width: :plot}], rows)
      kept = mark_rows(reduced)

      # The reduction is drastic, and the scales are the same: M4 keeps the extremes, so
      # the inferred domains — and so every pixel position — are the unreduced line's.
      assert length(kept) <= 4 * 600
      assert length(kept) > 600
      x = Frame.scale(reduced.frames.main, :x)
      y = Frame.scale(reduced.frames.main, :y)
      assert x == Frame.scale(whole.frames.main, :x)
      assert y == Frame.scale(whole.frames.main, :y)
      assert x.range == [0, 600]

      # Each point's pixel column (the plot's right edge belongs to its last column) and
      # its vertical pixel position, both through the frame's own scales.
      pixels = fn rs ->
        rs
        |> Enum.map(&{min(599, floor(Scale.apply(x, &1.t))), Scale.apply(y, &1.v)})
        |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      end

      before = pixels.(rows)
      after_m4 = pixels.(kept)

      assert Map.keys(after_m4) == Map.keys(before)
      assert map_size(before) == 600

      for {column, ys} <- before do
        kept_ys = after_m4[column]
        assert Enum.min(kept_ys) == Enum.min(ys), "column #{column}: bottom differs"
        assert Enum.max(kept_ys) == Enum.max(ys), "column #{column}: top differs"
        assert hd(kept_ys) == hd(ys), "column #{column}: entry differs"
        assert List.last(kept_ys) == List.last(ys), "column #{column}: exit differs"
      end
    end
  end
end
