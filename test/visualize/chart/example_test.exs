defmodule Visualize.Chart.ExampleTest do
  @moduledoc """
  The worked example of spec/14 §13, read from the document itself so the two cannot
  drift: it validates, round-trips as a map and as JSON, its JSON carries the tagged
  terms of §11.2, and it renders over the sources the section names — through
  `Visualize.Chart.apply/2` and `Visualize.Chart.render/2` on SVG and canvas, and through
  `Visualize.Chart.compile/2` (#72, D-67).
  """
  use ExUnit.Case, async: true

  alias Visualize.Chart
  alias Visualize.Chart.{Compiled, Frame, Validator}

  @spec_path Path.expand("../../../spec/14-declarative-chart.md", __DIR__)

  defp example do
    [_, rest] = @spec_path |> File.read!() |> String.split("```elixir\n", parts: 2)
    [block | _] = String.split(rest, "\n```", parts: 2)

    {design, _} = Code.eval_string(block)
    design
  end

  defp at(h), do: DateTime.add(~U[2026-09-08 00:00:00Z], h * 3600, :second)

  defp idle, do: for({v, h} <- Enum.with_index([97.5, 99.1, 98.2, 99.9]), do: %{t: at(h), v: v})
  defp deploys, do: [%{at: at(1), sha: "a1b2c3"}, %{at: at(3), sha: "d4e5f6"}]
  defp sources, do: %{primary: idle(), deploys: deploys()}

  test "validates and round-trips" do
    design = example()
    assert Validator.validate(design) == :ok
    chart = Chart.from_map!(design)
    assert Chart.to_map(chart) == design
    {:ok, json} = Chart.to_json(chart)
    assert Chart.from_json(json) == {:ok, chart}
    assert json =~ ~s({"$field":"sha"})
    assert json =~ ~s({"$var":"unit"})
    assert json =~ ~s({"$axis":"y"})
  end

  test "applies over the sources §13 names and renders one group per mark on SVG" do
    assert {:ok, applied} = Chart.apply(example(), sources: sources(), vars: %{unit: "mg/hr"})

    # The histogram's bins line up with the line on `y`; its counts run along `count`.
    assert Frame.scale(applied.frame, :count).domain == [0, 1]
    assert Frame.scale(applied.frame, :count).range == [0, 120]
    assert Frame.scale(applied.frame, :y).domain == [0.0, 100.0]

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

    {:ok, compiled} = Chart.compile(applied)
    assert Enum.all?(Compiled.targets(compiled), &match?({:svg, _}, &1))
    assert Compiled.svg(compiled, applied.sources) == Chart.render(applied)
  end
end
