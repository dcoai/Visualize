defmodule Visualize.Chart.ExampleTest do
  @moduledoc """
  The worked example of spec/14 §13, read from the document itself so the two cannot
  drift: it validates, round-trips as a map and as JSON, and its JSON carries the tagged
  terms of §11.2.
  """
  use ExUnit.Case, async: true

  alias Visualize.Chart
  alias Visualize.Chart.Validator

  @spec_path Path.expand("../../../spec/14-declarative-chart.md", __DIR__)

  defp example do
    [_, rest] = @spec_path |> File.read!() |> String.split("```elixir\n", parts: 2)
    [block | _] = String.split(rest, "\n```", parts: 2)

    {design, _} = Code.eval_string(block)
    design
  end

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
end
