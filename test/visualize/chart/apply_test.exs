defmodule Visualize.Chart.ApplyTest do
  @moduledoc """
  Application of a design to its data (spec/14 §7.3, D-65): variables resolved from the
  values or their defaults, slots bound from a pool and checked against the bound rows,
  every fault by path; one design bound to two sources renders on both — the acceptance
  example of #53.
  """
  use ExUnit.Case, async: true

  alias Visualize.Chart
  alias Visualize.Chart.{Applied, Frame, Validator}

  doctest Chart

  import Chart, only: [var: 1]

  @spec_path Path.expand("../../../spec/14-declarative-chart.md", __DIR__)

  # The worked example of spec/14 §13, read from the document itself.
  defp example do
    [_, rest] = @spec_path |> File.read!() |> String.split("```elixir\n", parts: 2)
    [block | _] = String.split(rest, "\n```", parts: 2)
    {design, _} = Code.eval_string(block)
    design
  end

  defp at(h), do: DateTime.add(~U[2026-09-08 00:00:00Z], h * 3600, :second)

  defp idle, do: for({v, h} <- Enum.with_index([97.5, 99.1, 98.2, 99.9]), do: %{t: at(h), v: v})
  defp deploys, do: [%{at: at(1), sha: "a1b2c3"}, %{at: at(3), sha: "d4e5f6"}]

  defp design(overrides \\ %{}) do
    Map.merge(
      %{
        version: 1,
        sources: %{primary: %{fields: [:t, :v], default: :uptime}},
        vars: %{unit: %{default: "%"}},
        styles: %{series: %{stroke_width: 2}},
        frame: %{
          kind: :cartesian,
          size: %{width: 300, height: 200},
          scales: %{x: %{kind: :linear}, y: %{kind: :linear, domain: [0, :auto]}},
          axes: [%{scale: :x, side: :bottom}, %{scale: :y, side: :left}]
        },
        marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v}, style: :series}],
        labels: [%{anchor: {:axis, :y}, text: ["unit: ", var(:unit)]}]
      },
      overrides
    )
  end

  @rows %{t: [1, 2, 3], v: [4, 9, 2]}

  describe "the acceptance example: one design, two sources" do
    test "the worked example binds to two pools and renders on both" do
      design = example()

      {:ok, a} =
        Chart.apply(design,
          sources: %{primary: idle(), deploys: deploys()},
          vars: %{unit: "mg/hr"}
        )

      other = Enum.map(idle(), &%{&1 | v: &1.v - 10})
      {:ok, b} = Chart.apply(design, sources: %{gitlab_uptime: other, deploys: deploys()})

      assert %Applied{chart: %Chart{vars: %{}}, frame: %Frame{}} = a
      assert a.sources == %{primary: idle(), deploys: deploys()}
      assert b.sources.primary == other

      assert Enum.at(a.chart.labels, 0).text == ["Uptime — ", "mg/hr"]
      assert Enum.at(b.chart.labels, 0).text == ["Uptime — ", "%"]
      assert a.chart.styles.series.stroke == :series_1
      assert a.chart.meta.description == ["Uptime in ", "mg/hr"]

      svg_a = Chart.render(a)
      svg_b = Chart.render(b)
      assert svg_a =~ ~s(class="mark mark-line") and svg_a =~ "deploy a1b2c3"
      assert svg_a =~ ~s(class="mark mark-rect")
      assert svg_b =~ ~s(class="mark mark-line") and svg_b =~ "Uptime — %"
      refute svg_a == svg_b

      assert Frame.scale(a.frame, :y).domain == [0.0, 100.0]
      assert Frame.scale(b.frame, :y).domain == [0.0, 90.0]

      canvas = Chart.render(b, backend: :canvas)
      assert canvas =~ "ctx." and not (canvas =~ "var(")
    end

    test "a slot binds under its own name before its default" do
      {:ok, applied} =
        Chart.apply(design(), sources: %{primary: @rows, uptime: %{t: [0], v: [0]}})

      assert applied.sources == %{primary: @rows}
      assert Frame.scale(applied.frame, :y).domain == [0, 9]
    end

    test "pool entries no slot names are ignored" do
      {:ok, applied} = Chart.apply(design(), sources: %{uptime: @rows, other: %{q: [1]}})
      assert Map.keys(applied.sources) == [:primary]
    end

    test "a chart struct and a design map apply alike" do
      {:ok, from_map} = Chart.apply(design(), sources: %{uptime: @rows})
      {:ok, from_chart} = Chart.apply(Chart.from_map!(design()), sources: %{uptime: @rows})
      assert from_map == from_chart
    end

    test "the applied chart validates as a design with no variable" do
      {:ok, applied} = Chart.apply(design(), sources: %{uptime: @rows})
      assert Validator.validate(Chart.to_map(applied.chart)) == :ok
      refute inspect(applied.chart) =~ "Var"
    end

    test "a bound source is kept as the pool gave it" do
      rows = Enum.map([1, 2], &%{"t" => &1, "v" => &1 * 2})
      {:ok, applied} = Chart.apply(design(), sources: %{primary: rows})
      assert applied.sources.primary == rows
      assert Frame.scale(applied.frame, :y).domain == [0, 4]
    end
  end

  describe "binding faults" do
    test "a missing field is reported at the slot's path, one per field" do
      assert Chart.apply(design(), sources: %{primary: %{t: [1]}}) ==
               {:error, [{[:sources, :primary], {:missing_field, :v}}]}

      assert Chart.apply(design(), sources: %{primary: [%{w: 1}]}) ==
               {:error,
                [
                  {[:sources, :primary], {:missing_field, :t}},
                  {[:sources, :primary], {:missing_field, :v}}
                ]}

      assert Validator.format({[:sources, :primary], {:missing_field, :v}}) ==
               "sources.primary: has no field :v"
    end

    test "a field carried by any row, in either spelling, is present" do
      assert {:ok, _} = Chart.apply(design(), sources: %{primary: [%{t: 1}, %{v: 2}]})
      assert {:ok, _} = Chart.apply(design(), sources: %{primary: [%{"t" => 1, v: 2}]})
    end

    test "an empty source binds without a check" do
      assert {:ok, applied} = Chart.apply(design(), sources: %{primary: []})
      assert Frame.scale(applied.frame, :y).domain == [0, 1]
      assert Chart.render(applied) =~ ~s(class="mark mark-line")
    end

    test "an unbound slot is reported at its path" do
      assert Chart.apply(design()) ==
               {:error, [{[:sources, :primary], {:unbound, :source, :primary}}]}

      assert Chart.apply(design(), sources: %{other: @rows}) ==
               {:error, [{[:sources, :primary], {:unbound, :source, :primary}}]}

      assert Validator.format({[:sources, :primary], {:unbound, :source, :primary}}) =~
               "slot :primary has no source in the pool"
    end

    test "every binding fault is reported together, ordered by path" do
      sources = %{a: %{fields: [:x]}, b: %{fields: [:y, :z]}}
      marks = []
      design = design(%{sources: sources, marks: marks})

      assert Chart.apply(design, sources: %{b: [%{y: 1}]}) ==
               {:error,
                [
                  {[:sources, :a], {:unbound, :source, :a}},
                  {[:sources, :b], {:missing_field, :z}}
                ]}
    end

    test "apply/1 applies a design that declares no source" do
      design = design(%{sources: %{}, marks: []})
      assert {:ok, applied} = Chart.apply(design)
      assert applied.sources == %{}
      assert Chart.render(applied) =~ "unit: %"
    end
  end

  describe "variables" do
    test "a supplied value beats the default and a default fills an absent one" do
      {:ok, applied} = Chart.apply(design(), sources: %{uptime: @rows}, vars: %{unit: "kg"})
      assert hd(applied.chart.labels).text == ["unit: ", "kg"]

      {:ok, applied} = Chart.apply(design(), sources: %{uptime: @rows})
      assert hd(applied.chart.labels).text == ["unit: ", "%"]
      assert applied.chart.vars == %{}
    end

    test "an unresolved variable is reported at every path it is used, before binding" do
      design =
        design(%{
          vars: %{unit: %{}},
          labels: [
            %{anchor: {:axis, :y}, text: ["unit: ", var(:unit)]},
            %{anchor: :title, text: [var(:unit)]}
          ]
        })

      assert Chart.apply(design) ==
               {:error,
                [
                  {[:labels, 0, :text, 1], {:unresolved, :var, :unit}},
                  {[:labels, 1, :text, 0], {:unresolved, :var, :unit}}
                ]}

      assert Validator.format({[:labels, 1, :text, 0], {:unresolved, :var, :unit}}) ==
               "labels[1].text[0]: variable :unit has no value at application and no default"
    end

    test "a declared default of nil is no default" do
      design = design(%{vars: %{unit: %{default: nil}}})

      assert Chart.apply(design, sources: %{uptime: @rows}) ==
               {:error, [{[:labels, 0, :text, 1], {:unresolved, :var, :unit}}]}

      assert {:ok, _} = Chart.apply(design, sources: %{uptime: @rows}, vars: %{unit: "kg"})
    end

    test "a value for a variable nothing declares is reported under vars" do
      assert Chart.apply(design(), sources: %{uptime: @rows}, vars: %{unti: "kg"}) ==
               {:error, [{[:vars, :unti], {:undeclared, :var, :unti}}]}
    end

    test "a number or an atom in a text is written as a string" do
      design =
        design(%{
          vars: %{n: %{default: 3}, unit: %{default: :kg}},
          labels: [%{anchor: :title, text: ["n = ", var(:n), " ", var(:unit)]}]
        })

      {:ok, applied} = Chart.apply(design, sources: %{uptime: @rows})
      assert hd(applied.chart.labels).text == ["n = ", "3", " ", "kg"]
      assert Chart.render(applied) =~ "n = 3 kg"
    end

    test "a variable stands for a whole node" do
      design =
        design(%{
          vars: %{
            unit: %{default: "%"},
            style: %{default: %{stroke: "red", stroke_width: 4}},
            margin: %{}
          },
          styles: %{series: var(:style)},
          frame: %{
            kind: :cartesian,
            size: %{width: 300, height: 200},
            margin: var(:margin),
            scales: %{x: %{kind: :linear}, y: %{kind: :linear}}
          }
        })

      vars = %{margin: %{top: 5, right: 5, bottom: 5, left: 5}}
      {:ok, applied} = Chart.apply(design, sources: %{uptime: @rows}, vars: vars)
      assert applied.chart.styles.series == %{stroke: "red", stroke_width: 4}
      assert applied.frame.plot == %{width: 290, height: 190}
      assert Chart.render(applied) =~ ~s(stroke="red")
    end

    test "a variable's value is typed by the validator where the variable stood" do
      design = design(%{vars: %{unit: %{}, w: %{}}, styles: %{series: %{stroke_width: var(:w)}}})

      assert Chart.apply(design, sources: %{uptime: @rows}, vars: %{unit: "%", w: "thick"}) ==
               {:error, [{[:styles, :series, :stroke_width], {:type, :size}}]}
    end

    test "a variable in a transform, a channel, a slot and an option resolves" do
      design =
        design(%{
          vars: %{unit: %{default: "%"}, bins: %{default: 4}, field: %{default: :v}},
          sources: %{primary: %{fields: [:t, var(:field)]}},
          marks: [
            %{
              type: :rect,
              data: %{
                source: :primary,
                transforms: [%{op: :bin, field: var(:field), thresholds: var(:bins)}]
              },
              channels: %{x0: :x0, x1: :x1, y0: :y0, y1: :count}
            }
          ]
        })

      {:ok, applied} = Chart.apply(design, sources: %{primary: @rows})
      [mark] = applied.chart.marks
      assert mark.data.transforms == [%{op: :bin, field: :v, thresholds: 4}]
      assert applied.chart.sources.primary.fields == [:t, :v]
      assert Chart.render(applied) =~ ~s(class="mark mark-rect")
    end
  end

  describe "the map, the frame and the render" do
    test "an invalid design map is its own errors" do
      assert Chart.apply(%{version: 1}) == {:error, [{[:frame], :required}]}
    end

    test "the theme option reaches the frame" do
      theme = Visualize.Theme.new(name: :house, series: ["#123456"])
      design = design(%{theme: :house})
      {:ok, applied} = Chart.apply(design, sources: %{uptime: @rows}, theme: theme)
      assert applied.frame.theme.name == :house
      assert Chart.render(applied, resolve: :literal) =~ "#123456"
    end

    test "a value a scale cannot take raises as the frame does" do
      design =
        design(%{frame: %{kind: :cartesian, scales: %{x: %{kind: :time}, y: %{kind: :linear}}}})

      assert_raise ArgumentError, ~r/scale :x \(time\) cannot take 1/, fn ->
        Chart.apply(design, sources: %{uptime: @rows})
      end
    end

    test "render/2 is the frame rendered over the bound sources" do
      {:ok, applied} = Chart.apply(design(), sources: %{uptime: @rows})

      assert Chart.render(applied) ==
               Frame.render(applied.frame, sources: %{primary: @rows})

      assert Chart.render(applied, backend: :canvas) ==
               Frame.render(applied.frame, sources: %{primary: @rows}, backend: :canvas)
    end
  end
end
