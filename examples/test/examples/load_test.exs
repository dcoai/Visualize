defmodule Examples.LoadTest do
  @moduledoc """
  The synthetic load and the log-age chart drawn from it (#415, #418): the signal is
  band-limited, and a point on the log-age axis is the mean of the span its slot covers,
  so the aged trace drifts leftward instead of boiling.
  """
  use ExUnit.Case, async: true

  alias Examples.Charts.{Load, LoadAge}

  doctest Load

  describe "the signal is band-limited (#418)" do
    test "a load average cannot jump: one second moves it by a fraction of its noise" do
      # The one-minute window is the jumpiest, with a noise of 0.55 over knots ten seconds
      # apart: smoothstep's steepest slope is 1.5 and two knots differ by at most 2, so a
      # second moves it by at most 0.55 · 2 · 1.5 / 10 of a load plus the sine's own
      # 0.8 · 2π / 600 — 0.174, against the 1.1 an independent hash per second gave.
      steps = for t <- 0..1800, do: abs(Load.at(:one, t + 1) - Load.at(:one, t))
      assert Enum.max(steps) <= 0.55 * 2 * 1.5 / 10 + 0.8 * 2 * :math.pi() / 600

      # A longer average is the steadier line, at every window.
      assert Enum.max(for(t <- 0..1800, do: abs(Load.at(:fifteen, t + 1) - Load.at(:fifteen, t)))) <
               Enum.max(steps)
    end

    test "it is still a pure function of its absolute second, and never at rest" do
      assert Load.at(:five, 1234) == Load.at(:five, 1234.4)
      assert Enum.all?(for(t <- 0..600, do: Load.at(:one, t)), &(&1 >= 0.05))
    end

    test "a span's mean is its readings', and one shorter than a stride is one reading" do
      assert Load.mean(:one, 100, 100) == Load.at(:one, 100)

      readings = for t <- 1000..1100, do: Load.at(:one, t)
      mean = Load.mean(:one, 1000, 1100)
      assert mean >= Enum.min(readings) and mean <= Enum.max(readings)
    end
  end

  describe "a log-age point stands for a bucket (#418)" do
    defp trace(tick, window) do
      {_design, %{loads: rows}} = LoadAge.design(animation_tick: tick)
      for %{window: ^window} = row <- rows, into: %{}, do: {row.age, row.load}
    end

    test "the aged trace drifts rather than boiling: a tick barely moves an old point" do
      before = trace(100, "1 min")
      later = trace(101, "1 min")

      aged =
        for {age, was} <- before, age >= 600, do: abs(later[age] - was)

      # Point-sampled on an independent second, these slots — seven minutes apart at the
      # oldest end, read three seconds later — moved by a third of a load on average and
      # by very nearly a whole one at worst. As bucket means they barely move.
      assert Enum.sum(aged) / length(aged) < 0.05
      assert Enum.max(aged) < 0.2
    end

    test "every window is drawn at every age, and the newest slot is a single reading" do
      {_design, %{loads: rows}} = LoadAge.design(animation_tick: 0)
      assert length(rows) == 3 * length(LoadAge.ages())

      newest = Enum.min(LoadAge.ages())
      [%{load: load}] = for(row <- rows, row.age == newest and row.window == "1 min", do: row)
      assert load == Load.at(:one, 10_800 - newest)
    end
  end
end
