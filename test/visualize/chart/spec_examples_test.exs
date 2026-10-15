defmodule Visualize.Chart.SpecExamplesTest.Doc do
  @moduledoc false
  # The reading of spec/14 the test is generated from; a module of its own because the
  # tests are generated at compile time, before the test module's own functions exist.

  # A deliberate skip, written on the line directly above the block's fence (spec/12 §6).
  def marker_regex, do: ~r/^<!-- not run:(.*)-->$/

  # The document as `{heading, ordinal, line, language, source, marker}` per fenced block,
  # `marker` being `{:skip, reason}` or nil. Headings are read outside fences only, since a
  # fenced `#` line is code; the ordinal counts the section's `elixir` blocks.
  def parse(text) do
    text
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reduce(%{heading: nil, fence: nil, prev: "", blocks: [], counts: %{}}, &step/2)
    |> Map.fetch!(:blocks)
    |> Enum.reverse()
  end

  defp step({line, n}, %{fence: nil} = st) do
    cond do
      String.starts_with?(line, "```") ->
        lang = String.trim_leading(line, "`") |> String.trim()
        ord = if lang == "elixir", do: Map.get(st.counts, st.heading, 0) + 1, else: nil
        counts = if ord, do: Map.put(st.counts, st.heading, ord), else: st.counts

        fence = %{
          heading: st.heading,
          ord: ord,
          line: n + 1,
          lang: lang,
          src: [],
          marker: marker(st.prev)
        }

        %{st | fence: fence, counts: counts, prev: line}

      Regex.match?(~r/^#+ /, line) ->
        %{st | heading: String.replace(line, ~r/^#+ /, ""), prev: line}

      true ->
        %{st | prev: line}
    end
  end

  defp step({"```" <> _ = line, _n}, %{fence: f} = st) do
    block =
      {f.heading, f.ord, f.line, f.lang, f.src |> Enum.reverse() |> Enum.join("\n"), f.marker}

    %{st | fence: nil, blocks: [block | st.blocks], prev: line}
  end

  defp step({line, _n}, %{fence: f} = st),
    do: %{st | fence: %{f | src: [line | f.src]}, prev: line}

  def marker(line) do
    case Regex.run(marker_regex(), String.trim(line)) do
      [_, reason] -> {:skip, String.trim(reason)}
      nil -> nil
    end
  end
end

defmodule Visualize.Chart.SpecExamplesTest do
  @moduledoc """
  Every runnable `elixir` block of spec/14, read from the document itself and run
  (spec/12 §6, #460). §13's two blocks are run by `Visualize.Chart.ExampleTest`; this is
  the same guard for the rest, so an example the API has moved away from is a red test
  rather than prose that quietly stopped being Elixir — as the README's did (#427, #454).

  Each block is paired with the heading it sits under and a test is generated per block,
  named by that heading: a block is chosen by section, never by position in the file. A
  block deliberately not runnable carries `<!-- not run: <reason> -->` on the line directly
  above its fence, and is skipped with that reason.
  """
  use ExUnit.Case, async: true

  alias Visualize.Chart.SpecExamplesTest.Doc
  alias Visualize.Chart.Validator

  @spec_path Path.expand("../../../spec/14-declarative-chart.md", __DIR__)
  @external_resource @spec_path

  # The context the sections' prose assumes for its examples (§16, §19.3).
  @prelude """
  import Visualize.Chart.Build
  import Visualize.Chart, only: [var: 1]
  alias Visualize.Chart.Use
  """

  # Run by `Visualize.Chart.ExampleTest`, which asserts far more of them than evaluation.
  @run_elsewhere ["13. Worked example"]

  # Blocks whose value is `Visualize.Chart.compose/1`'s: a whole design, which must validate.
  @pipelines [{"16.2 The design and its declarations", 1}, {"16.3 The frame", 2}]

  # Every block evaluated here, by section and ordinal within it. Held exactly, so a block
  # added to the document is noticed — classified as a pipeline, a fragment or a skip —
  # rather than covered or skipped without anyone saying so.
  @evaluated [
    {"3.1 Keys: a style in compound parts", 1},
    {"3.6 Composition at a site: the style stack", 1},
    {"3.6 Composition at a site: the style stack", 2},
    {"3.8 Defaults: inherited by container and mark kind", 1},
    {"7.4 Schemas: the contract and the facts", 1},
    {"7.4 Schemas: the contract and the facts", 2},
    {"16.2 The design and its declarations", 1},
    {"16.3 The frame", 1},
    {"16.3 The frame", 2},
    {"16.4 Marks and labels", 1},
    {"16.5 Data nodes and transforms", 1},
    {"19.3 The use site", 1},
    {"19.6 Composites: stored as structure, flattened at deployment", 1}
  ]

  @blocks @spec_path |> File.read!() |> Doc.parse()

  @runnable for {h, ord, line, "elixir", src, nil} <- @blocks,
                h not in @run_elsewhere,
                do: {h, ord, line, src}

  defp eval(source, line) do
    env = Code.env_for_eval(file: @spec_path, line: 1)
    {_, _, env} = Code.eval_quoted_with_env(Code.string_to_quoted!(@prelude), [], env)
    quoted = Code.string_to_quoted!(source, file: @spec_path, line: line)
    {value, _binding, _env} = Code.eval_quoted_with_env(quoted, [], env)
    value
  end

  for {heading, ord, line, source} <- @runnable do
    count = Enum.count(@runnable, &(elem(&1, 0) == heading))
    name = if count > 1, do: "§#{heading} (block #{ord} of #{count})", else: "§#{heading}"

    if {heading, ord} in @pipelines do
      test "#{name} composes a design that validates" do
        assert {:ok, design} = eval(unquote(source), unquote(line))
        assert Validator.validate(design) == :ok
      end
    else
      test "#{name} evaluates" do
        eval(unquote(source), unquote(line))
      end
    end
  end

  test "every elixir block is evaluated here, run by §13's test, or marked with a reason" do
    evaluated = for {h, ord, _, _} <- @runnable, do: {h, ord}
    assert evaluated == @evaluated
    assert Enum.all?(@pipelines, &(&1 in evaluated))

    elsewhere = for {h, _, _, "elixir", _, _} <- @blocks, h in @run_elsewhere, do: h
    assert length(elsewhere) == 2, "§13 holds the literal design and its Build pipeline"
  end

  test "a skip marker gives a reason and sits directly above an elixir fence" do
    for {h, _, line, lang, _, {:skip, reason}} <- @blocks do
      assert lang == "elixir", "a not-run marker above a #{lang} fence (§#{h}, line #{line - 1})"
      assert reason != "", "a not-run marker with no reason (§#{h}, line #{line - 1})"
    end

    # A marker anywhere else is a skip that skips nothing: it must sit above a fence.
    lines = @spec_path |> File.read!() |> String.split("\n")

    marked =
      for {l, i} <- Enum.with_index(lines, 1),
          Regex.match?(Doc.marker_regex(), String.trim(l)),
          do: i

    fenced = for {_, _, line, _, _, {:skip, _}} <- @blocks, do: line - 2
    assert marked == fenced
  end
end
