defmodule Visualize.Specs.ForceSimulationTest do
  @moduledoc """
  `Visualize.Specs.ForceSimulation` (spec/06 §8.5, spec/12 §5): the intended timer
  discipline verifies exhaustively, and each defect the code shipped with is FOUND by the
  checker when its switch is flipped — a model that could not see the bugs would prove
  nothing about the fix.
  """
  use ExUnit.Case, async: true

  import ExTLA.Spec.Test

  alias Visualize.Specs.ForceSimulation

  # `ExTLA.ModelChecker.run/2` and `assert_spec/2` take a complete assignment; the module's
  # `default:` values apply to `mix extla.check` only.
  @defaults %{
    guarded_deferred_start: true,
    restart_keeps_stopped: true,
    tagged_ticks: true,
    env_active: true,
    max_stale: 2
  }

  defp constants(overrides), do: Map.merge(@defaults, overrides)

  describe "the intended design" do
    test "safety: one live timer, exactly while running, over every interleaving" do
      assert_spec(ForceSimulation, %{constants: constants(%{})})
    end

    test "liveness: with the client quiet, a target below alpha_min leads to stopped" do
      assert_spec(ForceSimulation, %{
        constants: constants(%{env_active: false}),
        check_liveness: true
      })
    end
  end

  describe "the defects, found by the checker" do
    test "an unguarded deferred start arms a second timer" do
      result =
        ExTLA.ModelChecker.run(ForceSimulation, %{
          constants: constants(%{guarded_deferred_start: false})
        })

      assert result.status == :violation
      # Both timer invariants break in the same state; the trace shows the second timer.
      assert ExTLA.Trace.format(result.violation) =~ ~r/live\s+= 2   ← changed/
    end

    test "restart on a stopped simulation starts it" do
      result =
        ExTLA.ModelChecker.run(ForceSimulation, %{
          constants: constants(%{restart_keeps_stopped: false})
        })

      assert result.status == :violation
      assert ExTLA.Trace.format(result.violation) =~ "restart_never_starts"
    end

    test "untagged ticks let a stale tick start a second chain" do
      result =
        ExTLA.ModelChecker.run(ForceSimulation, %{constants: constants(%{tagged_ticks: false})})

      assert result.status == :violation
      assert ExTLA.Trace.format(result.violation) =~ ~r/live\s+= 2   ← changed/
    end
  end
end
