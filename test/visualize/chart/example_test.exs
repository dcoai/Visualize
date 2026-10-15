defmodule Visualize.Chart.ExampleTest do
  @moduledoc """
  The worked example of spec/14 §13, read from the document itself so the two cannot
  drift: it validates, round-trips as a map and as JSON, its JSON carries the tagged
  terms of §11.2, its `Visualize.Chart.Build` pipeline (§16) folds to the identical map,
  and it renders over the sources the section names — through
  `Visualize.Chart.apply/2` and `Visualize.Chart.render/2` on SVG and canvas, and through
  `Visualize.Chart.compile/2` (#72, D-67).
  """
  use ExUnit.Case, async: true

  alias Visualize.Chart
  alias Visualize.Chart.{Compiled, Frame, Validator}

  @spec_path Path.expand("../../../spec/14-declarative-chart.md", __DIR__)

  # The `elixir` blocks of one section, in order. §13 holds both — the literal design and
  # the `Build` pipeline beside it — and says so in its own prose. They were taken by
  # position in the whole file until a block added to an earlier section silently became
  # "the example"; a section is what each is about, so a section is what they come from.
  defp blocks_under(heading) do
    [_, below] = @spec_path |> File.read!() |> String.split("\n" <> heading, parts: 2)
    [section | _] = String.split(below, "\n## ", parts: 2)
    [_ | blocks] = String.split(section, "```elixir\n")
    for block <- blocks, do: block |> String.split("\n```", parts: 2) |> hd()
  end

  defp eval(block) do
    {value, _binding} = Code.eval_string(block)
    value
  end

  defp worked, do: blocks_under("## 13. Worked example")
  defp example, do: worked() |> Enum.at(0) |> eval()
  defp pipeline, do: worked() |> Enum.at(1) |> eval()

  defp at(h), do: DateTime.add(~U[2026-09-08 00:00:00Z], h * 3600, :second)

  defp idle, do: for({v, h} <- Enum.with_index([97.5, 99.1, 98.2, 99.9]), do: %{t: at(h), v: v})
  defp deploys, do: [%{at: at(1), sha: "a1b2c3"}, %{at: at(3), sha: "d4e5f6"}]
  defp sources, do: %{primary: idle(), deploys: deploys()}

  test "the Build pipeline beside the literal folds to the identical map" do
    assert {:ok, built} = pipeline()
    assert built == example()
  end

  test "validates and round-trips" do
    design = example()
    assert Validator.validate(design) == :ok
    chart = Chart.from_map!(design)
    # A text is written as the string it is (§7.1), whatever form the design gave it; the
    # example declares no paints, and `to_map/1` writes the schema's default for them.
    # The example declares no paints, no layout and no interaction, and `to_map/1` writes
    # the schema's default for each (§2.7, §2.8, §2.9).
    defaults = %{defs: %{}, layout: %{}, interaction: %{}}
    assert Chart.to_map(chart) == Map.merge(Visualize.Chart.Migration.canonical(design), defaults)
    {:ok, json} = Chart.to_json(chart)
    assert Chart.from_json(json) == {:ok, chart}
    # A text travels as its string, with its holes spelled as they are written (§7.1, §11).
    assert json =~ ~S|#{field(:sha)}|
    assert json =~ ~S|#{var(:unit)}|
    assert json =~ ~s({"$axis":"y"})
  end

  test "applies over the sources §13 names and renders one group per mark on SVG" do
    assert {:ok, applied} = Chart.apply(example(), sources: sources(), vars: %{unit: "mg/hr"})

    # The histogram's bins line up with the line on `y`; its counts run along `count`.
    assert Frame.scale(applied.frames.main, :count).domain == [0, 1]
    assert Frame.scale(applied.frames.main, :count).range == [0, 120]
    assert Frame.scale(applied.frames.main, :y).domain == [0.0, 100.0]

    svg = Chart.render(applied)
    assert svg =~ ~s(class="mark mark-line")
    assert svg =~ ~s(class="mark mark-rule")
    assert svg =~ ~s(class="mark mark-rect")
    assert svg =~ ~s(class="axis axis-top")
    assert svg =~ "deploy a1b2c3" and svg =~ "Uptime — mg/hr"
  end

  test "renders on a canvas and compiles" do
    {:ok, applied} = Chart.apply(example(), sources: sources())

    canvas = Chart.render(applied, backend: :canvas)
    assert canvas =~ "ctx." and not (canvas =~ "var(")

    {:ok, %{main: compiled}} = Chart.compile(applied)
    assert Enum.all?(Compiled.targets(compiled), &match?({:svg, _}, &1))
    assert Compiled.svg(compiled, applied.sources) == Chart.render(applied)
  end
end
