# Every gate CI runs (.gitlab-ci.yml), in CI's order, as `mix vis.check`. A script rather
# than a list alias for two reasons: the jobs need different MIX_ENVs, and Mix silently
# skips a task it has already run once inside a list alias. Stops at the first failure and
# exits non-zero, like the pipeline.
defmodule Visualize.Check do
  @jobs [
    {"format", "test", ~w(format --check-formatted)},
    {"compile", "test", ~w(compile --force --warnings-as-errors)},
    {"test", "test", ~w(test --warnings-as-errors --cover)},
    {"verify:api-surface", "dev", ~w(vis.surface --check)},
    {"verify:headings", "dev", ~w(vis.headings)},
    {"verify:citations", "dev", ~w(vis.citations)},
    {"verify:models", "dev", ~w(vis.verify)},
    {"verify:hooks", "test", ~w(test --warnings-as-errors --only js --include js_resvg), ".",
     :node},
    {"consumer-compile", "prod", ~w(compile --force --warnings-as-errors)},
    {"consumer-compile", "prod", {"elixir", ~w(scripts/consumer_check.exs)}},
    {"examples:compile", "test", ~w(compile --warnings-as-errors), "examples"},
    {"examples:test", "test", ~w(test --warnings-as-errors), "examples"},
    {"credo", "test", ~w(credo --strict)},
    {"docs", "dev", ~w(docs --warnings-as-errors)}
  ]

  def run do
    Enum.each(@jobs, &job/1)
    IO.puts("\nvis.check: every gate green")
  end

  defp job({name, env, args}), do: job({name, env, args, "."})

  # The test job's raster tests need a resvg binary, which CI downloads (spec/12 §4): here
  # it is the one VISUALIZE_RESVG names or the PATH holds, and without one
  # test/test_helper.exs excludes the :resvg tests in one printed line, as it does :js.
  #
  # A job that needs node runs when node is on the path; CI installs it (spec/12 §4), so a
  # workstation without it skips the job and stays green.
  defp job({name, env, args, dir, :node}) do
    if System.find_executable("node") do
      job({name, env, args, dir})
    else
      IO.puts("\n== #{name} ==\n#{name}: skipped: no node")
    end
  end

  # A job is `mix` with arguments, or `{command, arguments}` for a script run directly.
  defp job({name, env, {command, args}, dir}) do
    IO.puts("\n== #{name} (MIX_ENV=#{env}#{if dir != ".", do: ", in #{dir}"}) ==")

    {_, status} =
      System.cmd(command, args, env: [{"MIX_ENV", env}], cd: dir, into: IO.stream(:stdio, :line))

    if status != 0 do
      IO.puts(:stderr, "\nvis.check: #{name} failed (exit #{status})")
      System.halt(status)
    end
  end

  defp job({name, env, args, dir}) do
    IO.puts("\n== #{name} (MIX_ENV=#{env}#{if dir != ".", do: ", in #{dir}"}) ==")

    {_, status} =
      System.cmd("mix", args, env: [{"MIX_ENV", env}], cd: dir, into: IO.stream(:stdio, :line))

    if status != 0 do
      IO.puts(:stderr, "\nvis.check: #{name} failed (exit #{status})")
      System.halt(status)
    end
  end
end

Visualize.Check.run()
