defmodule Visualize.Chart.UseTest do
  @moduledoc """
  The use site and the composite (spec/14 §19.3–§19.6, D-101–D-103): four parts in one
  order, bindings as substitution, masks as the dual of local, save-as-structure flattened
  through a store, cycles refused, and a missing ref as a mask.
  """
  use ExUnit.Case, async: true

  import Visualize.Chart, only: [var: 1]

  alias Visualize.Chart
  alias Visualize.Chart.{Composite, Fragment, Use, Validator}

  doctest Visualize.Chart.Use
  doctest Visualize.Chart.Composite
  doctest Visualize.Chart.Refs

  # A store as a function of an id, which is all resolution needs.
  @library %{
    {:style, 1} => %{stroke: "#111", stroke_width: 1, fill: var(:color)},
    {:style, 2} => %{stroke_width: 5, opacity: 0.5},
    {:design, 1} => %{styles: %{s: %{fill: var(:color)}}},
    {:theme, 1} => %{theme: :dark},
    {:frame, 1} => %{frame: %{kind: :cartesian, margin: %{top: 24}}},
    {:composite, 1} => %{
      composite: %{
        uses: [
          Use.new({:theme, 1}),
          %Use{id: {:use, 2}, ref: {:frame, 1}, mask: [[:frame, :margin]]}
        ],
        vars: %{}
      }
    },
    {:composite, 2} => %{composite: %{uses: [Use.new({:composite, 3})], vars: %{}}},
    {:composite, 3} => %{composite: %{uses: [Use.new({:composite, 2})], vars: %{}}}
  }

  defp fetch(id), do: Map.fetch(@library, id)

  describe "the order of operations (spec/14 §19.3, D-101)" do
    test "ref, then local, then mask, then bind, in that order" do
      use = %Use{
        id: {:use, 1},
        ref: {:style, 1},
        mask: [:stroke],
        vars: %{color: var(:color_1)},
        local: %{opacity: 0.8}
      }

      assert {:ok, resolved} = Chart.resolve(use, &fetch/1)

      # stroke masked; color renamed; opacity added; width from the ref.
      assert resolved == %{stroke_width: 1, fill: var(:color_1), opacity: 0.8}
    end

    test "mask runs after local, so it removes what the site says whichever part said it" do
      use = %Use{id: {:use, 1}, ref: {:style, 1}, mask: [:stroke], local: %{stroke: "#f00"}}
      assert {:ok, resolved} = Chart.resolve(use, &fetch/1)
      refute Map.has_key?(resolved, :stroke)

      inline = %Use{
        id: {:use, 1},
        ref: nil,
        mask: [:stroke],
        local: %{stroke: "#f00", opacity: 1}
      }

      assert Chart.resolve(inline, &fetch/1) == {:ok, %{opacity: 1}}
    end

    test "a nil ref is an inline-only site: its local node alone, bound like any other" do
      use = %Use{id: {:use, 1}, ref: nil, local: %{opacity: 0.8}}
      assert Chart.resolve(use, &fetch/1) == {:ok, %{opacity: 0.8}}

      inline = %Use{id: {:use, 1}, ref: nil, local: %{fill: var(:color)}, vars: %{color: "red"}}
      assert Chart.resolve(inline, &fetch/1) == {:ok, %{fill: "red"}}
    end

    test "a ref the fetch cannot find is a mask of everything, and is named" do
      use = %Use{id: {:use, 1}, ref: {:style, 99}, local: %{opacity: 0.8}}
      assert Chart.resolve(use, &fetch/1) == {:missing, {:style, 99}, %{opacity: 0.8}}
    end

    test "a site's id is one more than the highest it will sit beside" do
      first = Use.new({:style, 1})
      second = Use.new({:style, 2}, [first])
      third = Use.new({:style, 1}, [second, first])
      assert Enum.map([first, second, third], & &1.id) == [use: 1, use: 2, use: 3]
    end
  end

  describe "bindings (spec/14 §19.4, D-102)" do
    test "shared, set, and renamed are three states of one map" do
      fragment = %{fill: var(:color), text: ["u: ", var(:unit)]}

      assert Chart.bind(fragment, %{}) == fragment
      assert Chart.bind(fragment, %{color: "blue"}).fill == "blue"
      assert Chart.bind(fragment, %{color: var(:color_1)}).fill == var(:color_1)

      # The variable the map does not name is untouched.
      assert Chart.bind(fragment, %{color: "blue"}).text == ["u: ", var(:unit)]
    end

    test "the composite's free variables reflect the rename, and never the inner name" do
      # One site per case, so what is free is exactly the site's state.
      free = fn use ->
        {:ok, flat, _} = Chart.flatten(%{composite: %{uses: [use], vars: %{}}}, &fetch/1)
        flat |> Chart.free_vars() |> Enum.map(& &1.name)
      end

      shared = %Use{id: {:use, 1}, ref: {:design, 1}}
      set = %Use{id: {:use, 1}, ref: {:design, 1}, vars: %{color: "blue"}}
      renamed = %Use{id: {:use, 1}, ref: {:design, 1}, vars: %{color: var(:color_1)}}

      assert free.(shared) == [:color]
      assert free.(set) == []
      assert free.(renamed) == [:color_1]
    end

    test "a struct other than a variable is a leaf" do
      inner = Use.new({:style, 1})
      assert Chart.bind(%{u: inner}, %{color: "x"}) == %{u: inner}
    end
  end

  describe "masks (spec/14 §19.5)" do
    test "a key, a path, and everything" do
      assert Chart.mask(%{a: 1, b: 2}, [:a]) == %{b: 2}

      assert Chart.mask(%{frame: %{size: 1, margin: 2}}, [[:frame, :margin]]) == %{
               frame: %{size: 1}
             }

      assert Chart.mask(%{a: 1}, :all) == %{}
    end

    test "a path the fragment does not carry removes nothing" do
      assert Chart.mask(%{a: 1}, [:zzz, [:a, :b, :c]]) == %{a: 1}
    end

    test "a masked key shows through from the layer below once stacked" do
      lower = %{theme: :dark, version: 1}
      upper = Chart.mask(%{theme: :light, version: 2}, [:theme])
      assert Chart.stack([lower, upper]) == %{theme: :dark, version: 2}
    end
  end

  describe "flatten (spec/14 §19.6, D-103)" do
    test "a composite flattens to a design; its vars are the base layer" do
      composite = %{
        composite: %{
          uses: [Use.new({:theme, 1}), %Use{id: {:use, 2}, ref: {:frame, 1}}],
          vars: %{unit: %{default: "%"}}
        }
      }

      assert {:ok, flat, %{missing: []}} = Chart.flatten(composite, &fetch/1)
      assert flat.theme == :dark
      assert flat.frame.margin.top == 24
      assert flat.vars == %{unit: %{default: "%"}}
      refute Map.has_key?(flat, :composite)
    end

    test "a mask at a site removes from that site's contribution only" do
      assert {:ok, flat, _} = Chart.flatten(@library[{:composite, 1}], &fetch/1)
      assert Map.has_key?(flat.frame, :kind)
      refute Map.has_key?(flat.frame, :margin)
    end

    test "composites nest, and the nested one's missing refs are reported" do
      outer = %{
        composite: %{
          uses: [Use.new({:composite, 1}), %Use{id: {:use, 2}, ref: {:style, 99}}],
          vars: %{}
        }
      }

      assert {:ok, flat, %{missing: [{{:use, 2}, {:style, 99}}]}} = Chart.flatten(outer, &fetch/1)
      assert flat.theme == :dark
    end

    test "a cycle through any chain is refused, naming it" do
      assert {:error, {:cycle, chain}} = Chart.flatten(@library[{:composite, 2}], &fetch/1)
      assert {:composite, 3} in chain
      assert {:composite, 2} in chain
    end

    test "a design that is not a composite flattens to itself" do
      design = %{version: 1, frame: %{}}
      assert Chart.flatten(design, &fetch/1) == {:ok, design, %{missing: [], keyless: []}}
    end

    test "composite? tells the two apart" do
      assert Composite.composite?(@library[{:composite, 1}])
      refute Composite.composite?(%{version: 1})
    end
  end

  describe "placement by kind (spec/14 §19.6)" do
    @placed %{
      {:theme, 1} => %{theme: :dark},
      {:style, 1} => %{style: %{stroke_width: 5}},
      {:scale, 1} => %{scale: %{kind: :linear, domain: :auto}},
      {:source, 1} => %{source: %{fields: [:hour, :value]}},
      {:mark, 1} => %{
        mark: %{id: :m, type: :line, data: :primary, channels: %{x: :hour, y: :value}}
      },
      {:frame, 1} => %{frame: %{kind: :cartesian}},
      {:style, 2} => %{
        composite: %{
          uses: [
            Use.new({:style, 1}),
            %Use{id: {:use, 2}, ref: nil, local: %{style: %{opacity: 0.5}}}
          ],
          vars: %{}
        }
      }
    }

    defp placed(id), do: Map.fetch(@placed, id)

    test "every site lands where the design keeps its kind, a name-keyed one under its key" do
      composite = %{
        composite: %{
          uses: [
            Use.new({:theme, 1}),
            %Use{id: {:use, 2}, ref: {:frame, 1}},
            %Use{id: {:use, 3}, ref: {:style, 1}, key: :series},
            %Use{id: {:use, 4}, ref: {:scale, 1}, key: :hour},
            %Use{id: {:use, 5}, ref: {:source, 1}, key: :primary},
            %Use{id: {:use, 6}, ref: {:mark, 1}}
          ],
          vars: %{}
        }
      }

      assert {:ok, flat, %{missing: [], keyless: []}} = Chart.flatten(composite, &placed/1)
      assert flat.theme == :dark
      assert flat.frame.kind == :cartesian
      assert flat.styles == %{series: %{stroke_width: 5}}
      assert flat.frame.scales == %{hour: %{kind: :linear, domain: :auto}}
      assert flat.sources == %{primary: %{fields: [:hour, :value]}}
      assert [%{id: :m}] = flat.marks
    end

    test "the same body is series in one composite and line in another" do
      at = fn key ->
        {:ok, flat, _} =
          Chart.flatten(
            %{
              composite: %{
                uses: [%Use{id: {:use, 1}, ref: {:style, 1}, key: key}, Use.new({:theme, 1})],
                vars: %{}
              }
            },
            &placed/1
          )

        Map.keys(flat.styles)
      end

      assert at.(:series) == [:series]
      assert at.(:line) == [:line]
    end

    test "a name-keyed site with no key is reported and not placed" do
      composite = %{
        composite: %{
          uses: [Use.new({:theme, 1}), %Use{id: {:use, 2}, ref: {:style, 1}}],
          vars: %{}
        }
      }

      assert {:ok, flat, %{keyless: [{:use, 2}]}} = Chart.flatten(composite, &placed/1)
      refute Map.has_key?(flat, :styles)
      refute Map.has_key?(flat, :style)
    end

    test "a composer of one kind stacks bodies, and its result is placed by the outer key" do
      # {:style, 2} is a composite of two keyless style sites: a style, not a design.
      assert {:ok, %{style: %{stroke_width: 5, opacity: 0.5}}, %{keyless: []}} =
               Chart.flatten(@placed[{:style, 2}], &placed/1)

      outer = %{
        composite: %{uses: [%Use{id: {:use, 1}, ref: {:style, 2}, key: :series}], vars: %{}}
      }

      assert {:ok, %{styles: %{series: %{stroke_width: 5, opacity: 0.5}}}, _} =
               Chart.flatten(outer, &placed/1)
    end

    test "a document decomposes into sites, one kind each, and flattens back to itself" do
      document = %{
        version: 1,
        theme: :dark,
        meta: %{name: "Uptime"},
        styles: %{series: %{stroke: "#111"}, faint: %{opacity: 0.4}},
        sources: %{primary: %{fields: [:t, :v]}},
        vars: %{unit: %{default: "%"}},
        frame: %{
          kind: :cartesian,
          scales: %{x: %{kind: :linear}, y: %{kind: :linear}},
          axes: [%{scale: :x, side: :bottom}, %{scale: :y, side: :left}]
        },
        marks: [%{id: :m, type: :line, data: :primary, channels: %{x: :t, y: :v}}],
        labels: [%{id: :title, anchor: :title, text: ["Uptime"]}]
      }

      {uses, labels} = Composite.decompose(document)

      assert Enum.map(uses, &Fragment.kind(&1.local)) ==
               [
                 :theme,
                 :meta,
                 :frame,
                 :style,
                 :style,
                 :scale,
                 :scale,
                 :source,
                 :var,
                 :axis,
                 :axis,
                 :mark,
                 :label
               ]

      assert Enum.map(uses, & &1.key) ==
               [nil, nil, nil, :faint, :series, :x, :y, :primary, :unit, nil, nil, nil, nil]

      assert labels[{:use, 12}] == "mark m"
      assert labels[{:use, 10}] == "axis x bottom"

      composite = %{composite: %{uses: uses, vars: %{}}}
      assert {:ok, ^document, %{missing: [], keyless: []}} = Chart.flatten(composite, &placed/1)
    end

    test "a map that is many things is no kind of fragment" do
      assert Fragment.kind(%{theme: :dark, frame: %{}}) == nil
      assert Fragment.kind(%{version: 1}) == nil
      refute :design in Fragment.kinds()

      assert {:error, [{[], :many_kinds}]} = Validator.validate(%{theme: :dark, frame: %{}}, nil)

      assert Validator.format({[], :many_kinds}) =~ "no kind of fragment"
    end

    test "key round-trips through the codec" do
      use = %Use{id: {:use, 1}, ref: {:style, 1}, key: :series}
      encoded = Chart.Codec.encode(%{composite: %{uses: [use], vars: %{}}})
      assert %{"$use" => %{"key" => "series"}} = hd(encoded["composite"]["uses"])
      assert Chart.Codec.decode(encoded) == %{composite: %{uses: [use], vars: %{}}}
    end
  end

  describe "the JSON form (spec/14 §11, §19.6)" do
    test "an id and a use round-trip through the codec, and never make an atom" do
      design = %{
        version: 1,
        frame: %{},
        composite: %{
          uses: [
            %Use{
              id: {:use, 7},
              ref: {:style, 11},
              mask: [:stroke, [:frame, :margin]],
              vars: %{color: var(:color_1)},
              local: %{opacity: 0.8}
            },
            %Use{id: {:use, 8}, ref: nil, mask: :all}
          ],
          vars: %{}
        }
      }

      encoded = Chart.Codec.encode(design)

      assert %{"$use" => %{"id" => 7, "ref" => %{"$id" => ["style", 11]}}} =
               hd(encoded["composite"]["uses"])

      assert Chart.Codec.decode(encoded) == design
    end

    test "an id whose kind is not one is left as it was read, not made into an atom" do
      assert Chart.Codec.decode(%{"x" => %{"$id" => ["nonsense", 1]}}) == %{
               x: %{"$id" => ["nonsense", 1]}
             }
    end
  end

  describe "the validator (spec/14 §19.2, D-100)" do
    test "an id of the right kind is accepted at a reference site" do
      design = %{
        version: 1,
        frame: %{scales: %{x: %{kind: :linear}}, axes: []},
        marks: [
          %{id: :m, type: :line, data: :primary, channels: %{x: :a, y: :b}, style: {:style, 11}}
        ],
        sources: %{primary: %{fields: [:a, :b]}}
      }

      errors =
        case Validator.validate(design) do
          :ok -> []
          {:error, errors} -> errors
        end

      refute Enum.any?(errors, fn {path, _} -> path == [:marks, 0, :style] end)
    end

    test "an id of the wrong kind is refused before anything resolves it" do
      design = %{marks: [%{id: :m, type: :line, style: {:scale, 4}}]}

      {:error, errors} = Validator.validate(design)
      assert {[:marks, 0, :style], {:ref_kind, :style, :scale}} in errors

      assert Validator.format({[:marks, 0, :style], {:ref_kind, :style, :scale}}) =~
               "scale id where a style was expected"
    end
  end
end
