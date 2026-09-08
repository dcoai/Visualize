defmodule Visualize.Designs do
  @moduledoc """
  The twelve metresis panel types (metresis `spec.md` §8.2: `line`, `step`, `area` and
  `stacked_area`, `bar` and `stacked_bar`, `state_timeline`, `status_strip`, `single_stat`,
  `heatmap`, `histogram`, `scatter`, `rose`; `table` is not a chart) as stored designs
  under `test/support/designs/`, one `.exs` file returning the design map each, with the
  fixture sources every one binds to. `render/2` applies a design to the fixture pool
  through `Visualize.Chart.apply/2` — slots bound, variables their defaults — and draws
  it through `Visualize.Chart.render/2`, frame and marks, which is what the goldens of
  spec/14 §5 hold.
  """

  alias Visualize.Chart

  @dir Path.join(__DIR__, "designs")
  @names ~w(line step area stacked_area bar stacked_bar state_timeline status_strip
            single_stat heatmap histogram scatter rose)a

  @t0 ~U[2026-09-08 00:00:00Z]

  @doc "Every design name, in the order of metresis's table."
  def names, do: @names

  @doc "The design map stored under the name."
  def design(name) when name in @names do
    {design, _binding} = Code.eval_file(Path.join(@dir, "#{name}.exs"))
    design
  end

  @doc "The chart of a stored design: it validates."
  def chart(name), do: Chart.from_map!(design(name))

  @doc "The fixture sources every design binds to."
  def sources do
    series =
      for {v, h} <- Enum.with_index([4, 9, 2, 7, 5, 8]),
          do: %{t: at(h), v: v, a: v, b: 10 - v, c: 3, mood: Enum.at(~w(down base up), rem(h, 3))}

    %{
      series: series,
      categories:
        for(
          {c, i} <- Enum.with_index(~w(mon tue wed thu)),
          do: %{cat: c, n: i * 3 + 2, a: i + 1, b: 4 - i, c: 2}
        ),
      states: [
        %{t0: at(0), t1: at(2), state: "ok"},
        %{t0: at(2), t1: at(3), state: "degraded"},
        %{t0: at(3), t1: at(5), state: "ok"},
        %{t0: at(5), t1: at(6), state: "down"}
      ],
      flags:
        for(
          h <- 0..5,
          do: %{t0: at(h), t1: at(h + 1), ok: if(rem(h, 4) == 3, do: "fail", else: "pass")}
        ),
      heat:
        for(
          d <- 0..2,
          h <- 0..3,
          do: %{hour: h * 6, day: Enum.at(~w(mon tue wed), d), v: rem(d * 5 + h * 3, 7)}
        ),
      samples: for(i <- 0..11, do: %{w: 70 + rem(i * 7, 11), s: 6 + rem(i * 5, 4)}),
      wind:
        for(
          {n, i} <- Enum.with_index([3, 7, 12, 5, 2, 9, 4, 6]),
          do: %{bearing: i * 45, count: n}
        ),
      events: [%{at: at(2), sha: "a1b2c3"}, %{at: at(4), sha: "d4e5f6"}]
    }
  end

  @doc """
  The design applied to the fixture pool — its slots bound, its variables their defaults
  — with `sources:` and `vars:` as `Visualize.Chart.apply/2` takes them.
  """
  def apply(name, opts \\ []) do
    {:ok, applied} = Chart.apply(chart(name), Keyword.put_new(opts, :sources, sources()))
    applied
  end

  @doc "The design rendered, frame and marks, over the fixture sources."
  def render(name, opts \\ []) do
    {binding, opts} = Keyword.split(opts, [:sources, :vars])
    Chart.render(__MODULE__.apply(name, binding), opts)
  end

  defp at(h), do: DateTime.add(@t0, h * 4 * 3600, :second)
end
