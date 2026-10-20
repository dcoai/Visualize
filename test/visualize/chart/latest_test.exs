defmodule Visualize.Chart.LatestTest do
  @moduledoc """
  A mark that keeps each entity's latest row (spec/14 §5.4.1, §7.3, #626, D-168): a
  `:window` step with `latest: true` keeps each declared identity's last row, and
  `Visualize.Chart.apply/2` refuses it over a slot whose feed declares no identity.
  """
  use ExUnit.Case, async: true

  alias Visualize.Chart
  alias Visualize.Chart.{Build, Compiled, Mark, Transform, Validator}
  alias Visualize.Data.{Delivery, Schema}

  @fleet Schema.new!(%{
           t: %{type: :number, window: true},
           car: %{type: :category, identity: true},
           x: %{type: :number},
           y: %{type: :number}
         })

  @anonymous Schema.new!(%{
               t: %{type: :number, window: true},
               car: %{type: :category},
               x: %{type: :number},
               y: %{type: :number}
             })

  defp rows(ticks) do
    for t <- ticks,
        {car, i} <- Enum.with_index(["a", "b"]),
        do: %{t: t, car: car, x: t + i, y: t * 2 + i}
  end

  defp delivery(rows, schema \\ @fleet), do: Delivery.new(rows, schema: Schema.version(schema))

  defp design(latest \\ true) do
    %{
      version: 3,
      sources: %{cars: %{fields: [:t, :car, :x, :y]}},
      frames: %{
        main: %{
          kind: :cartesian,
          scales: %{x: %{kind: :linear, domain: [0, 20]}, y: %{kind: :linear, domain: [0, 40]}}
        }
      },
      marks: [
        %{
          type: :circle,
          data: %{
            source: :cars,
            transforms: [%{op: :window, field: :t, from: [5, :second], latest: latest}]
          },
          channels: %{x: :x, y: :y}
        }
      ]
    }
  end

  defp describe(schema), do: fn :cars -> {:ok, schema} end

  describe "the :window step" do
    test "latest keeps each declared identity's last row within the window, in order" do
      step = [%{op: :window, field: :t, from: [3, :second], latest: true}]
      kept = Transform.apply(step, rows(1..9), schema: @fleet)
      assert kept == [%{t: 9, car: "a", x: 9, y: 18}, %{t: 9, car: "b", x: 10, y: 19}]

      # An entity whose last row falls before the window has none.
      older = Enum.reject(rows(1..9), &(&1.car == "b" and &1.t > 4))
      assert [%{car: "a", t: 9}] = Transform.apply(step, older, schema: @fleet)
    end

    test "without latest the window is as it was, and latest: false is the same" do
      plain = [%{op: :window, field: :t, from: [3, :second]}]
      off = [%{op: :window, field: :t, from: [3, :second], latest: false}]
      assert Transform.apply(plain, rows(1..9)) == Transform.apply(off, rows(1..9))
      assert length(Transform.apply(plain, rows(1..9))) == 8
    end

    test "latest without a schema, or over one that declares no identity, raises" do
      step = [%{op: :window, field: :t, latest: true}]

      assert_raise ArgumentError, ~r/needs the schema of its source/, fn ->
        Transform.apply(step, rows(1..3))
      end

      assert_raise ArgumentError, ~r/declares no identity/, fn ->
        Transform.apply(step, rows(1..3), schema: @anonymous)
      end
    end

    test "the step takes latest as a boolean, and the builder appends it" do
      assert Chart.Schema.transform_keys(:window).optional == [:from, :to, :latest]

      assert %{transforms: [%{op: :window, latest: true}]} =
               Build.window(Build.from(:cars), :t, latest: true)

      bad =
        put_in(design(), [:marks, Access.at(0), :data, :transforms, Access.at(0), :latest], :yes)

      assert {:error, [{[:marks, 0, :data, :transforms, 0, :latest], {:type, :boolean}}]} =
               Validator.validate(bad)
    end
  end

  describe "apply/2" do
    test "draws each entity's latest row over a feed that declares identity" do
      assert {:ok, applied} =
               Chart.apply(design(),
                 sources: %{cars: delivery(rows(1..9))},
                 describe: describe(@fleet)
               )

      assert applied.schemas == %{"cars" => @fleet}
      [mark] = applied.frame.marks

      assert Mark.rows(applied.frame, mark, applied.sources) |> Enum.map(&{&1.car, &1.t}) == [
               {"a", 9},
               {"b", 9}
             ]
    end

    test "refuses latest over a feed that declares no identity, at the mark" do
      assert Chart.apply(design(),
               sources: %{cars: delivery(rows(1..9), @anonymous)},
               describe: describe(@anonymous)
             ) == {:error, [{[:marks, 0], {:identity_required, "cars"}}]}
    end

    test "refuses latest over rows, which have no schema and so declare nothing" do
      assert Chart.apply(design(), sources: %{cars: rows(1..9)}) ==
               {:error, [{[:marks, 0], {:identity_required, "cars"}}]}

      assert {:ok, _applied} = Chart.apply(design(false), sources: %{cars: rows(1..9)})
    end

    test "a version that does not resolve is its own fault, not the refusal" do
      assert Chart.apply(design(), sources: %{cars: delivery(rows(1..3))}) ==
               {:error, [{[:sources, "cars"], {:unknown_schema, :cars, Schema.version(@fleet)}}]}
    end

    test "the refusal reads as a line a person reads" do
      line = Validator.format({[:marks, 0], {:identity_required, "cars"}})
      assert line =~ "marks[0]"
      assert line =~ "declares no identity"
    end
  end

  test "a compiled chart keeps the latest rows tick after tick" do
    {:ok, frames} =
      Chart.compile(design(),
        sources: %{cars: delivery(rows(1..9))},
        describe: describe(@fleet),
        size: {300, 200}
      )

    compiled = frames["main"]
    assert compiled.schemas == %{"cars" => @fleet}

    {payload, _compiled} = Compiled.tick(compiled, %{cars: delivery(rows(1..12))})
    assert payload.svg =~ "<circle"
    assert length(Regex.scan(~r/<circle/, payload.svg)) == 2
  end
end
