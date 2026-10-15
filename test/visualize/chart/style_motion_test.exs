defmodule Visualize.Chart.StyleMotionTest do
  @moduledoc """
  A style's `transition` part (spec/14 §3.10, #653, D-176): the schema, the resolution, the
  identity a moving mark's elements carry, the `:css` class and rule with its colours in
  `oklch()`, and the motion span of the canvas encoders.
  """
  use ExUnit.Case, async: true

  alias Visualize.Backend.CanvasBinary
  alias Visualize.Backend.CanvasBinary.Decoder
  alias Visualize.Chart
  alias Visualize.Chart.{Frame, Style, Validator}
  alias Visualize.IR.Motion

  doctest Visualize.IR.Motion

  @theme Visualize.Theme.default()

  # Points coloured by their row's state: `error` names a style that moves its fill.
  defp design(styles \\ nil) do
    %{
      version: 3,
      sources: %{s: %{fields: [:x, :y, :state]}},
      styles:
        styles ||
          %{
            error: %{
              fill: Visualize.Color.color(:red),
              transition: %{fill: %{duration: 400, easing: :linear}}
            }
          },
      frames: %{
        main: %{kind: :cartesian, scales: %{x: %{kind: :linear}, y: %{kind: :linear}}}
      },
      marks: [
        %{
          type: :symbol,
          data: :s,
          channels: %{x: :x, y: :y, series: :state},
          style: [{:field, :state}]
        }
      ]
    }
  end

  @rows [%{x: 1, y: 2, state: "ok"}, %{x: 2, y: 3, state: "error"}]

  defp applied(design, rows \\ @rows) do
    {:ok, applied} = Chart.apply(Chart.from_map!(design), sources: %{s: rows})
    applied
  end

  describe "the part" do
    test "validates, and names an unknown key, an easing that is no curve and a negative time" do
      assert :ok = Validator.validate(design())

      bad =
        design(%{
          error: %{transition: %{duration: -1, easing: :wobble, stroke: %{duration: -5}, x: 1}}
        })

      assert {:error, errors} = Validator.validate(bad)
      assert {[:styles, :error, :transition, :x], :unknown_key} in errors
      assert {[:styles, :error, :transition, :duration], :negative} in errors
      assert {[:styles, :error, :transition, :stroke, :duration], :negative} in errors

      assert Enum.any?(errors, &match?({[:styles, :error, :transition, :easing], {:enum, _}}, &1))
      assert Validator.format({[:x], :negative}) =~ "must not be negative"
    end

    test "resolves to the properties it moves, each its entry's, else the part's, else 300 and :cubic_in_out" do
      resolve = &Style.resolve(%{transition: &1}, @theme, :css)

      assert resolve.(%{duration: 200}) == %{
               transition: [
                 {:fill, 200, :cubic_in_out},
                 {:stroke, 200, :cubic_in_out},
                 {:opacity, 200, :cubic_in_out}
               ]
             }

      assert resolve.(%{fill: %{duration: 400}, stroke: %{easing: :linear}}) == %{
               transition: [{:fill, 400, :cubic_in_out}, {:stroke, 300, :linear}]
             }

      assert resolve.(%{easing: :quad_out, opacity: %{duration: 0}}) == %{
               transition: [{:fill, 300, :quad_out}, {:stroke, 300, :quad_out}]
             }

      # A node that names nothing moves nothing, and is no key.
      assert resolve.(%{}) == %{}
    end

    test "merges key by key as a part, and a container's defaults give it" do
      under = %{transition: %{duration: 200, fill: %{easing: :linear}}}

      assert Style.merge(under, %{transition: %{duration: 500}}) ==
               %{transition: %{duration: 500, fill: %{easing: :linear}}}

      with_defaults =
        design(%{error: %{fill: Visualize.Color.color(:red)}})
        |> Map.put(:defaults, %{transition: %{duration: 250}})

      assert :ok = Validator.validate(with_defaults)
      svg = Chart.render(applied(with_defaults))
      assert svg =~ "fill 250ms linear("
    end
  end

  describe ":css output" do
    test "a class per distinct transition, one rule, the curve as linear(), and the reduced-motion rule" do
      svg = Chart.render(applied(design()))

      [class] = Regex.run(~r/class="(vis-transition-[0-9a-z]+)"/, svg, capture: :all_but_first)

      assert svg =~
               "<style>.#{class}, :where(.#{class}) * { transition: fill 400ms linear, fill-opacity 400ms linear; }\n"

      assert svg =~
               ~s|@media (prefers-reduced-motion: reduce) { [class*="vis-transition-"], [class*="vis-transition-"] * { transition: none !important; } }</style>|

      # One element moves its fill: it is written in oklch(), a slot as a relative colour.
      assert svg =~ ~s|fill="oklch(from var(--vis-red, #c23238) l c h / alpha)"|
      # The row whose style does not move keeps its colour as it was.
      assert svg =~
               ~s|data-series="ok" data-vis-id="main.1.state=ok" fill="var(--vis-series-1, #3b6fa8)"|
    end

    test "a literal colour is written in oklch() coordinates, and the easing as the samples of its curve" do
      styles = %{error: %{fill: "#ff0000", transition: %{duration: 100, easing: :quad_in}}}
      svg = Chart.render(applied(design(styles)))
      assert svg =~ ~s|fill="oklch(0.628 0.2577 29.23)"|
      assert svg =~ "fill 100ms " <> Motion.css_easing(:quad_in)
      assert Motion.samples(:quad_in) |> length() == 21
    end

    test "a mark's own transition is on its group, and its children move with it" do
      d =
        design(%{})
        |> put_in([:marks, Access.at(0), :style], %{
          fill: "#0000ff",
          transition: %{fill: %{duration: 300}}
        })

      svg = Chart.render(applied(d))
      assert svg =~ ~r/<g class="mark mark-symbol vis-transition-[0-9a-z]+" fill="oklch\(/
    end

    test "nothing is written in :literal mode, and the end state is drawn" do
      svg = Chart.render(applied(design()), resolve: :literal)
      refute svg =~ "vis-transition"
      refute svg =~ "<style>"
      refute svg =~ "transition"
      assert svg =~ ~s|fill="#c23238"|
    end
  end

  describe "identity" do
    test "a moving mark's elements name their rows: inferred from the series, else the ordinal" do
      svg = Chart.render(applied(design()))
      assert svg =~ ~s|data-vis-id="main.1.state=ok"|
      assert svg =~ ~s|data-vis-id="main.1.state=error"|

      no_series = put_in(design(), [:marks, Access.at(0), :channels], %{x: :x, y: :y})
      svg = Chart.render(applied(no_series))
      assert svg =~ ~s|data-vis-id="main.1.#0"|
      assert svg =~ ~s|data-vis-id="main.1.#1"|
    end

    test "the identity the slot's schema declares comes first, several fields joined in name order" do
      schema =
        Visualize.Data.Schema.new!(%{
          x: %{type: :number},
          y: %{type: :number, identity: true},
          state: %{type: :category, identity: true}
        })

      chart = Chart.from_map!(design())
      sources = %{s: @rows}
      frame = Frame.new(chart, sources: sources, schemas: %{s: schema})
      svg = frame |> Frame.generate(sources: sources) |> to_string()
      assert svg =~ ~s|data-vis-id="main.1.state=error&amp;y=3"|
    end

    test "a design without motion writes no identity, no class and no style" do
      plain = design(%{error: %{fill: Visualize.Color.color(:red)}})
      svg = Chart.render(applied(plain))
      refute svg =~ "data-vis-id"
      refute svg =~ "<style>"
      refute svg =~ "oklch"
    end
  end

  describe "canvas" do
    test "the :json commands wrap each row in a motion span, an empty one for a row that does not move" do
      json = Chart.render(applied(design()), backend: :canvas, format: :json)

      assert json =~
               ~s|{"cmd":"motion","args":["main.1.state=ok",[-4.5135,-4.5135,9.027,9.027],[]]}|

      assert json =~
               ~s|{"cmd":"motion","args":["main.1.state=error",[-4.5135,-4.5135,9.027,9.027],[["fill",400,[0,1]]]]}|

      assert length(String.split(json, ~s|{"cmd":"motionEnd","args":[]}|)) == 3
    end

    test "a :js script draws the end state and writes no span" do
      js = Chart.render(applied(design()), backend: :canvas, format: :js)
      refute js =~ "motion"
      assert js =~ "ctx.fillStyle = '#c23238';"
    end

    test "the binary stream is version 2 and carries the span's JSON, which the decoder reads" do
      tree = Chart.generate(applied(design()), resolve: :literal)
      records = tree |> CanvasBinary.encode_element!() |> Decoder.decode()
      assert hd(records) == {:version, 2}

      spans = for {:motion, json} <- records, do: json

      assert spans == [
               ~s|["main.1.state=ok",[-4.5135,-4.5135,9.027,9.027],[]]|,
               ~s|["main.1.state=error",[-4.5135,-4.5135,9.027,9.027],[["fill",400,[0,1]]]]|
             ]

      assert Enum.count(records, &(&1 == :motion_end)) == 2
    end

    test "a stream without motion is version 1, byte for byte as before" do
      tree = Chart.generate(applied(design(%{error: %{fill: "#ff0000"}})), resolve: :literal)
      records = tree |> CanvasBinary.encode_element!() |> Decoder.decode()
      refute Enum.any?(records, &match?({:version, _}, &1))
      refute Enum.any?(records, &match?({:motion, _}, &1))
    end
  end

  test "a span's JSON escapes every character a datum may hold" do
    assert Motion.json(["a\"b\\c\n\u0001", nil, [1.5, :x]]) ==
             ~S(["a\"b\\c\u000A\u0001",null,[1.5,"x"]])
  end
end
