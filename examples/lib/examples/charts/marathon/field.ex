defmodule Examples.Charts.Marathon.Field do
  @moduledoc """
  The field of `Examples.Charts.Marathon` (#783): ten **fictional** elite runners, five in
  the men's race and five in the women's, in one field on one course.

  The names and bibs are made up, and so are the times. No real athlete's name, result or
  likeness is used.

  **Each runner has a pace profile**: a target finish between 2:10 and 2:35, and a
  relative pace over the course in steps of a tenth of a mile. The profile has four
  parts:

  - a trend through the race, so a runner either fades (`split` above zero, the second half
    slower) or runs a negative split (below zero);
  - a deterministic variation, two slow waves at the runner's own phase, the same on every
    compile like the old GPS track's noise;
  - a slowdown on Lemon Drop Hill, miles 21.95 to 22.57;
  - a scale, so the steps add up to the target time exactly.

  The gaps therefore open and close over the race instead of staying fixed.

  **Position is distance at the race clock.** A runner's distance at a clock time is read
  off the schedule of cumulative step times and interpolated between steps, so it is
  monotonic in time. It reaches the finish at the target time and stays there.
  """

  alias Examples.Charts.Marathon.Course

  # Steps of the pace profile: the course in 262 equal parts, a tenth of a mile each.
  @steps 262

  # Lemon Drop Hill, in miles from the start: the longest climb, late in the race.
  @hill {21.95, 22.57}
  @hill_cost 0.07

  # bib, name, division, target finish (seconds), split, phase.
  @runners [
    {"M1", "Anders Velk", "men", 7_900, -0.05, 0.4},
    {"M2", "Kofi Brannagh", "men", 7_975, 0.08, 1.9},
    {"M3", "Mateo Strandquist", "men", 8_060, -0.04, 3.1},
    {"M4", "Daniel Ostrowe", "men", 8_195, 0.07, 4.6},
    {"M5", "Jonah Kettering", "men", 8_350, -0.06, 5.5},
    {"W1", "Nadia Ferrow", "women", 8_850, 0.08, 0.9},
    {"W2", "Lena Marsk", "women", 8_930, -0.05, 2.4},
    {"W3", "Priya Calloway", "women", 9_015, 0.06, 3.7},
    {"W4", "Ilse Varrow", "women", 9_140, -0.04, 5.0},
    {"W5", "Ruth Halvard", "women", 9_280, 0.09, 6.0}
  ]

  @field (for {bib, name, division, finish, split, phase} <- @runners do
            miles = Course.miles()
            {hill_from, hill_to} = @hill

            weights =
              for i <- 0..(@steps - 1) do
                x = (i + 0.5) * miles / @steps
                trend = split * (x / miles - 0.5)

                wave =
                  0.018 * :math.sin(2 * :math.pi() * x / 3.1 + phase) +
                    0.008 * :math.sin(2 * :math.pi() * x / 1.3 + 2 * phase)

                hill = if x >= hill_from and x <= hill_to, do: @hill_cost, else: 0.0
                1.0 + trend + wave + hill
              end

            total = Enum.sum(weights)

            schedule =
              weights
              |> Enum.scan(0.0, &(&1 * finish / total + &2))
              |> then(&[0.0 | &1])
              |> List.replace_at(@steps, finish * 1.0)
              |> List.to_tuple()

            %{
              bib: bib,
              name: name,
              division: division,
              finish: finish,
              split: split,
              schedule: schedule
            }
          end)

  @doc """
  The runners, in bib order: `bib`, `name`, `division` (`"men"` or `"women"`), `finish`
  (the target in seconds), `split` (above zero a fade, below a negative split), and
  `schedule`, the race clock at each tenth-of-a-mile step.
  """
  @spec runners() :: [map()]
  def runners, do: @field

  @doc "A runner's legend key: the bib, whose letter is the division, and the name."
  @spec label(map()) :: String.t()
  def label(%{bib: bib, name: name}), do: "#{bib} #{name}"

  @doc "Every runner's legend key, in bib order: the color scale's domain."
  @spec labels() :: [String.t()]
  def labels, do: Enum.map(@field, &label/1)

  @doc "Lemon Drop Hill, `{from, to}` in miles from the start."
  @spec hill() :: {float(), float()}
  def hill, do: @hill

  @doc """
  The runner's distance in meters at `clock` seconds of race time: zero before the gun,
  interpolated along the schedule, and the course's length from the target time on.
  """
  @spec meters(map(), number()) :: float()
  def meters(_runner, clock) when clock <= 0, do: 0.0
  def meters(%{finish: finish}, clock) when clock >= finish, do: Course.length()

  def meters(%{schedule: schedule}, clock) do
    i = bisect(schedule, clock, 0, @steps)
    t0 = elem(schedule, i)
    t1 = elem(schedule, i + 1)
    (i + (clock - t0) / (t1 - t0)) * Course.length() / @steps
  end

  @doc """
  The race clock at which the runner reached `meters` along the course: the inverse of
  `meters/2`, which is what a gap to the leader is measured by.
  """
  @spec clock_at(map(), number()) :: float()
  def clock_at(%{schedule: schedule}, meters) do
    step = Course.length() / @steps
    i = min(trunc(meters / step), @steps - 1)
    t0 = elem(schedule, i)
    t0 + (elem(schedule, i + 1) - t0) * (meters / step - i)
  end

  @doc """
  The standings at `clock`: one row per runner, leader first. A runner further along is
  ahead, and of two at the finish the one who got there first. Each row carries the
  runner's position along the course, the miles covered, the place, and the gap to the
  leader in time. The gap is the clock now less the moment the leader passed the same
  point, or the difference of the two finish times once both are in.
  """
  @spec standings(number()) :: [map()]
  def standings(clock) do
    placed =
      @field
      |> Enum.map(&{&1, meters(&1, clock)})
      |> Enum.sort_by(fn {runner, m} -> {-m, finished_at(runner, clock)} end)

    [{leader, _} | _] = placed

    placed
    |> Enum.with_index(1)
    |> Enum.map(fn {{runner, m}, place} ->
      {lon, lat} = Course.at(m)

      %{
        "bib" => runner.bib,
        "name" => runner.name,
        "runner" => label(runner),
        "division" => runner.division,
        "lon" => Float.round(lon, 6),
        "lat" => Float.round(lat, 6),
        "miles" => Float.round(m / Course.mile(), 2),
        "place" => place,
        "gap" => gap(runner, leader, m, clock, place),
        "finished" => clock >= runner.finish
      }
    end)
  end

  # A runner still on the course has not finished; ties at the finish go by finish time.
  defp finished_at(%{finish: finish}, clock) when clock >= finish, do: finish
  defp finished_at(_runner, _clock), do: :infinity

  defp gap(_runner, _leader, _m, _clock, 1), do: "leader"

  defp gap(runner, leader, m, clock, _place) do
    behind =
      if clock >= runner.finish,
        do: runner.finish - leader.finish,
        else: clock - clock_at(leader, m)

    "+" <> duration(behind)
  end

  @doc "Seconds as `h:mm:ss`, or `m:ss` under the hour."
  @spec duration(number()) :: String.t()
  def duration(seconds) do
    s = max(round(seconds), 0)
    {h, m, s} = {div(s, 3600), div(rem(s, 3600), 60), rem(s, 60)}
    pad = &String.pad_leading(Integer.to_string(&1), 2, "0")
    if h > 0, do: "#{h}:#{pad.(m)}:#{pad.(s)}", else: "#{m}:#{pad.(s)}"
  end

  # The last step whose clock is at or before `clock`.
  defp bisect(_schedule, _clock, lo, hi) when hi - lo <= 1, do: lo

  defp bisect(schedule, clock, lo, hi) do
    mid = div(lo + hi, 2)

    if elem(schedule, mid) <= clock,
      do: bisect(schedule, clock, mid, hi),
      else: bisect(schedule, clock, lo, mid)
  end
end
