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
    {"verify:models", "dev", ~w(vis.verify)},
    {"consumer-compile", "prod", ~w(compile --force --warnings-as-errors)},
    {"consumer-compile", "prod", {"elixir", ~w(scripts/consumer_check.exs)}},
    {"examples:test", "test", ~w(test), "examples"},
    {"credo", "test", ~w(credo --strict)},
    {"docs", "dev", ~w(docs --warnings-as-errors)}
  ]

  def run do
    Enum.each(@jobs, &job/1)
    IO.puts("\nvis.check: every gate green")
  end

  defp job({name, env, args}), do: job({name, env, args, "."})

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
