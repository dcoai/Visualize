defmodule Visualize.Audit.AdvisoriesTest do
  use ExUnit.Case, async: true

  alias Visualize.Audit.Advisories

  # A stand-in for `mix hex.audit`: each project's lock holds `findings`, an advisory as
  # its ids (primary and aliases) or a retirement as its package, and the audit exits 1
  # unless every finding is ignored, as Hex's does. It records every call it answers.
  defp runner(findings) do
    test = self()

    fn dir, ignores, quiet? ->
      send(test, {:audit, Path.basename(dir), ignores, quiet?})

      findings
      |> Map.get(Path.basename(dir), [])
      |> Enum.all?(&ignored?(&1, ignores))
      |> if(do: 0, else: 1)
    end
  end

  defp ignored?({:advisory, ids}, ignores), do: Enum.any?(ids, &(&1 in ignores.advisories))
  defp ignored?({:retired, package}, ignores), do: package in ignores.retirements

  @bandit {:advisory, ["EEF-CVE-2026-105659", "CVE-2026-105659", "GHSA-69m6-wcv4-rwcf"]}

  defp entry(project, finding), do: Map.merge(%{project: project, reason: "accepted"}, finding)

  test "clean locks pass, and each project's audit prints" do
    assert Advisories.run("/r", [], runner(%{})) == []

    empty = %{advisories: [], retirements: []}
    assert_received {:audit, "r", ^empty, false}
    assert_received {:audit, "examples", ^empty, false}
  end

  test "an advisory in either lock fails, naming the project" do
    assert [problem] = Advisories.run("/r", [], runner(%{"examples" => [@bandit]}))
    assert problem =~ "examples (examples/mix.lock): mix hex.audit exited 1"

    assert [problem] = Advisories.run("/r", [], runner(%{"r" => [@bandit]}))
    assert problem =~ "library (./mix.lock)"
  end

  test "a retired package fails too" do
    findings = %{"r" => [{:retired, "decimal"}]}
    assert [_] = Advisories.run("/r", [], runner(findings))
    assert Advisories.run("/r", [entry(:library, %{retired: "decimal"})], runner(findings)) == []
  end

  test "an allowed advisory passes by any of its ids, and is proved live" do
    findings = %{"examples" => [@bandit]}

    for id <- elem(@bandit, 1) do
      assert Advisories.run("/r", [entry(:examples, %{advisory: id})], runner(findings)) == []
    end

    # The probe without the entry ran quietly, and failed, so the entry is live.
    assert_received {:audit, "examples", %{advisories: []}, true}
  end

  test "an entry allows only its own project's lock" do
    findings = %{"r" => [@bandit]}
    entries = [entry(:examples, %{advisory: "EEF-CVE-2026-105659"})]

    assert [library, stale] = Advisories.run("/r", entries, runner(findings))
    assert library =~ "library (./mix.lock): mix hex.audit exited 1"
    assert stale =~ "advisory EEF-CVE-2026-105659 for examples is stale"
  end

  test "an entry the audit passes without is stale" do
    entries = [
      entry(:examples, %{advisory: "EEF-CVE-2026-105659"}),
      entry(:examples, %{advisory: "GHSA-69m6-wcv4-rwcf"})
    ]

    # Two ids of one advisory: either alone allows it, so each is redundant beside the other.
    assert [first, second] = Advisories.run("/r", entries, runner(%{"examples" => [@bandit]}))
    assert first =~ "EEF-CVE-2026-105659 for examples is stale"
    assert second =~ "GHSA-69m6-wcv4-rwcf for examples is stale"
  end

  test "a malformed entry fails before any audit runs" do
    for bad <- [
          %{project: :examples, advisory: "X"},
          %{project: :examples, advisory: "X", reason: ""},
          %{project: :gallery, advisory: "X", reason: "r"},
          %{project: :examples, reason: "r"},
          %{project: :examples, advisory: "X", retired: "y", reason: "r"}
        ] do
      assert [problem] = Advisories.run("/r", [bad], runner(%{}))
      assert problem =~ "audit/advisories_allowlist.exs"
    end

    refute_received {:audit, _, _, _}
  end

  test "the allowlist is well formed" do
    {entries, _} = Code.eval_file("audit/advisories_allowlist.exs")
    assert Advisories.run("/r", entries, fn _, _, _ -> 1 end) |> Enum.all?(&(&1 =~ "exited 1"))
  end
end
