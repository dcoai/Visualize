defmodule Visualize.GeneratorsTest.Tenants do
  @moduledoc false
  # A host's generators, as spec/14 §3.13 writes them: each reports its call to the caller,
  # so a test can count them.
  use Visualize.Generators

  import Visualize.Color, only: [color: 1]

  defgenerator tenant_style(tenant, ctx) do
    send(self(), {:called, :tenant_style, tenant})

    case tenant do
      "acme" -> %{fill: color(:red), stroke: %{width: viewer_width(ctx, "acme")}}
      "globex" -> [:bad, %{stroke: %{width: viewer_width(ctx, "globex")}}]
      "named" -> :warning
      "wrong" -> 42
      "nested" -> %{fill: {:generate, :brand_color, ["acme"]}}
      "gradient" -> %{fill: %{type: :linear, color: [color(:red), color(:blue)]}}
      "unknown_color" -> %{fill: {:color, :no_such_color}}
      nil -> :good
    end
  end

  defgenerator brand_color(tenant, _ctx) do
    send(self(), {:called, :brand_color, tenant})

    case tenant do
      "acme" -> color(:blue)
      "globex" -> "#00ff00"
      "none" -> :none
      _other -> :not_a_color
    end
  end

  # The context: the theme, the variables and the host's assigns.
  defgenerator echo(ctx) do
    send(self(), {:context, ctx})
    %{opacity: 0.5}
  end

  defgenerator(crash(_tenant, _ctx), do: raise(ArgumentError, "the host's bug"))

  # A generator of two clauses is listed once.
  defgenerator(tier(:gold, _ctx), do: :good)
  defgenerator(tier(_other, _ctx), do: :neutral)

  defp viewer_width(%{assigns: %{viewer: viewer}}, viewer), do: 3
  defp viewer_width(_ctx, _tenant), do: 1
end

defmodule Visualize.GeneratorsTest.Other do
  @moduledoc false
  use Visualize.Generators
  defgenerator(brand_color(_tenant, _ctx), do: "#000000")
end

