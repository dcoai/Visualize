defmodule Visualize.ReadmeExampleTest do
  @moduledoc """
  The README's example, read from `README.md` itself and run (spec/12 §6, #454). It is the
  first code a reader runs, and nothing else executes it: the docs build checks its links
  and doctests cover documentation attributes only. It stopped compiling when #427 removed
  the size from `cartesian/1` and stayed broken until #453 noticed.
  """
  use ExUnit.Case, async: true

  @readme_path Path.expand("../../README.md", __DIR__)

  # The `elixir` blocks of one `##` section, in order. The block is taken by section, not
  # by position: the README has a second `elixir` block under `## Installation`, a `deps`
  # fragment that is not evaluable, and a block added above the example must not silently
  # become "the example".
  defp blocks_under(heading) do
    [_, below] = @readme_path |> File.read!() |> String.split("\n" <> heading <> "\n", parts: 2)
    [section | _] = String.split(below, "\n## ", parts: 2)
    [_ | blocks] = String.split(section, "```elixir\n")
    for block <- blocks, do: block |> String.split("\n```", parts: 2) |> hd()
  end

  defp example do
    assert [block] = blocks_under("## Example")
    block
  end

  test "the Example section's block evaluates, ending in the canvas render it promises" do
    {canvas, binding} = Code.eval_string(example())

    # The block's last expression is the canvas render.
    assert is_binary(canvas) and canvas =~ "ctx."

    # The SVG render before it is not the block's value, so it is asked of what it bound.
    applied = Keyword.fetch!(binding, :applied)
    svg = Visualize.Chart.render(applied)
    # SVG markup: the frame's group, which is what `render/1` gives without `root: true`
    # (spec/14 §4.7), with the line the design declares inside it.
    assert String.starts_with?(svg, ~s(<g class="frame"))
    assert svg =~ ~s(class="mark mark-line")
    assert Visualize.Chart.render(applied, backend: :canvas) == canvas
  end
end
