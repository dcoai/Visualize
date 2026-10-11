defmodule Visualize.Chart.LimitsTest do
  @moduledoc """
  Documents from elsewhere (spec/14 §9.1, §9.2, #541, D-137): a newer schema is refused by
  name before anything of it is read, and every reader holds a document to sanity limits
  the host may tighten.
  """
  use ExUnit.Case, async: true

  alias Visualize.Chart
  alias Visualize.Chart.Builder.{Bundle, Store}
  alias Visualize.Chart.{Fragment, Limits, Migration, Validator}
  alias Visualize.Designs

  doctest Visualize.Chart.Limits

  # A store holding one style, enough to export a bundle from.
  defmodule OneEntry do
    @behaviour Store
    @impl true
    def list(_context), do: []
    @impl true
    def get({:style, 1}, _context), do: {:ok, %{name: "s", kind: :style, fragment: %{style: %{}}}}
    def get(_id, _context), do: :error
    @impl true
    def put(_entry, _context), do: {:ok, {:style, 99}}
    @impl true
    def delete(_id, _context), do: :ok
    @impl true
    def import(bundle, context), do: Store.relocate(bundle, context, &put/2)
  end

  @current Migration.current()

  # A design that validates, with an axis, a force step and a bin step to hang limits on.
  @design %{
    version: 2,
    sources: %{links: %{fields: [:source, :target]}, points: %{fields: [:v]}},
    frames: %{
      main: %{
        kind: :cartesian,
        scales: %{x: %{kind: :linear, domain: [0, 1]}, y: %{kind: :linear, domain: [0, 1]}},
        axes: [
          %{scale: :x, side: :bottom, ticks: 5},
          %{scale: :y, side: :left, ticks: %{count: 4}}
        ]
      }
    },
    marks: [
      %{
        type: :circle,
        data: %{
          source: :links,
          transforms: [%{op: :force, fields: [:source, :target], ticks: 3}]
        },
        channels: %{x: {:field, :x}, y: {:field, :y}}
      },
      %{
        type: :line,
        data: %{source: :points, transforms: [%{op: :bin, field: :v, thresholds: 10}]},
        channels: %{x: {:field, :x0}, y: {:field, :count}}
      }
    ]
  }

  defp put(design, path, value), do: put_in(design, Enum.map(path, &Access.key/1), value)

  defp axis(design, i, key, value) do
    update_in(
      design,
      [:frames, :main, :axes],
      &List.update_at(&1, i, fn a -> Map.put(a, key, value) end)
    )
  end

  defp step(design, mark, step) do
    update_in(design, [:marks], fn marks ->
      List.update_at(marks, mark, &put_in(&1, [:data, :transforms], [step]))
    end)
  end

  test "the fixture reads under the defaults" do
    assert {:ok, %Chart{}} = Chart.from_map(@design)
    assert Limits.check(@design) == :ok
  end

  describe "a newer schema (§9.1)" do
    test "is refused by name from a map, before the limits or the validator see it" do
      newer = @design |> Map.put(:version, @current + 1) |> Map.put(:bogus, List.duplicate(1, 10))

      assert Chart.from_map(newer, limits: [items: 2]) ==
               {:error, [{[:version], {:newer_schema, @current + 1, @current}}]}

      assert Validator.format({[:version], {:newer_schema, 3, 2}}) ==
               "version: needs schema v3, this is v2"

      assert_raise ArgumentError, ~r/needs schema v#{@current + 1}, this is v#{@current}/, fn ->
        Chart.from_map!(newer)
      end
    end

    test "is refused from JSON before the codec decodes a key, so no atom is made" do
      key = "limits_test_never_an_atom_#{System.unique_integer([:positive])}"
      json = Jason.encode!(%{"version" => @current + 1, key => %{key => key}})

      assert Chart.from_json(json) ==
               {:error, [{[:version], {:newer_schema, @current + 1, @current}}]}

      assert_raise ArgumentError, fn -> String.to_existing_atom(key) end
    end

    test "an older version still migrates" do
      v1 = %{version: 1, frame: %{kind: :cartesian}}
      assert {:ok, chart} = Chart.from_map(v1)
      assert chart.version == @current
      assert Migration.readable(1) == :ok
    end

    test "a fragment document is stamped, and a newer stamp is refused" do
      fragment = %{style: %{stroke_width: 5}}
      {:ok, json} = Fragment.to_json(fragment)
      assert Jason.decode!(json)["$version"] == @current
      assert Fragment.from_json(json) == {:ok, fragment}

      newer = json |> Jason.decode!() |> Map.put("$version", @current + 1) |> Jason.encode!()
      assert Fragment.from_json(newer) == {:error, {:newer_schema, @current + 1, @current}}

      design = Jason.encode!(%{"version" => @current + 1, "theme" => "dark"})
      assert Fragment.from_json(design) == {:error, {:newer_schema, @current + 1, @current}}
    end

    test "a fragment document written before the stamp reads as the current version" do
      assert Fragment.from_json(~s({"style": {"stroke_width": 5}})) ==
               {:ok, %{style: %{stroke_width: 5}}}
    end

    test "a bundle carries the schema it was exported at, and a newer one is refused before a put" do
      bundle = Bundle.export(OneEntry, {:style, 1}, :here)
      assert bundle.provenance.schema == @current
      assert [%{id: {:style, 1}}] = bundle.entries

      put = fn entry, _context ->
        send(self(), {:put, entry})
        {:ok, {:style, 7}}
      end

      newer = put_in(bundle.provenance.schema, @current + 1)
      assert Store.relocate(newer, nil, put) == {:error, {:newer_schema, @current + 1, @current}}
      refute_received {:put, _}

      older = %{bundle | provenance: Map.delete(bundle.provenance, :schema)}
      assert {:ok, %{ids: %{{:style, 1} => {:style, 7}}}} = Store.relocate(older, nil, put)
    end
  end

  describe "each limit (§9.2)" do
    test "depth is reported at the first map or list past it, with its depth" do
      deep = put(@design, [:vars], %{v: %{default: [[[[[[[1]]]]]]]}})

      assert Chart.from_map(deep, limits: [depth: 8]) ==
               {:error, [{[:vars, :v, :default, 0, 0, 0, 0, 0], {:limit, :depth, 8, 9}}]}

      assert Validator.format({[:vars, :v, :default, 0, 0], {:limit, :depth, 5, 6}}) ==
               "vars.v.default[0][0]: is nested 6 deep; the limit depth is 5"
    end

    test "items bounds every list and map held inline" do
      long = put(@design, [:vars], %{v: %{default: Enum.to_list(1..20)}})

      assert Chart.from_map(long, limits: [items: 10]) ==
               {:error, [{[:vars, :v, :default], {:limit, :items, 10, 20}}]}

      assert Validator.format({[:vars, :v, :default], {:limit, :items, 10, 20}}) ==
               "vars.v.default: holds 20 items; the limit items is 10"
    end

    test "ticks bounds an axis's integer ticks and a ticks node's count" do
      many = @design |> axis(0, :ticks, 5000) |> axis(1, :ticks, %{count: 2000})

      assert Chart.from_map(many) ==
               {:error,
                [
                  {[:frames, :main, :axes, 0, :ticks], {:limit, :ticks, 1000, 5000}},
                  {[:frames, :main, :axes, 1, :ticks, :count], {:limit, :ticks, 1000, 2000}}
                ]}

      assert Chart.from_map(@design, limits: [ticks: 4]) ==
               {:error, [{[:frames, :main, :axes, 0, :ticks], {:limit, :ticks, 4, 5}}]}
    end

    test "iterations bounds a force step's ticks" do
      busy = step(@design, 0, %{op: :force, ticks: 20_000})

      assert Chart.from_map(busy) ==
               {:error,
                [
                  {[:marks, 0, :data, :transforms, 0, :ticks],
                   {:limit, :iterations, 10_000, 20_000}}
                ]}

      assert Validator.format(
               {[:marks, 0, :data, :transforms, 0, :ticks], {:limit, :iterations, 10, 20}}
             ) ==
               "marks[0].data.transforms[0].ticks: asks for 20 layout iterations; the limit iterations is 10"
    end

    test "counts bounds bins, samples, n, width and a grid's size" do
      cases = [
        {%{op: :bin, field: :v, thresholds: 50}, [:thresholds], 50},
        {%{op: :spectrum, field: :v, samples: 64}, [:samples], 64},
        {%{op: :take, n: 40}, [:n], 40},
        {%{op: :lttb, fields: [:v, :v], n: 40}, [:n], 40},
        {%{op: :m4, fields: [:v, :v], width: 40}, [:width], 40},
        {%{op: :contour, field: :v, size: [10, 40]}, [:size, 1], 40}
      ]

      for {transform, at, given} <- cases do
        design = step(@design, 1, transform)

        assert Chart.from_map(design, limits: [counts: 30]) ==
                 {:error,
                  [{[:marks, 1, :data, :transforms, 0] ++ at, {:limit, :counts, 30, given}}]},
               inspect(transform)
      end

      # `:plot` is not a count the document gives.
      assert Limits.counts(step(@design, 1, %{op: :take, n: :plot}), Limits.new(counts: 1)) == []
    end

    test "a variable is not a literal of the document and is not checked" do
      held = @design |> axis(0, :ticks, Chart.var(:n)) |> put([:vars], %{n: %{default: 5}})
      assert Limits.counts(held, Limits.new(ticks: 4)) == []
    end

    test "every fault is reported, ordered by path" do
      both = @design |> axis(0, :ticks, 50) |> step(0, %{op: :force, ticks: 50})
      limits = Limits.new(ticks: 10, iterations: 10)

      assert {:error,
              [
                {[:frames | _], {:limit, :ticks, 10, 50}},
                {[:marks | _], {:limit, :iterations, 10, 50}}
              ]} =
               Limits.check(both, limits)
    end
  end

  describe "from JSON (§9.2)" do
    test "depth and items are checked on the parsed document, by its own key strings" do
      {:ok, json} =
        @design
        |> put([:vars], %{v: %{default: Enum.to_list(1..20)}})
        |> Chart.from_map!()
        |> Chart.to_json()

      assert Chart.from_json(json, limits: [items: 15]) ==
               {:error, [{["vars", "v", "default"], {:limit, :items, 15, 20}}]}

      assert Validator.format({["vars", "v", "default"], {:limit, :items, 10, 20}}) ==
               "vars.v.default: holds 20 items; the limit items is 10"
    end

    test "the schema's limits are checked on the decoded design" do
      {:ok, json} = @design |> Chart.from_map!() |> Chart.to_json()

      assert Chart.from_json(json, limits: [ticks: 4]) ==
               {:error, [{[:frames, :main, :axes, 0, :ticks], {:limit, :ticks, 4, 5}}]}

      assert {:ok, %Chart{}} = Chart.from_json(json)
    end

    test "a fragment document is held to depth and items before it is decoded" do
      {:ok, json} = Fragment.to_json(%{style: %{dash: Enum.to_list(1..20)}})

      assert Fragment.from_json(json, limits: [items: 10]) ==
               {:error, {:limits, [{["style", "dash"], {:limit, :items, 10, 20}}]}}
    end
  end

  describe "the host holds the number" do
    test "a limit not named keeps its default" do
      assert Limits.new(items: 5) == %{Limits.defaults() | items: 5}
      assert Limits.new(%{}) == Limits.defaults()
    end

    test "a name that is not a limit, or a value that is not a positive integer, raises" do
      assert_raise ArgumentError, ~r/not a limit: :rows/, fn -> Limits.new(rows: 5) end
      assert_raise ArgumentError, ~r/positive integer/, fn -> Limits.new(depth: 0) end

      assert_raise ArgumentError, ~r/positive integer/, fn ->
        Chart.from_map(@design, limits: [items: 1.5])
      end
    end

    test "every stored design passes the defaults" do
      for name <- Designs.names() do
        design = name |> Designs.chart() |> Chart.to_map()
        assert Limits.check(design) == :ok, inspect(name)
      end
    end
  end
end