defmodule Visualize.GeneratorsTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Visualize.Generators, only: [generate: 1, generate: 2]

  alias Visualize.Chart
  alias Visualize.Chart.Validator
  alias Visualize.GeneratorsTest.{Other, Tenants}

  doctest Visualize.Generators

  @gens [generators: [Tenants]]

  defp design(style, opts \\ []) do
    %{
      version: 3,
      sources: %{s: %{fields: [:x, :y, :tenant, :state]}},
      vars: %{unit: %{default: "%"}},
      frames: %{
        main: %{
          kind: :cartesian,
          scales: %{x: %{kind: :linear}, y: %{kind: :linear}},
          axes: Keyword.get(opts, :axes, [])
        }
      },
      marks: [
        %{type: :symbol, data: :s, channels: %{x: :x, y: :y}, style: style}
        |> then(&if(label = opts[:label], do: Map.put(&1, :label, label), else: &1))
      ]
    }
  end

  @rows [
    %{x: 0, y: 0, tenant: "acme", state: "ok"},
    %{x: 1, y: 1, tenant: "globex", state: "ok"},
    %{x: 2, y: 2, tenant: "acme", state: "warning"}
  ]

  defp apply!(design, rows \\ @rows, opts \\ []) do
    {:ok, applied} = Chart.apply(design, [sources: %{s: rows}] ++ @gens ++ opts)
    applied
  end

  # The mark's group, and its elements' styles in row order.
  defp group(applied) do
    %{children: [mark]} = Chart.generate(applied)
    mark
  end

  defp styles(applied), do: Enum.map(group(applied).children, & &1.style)

  defp calls do
    receive do
      {:called, name, arg} -> [{name, arg} | calls()]
    after
      0 -> []
    end
  end

  describe "defining and registering" do
    test "__generators__/0 lists each generator once, in definition order" do
      assert Tenants.__generators__() ==
               [tenant_style: 2, brand_color: 2, echo: 1, crash: 2, tier: 2]
    end

    test "generate/2 is the stored call, and refuses what is not one" do
      assert generate(:echo) == {:generate, :echo, []}
      assert_raise ArgumentError, fn -> generate("echo", []) end
      assert_raise ArgumentError, fn -> generate(:echo, :not_a_list) end
    end

    test "the registry is the modules given and then the configuration's" do
      assert Visualize.Generators.registry([Tenants])[{:tenant_style, 2}] == Tenants

      message = ~r/defined by both/

      assert_raise ArgumentError, message, fn ->
        Visualize.Generators.registry([Tenants, Other])
      end

      assert_raise ArgumentError, ~r/not a generator module/, fn ->
        Visualize.Generators.registry([Enum])
      end
    end

    test "a head without the context parameter does not compile" do
      assert_raise CompileError, ~r/context parameter/, fn ->
        Code.compile_string("""
        defmodule Visualize.GeneratorsTest.NoContext do
          use Visualize.Generators
          defgenerator bare, do: 1
        end
        """)
      end
    end
  end

  describe "validation when the chart is built" do
    test "an unknown name is a fault at its path; a registered one is not" do
      style = [generate(:tenant_style, [{:field, :tenant}]), generate(:nope, [])]

      assert {:error, [{[:marks, 0, :style, 1], {:undeclared, :generator, :nope}}]} =
               Chart.from_map(design(style), @gens)

      assert {:error, [{[:marks, 0, :style, 0], {:undeclared, :generator, :tenant_style}}, _]} =
               Chart.from_map(design(style))
    end

    test "a name registered at another arity, and a malformed call" do
      style = [generate(:tenant_style, []), {:generate, "x", []}]

      assert {:error, errors} = Chart.from_map(design(style), @gens)
      assert {[:marks, 0, :style, 0], {:arity, :generator, :tenant_style, 0}} in errors
      assert {[:marks, 0, :style, 1], {:type, :generator}} in errors

      assert Validator.format({[:marks, 0, :style, 0], {:arity, :generator, :tenant_style, 0}}) =~
               "registered, but not for 0 arguments"
    end

    test "a field argument is checked as any field binding" do
      style = generate(:tenant_style, [{:field, :nope}])

      assert {:error, [{[:marks, 0, :style, 0], {:undeclared, :field, :nope}}]} =
               Chart.from_map(design(style), @gens)
    end

    test "a color generator goes in a solid paint, never in a gradient, defs or a theme" do
      solid = %{fill: generate(:brand_color, [{:field, :tenant}])}
      assert {:ok, _chart} = Chart.from_map(design(solid), @gens)

      gradient = %{fill: %{type: :linear, color: generate(:brand_color, ["acme"])}}
      assert {:error, errors} = Chart.from_map(design(gradient), @gens)
      assert {[:marks, 0, :style, :fill, :color], {:invalid_for, :linear}} in errors

      theme = Map.put(design(:style_1), :theme, %{background: generate(:brand_color, ["acme"])})
      assert {:error, errors} = Chart.from_map(theme, @gens)
      assert Enum.any?(errors, &match?({[:theme, :background], {:type, _}}, &1))

      defaults = Map.put(design(:style_1), :defaults, %{fill: generate(:brand_color, ["acme"])})

      assert {:error, [{[:defaults, :fill, :color], {:type, :color}}]} =
               Chart.from_map(defaults, @gens)
    end

    test "the host's configuration registers for every read" do
      Application.put_env(:visualize, :generators, [Tenants])
      on_exit(fn -> Application.delete_env(:visualize, :generators) end)
      assert {:ok, _chart} = Chart.from_map(design(generate(:tenant_style, ["acme"])))
    end
  end

  describe "resolution at render" do
    test "a generator over a field binding styles each row" do
      applied = apply!(design([:style_1, generate(:tenant_style, [{:field, :tenant}])]))

      [acme, globex, acme2] = styles(applied)
      assert acme.fill == "var(--vis-red, #c23238)"
      assert acme2.fill == acme.fill
      assert globex.stroke == "var(--vis-bad, #c23238)"
      assert globex.stroke_width == 1
    end

    test "each distinct argument is called once within a mark's drawing" do
      rows =
        for i <- 1..100,
            do: %{x: i, y: i, tenant: Enum.at(["acme", "globex"], rem(i, 2)), state: "ok"}

      applied = apply!(design(generate(:tenant_style, [{:field, :tenant}])), rows)
      calls()
      styles(applied)

      assert Enum.sort(calls()) == [tenant_style: "acme", tenant_style: "globex"]
    end

    test "the context carries the theme, the variables and the host's assigns" do
      applied =
        apply!(design(generate(:echo)), @rows, vars: %{unit: "kg"}, assigns: %{viewer: "acme"})

      styles(applied)

      assert_received {:context,
                       %{
                         theme: %Visualize.Theme{},
                         vars: %{unit: "kg"},
                         assigns: %{viewer: "acme"}
                       }}
    end

    test "the assigns reach the generator: the viewer's own tenant is outlined" do
      applied =
        apply!(design(generate(:tenant_style, [{:field, :tenant}])), @rows,
          assigns: %{viewer: "acme"}
        )

      [acme, globex, _] = styles(applied)
      assert acme.stroke_width == 3
      assert globex.stroke_width == 1
    end

    test "a color generator paints each row, and :none is no paint" do
      rows = @rows ++ [%{x: 3, y: 3, tenant: "none", state: "ok"}]
      applied = apply!(design(%{fill: generate(:brand_color, [{:field, :tenant}])}), rows)

      assert Enum.map(styles(applied), &Map.get(&1, :fill)) ==
               ["var(--vis-blue, #3b6fa8)", "#00ff00", "var(--vis-blue, #3b6fa8)", :none]
    end

    test "a wrong-typed result applies nothing and is logged at its site" do
      rows = [%{x: 0, y: 0, tenant: "wrong", state: "ok"}]

      log =
        capture_log(fn ->
          applied =
            apply!(
              design([
                %{fill: Visualize.Color.color(:green)},
                generate(:tenant_style, [{:field, :tenant}])
              ]),
              rows
            )

          # The element changes nothing over its mark's green.
          assert [style] = styles(applied)
          refute Map.has_key?(style, :fill)
          assert group(applied).style.fill == "var(--vis-green, #4ca34b)"
        end)

      assert log =~ "marks[0].style: generator :tenant_style returned no style"
    end

    test "a color result that is no color applies nothing: the layer under it shows" do
      rows = [%{x: 0, y: 0, tenant: "other", state: "ok"}]

      log =
        capture_log(fn ->
          applied =
            apply!(
              design([
                %{fill: Visualize.Color.color(:green)},
                %{fill: generate(:brand_color, [{:field, :tenant}])}
              ]),
              rows
            )

          assert [style] = styles(applied)
          refute Map.has_key?(style, :fill)
          assert group(applied).style.fill == "var(--vis-green, #4ca34b)"
        end)

      assert log =~ "generator :brand_color returned no color"
    end

    test "a result holding a generator, a gradient in place or an unknown color is a fault" do
      for tenant <- ["nested", "gradient", "unknown_color"] do
        rows = [%{x: 0, y: 0, tenant: tenant, state: "ok"}]

        log =
          capture_log(fn ->
            applied = apply!(design(generate(:tenant_style, [{:field, :tenant}])), rows)
            assert [style] = styles(applied)
            refute Map.has_key?(style, :fill)
          end)

        assert log =~ "returned no style", tenant
      end
    end

    test "a generator that raises is not rescued" do
      applied = apply!(design(generate(:crash, [{:field, :tenant}])))
      assert_raise ArgumentError, "the host's bug", fn -> styles(applied) end
    end

    test "a generator entry is laid where it stands, above a field entry before it" do
      styles = %{
        ok: %{fill: Visualize.Color.color(:green)},
        warning: %{fill: Visualize.Color.color(:amber)}
      }

      chart =
        design([{:field, :state}, generate(:tenant_style, [{:field, :tenant}])])
        |> Map.put(:styles, styles)

      [acme, _globex, acme2] = apply!(chart) |> styles()
      # The generator's red is laid over the field's green and amber.
      assert acme.fill == "var(--vis-red, #c23238)"
      assert acme2.fill == "var(--vis-red, #c23238)"

      # A view state goes after it, and a trailing local edit over that.
      state =
        Visualize.Chart.Style.with_state(
          [generate(:tenant_style, ["acme"]), %{opacity: 1}],
          :selected
        )

      assert state == [generate(:tenant_style, ["acme"]), :selected, %{opacity: 1}]
    end

    test "a generator in an inline label resolves per datum" do
      label = %{text: "x", style: [:label, generate(:tenant_style, [{:field, :tenant}])]}
      applied = apply!(design(:style_1, label: label))
      svg = Chart.render(applied)
      assert svg =~ "var(--vis-red, #c23238)"
    end

    test "an axis's generator resolves once, with no datum" do
      axes = [
        %{scale: :x, side: :bottom, style: [:axis, generate(:tenant_style, [{:field, :tenant}])]}
      ]

      calls()
      svg = apply!(design(:style_1, axes: axes)) |> Chart.render()
      # With no datum the field argument is nil: the generator answers :good.
      assert {:tenant_style, nil} in calls()
      assert svg =~ "var(--vis-good"
    end

    test "a compiled chart's ticks call the applied chart's generators" do
      applied =
        apply!(design(generate(:tenant_style, [{:field, :tenant}])), @rows,
          assigns: %{viewer: "acme"}
        )

      {:ok, %{main: compiled}} = Chart.compile(applied)
      {group, _compiled} = Visualize.Chart.Compiled.step(compiled, %{s: @rows})
      assert Visualize.Render.to_string(group) =~ ~s(stroke-width="3")
    end

    test "a design without a generator draws as before, the per-datum path untaken" do
      plain = design(:style_1)
      {:ok, applied} = Chart.apply(plain, sources: %{s: @rows})
      assert Chart.render(applied) == Chart.render(apply!(plain))
    end
  end

  describe "explain/2" do
    test "attributes a generator entry's result at layer :generator, with its arguments" do
      applied = apply!(design([:style_1, generate(:tenant_style, [{:field, :tenant}])]))
      explained = Chart.explain(applied, at: [:marks, 0], datum: hd(@rows))

      assert [%{name: :tenant_style, args: ["acme"], at: [], layer: :generator, result: result}] =
               explained.generators

      assert result.fill.color == {:color, :red}
      assert [_theme | _] = explained.parts.fill.chain
      assert List.last(explained.parts.fill.chain).layer == :generator
    end

    test "attributes a color generator at its leaf, and shows a fault" do
      applied = apply!(design(%{fill: generate(:brand_color, [{:field, :tenant}])}))

      explained = Chart.explain(applied, at: [:marks, 0], datum: hd(@rows))

      assert [%{at: [:fill, :color], args: ["acme"], result: {:color, :blue}, layer: :local}] =
               explained.generators

      other = Chart.explain(applied, at: [:marks, 0], datum: %{tenant: "other"})
      assert [%{result: {:fault, _reason}}] = other.generators
    end
  end

  describe "JSON" do
    test "a generator round-trips as $generate" do
      chart =
        design([:style_1, generate(:tenant_style, [{:field, :tenant}]), generate(:tier, [:gold])])
        |> Map.update!(:marks, fn [m] ->
          [Map.put(m, :label, %{text: "x", style: %{fill: generate(:brand_color, ["acme"])}})]
        end)
        |> Chart.from_map!(@gens)

      {:ok, json} = Chart.to_json(chart)
      assert json =~ ~s({"$generate":["tenant_style",[{"$field":"tenant"}]]})
      assert json =~ ~s({"$generate":["tier",[{"$atom":"gold"}]]})
      assert Chart.from_json(json, @gens) == {:ok, chart}
    end

    test "a name that is not plain words is left as read and refused" do
      {:ok, json} =
        Chart.to_json(Chart.from_map!(design(generate(:tenant_style, ["acme"])), @gens))

      json = String.replace(json, ~s("tenant_style"), ~s("Tenant-Style"))

      # Never made into an atom: refused where it stands.
      assert {:error, [{[:marks, 0, :style | _], _reason}]} = Chart.from_json(json, @gens)
      refute json =~ "tenant_style"
    end
  end

  describe "a board" do
    test "realizes its cells with the generators and the assigns" do
      store = %{{:composite, 1} => design(generate(:tenant_style, [{:field, :tenant}]))}

      board =
        Visualize.Board.from_map!(%{
          cells: %{chat: %{x: 0, y: 0, w: 12, h: 4, ref: {:composite, 1}}}
        })

      assert {:error,
              [
                {[:cells, :chat, :ref, :marks, 0, :style],
                 {:undeclared, :generator, :tenant_style}}
              ]} =
               Visualize.Board.realize(board, store, %{chat: %{s: @rows}})

      {:ok, %{chat: applied}, _cache} =
        Visualize.Board.realize(board, store, %{chat: %{s: @rows}},
          generators: [Tenants],
          assigns: %{viewer: "globex"}
        )

      [acme, globex, _] = styles(applied)
      assert acme.stroke_width == 1
      assert globex.stroke_width == 3
    end
  end
end
