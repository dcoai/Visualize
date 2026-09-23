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

  test "a curve of fifty thousand points is built in time proportional to them" do
    big = for i <- 1..50_000, do: {i, rem(i * 7, 97)}
    {us, path} = :timer.tc(fn -> Curve.linear(big) end)
    assert Path.command_count(path) == 50_000

    # Built in order this is milliseconds; appended one command at a time it was six
    # seconds, the cost of a list per command. A second is a hundredfold of the one and a
    # sixth of the other, so the bound holds whatever else the machine is doing.
    assert us < 1_000_000, "50,000 points took #{div(us, 1000)} ms to build"
  end

  test "every curve type builds the same path it always did, at ten thousand points" do
    points = for i <- 1..10_000, do: {i, :math.sin(i / 50) * 40 + 50}

    for type <- Visualize.Chart.Schema.curve_types() do
      {us, path} = :timer.tc(fn -> Curve.generate(type, points) end)
      assert Path.command_count(path) > 0, "#{type} drew nothing"

      assert us < 2_000_000,
             "#{type} took #{div(us, 1000)} ms over 10,000 points"
    end
  end
end
