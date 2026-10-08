defmodule Visualize.IR.PathBuildTest do
  @moduledoc """
  Building a path costs its commands, not a square of them (spec/02 §2.2, #414): the
  appenders put one command at the end of a list, so a builder that draws per datum
  collects its commands and makes the path once (`from_commands/1`).
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Visualize.IR.Path
  alias Visualize.Shape.Curve
  alias Visualize.Work

  test "from_commands/1 is the list it is given, in order" do
    commands = [{:M, 0, 0}, {:L, 10, 5}, {:C, 1, 2, 3, 4, 5, 6}, :Z]
    assert %Path{commands: ^commands} = Path.from_commands(commands)
    assert Path.from_commands([]) == Path.new()
    assert Path.command_count(Path.from_commands(commands)) == 4
  end

  property "a path built command by command is the path of those commands" do
    check all(
            points <-
              list_of(tuple({integer(0..1000), integer(0..1000)}), min_length: 2, max_length: 40)
          ) do
      appended =
        Enum.reduce(
          tl(points),
          Path.move_to(Path.new(), elem(hd(points), 0), elem(hd(points), 1)),
          fn {x, y}, path ->
            Path.line_to(path, x, y)
          end
        )

      assert appended == Curve.linear(points)
      assert Path.to_string(appended) == Path.to_string(Curve.linear(points))
    end
  end

  # Counted, not timed (spec/12 §6, D-114): the work of building, in reductions, at ten
  # times the points is about ten times the work — a square of them would be a hundred.
  test "a curve of fifty thousand points is built in work proportional to them" do
    line = fn n -> for i <- 1..n, do: {i, rem(i * 7, 97)} end
    {few, many} = {line.(5_000), line.(50_000)}
    {small, _} = Work.reductions(fn -> Curve.linear(few) end)
    {large, path} = Work.reductions(fn -> Curve.linear(many) end)
    assert Path.command_count(path) == 50_000

    # Appended one command at a time this was quadratic — six seconds at 50,000 points,
    # the cost of a list per command; built in order it is linear.
    assert large < small * 20,
           "ten times the points cost #{Float.round(large / small, 1)}x the reductions"
  end

  test "every curve type is built in work linear in its points" do
    points = fn n -> for i <- 1..n, do: {i, :math.sin(i / 50) * 40 + 50} end
    {thousand, ten_thousand} = {points.(1_000), points.(10_000)}

    for type <- Visualize.Chart.Schema.curve_types() do
      {small, _} = Work.reductions(fn -> Curve.generate(type, thousand) end)
      {large, path} = Work.reductions(fn -> Curve.generate(type, ten_thousand) end)
      assert Path.command_count(path) > 0, "#{type} drew nothing"

      # `:natural` and the closed loops read points with `Enum.at/2` and cost ninety to a
      # hundred times the work here until #462; every type is ten to twelve now.
      assert large < small * 20,
             "#{type}: ten times the points cost #{Float.round(large / small, 1)}x the reductions"
    end
  end
end
