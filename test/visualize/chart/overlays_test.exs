defmodule Visualize.Chart.OverlaysTest do
  @moduledoc """
  The overlays a host drew around a chart, drawn as marks fed from sources (#565, D-143,
  spec/14 §2.9, §4.3, §5.2): event markers and spans colored by what their feed says a
  severity means, threshold rules from a source and a target rule from a feed's schema,
  rules and bands cut to the plot, a mark's own color scale inside a series-colored
  chart, polarity on a ramp, and the design's brush — each from data on SVG, the canvas,
  the binary stream and the hybrid page, in the colors of whichever theme draws it.
  """
  use ExUnit.Case, async: true

  import Visualize.Chart, only: [fact: 3]

  alias Visualize.Backend.CanvasBinary
  alias Visualize.Backend.CanvasBinary.Decoder
  alias Visualize.Chart
  alias Visualize.Chart.{Compiled, Frame, Validator}
  alias Visualize.Data.{Delivery, Schema}
  alias Visualize.IR.Element
  alias Visualize.{Render, Theme}

  @size {300, 200}
  @margin %{top: 0, right: 0, bottom: 0, left: 0}

  # The events feed: what each severity means, never a color (spec/08 §10.1).
  @events_schema Schema.new!(%{
                   at: %{type: :number},
                   ends: %{type: :number},
                   title: %{type: :text, label: "Event"},
                   severity: %{
                     type: :category,
                     order: ["info", "warning", "critical"],
                     status: %{"info" => :info, "warning" => :warning, "critical" => :bad}
                   }
                 })

  # The series feed: its target, and which way from it is better.
  @primary_schema Schema.new!(%{
                    t: %{type: :number},
                    v: %{type: :number, target: 7, polarity: :lower_is_better},
                    host: %{type: :category}
                  })

  @primary for t <- 0..10, host <- ["a", "b"], do: %{t: t * 10, v: rem(t, 5) + 2, host: host}

  @events [
    %{at: 20, ends: nil, title: "deploy", severity: "info"},
    %{at: 50, ends: nil, title: "outage", severity: "critical"},
    %{at: 130, ends: nil, title: "later", severity: "warning"},
    %{at: -20, ends: 30, title: "maintenance", severity: "warning"},
    %{at: 80, ends: 140, title: "incident", severity: "critical"},
    %{at: 120, ends: 160, title: "future", severity: "info"}
  ]

  @thresholds [%{value: 3, severity: "warning"}, %{value: 8, severity: "critical"}]

  # The overlay layer over a line per host, with every color by meaning (spec/14 §5.2).
  defp design(extra \\ %{}) do
    Map.merge(
      %{
        version: 3,
        sources: %{
          primary: %{fields: [:t, :v, :host]},
          events: %{fields: [:at, :ends, :title, :severity]},
          thresholds: %{fields: [:value, :severity]}
        },
        frames: %{
          main: %{
            kind: :cartesian,
            margin: @margin,
            scales: %{
              x: %{kind: :linear, domain: [0, 100]},
              y: %{kind: :linear, domain: [0, 10]},
              color: %{kind: :ordinal},
              severity: %{kind: :ordinal, range: fact(:events, :severity, :status)}
            }
          }
        },
        marks: [
          %{type: :line, data: :primary, channels: %{x: :t, y: :v, series: :host}},
          %{
            type: :rule,
            data: %{source: :events, transforms: [%{op: :filter, field: :ends, test: :absent}]},
            channels: %{x: :at},
            scales: %{color: :severity},
            style: %{stroke: {:field, :severity}, stroke_dasharray: [3, 3]},
            label: %{text: "\#{field(:title)}"},
            tooltip: %{
              fields: [:title, :severity],
              template: "{title} · {severity}",
              event: :event
            }
          },
          %{
            type: :x_band,
            data: %{source: :events, transforms: [%{op: :filter, field: :ends, test: :present}]},
            channels: %{x0: :at, x1: :ends},
            scales: %{color: :severity},
            style: %{fill: {:field, :severity}, fill_opacity: 0.15}
          },
          %{
            type: :rule,
            data: :thresholds,
            channels: %{y: :value},
            scales: %{color: :severity},
            style: %{stroke: {:field, :severity}}
          }
        ]
      },
      extra
    )
  end

  defp sources do
    %{
      primary: Delivery.new(@primary, schema: Schema.version(@primary_schema)),
      events: Delivery.new(@events, schema: Schema.version(@events_schema)),
      thresholds: @thresholds
    }
  end

  defp describe(:events), do: {:ok, @events_schema}
  defp describe(:primary), do: {:ok, @primary_schema}

  defp apply!(design, opts \\ []) do
    {:ok, applied} =
      Chart.apply(
        design,
        Keyword.merge([sources: sources(), describe: &describe/1, size: @size], opts)
      )

    applied
  end

  defp group(applied, opts \\ []), do: Chart.generate(applied, opts)

  # Every element of a class, depth first.
  defp find(%Element{} = element, class) do
    own = if element.style[:class] == class, do: [element], else: []
    own ++ Enum.flat_map(element.children || [], &find(&1, class))
  end

  defp lines(element),
    do: for(rule <- find(element, "rule"), [line | _] = rule.children, do: line)

  defp role(theme, role, mode), do: Theme.resolve(theme, role, mode)

  describe "event markers and spans from a source (spec/14 §5.2)" do
    test "an instant is a rule at x, labeled and colored by its feed's meaning" do
      root = group(apply!(design()))
      [rules, thresholds] = find(root, "mark mark-rule")

      # The instants inside the window: deploy (info) and outage (critical); 130 is past it.
      assert [deploy, outage] = lines(rules)
      assert {deploy.attrs.x1, outage.attrs.x1} == {60.0, 150.0}
      assert deploy.style.stroke == role(Theme.default(), :info, :css)
      assert outage.style.stroke == role(Theme.default(), :bad, :css)
      assert deploy.style.stroke_dasharray == "3 3"

      # The label and the hover text read the row; a click pushes `event`.
      svg = Render.to_string(rules, backend: :svg)
      assert svg =~ ">deploy</text>"
      assert svg =~ ">outage</text>"
      refute svg =~ ">later</text>"
      assert svg =~ ~s(data-tooltip-template="{title} · {severity}")
      assert svg =~ ~s(data-tooltip-event="event")

      # The threshold rules: horizontal across the plot at each value.
      assert [low, high] = lines(thresholds)
      assert {low.attrs.x1, low.attrs.x2, low.attrs.y1, low.attrs.y2} == {0, 300, 140.0, 140.0}
      assert {high.attrs.y1, high.attrs.y2} == {40.0, 40.0}
      assert low.style.stroke == role(Theme.default(), :warning, :css)
      assert high.style.stroke == role(Theme.default(), :bad, :css)
    end

    test "a span is an x band cut to the plot; one wholly outside draws nothing" do
      [spans] = group(apply!(design())) |> find("mark mark-x_band")

      rects = for band <- spans.children, [rect | _] = band.children, do: rect

      # maintenance began before the window and is clamped at its left edge; incident ends
      # after it and is clamped at its right; future lies wholly outside.
      assert [{+0.0, 90.0}, {240.0, 60.0}] =
               Enum.map(rects, &{&1.attrs.x * 1.0, &1.attrs.width * 1.0})

      assert [maintenance, incident] = rects
      assert maintenance.style.fill == role(Theme.default(), :warning, :css)
      assert incident.style.fill == role(Theme.default(), :bad, :css)
    end

    test "the series keep their colors: the overlay reads a color scale of its own (D-143)" do
      [line] = group(apply!(design())) |> find("mark mark-line")
      strokes = for path <- line.children, do: path.style.stroke

      assert strokes == [
               role(Theme.default(), :series_1, :css),
               role(Theme.default(), :series_2, :css)
             ]

      # The events' scale holds the severities its map names, in the order they appeared.
      applied = apply!(design())
      assert Frame.scale(applied.frame, :severity).domain == ["info", "critical", "warning"]
      assert Frame.scale(applied.frame, :color).domain == ["a", "b"]
    end

    test "a severity the feed does not describe draws the theme's neutral, never nothing" do
      events = [%{at: 40, ends: nil, title: "odd", severity: "debug"}]

      sources =
        Map.put(sources(), :events, Delivery.new(events, schema: Schema.version(@events_schema)))

      {:ok, applied} =
        Chart.apply(design(), sources: sources, describe: &describe/1, size: @size)

      [rules, _thresholds] = group(applied) |> find("mark mark-rule")
      assert [odd] = lines(rules)
      assert odd.style.stroke == role(Theme.default(), :axis, :css)
    end

    test "with no events the overlay draws no element" do
      sources =
        Map.put(sources(), :events, Delivery.new([], schema: Schema.version(@events_schema)))

      {:ok, applied} = Chart.apply(design(), sources: sources, describe: &describe/1, size: @size)
      [rules, _thresholds] = group(applied) |> find("mark mark-rule")
      assert lines(rules) == []
      assert [%Element{children: []}] = group(applied) |> find("mark mark-x_band")
    end
  end

  describe "thresholds and the feed's target (spec/14 §4.3, §5.2)" do
    test "a threshold feeds an inferred domain, so it is always in view" do
      design =
        put_in(design(), [:frames, :main, :scales, :y], %{kind: :linear, domain: [0, :auto]})

      sources = %{sources() | thresholds: [%{value: 12, severity: "critical"}]}
      {:ok, applied} = Chart.apply(design, sources: sources, describe: &describe/1, size: @size)
      assert [0, 12] = Frame.scale(applied.frame, :y).domain

      [_rules, thresholds] = group(applied) |> find("mark mark-rule")
      assert [%{attrs: %{y1: +0.0}}] = lines(thresholds)
    end

    test "a threshold outside a fixed domain is cut: it draws nothing" do
      sources = %{sources() | thresholds: [%{value: 12, severity: "critical"}]}

      {:ok, applied} =
        Chart.apply(design(), sources: sources, describe: &describe/1, size: @size)

      [_rules, thresholds] = group(applied) |> find("mark mark-rule")
      assert lines(thresholds) == []
    end

    test "the target line reads the feed's schema with fact/3" do
      target = %{
        type: :rule,
        data: %{source: :primary, transforms: [%{op: :take, n: 1}]},
        channels: %{y: fact(:primary, :v, :target)},
        style: %{stroke: :neutral},
        label: %{text: "target \#{fact(:primary, :v, :target)}"}
      }

      design = update_in(design(), [:marks], &(&1 ++ [target]))
      [_rules, _thresholds, rule] = group(apply!(design)) |> find("mark mark-rule")

      assert [line] = lines(rule)
      assert {line.attrs.y1, line.attrs.x2} == {60.0, 300}
      assert line.style.stroke == role(Theme.default(), :neutral, :css)
      assert Render.to_string(rule, backend: :svg) =~ ">target 7</text>"
    end

    test "a feed without a target fails application, naming the slot, field and attribute" do
      target = %{
        type: :rule,
        data: %{source: :primary, transforms: [%{op: :take, n: 1}]},
        channels: %{y: fact(:primary, :v, :target)}
      }

      bare = Schema.new!(%{t: %{type: :number}, v: %{type: :number}, host: %{type: :category}})
      design = update_in(design(), [:marks], &(&1 ++ [target]))
      sources = %{sources() | primary: Delivery.new(@primary, schema: Schema.version(bare))}

      describe = fn
        :primary -> {:ok, bare}
        other -> describe(other)
      end

      assert {:error, errors} = Chart.apply(design, sources: sources, describe: describe)
      assert {[:marks, 4, :channels, :y], {:missing_attribute, :primary, :v, :target}} in errors
    end
  end

  describe "polarity places a ramp by worth (spec/14 §4.3)" do
    defp worth_design(polarity) do
      design(%{
        marks: [
          %{
            type: :circle,
            data: :primary,
            channels: %{x: :t, y: :v},
            scales: %{color: :worth},
            style: %{fill: {:field, :v}}
          }
        ]
      })
      |> put_in(
        [:frames, :main, :scales, :worth],
        Map.reject(
          %{
            kind: :threshold,
            domain: [fact(:primary, :v, :target)],
            range: {:ramp, :status},
            polarity: polarity
          },
          fn {_key, value} -> value == nil end
        )
      )
    end

    # The fill of each circle by its reading, below and above the target 7.
    defp fills(design) do
      [circles] = group(apply!(design)) |> find("mark mark-circle")
      for c <- circles.children, uniq: true, do: {c.attrs.cy < 60, c.style.fill}
    end

    test "the feed's polarity: lower is better, so beyond the target is bad" do
      good = role(Theme.default(), :good, :css)
      bad = role(Theme.default(), :bad, :css)

      design = worth_design(fact(:primary, :v, :polarity))
      assert Enum.sort(fills(design)) == Enum.sort([{false, good}])

      high = for row <- @primary, do: %{row | v: row.v + 4}

      sources = %{
        sources()
        | primary: Delivery.new(high, schema: Schema.version(@primary_schema))
      }

      {:ok, applied} = Chart.apply(design, sources: sources, describe: &describe/1, size: @size)
      [circles] = group(applied) |> find("mark mark-circle")
      colors = for c <- circles.children, uniq: true, do: c.style.fill
      assert Enum.sort(colors) == Enum.sort([good, bad])
    end

    test "higher is better reverses the ramp, and neutral draws both sides bad" do
      frame = fn polarity -> apply!(worth_design(polarity)).frame end
      scale = fn polarity -> Frame.scale(frame.(polarity), :worth) end

      assert scale.(:lower_is_better).range == [{:ramp, :status, 0.0}, {:ramp, :status, 1.0}]
      assert scale.(:higher_is_better).range == [{:ramp, :status, 1.0}, {:ramp, :status, 0.0}]
      assert scale.(:neutral).range == [{:ramp, :status, 1.0}, {:ramp, :status, 1.0}]
      assert scale.(nil).range == scale.(:lower_is_better).range
    end

    test "on a sequential scale polarity reverses the interpolated ramp" do
      node = fn
        nil -> %{kind: :sequential, domain: [0, 10]}
        polarity -> %{kind: :sequential, domain: [0, 10], polarity: polarity}
      end

      at = fn polarity, v ->
        design = put_in(design(), [:frames, :main, :scales, :heat], node.(polarity))
        applied = apply!(design)
        Visualize.Scale.apply(Frame.scale(applied.frame, :heat), v)
      end

      assert at.(:higher_is_better, 0) == at.(nil, 10)
      assert at.(:higher_is_better, 10) == at.(nil, 0)
    end
  end

  describe "every backend draws the overlays (spec/14 §5.2)" do
    test "SVG, canvas and the binary stream carry the role colors, literal on a canvas" do
      applied = apply!(design())
      bad = role(Theme.default(), :bad, :literal)
      info = role(Theme.default(), :info, :literal)
      warning = role(Theme.default(), :warning, :literal)

      svg = Chart.render(applied)
      assert svg =~ role(Theme.default(), :bad, :css)

      canvas = Chart.render(applied, backend: :canvas)
      for color <- [bad, info, warning], do: assert(canvas =~ "'#{color}'")

      records =
        group(applied, resolve: :literal) |> CanvasBinary.encode_element!() |> Decoder.decode()

      colors = for {:style, style} <- records, c <- [style.stroke, style.fill], c != nil, do: c
      for color <- [bad, info, warning], do: assert(rgba(color) in colors)
    end

    test "a hybrid page draws them on its canvas layer and its SVG layer alike" do
      for render <- [:canvas, :binary, :svg] do
        design =
          update_in(design(), [:marks], fn marks ->
            Enum.map(marks, &Map.put(&1, :render, render))
          end)

        {:ok, %{main: compiled}} =
          Chart.compile(design, sources: sources(), describe: &describe/1, size: @size)

        map = Compiled.render(compiled, sources())
        drawn = if render == :svg, do: map.dynamic_svg, else: map.dynamic
        root = Element.group(drawn)

        [rules, thresholds] = find(root, "mark mark-rule")
        assert length(lines(rules)) == 2, "#{render}"
        assert length(lines(thresholds)) == 2, "#{render}"
        assert [%{children: [_, _]}] = find(root, "mark mark-x_band")

        bad = role(Theme.default(), :bad, if(render == :svg, do: :css, else: :literal))
        assert Enum.any?(lines(rules), &(&1.style.stroke == bad)), "#{render}"
      end
    end
  end

  describe "the theme draws the meaning (D-135)" do
    test "default, dark and color-safe draw each severity in their own tones" do
      colors =
        for theme <- [:default, :dark, :color_safe] do
          applied = apply!(design(%{theme: theme}))
          [rules, _thresholds] = group(applied, resolve: :literal) |> find("mark mark-rule")
          [deploy, outage] = lines(rules)
          resolved = Theme.builtin(theme)
          assert deploy.style.stroke == role(resolved, :info, :literal)
          assert outage.style.stroke == role(resolved, :bad, :literal)
          {theme, outage.style.stroke}
        end

      assert colors |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> length() == 3
    end
  end

  describe "validation and the codec (spec/14 §10.1, §11.2)" do
    test "a map of colors is an ordinal scale's, and polarity orders a ramp" do
      design =
        design()
        |> put_in([:frames, :main, :scales, :severity], %{kind: :linear, range: %{"a" => :bad}})
        |> put_in([:frames, :main, :scales, :worth], %{
          kind: :threshold,
          domain: [5],
          range: [:good, :bad],
          polarity: :higher_is_better
        })

      assert {:error, errors} = Validator.validate(design)
      assert {[:frames, :main, :scales, :severity, :range], {:color_map, :linear}} in errors
      assert {[:frames, :main, :scales, :worth, :polarity], {:polarity, :range}} in errors

      formatted = Enum.map(errors, &Validator.format/1)
      assert Enum.any?(formatted, &(&1 =~ "a map pins categories"))
      assert Enum.any?(formatted, &(&1 =~ "orders a ramp"))
    end

    test "a color in a map is checked as a style's color is, at the category's path" do
      design = put_in(design(), [:frames, :main, :scales, :severity, :range], %{"x" => 7})
      assert {:error, errors} = Validator.validate(design)
      assert {[:frames, :main, :scales, :severity, :range, "x"], {:type, :color}} in errors
    end

    test "polarity on a sequential scale's own ramp is accepted" do
      design =
        put_in(design(), [:frames, :main, :scales, :heat], %{
          kind: :sequential,
          polarity: :higher_is_better
        })

      assert Validator.validate(design) == :ok
    end

    test "a map of colors, polarity and the brush round-trip through JSON" do
      design =
        design(%{interaction: %{brush: :x}})
        |> put_in([:frames, :main, :scales, :severity], %{
          kind: :ordinal,
          range: %{"critical" => :bad, :warn => {:ramp, :status, 0.5}, 3 => "#123456"}
        })
        |> put_in([:frames, :main, :scales, :worth], %{
          kind: :threshold,
          domain: [fact(:primary, :v, :target)],
          range: {:ramp, :status},
          polarity: fact(:primary, :v, :polarity)
        })

      chart = Chart.from_map!(design)
      {:ok, json} = Chart.to_json(chart)

      assert json =~
               ~s("$colors":[[3,"#123456"],[{"$atom":"warn"},{"$ramp":["status",0.5]}],["critical",{"$color":"bad"}]])

      assert {:ok, ^chart} = Chart.from_json(json)
    end
  end

  describe "the design's brush (spec/14 §2.9, spec/10 §6.5)" do
    test "the brush frame carries its kind, its x mapping and its plot area" do
      design = design(%{interaction: %{brush: :x}})

      design =
        put_in(design, [:frames, :main, :margin], %{top: 10, right: 20, bottom: 30, left: 40})

      svg = Chart.render(apply!(design), root: true)

      assert svg =~ ~s(data-vis-brush="x")
      assert svg =~ ~s(data-vis-brush-x="0,100,40,280,300")
      assert svg =~ ~s(data-vis-brush-extent="40,10,280,170")
      refute svg =~ "data-vis-sync"
    end

    test "a time x maps in milliseconds, and the frame named or first by name is brushed" do
      from = ~U[2026-10-11 00:00:00Z]
      to = ~U[2026-10-11 01:00:00Z]

      design = %{
        version: 3,
        interaction: %{brush: :x, frame: :lower},
        frames: %{
          upper: %{
            kind: :cartesian,
            box: [0, 0, 1, 0.5],
            margin: @margin,
            scales: %{x: %{kind: :linear, domain: [0, 1]}}
          },
          lower: %{
            kind: :cartesian,
            box: [0, 0.5, 1, 0.5],
            margin: @margin,
            scales: %{x: %{kind: :time, domain: [from, to]}}
          }
        }
      }

      svg = Chart.render(apply!(design, sources: %{}))
      ms = DateTime.to_unix(from, :millisecond)
      assert svg =~ ~s(data-vis-brush-x="#{ms},#{ms + 3_600_000},0,300,300")
      assert svg =~ ~s(data-vis-brush-extent="0,100,300,200")
      assert length(String.split(svg, "data-vis-brush=")) == 2
    end

    test "a design without a brush writes nothing" do
      refute Chart.render(apply!(design())) =~ "data-vis-brush"
      assert Frame.brush_attrs(apply!(design()).frame) == %{}
    end

    test "the brush frame is cartesian with a linear or time x" do
      polar =
        design(%{interaction: %{brush: :x}})
        |> put_in([:frames, :main, :kind], :polar)

      assert {:error, errors} = Validator.validate(polar)
      assert {[:interaction, :brush], {:brush, :frame_kind, :polar}} in errors

      band =
        design(%{interaction: %{brush: :x}})
        |> put_in([:frames, :main, :scales, :x], %{kind: :band})

      assert {:error, [{[:interaction, :brush], {:brush, :x_scale, :band}} = e]} =
               Validator.validate(band)

      assert Validator.format(e) =~ "only a linear or time x is brushed"
    end
  end

  # A `#rrggbb` as the binary stream's RGBA.
  defp rgba("#" <> hex) do
    <<r::8, g::8, b::8>> = Base.decode16!(hex, case: :lower)
    {r, g, b, 255}
  end
end
