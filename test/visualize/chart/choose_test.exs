defmodule Visualize.Chart.ChooseTest do
  # Consumers of a field's values (spec/14 §5.2, §4.5, §7.4; D-194): a choice by value,
  # a legend of declared values, and coverage of the values a schema declares.
  use ExUnit.Case, async: true

  alias Visualize.Chart
  alias Visualize.Data.{Delivery, Schema}

  @state :"health.state"

  defp design(marks, frame \\ %{}) do
    %{
      version: 3,
      sources: %{hosts: %{fields: [:x, :y, @state]}},
      frames: %{
        main:
          Map.merge(
            %{kind: :cartesian, scales: %{x: %{kind: :linear}, y: %{kind: :linear}}},
            frame
          )
      },
      marks: marks
    }
  end

  defp choose(extra \\ %{}) do
    Map.merge(
      %{
        type: :choose,
        data: :hosts,
        channels: %{x: :x, y: :y},
        on: @state,
        cases: %{ok: %{type: :circle, style: :good}, error: %{type: :symbol, style: :bad}}
      },
      extra
    )
  end

  @rows [
    %{x: 1, y: 1, "health.state": :ok},
    %{x: 2, y: 3, "health.state": "error"},
    %{x: 3, y: 2, "health.state": :warning}
  ]

  @schema Schema.new!(%{
            x: %{type: :number},
            y: %{type: :number},
            "health.state": %{type: :category, values: [:ok, :warning, :error]}
          })

  defp delivery, do: Delivery.new(@rows, schema: Schema.version(@schema))
  defp describe, do: fn :hosts -> {:ok, @schema} end

  describe ":choose" do
    test "each datum is drawn by the child its value names, the cases in name order, then else" do
      marks = [choose(%{else: %{type: :text, label: %{text: "?"}}})]
      {:ok, applied} = Chart.apply(design(marks), sources: %{hosts: @rows})
      svg = Chart.render(applied)

      [_, inner] = String.split(svg, ~s(class="mark mark-choose"), parts: 2)
      assert inner =~ ~r/mark-symbol.*mark-circle.*mark-text/s
      assert length(Regex.scan(~r/<circle /, inner)) == 1
    end

    test "a value no case names, with no else, draws nothing" do
      {:ok, applied} = Chart.apply(design([choose()]), sources: %{hosts: @rows})
      refute Chart.render(applied) =~ "mark-text"
    end

    test "its keys are its own; on and cases are required; a child is a point mark" do
      line = %{type: :line, data: :hosts, channels: %{x: :x, y: :y}, on: :x}

      assert {:error, [{[:marks, 0, :on], {:invalid_for, :line}}]} =
               Chart.from_map(design([line]))

      bare = %{type: :choose, data: :hosts, channels: %{x: :x, y: :y}}

      assert {:error, [{[:marks, 0, :cases], :required}, {[:marks, 0, :on], :required}]} =
               Chart.from_map(design([bare]))

      bad =
        choose(%{
          cases: %{ok: %{type: :line}, a: %{type: :circle, channels: %{x0: :x}}},
          on: :nope
        })

      assert {:error, errors} = Chart.from_map(design([bad]))
      assert {[:marks, 0, :cases, :a, :channels, :x0], {:invalid_for, :circle}} in errors

      assert {[:marks, 0, :cases, :ok, :type], {:enum, [:circle, :symbol, :text, :rect]}} in errors

      assert {[:marks, 0, :on], {:undeclared, :field, :nope}} in errors
    end

    test "the JSON form round-trips" do
      {:ok, chart} = Chart.from_map(design([choose(%{else: %{type: :rect}})]))
      {:ok, json} = Chart.to_json(chart)
      assert Chart.from_json(json) == {:ok, chart}
    end
  end

  describe "a legend of declared values" do
    test "entries are the values, swatched by the style each names" do
      frame = %{legend: %{values: Chart.fact(:hosts, @state, :values), title: "Health"}}
      marks = [%{type: :circle, data: :hosts, channels: %{x: :x, y: :y}}]

      {:ok, applied} =
        Chart.apply(design(marks, frame),
          sources: %{hosts: delivery()},
          describe: describe(),
          theme: Visualize.Theme.default()
        )

      svg = Chart.render(applied)
      assert svg =~ ~s(data-series="ok")

      # A style whose fill is a paint swatches by its stroke (the print theme hatches roles).
      {:ok, print} =
        Chart.apply(design(marks, frame),
          sources: %{hosts: delivery()},
          describe: describe(),
          theme: Visualize.Theme.print()
        )

      refute Chart.render(print) =~ "{:paint"

      # A compiled chart's legend region is static: it reads no scale.
      {:ok, %{main: compiled}} = Chart.compile(applied)

      assert Visualize.Chart.Compiled.svg(compiled, %{hosts: delivery()}) =~
               ~s(data-series="warning")

      assert svg =~ ~s(data-series="warning")
      assert svg =~ ~s(fill="var(--vis-warning)
    end
  end

  describe "coverage of declared values (spec/14 §7.4)" do
    defp applied(marks, styles \\ %{}) do
      Chart.apply(Map.put(design(marks), :styles, styles),
        sources: %{hosts: delivery()},
        describe: describe()
      )
    end

    test "a choose names every value, or has an else" do
      assert {:error, [{[:marks, 0, :cases], {:uncovered, @state, [:warning]}}]} =
               applied([choose()])

      assert {:ok, _applied} = applied([choose(%{else: %{type: :circle}})])
    end

    test "a style by field names a style for every value" do
      mark = %{
        type: :circle,
        data: :hosts,
        channels: %{x: :x, y: :y},
        style: [:outline, {:field, @state}]
      }

      # :warning is a palette name; :ok and :error are not.
      assert {:error, [{[:marks, 0, :style], {:uncovered, @state, [:ok, :error]}} = fault]} =
               applied([mark])

      assert Chart.Validator.format(fault) =~ "names no style or case"

      assert {:ok, _applied} =
               applied([mark], %{
                 ok: %{fill: %{color: Visualize.Color.color(:good)}},
                 error: %{fill: %{color: Visualize.Color.color(:bad)}}
               })
    end

    test "a field with no declared values, or a slot with no schema, is not checked" do
      assert {:ok, _applied} = Chart.apply(design([choose()]), sources: %{hosts: @rows})
    end
  end
end
