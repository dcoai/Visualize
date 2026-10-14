defmodule Visualize.Chart.FreeVarsTest do
  @moduledoc """
  The variables a design still demands (spec/14 §17.2, D-84) and the single-level rule
  of §7.1: `free_vars/1` walks where `Visualize.Chart.apply/2` walks, so what it lists
  and what application demands are one set, and a variable bound to a variable is
  reported by path rather than substituted.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Visualize.Chart

  @house %{
    vars: %{accent: %{default: :series_1}, width: %{default: 2}},
    styles: %{series: %{stroke: Chart.var(:accent), stroke_width: Chart.var(:width)}}
  }
  @panel %{
    vars: %{unit: %{}},
    labels: [%{anchor: :title, text: ["Uptime in ", Chart.var(:unit)]}],
    marks: [%{type: :line, data: :p, channels: %{x: :t, y: Chart.var(:y)}}]
  }

  defp free(design), do: Chart.free_vars(design)
  defp entry(design, name), do: Enum.find(free(design), &(&1.name == name))

  describe "free_vars/1" do
    test "one entry per variable, ordered by name" do
      assert Enum.map(free([@house, @panel]), & &1.name) == [:accent, :unit, :width, :y]
    end

    test "the default comes from the stacked vars node and required is its absence" do
      vars = free([@house, @panel])

      assert entry([@house, @panel], :accent) == %{
               name: :accent,
               default: :series_1,
               required: false,
               uses: [%{path: [:styles, :series, :stroke], expects: :colour, layer: 0}]
             }

      assert entry([@house, @panel], :unit).default == nil
      assert entry([@house, @panel], :unit).required == true
      assert entry([@house, @panel], :y).required == true
      assert Enum.count(vars, & &1.required) == 2
    end

    test "a default declared by a higher layer wins" do
      higher = %{vars: %{accent: %{default: :series_3}}}
      assert entry([@house, higher], :accent).default == :series_3
      assert entry([higher, @house], :accent).default == :series_1
    end

    test "the expectation is the schema's type at the path" do
      design = %{
        styles: %{s: %{stroke: Chart.var(:colour), curve_opts: Chart.var(:opts)}},
        marks: [%{type: :line, data: :p, style: Chart.var(:style), options: Chart.var(:options)}],
        labels: [%{anchor: :title, text: ["a ", Chart.var(:part)]}],
        frames: %{main: %{scales: %{x: %{kind: :linear, domain: Chart.var(:domain)}}}},
        sources: %{p: %{fields: [:t], default: Chart.var(:pool)}}
      }

      expects = for v <- free(design), use <- v.uses, into: %{}, do: {v.name, use.expects}

      assert expects == %{
               colour: :colour,
               opts: {:node, :curve_opts},
               # A style site admits a reference, an inline node, a field naming a style by
               # data, or a list of those (spec/14 §3.6); the expectation is the whole type,
               # as it is for any key.
               style:
                 {:one_of,
                  [
                    {:ref, :style},
                    {:node, :style},
                    :field_ref,
                    {:list, {:one_of, [{:ref, :style}, {:node, :style}, :field_ref]}}
                  ]},
               options: {:node, :options},
               part: :text,
               domain: :extent,
               pool: :name
             }
    end

    test "every path a variable stands at is a use, ordered by path" do
      design = %{
        styles: %{a: %{stroke: Chart.var(:c)}, b: %{fill: Chart.var(:c)}},
        labels: [%{anchor: :title, text: [Chart.var(:c), " and ", Chart.var(:c)]}]
      }

      # A text is one use however many times it names the variable (§7.1).
      assert entry(design, :c).uses |> Enum.map(& &1.path) == [
               [:labels, 0, :text],
               [:styles, :a, :stroke],
               [:styles, :b, :fill]
             ]
    end

    test "a use carries the layer that set the leaf it stands in" do
      uses = entry([@house, @panel], :unit).uses
      assert Enum.map(uses, & &1.layer) == [1]

      named = entry([{:house, @house}, {:panel, @panel}], :unit).uses
      assert Enum.map(named, & &1.layer) == [:panel]
    end

    test "a fragment and a chart are one-layer stacks" do
      assert free(@house) == free([@house])
      assert Enum.all?(free(@house), fn v -> Enum.all?(v.uses, &(&1.layer == 0)) end)

      chart =
        Chart.from_map!(%{
          version: 2,
          vars: %{unit: %{default: "%"}},
          frames: %{main: %{kind: :cartesian}},
          labels: [%{anchor: :title, text: [Chart.var(:unit)]}]
        })

      assert [%{name: :unit, default: "%", required: false}] = free(chart)
    end

    test "a literal above a variable closes it and a variable above a literal opens one" do
      lower = %{styles: %{s: %{stroke: Chart.var(:accent)}}}
      literal = %{styles: %{s: %{stroke: "#3b6fa8"}}}

      assert free([lower, literal]) == []
      assert Enum.map(free([literal, lower]), & &1.name) == [:accent]
      assert Enum.map(free([lower]), & &1.name) == [:accent]
    end

    test "no variables is no entries" do
      assert Chart.free_vars([]) == []
      assert Chart.free_vars(%{version: 2, frames: %{main: %{kind: :cartesian}}}) == []
    end
  end

  describe "free_vars/1 lists exactly what apply/2 demands" do
    @design %{
      version: 2,
      vars: %{unit: %{}, accent: %{default: :series_2}},
      sources: %{p: %{fields: [:t, :v]}},
      styles: %{s: %{stroke: Chart.var(:accent)}},
      frames: %{main: %{kind: :cartesian, scales: %{x: %{kind: :linear}, y: %{kind: :linear}}}},
      marks: [%{type: :line, data: :p, channels: %{x: :t, y: :v}, style: :s}],
      labels: [%{anchor: :title, text: ["Uptime in ", Chart.var(:unit)]}]
    }

    test "the required ones are exactly the unresolved paths apply/2 reports" do
      required = for v <- free(@design), v.required, use <- v.uses, do: use.path

      assert {:error, errors} = Chart.apply(@design, sources: %{p: %{t: [1], v: [2]}})
      assert Enum.map(errors, &elem(&1, 0)) == required
      assert Enum.all?(errors, &match?({_, {:unresolved, :var, :unit}}, &1))
    end

    test "supplying exactly the free variables applies" do
      values = for v <- free(@design), into: %{}, do: {v.name, v.default || "%"}

      assert {:ok, applied} = Chart.apply(@design, sources: %{p: %{t: [1], v: [2]}}, vars: values)
      assert applied.chart.labels == [%{anchor: :title, text: "Uptime in %"}]
      assert Chart.free_vars(applied.chart) == []
    end
  end

  describe "the var-to-var error (spec/14 §7.1)" do
    @design %{
      version: 2,
      vars: %{unit: %{}, other: %{}},
      frames: %{main: %{kind: :cartesian}},
      labels: [
        %{anchor: :title, text: ["a ", Chart.var(:unit)]},
        %{anchor: :caption, text: [Chart.var(:unit)]}
      ]
    }

    test "a value given as a variable is reported at every path the variable stood at" do
      assert Chart.apply(@design, vars: %{unit: Chart.var(:other), other: "%"}) ==
               {:error,
                [
                  {[:labels, 0, :text], {:var_binding, :unit}},
                  {[:labels, 1, :text], {:var_binding, :unit}}
                ]}
    end

    test "a declared default that is a variable is the same error" do
      design = put_in(@design, [:vars, :unit], %{default: Chart.var(:other)})

      assert {:error, errors} = Chart.apply(design, vars: %{other: "%"})
      assert Enum.all?(errors, &match?({_, {:var_binding, :unit}}, &1))
      assert length(errors) == 2
    end

    test "the error formats as a line a person reads" do
      assert Visualize.Chart.Validator.format({[:labels, 0, :text], {:var_binding, :unit}}) ==
               "labels[0].text: variable :unit is bound to another variable; " <>
                 "resolution is single level"
    end

    test "a variable nested inside a bound value is the validator's undeclared" do
      design = %{
        version: 2,
        vars: %{opts: %{}},
        styles: %{s: Chart.var(:opts)},
        frames: %{main: %{kind: :cartesian}}
      }

      assert Chart.apply(design, vars: %{opts: %{stroke: Chart.var(:deep)}}) ==
               {:error, [{[:styles, :s, :stroke], {:undeclared, :var, :deep}}]}
    end
  end

  # -- properties ------------------------------------------------------------------------

  defp value(gen), do: one_of([gen, map(member_of([:a, :b, :c]), &Chart.var/1)])

  defp style, do: optional_map(%{stroke_width: value(integer(1..5)), opacity: value(float())})

  defp names(pool, gen),
    do: map(list_of(tuple({member_of(pool), gen}), max_length: 2), &Map.new/1)

  defp fragment do
    optional_map(%{
      version: constant(1),
      vars: names([:a, :b, :c], optional_map(%{default: integer()})),
      styles: names([:series, :muted], style()),
      labels:
        list_of(
          fixed_map(%{
            anchor: member_of([:title, :caption]),
            text: list_of(value(string(:alphanumeric)), max_length: 2)
          }),
          max_length: 2
        )
    })
  end

  property "the free variables are the variables of the stack, once each, ordered by name" do
    check all(layers <- list_of(fragment(), max_length: 3)) do
      stacked = Chart.stack(layers)
      free = Chart.free_vars(layers)
      names = Enum.map(free, & &1.name)

      assert names == Enum.sort(names)
      assert names == Enum.uniq(names)
      assert MapSet.new(names) == MapSet.new(occurrences(stacked))

      for v <- free, use <- v.uses do
        # A text holds its variables among its parts; anything else is the variable itself.
        case at(stacked, use.path) do
          parts when is_list(parts) -> assert Chart.var(v.name) in parts
          value -> assert value == Chart.var(v.name)
        end

        assert v.required == (v.default == nil)
      end
    end
  end

  property "free_vars/1 of a fragment is free_vars/1 of the one-layer stack of it" do
    check all(a <- fragment()) do
      assert Chart.free_vars(a) == Chart.free_vars([a])
      assert Chart.free_vars(Chart.stack([a])) == Chart.free_vars([a])
    end
  end

  # Every variable name in a term, found structurally rather than by the schema.
  defp occurrences(%Visualize.Chart.Var{name: name}), do: [name]

  defp occurrences(v) when is_map(v) and not is_struct(v),
    do: Enum.flat_map(v, fn {_k, e} -> occurrences(e) end)

  defp occurrences(v) when is_list(v), do: Enum.flat_map(v, &occurrences/1)
  defp occurrences(_v), do: []

  defp at(value, []), do: value
  defp at(value, [k | rest]) when is_list(value), do: at(Enum.at(value, k), rest)
  defp at(value, [k | rest]) when is_map(value), do: at(Map.fetch!(value, k), rest)
end
