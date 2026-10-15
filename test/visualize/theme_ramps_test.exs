defmodule Visualize.ThemeRampsTest do
  @moduledoc """
  A theme's meaning-bearing ramps and roles (spec/08 §7.5, D-135): the shipped themes hold
  their contracts, a theme that breaks one is refused naming the ramp, roles are fixed
  points on the status ramp, scales range over ramps, and the fallback is the default
  theme's, never a series colour.
  """
  use ExUnit.Case, async: true

  alias Visualize.{Chart, Color, Scale, Theme}
  alias Visualize.Chart.{Frame, Style, Validator}

  @themes [Theme.default(), Theme.dark(), Theme.color_safe()]

  defp lch(hex), do: hex |> Color.parse() |> Color.to_hcl()

  describe "the shipped themes" do
    test "every one holds every ramp and role contract" do
      for theme <- @themes, do: assert(Theme.check(theme) == :ok, inspect(theme.name))
    end

    test "every one carries the four ramps and the two free roles" do
      for theme <- @themes do
        assert theme.ramps |> Map.keys() |> Enum.sort() ==
                 Enum.sort([:status, :thermal, :diverging, :sequential])

        # The roles are names by use in the color table (spec/08 §7.1, #663).
        for role <- Theme.role_names(), do: assert(Map.has_key?(theme.colors, role))
      end
    end

    test "status and sequential run away from the background: the low end recedes" do
      for theme <- @themes, ramp <- [:status, :sequential] do
        page = lch(theme.background).l
        low = lch(Theme.ramp(theme, ramp, 0)).l
        high = lch(Theme.ramp(theme, ramp, 1)).l
        assert abs(low - page) < abs(high - page), "#{theme.name} #{ramp}"
      end
    end

    test "the status roles hold 3:1 on the light themes' white" do
      for theme <- [Theme.default(), Theme.color_safe()], role <- [:good, :warning, :bad] do
        colour = Color.parse(Theme.resolve(theme, role, :literal))
        assert Color.contrast(colour, Color.parse(theme.background)) >= 3, "#{theme.name} #{role}"
      end
    end

    test "builtin/1 names the three, and nothing else" do
      assert Enum.map([:default, :dark, :color_safe], &Theme.builtin(&1).name) ==
               [:default, :dark, :color_safe]

      assert Theme.builtin(:house) == nil
    end
  end

  describe "contracts refuse a theme that breaks one, naming the ramp" do
    test "reordered status hues" do
      error =
        assert_raise ArgumentError, fn ->
          Theme.new(name: :house, ramps: %{status: ~w(#c23238 #bd7407 #4ca34b)})
        end

      assert error.message =~ "theme :house: ramp :status breaks its contract"
      assert error.message =~ "good (0) must be green or blue"
    end

    test "status lightness that is not monotonic" do
      error =
        assert_raise ArgumentError, fn ->
          Theme.new(ramps: %{status: ~w(#4ca34b #e0a030 #c23238)})
        end

      assert error.message =~ "ramp :status"
      assert error.message =~ "lightness must change one way along the ramp, by at least 3 L*"
      assert error.message =~ ~s(anchor 2 "#e0a030")
    end

    test "sequential lightness that steps by less than the tolerance" do
      assert {:error, {:ramp, :sequential}, message} =
               Theme.check(%{Theme.default() | ramps: %{sequential: ~w(#5e95d3 #5a92d0 #004580)}})

      assert message =~ "only"
    end

    test "a status whose hue turns back between its anchors" do
      # Green, then a blue, then amber and red: the ends and the middle are right and the
      # lightness falls, but the hue climbs from green to blue before it falls.
      ramp = ~w(#68be64 #65a0e2 #bd7407 #ca4c23 #c23238)

      assert {:error, {:ramp, :status}, message} =
               Theme.check(%{Theme.default() | ramps: %{status: ramp}})

      assert message =~ "hue must fall from good to bad"
    end

    test "a thermal ramp with no neutral midpoint, and a diverging one of one hue" do
      assert {:error, {:ramp, :thermal}, message} =
               Theme.check(%{Theme.default() | ramps: %{thermal: ~w(#0e68ad #5e95d3 #c02e31)}})

      assert message =~ "midpoint (0.5) must be neutral"

      assert {:error, {:ramp, :diverging}, message} =
               Theme.check(%{Theme.default() | ramps: %{diverging: ~w(#b35806 #ededed #c02e31)}})

      assert message =~ "at least 60° apart"
    end

    test "a sequential ramp of more than one hue family" do
      viridis = Visualize.Scale.Color.scheme(:viridis)

      assert {:error, {:ramp, :sequential}, message} =
               Theme.check(%{Theme.default() | ramps: %{sequential: viridis}})

      assert message =~ "one hue family"

      for scheme <- [:blues, :greens, :greys, :oranges, :purples, :reds] do
        sequential = Visualize.Scale.Color.scheme(scheme)
        assert Theme.check(%{Theme.default() | ramps: %{sequential: sequential}}) == :ok
      end
    end

    test "roles: info is a blue, neutral is neutral" do
      assert {:error, {:color, :neutral}, _} =
               Theme.check(Theme.build(Theme.default(), colors: %{neutral: "#3b6fa8"}))

      assert {:error, {:color, :info}, _} =
               Theme.check(Theme.build(Theme.default(), roles: %{info: "#c23238"}))
    end

    test "what is not a ramp, a role or a colour" do
      assert_raise ArgumentError, ~r/ramp :heat breaks its contract: is not a ramp/, fn ->
        Theme.new(ramps: %{heat: ~w(#fff #000)})
      end

      assert_raise ArgumentError,
                   ~r/color :good breaks its contract: "nope" is not a colour/,
                   fn ->
                     Theme.new(colors: %{good: "nope"})
                   end

      assert_raise ArgumentError, ~r/color :mine breaks its contract: names :nope/, fn ->
        Theme.new(colors: %{mine: {:color, :nope}})
      end

      assert_raise ArgumentError, ~r/color :a breaks its contract: reaches itself/, fn ->
        Theme.new(colors: %{a: {:color, :b}, b: {:color, :a}})
      end

      assert_raise ArgumentError, ~r/needs at least two anchors/, fn ->
        Theme.new(ramps: %{sequential: ["#004580"]})
      end

      assert_raise ArgumentError, ~r/anchor 2 "nope" is not a colour/, fn ->
        Theme.new(ramps: %{sequential: ["#e9f2fc", "nope"]})
      end
    end

    test "a background alone never breaks a contract: lightness may run either way" do
      assert Theme.new(background: "#000000").ramps == Theme.default().ramps
      assert Theme.new(background: "transparent").name == :default
    end
  end

  describe "ramps and roles resolve" do
    test "{:ramp, :status, 0.5} is :warning in every theme, in both modes" do
      for theme <- @themes, mode <- [:literal, :css] do
        for {role, t} <- [good: 0, warning: 0.5, bad: 1, bad: 1.0] do
          assert Theme.resolve(theme, {:ramp, :status, t}, mode) ==
                   Theme.resolve(theme, role, mode)
        end
      end
    end

    test "a role is a slot: a CSS reference with its literal, declared by the stylesheet" do
      theme = Theme.default()
      assert Theme.resolve(theme, :bad, :css) == "var(--vis-bad, #c23238)"
      assert Theme.resolve(theme, :neutral, :literal) == "#6f7480"
      assert Theme.stylesheet(theme) =~ "\n  --vis-warning: #bd7407;\n"
      assert Theme.stylesheet(Theme.color_safe()) =~ ".vis-theme-color_safe {\n"
      assert Theme.stylesheet(Theme.color_safe()) =~ "\n  --vis-good: #5996d6;\n"
    end

    test "a ramp position between anchors is Lab-interpolated, a literal in both modes" do
      theme = Theme.default()
      quarter = Theme.ramp(theme, :thermal, 0.25)

      expected =
        Color.interpolate_lab(Color.parse("#0e68ad"), Color.parse("#e8e8e8"), 0.5)
        |> Color.to_hex()

      assert quarter == expected
      assert Theme.resolve(theme, {:ramp, :thermal, 0.25}, :css) == quarter
      assert Theme.ramp(theme, :thermal, -1) == "#0e68ad"
      assert Theme.ramp(theme, :thermal, 2) == "#c02e31"
    end

    test "lightness along a shipped sequential ramp is monotonic at every position" do
      for theme <- @themes do
        ls = for i <- 0..20, do: lch(Theme.ramp(theme, :sequential, i / 20)).l
        assert ls == Enum.sort(ls) or ls == Enum.sort(ls, :desc), inspect(theme.name)
      end
    end

    test "an unknown ramp or a position that is not a number raises" do
      assert_raise ArgumentError, ~r/unknown ramp :heat/, fn ->
        Theme.ramp(Theme.default(), :heat, 0.5)
      end

      assert_raise ArgumentError, ~r/a position is a number/, fn ->
        Theme.ramp(Theme.default(), :status, "half")
      end
    end
  end

  describe "fallback is the default theme's, never a series colour" do
    test "a struct that lacks a ramp or a role" do
      bare = %{Theme.dark() | ramps: %{}, colors: %{}}
      assert Theme.ramp(bare, :status, 0) == Theme.ramp(Theme.default(), :status, 0)

      assert Theme.resolve(bare, :info, :literal) ==
               Theme.resolve(Theme.default(), :info, :literal)

      refute Theme.resolve(bare, :good, :literal) in bare.series
    end

    test "new/1 and merge/2 merge ramps and roles key by key" do
      theme = Theme.new(ramps: %{sequential: ~w(#fff5eb #fd8d3c #8c2d04)})
      assert theme.ramps.status == Theme.default().ramps.status
      assert theme.ramps.sequential == ~w(#fff5eb #fd8d3c #8c2d04)

      night = Theme.merge(Theme.dark(), roles: %{info: "#5e95d3"})
      assert night.colors == %{Theme.dark().colors | info: "#5e95d3"}
      assert night.ramps == Theme.dark().ramps
    end
  end

  # -- scales over ramps ----------------------------------------------------------------

  @size {300, 200}

  defp chart(scales, extra \\ %{}) do
    Chart.from_map!(
      Map.merge(
        %{
          version: 3,
          sources: %{states: %{fields: [:from, :to, :state]}},
          frames: %{main: %{kind: :cartesian, scales: scales}}
        },
        extra
      )
    )
  end

  describe "a colour scale over a ramp" do
    test "an ordinal scale spreads its domain end to end" do
      color = %{kind: :ordinal, domain: ["ok", "degraded", "down"], range: {:ramp, :status}}
      frame = Frame.new(chart(%{color: color}), size: @size)
      scale = Frame.scale(frame, :color)

      assert Enum.map(["ok", "degraded", "down"], &Scale.apply(scale, &1)) ==
               [{:ramp, :status, 0.0}, {:ramp, :status, 0.5}, {:ramp, :status, 1.0}]

      for {state, role} <- [{"ok", :good}, {"degraded", :warning}, {"down", :bad}] do
        assert Style.color(Scale.apply(scale, state), frame.theme, :css) ==
                 Theme.resolve(frame.theme, role, :css)
      end

      four = %{color | domain: ~w(a b c d)}
      scale = Frame.scale(Frame.new(chart(%{color: four}), size: @size), :color)
      assert Enum.map(~w(a b c d), &elem(Scale.apply(scale, &1), 2)) == [0.0, 1 / 3, 2 / 3, 1.0]

      one = %{color | domain: ["only"]}
      scale = Frame.scale(Frame.new(chart(%{color: one}), size: @size), :color)
      assert Scale.apply(scale, "only") == {:ramp, :status, 0}
    end

    test "a threshold scale takes one position per bucket" do
      color = %{kind: :threshold, domain: [10, 20], range: {:ramp, :status}}
      scale = Frame.scale(Frame.new(chart(%{color: color}), size: @size), :color)

      assert Enum.map([5, 15, 25], &Scale.apply(scale, &1)) ==
               [{:ramp, :status, 0.0}, {:ramp, :status, 0.5}, {:ramp, :status, 1.0}]
    end

    test "a sequential or diverging scale interpolates the ramp" do
      scales = %{
        heat: %{kind: :sequential, domain: [0, 10], range: {:ramp, :thermal}},
        delta: %{kind: :diverging, domain: [-5, 5]}
      }

      frame = Frame.new(chart(scales), size: @size)
      theme = frame.theme
      assert Scale.apply(Frame.scale(frame, :heat), 0) == "#0e68ad"
      assert Scale.apply(Frame.scale(frame, :heat), 2.5) == Theme.ramp(theme, :thermal, 0.25)
      assert Scale.apply(Frame.scale(frame, :heat), 10) == "#c02e31"
      # :auto on a diverging scale is the theme's diverging ramp, its midpoint neutral.
      assert Scale.apply(Frame.scale(frame, :delta), 0) == "#ededed"
    end

    test "a ramp follows the theme the frame is built with" do
      color = %{kind: :sequential, domain: [0, 1]}
      frame = Frame.new(chart(%{color: color}), size: @size, theme: Theme.dark())
      assert Scale.apply(Frame.scale(frame, :color), 0) == "#273b4f"
    end

    test "a scale whose range length is its bucket count refuses a ramp" do
      color = %{kind: :quantize, domain: [0, 1], range: {:ramp, :status}}

      assert_raise ArgumentError, ~r/scale :color \(quantize\) cannot range over/, fn ->
        Frame.new(chart(%{color: color}), size: @size)
      end
    end
  end

  # -- one design, three themes -----------------------------------------------------------

  @rows [
    %{from: 0, to: 1, state: "ok"},
    %{from: 1, to: 2, state: "degraded"},
    %{from: 2, to: 3, state: "down"}
  ]

  defp status_design(range) do
    %{
      version: 3,
      sources: %{states: %{fields: [:from, :to, :state]}},
      styles: %{by_state: %{fill: {:field, :state}}},
      frames: %{
        main: %{
          kind: :cartesian,
          scales: %{
            x: %{kind: :linear, domain: [0, 3]},
            y: %{kind: :linear, domain: [0, 1]},
            color: %{kind: :ordinal, domain: ["ok", "degraded", "down"], range: range}
          }
        }
      },
      marks: [
        %{
          type: :rect,
          data: :states,
          channels: %{x0: :from, x1: :to, y0: 0, y1: 1},
          style: :by_state
        }
      ]
    }
  end

  defp fills(svg) do
    ~r/<rect[^>]* fill="(#[0-9a-f]{6})"/ |> Regex.scan(svg) |> Enum.map(&List.last/1)
  end

  test "the same design keeps good → warning → bad under the light, dark and colour-safe themes" do
    for range <- [{:ramp, :status}, [:good, :warning, :bad]], theme <- @themes do
      {:ok, applied} =
        Chart.apply(status_design(range), sources: %{states: @rows}, theme: theme, size: @size)

      fills = applied |> Chart.render(resolve: :literal) |> fills()

      assert fills == Enum.map([:good, :warning, :bad], &Theme.resolve(theme, &1, :literal))

      [good, warning, bad] = Enum.map(fills, &lch/1)
      # The hue order: green or blue, then amber, then red (spec/08 §7.5).
      assert good.h >= 100 and good.h < 315
      assert warning.h >= 45 and warning.h < 100
      assert bad.h < 45 or bad.h >= 345
      # The lightness order: monotonic, so a reader who sees no hue still reads it.
      assert (good.l - warning.l) * (warning.l - bad.l) > 0, inspect(theme.name)
    end
  end

  # -- the validator and the codec --------------------------------------------------------

  describe "the validator" do
    test "a ramp position and a role are colours; a ramp out of range is not" do
      design = status_design({:ramp, :status})
      assert Validator.validate(design) == :ok

      for fill <- [{:ramp, :thermal, 0.3}, :good, :neutral] do
        assert Validator.validate(put_in(design, [:styles, :by_state, :fill], fill)) == :ok
      end

      for fill <- [{:ramp, :heat, 0.3}, {:ramp, :status, 2}] do
        assert {:error, [{[:styles, :by_state, :fill, :color], {:type, :color}}]} =
                 Validator.validate(put_in(design, [:styles, :by_state, :fill], fill))
      end

      bad = put_in(design, [:frames, :main, :scales, :color, :range], {:ramp, :heat})

      assert {:error, [{[:frames, :main, :scales, :color, :range], {:type, :ramp}}]} =
               Validator.validate(bad)
    end

    test "an inline theme that breaks a contract is a fault at the ramp" do
      design =
        Map.put(status_design({:ramp, :status}), :theme, %{
          ramps: %{status: ~w(#c23238 #bd7407 #4ca34b)}
        })

      assert {:error, [{[:theme, :ramps, :status], {:contract, message}} = error]} =
               Validator.validate(design)

      assert message =~ "good (0) must be green or blue"
      assert Validator.format(error) =~ "theme.ramps.status: breaks its contract: good (0)"

      colors = Map.put(status_design({:ramp, :status}), :theme, %{colors: %{info: "#c23238"}})
      assert {:error, [{[:theme, :colors, :info], {:contract, _}}]} = Validator.validate(colors)

      # The role colors of before #663 are read as the color table, silently.
      roles = Map.put(status_design({:ramp, :status}), :theme, %{roles: %{info: "#c23238"}})
      assert {:error, [{[:theme, :colors, :info], {:contract, _}}]} = Validator.validate(roles)
    end

    test "theme: :color_safe is built in, and its roles are slots" do
      design =
        status_design([:good, :warning, :bad])
        |> Map.put(:theme, :color_safe)
        |> put_in([:styles, :by_state, :stroke], :bad)

      assert Validator.validate(design) == :ok
    end
  end

  test "JSON carries a ramp position, a ramp range, roles and an inline theme's ramps" do
    design =
      status_design({:ramp, :status})
      |> put_in([:styles, :by_state, :stroke], {:ramp, :thermal, 0.25})
      |> put_in([:styles, :edge], %{stroke: :warning})
      |> Map.put(:theme, %{ramps: %{sequential: ~w(#fff5eb #fd8d3c #8c2d04)}})

    chart = Chart.from_map!(design)
    {:ok, json} = Chart.to_json(chart)
    assert json =~ ~s("$ramp":"status")
    assert json =~ ~s("$ramp":["thermal",0.25])
    assert {:ok, ^chart} = Chart.from_json(json)
  end

  describe "Visualize.Color's Lab" do
    test "to_lab/1 and lab/4 are each other's inverse" do
      for hex <- ~w(#808080 #3b6fa8 #c8373b #f7f7f7 #000000 #ffffff #4ca34b) do
        %{l: l, a: a, b: b} = hex |> Color.parse() |> Color.to_lab()
        assert Color.to_hex(Color.lab(l, a, b)) == hex
      end
    end

    test "a grey is neutral" do
      for hex <- ~w(#808080 #f7f7f7 #333333) do
        %{a: a, b: b} = hex |> Color.parse() |> Color.to_lab()
        assert abs(a) < 2 and abs(b) < 4
      end

      assert %{a: +0.0, b: +0.0} = "#808080" |> Color.parse() |> Color.to_lab()
    end
  end
end
