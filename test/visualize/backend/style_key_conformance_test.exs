defmodule Visualize.Backend.StyleKeyConformanceTest do
  @moduledoc """
  Every style key the schema lists, on SVG, the `:json` canvas and the binary canvas
  (spec/09 §4.8, #788, D-208): the recurrence guard that keeps a style key from shipping
  SVG-only.

  The keys are walked from `Visualize.Chart.Schema.describe(:style)`, every leaf of every
  part, and each must have a row in spec/09 §4.8 — its binary records, or **not drawn** and
  why — and a sample here. One design — a `:rect`, a `:line`, a `:symbol` and a `:text`
  mark, all styled by the one style the key is set in — is drawn with the key and without
  it. A sample must change the SVG, or it tests nothing. A drawn key must change the binary
  stream, and the `:json` commands replayed on `CanvasChart` and the binary stream replayed
  on `CanvasBinaryChart` must make the same draws, outside the texts, in the same state; a
  key marked **not drawn** must leave the binary stream as it was, so a deviation that no
  longer holds is found too.
  """
  use ExUnit.Case, async: true

  alias Visualize.Backend.{Canvas, CanvasBinary}
  alias Visualize.CanvasEncoders
  alias Visualize.Chart
  alias Visualize.Chart.{Frame, Schema}

  @size {240, 200}

  @rows [
    %{x: 1, y: 2, x1: 3, y1: 6, t: "a"},
    %{x: 4, y: 5, x1: 6, y1: 9, t: "b"},
    %{x: 7, y: 3, x1: 9, y1: 7, t: "c\nd"}
  ]

  # The style every sample is laid over: a solid fill and a stroke, so a key that changes
  # either has something to change.
  @base %{fill: %{type: :solid, color: "#336699"}, stroke: %{color: "#cc0000", width: 2}}

  defp stops(second \\ %{}),
    do: [%{at: 0, color: "#ffffff"}, Map.merge(%{at: 1, color: "#000000"}, second)]

  defp linear(extra \\ %{}), do: Map.merge(%{type: :linear, stops: stops()}, extra)
  defp radial(extra \\ %{}), do: Map.merge(%{type: :radial, stops: stops()}, extra)
  defp hatch(extra \\ %{}), do: Map.merge(%{type: :hatch, color: "#2ca02c"}, extra)

  # For each key, the style without it and with it, each laid over the base: the key the
  # only difference between the two.
  defp samples do
    paint = fn part ->
      %{
        "#{part}.type" => {%{}, %{part => %{type: :none}}},
        "#{part}.color" => {%{}, %{part => %{color: "#2ca02c"}}},
        "#{part}.opacity" => {%{}, %{part => %{opacity: 0.4}}},
        "#{part}.stops.at" =>
          {%{part => linear()}, %{part => linear(%{stops: stops(%{at: 0.6})})}},
        "#{part}.stops.color" =>
          {%{part => linear()}, %{part => linear(%{stops: stops(%{color: "#ff0000"})})}},
        "#{part}.stops.opacity" =>
          {%{part => linear()}, %{part => linear(%{stops: stops(%{opacity: 0.5})})}},
        "#{part}.angle" => {%{part => linear()}, %{part => linear(%{angle: 90})}},
        "#{part}.center" => {%{part => radial()}, %{part => radial(%{center: [0.3, 0.2]})}},
        "#{part}.radius" => {%{part => radial()}, %{part => radial(%{radius: 0.25})}},
        "#{part}.name" =>
          {%{part => %{type: :paint, name: "p1"}}, %{part => %{type: :paint, name: "p2"}}}
      }
    end

    shadow = %{effect: %{type: :shadow}}

    Map.merge(paint.(:fill), paint.(:stroke))
    |> Map.merge(%{
      "fill.pattern" => {%{fill: hatch()}, %{fill: hatch(%{pattern: :dots})}},
      "fill.spacing" => {%{fill: hatch()}, %{fill: hatch(%{spacing: 11})}},
      "fill.width" => {%{fill: hatch()}, %{fill: hatch(%{width: 3})}},
      "fill.background" => {%{fill: hatch()}, %{fill: hatch(%{background: "#ffeeaa"})}},
      "stroke.width" => {%{}, %{stroke: %{width: 5}}},
      "stroke.dash" => {%{}, %{stroke: %{dash: [4, 2]}}},
      "stroke.join" => {%{}, %{stroke: %{join: :bevel}}},
      "stroke.cap" => {%{}, %{stroke: %{cap: :round}}},
      "stroke.placement" => {%{}, %{stroke: %{placement: :inside}}},
      "stroke.non_scaling" => {%{}, %{stroke: %{non_scaling: true}}},
      "font.family" => {%{}, %{font: %{family: "serif"}}},
      "font.size" => {%{}, %{font: %{size: 21}}},
      "font.weight" => {%{}, %{font: %{weight: :bold}}},
      "font.style" => {%{}, %{font: %{style: :italic}}},
      "font.line_height" => {%{}, %{font: %{line_height: 2.5}}},
      "text.anchor" => {%{}, %{text: %{anchor: :end}}},
      "text.baseline" => {%{}, %{text: %{baseline: :top}}},
      "text.offset" => {%{}, %{text: %{offset: [5, 7]}}},
      "text.angle" => {%{}, %{text: %{angle: 30}}},
      "effect.type" => {%{}, shadow},
      "effect.radius" => {shadow, %{effect: %{type: :shadow, radius: 7}}},
      "effect.offset" => {shadow, %{effect: %{type: :shadow, offset: [4, 1]}}},
      "effect.color" => {shadow, %{effect: %{type: :shadow, color: "#ff0000"}}},
      "opacity" => {%{}, %{opacity: 0.5}},
      "blend" => {%{}, %{blend: :multiply}},
      "marker.shape" => {%{}, %{marker: %{shape: :square}}},
      "marker.size" => {%{}, %{marker: %{size: 200}}},
      "curve.type" => {%{}, %{curve: %{type: :step}}},
      "curve.tension" =>
        {%{curve: %{type: :cardinal}}, %{curve: %{type: :cardinal, tension: 0.6}}},
      "curve.alpha" =>
        {%{curve: %{type: :catmull_rom}}, %{curve: %{type: :catmull_rom, alpha: 1}}},
      "class" => {%{}, %{class: "highlight"}}
    })
    |> Map.merge(motion_samples())
  end

  # The motion parts: each key changed under a part that already moves, so the key is the
  # one difference; a part's first key from nothing.
  defp motion_samples do
    moving = %{duration: 300}
    animated = %{name: :pulse, duration: 1000}

    part = fn name, base, changes ->
      Map.new(changes, fn {key, value} ->
        {"#{name}.#{key}", {%{name => base}, %{name => Map.put(base, key, value)}}}
      end)
    end

    per_property =
      for property <- [:fill, :stroke, :opacity], into: %{} do
        {"transition.#{property}.duration",
         {%{transition: %{property => %{duration: 100}}},
          %{transition: %{property => %{duration: 400}}}}}
      end

    per_property_easing =
      for property <- [:fill, :stroke, :opacity], into: %{} do
        {"transition.#{property}.easing",
         {%{transition: %{property => %{duration: 100}}},
          %{transition: %{property => %{duration: 100, easing: :bounce_out}}}}}
      end

    %{}
    |> Map.merge(part.(:transition, moving, duration: 600, easing: :bounce_out))
    |> Map.merge(per_property)
    |> Map.merge(per_property_easing)
    |> Map.merge(
      part.(:animation, animated,
        name: :blink,
        duration: 2000,
        easing: :bounce_out,
        iterations: 3,
        delay: 250
      )
    )
    |> Map.merge(part.(:enter, %{name: :fade}, name: :grow, duration: 900, easing: :bounce_out))
    |> Map.merge(part.(:exit, %{name: :fade}, name: :shrink, duration: 900, easing: :bounce_out))
  end

  # -- the schema's style keys ----------------------------------------------------------

  # Every leaf of the style kind's parts, a node's keys under its name; `extends` names
  # another style and is no key of its own.
  defp schema_keys, do: walk(:style, [], [:style])

  defp walk(kind, prefix, seen) do
    for spec <- Schema.describe(kind), spec.key != :extends, reduce: [] do
      acc ->
        path = prefix ++ [spec.key]

        case nodes(spec.type) do
          [] -> acc ++ [Enum.join(path, ".")]
          kinds -> acc ++ Enum.flat_map(kinds -- seen, &walk(&1, path, [&1 | seen]))
        end
    end
  end

  defp nodes({:node, kind}), do: [kind]
  defp nodes({:list, type}), do: nodes(type)
  defp nodes({:one_of, types}), do: Enum.flat_map(types, &nodes/1)
  defp nodes(_type), do: []

  # -- spec/09 §4.8 ---------------------------------------------------------------------

  # The table's rows, as each key or wildcard it names and whether it is drawn on the binary
  # stream and on the SVG-element stream (D-211).
  defp table do
    [_, section] = String.split(File.read!("spec/09-rendering-backends.md"), "### 4.8 ", parts: 2)
    [section | _] = String.split(section, ~r/^##+ /m, parts: 2)
    drawn? = &(not String.starts_with?(&1, "**not drawn**"))

    for [_, keys, binary, svg] <-
          Regex.scan(~r/^\| ([^|]*`[^|]*) \| ([^|]+) \| ([^|]+) \|$/m, section),
        [_, key] <- Regex.scan(~r/`([a-z_.*]+)`/, keys),
        into: %{},
        do: {key, {drawn?.(binary), drawn?.(svg)}}
  end

  defp row(table, key) do
    Map.get_lazy(table, key, fn ->
      Enum.find_value(table, fn {pattern, drawn} ->
        String.ends_with?(pattern, ".*") and
          String.starts_with?(key, String.trim_trailing(pattern, "*")) and {:ok, drawn}
      end)
      |> case do
        {:ok, drawn} -> drawn
        _ -> nil
      end
    end)
  end

  # -- the design --------------------------------------------------------------------------

  defp design(style) do
    %{
      version: 3,
      sources: %{s: %{fields: [:x, :y, :x1, :y1, :t]}},
      defs: %{
        "p1" => %{type: :linear, color: ["#d62728", "#1f77b4"]},
        "p2" => %{type: :radial, color: ["#ffbf00", "#2ca02c"]}
      },
      styles: %{"s" => style},
      frames: %{
        main: %{
          kind: :cartesian,
          scales: %{x: %{kind: :linear, domain: [0, 10]}, y: %{kind: :linear, domain: [0, 10]}}
        }
      },
      marks: [
        %{type: :rect, data: :s, channels: %{x0: :x, x1: :x1, y0: :y, y1: :y1}, style: "s"},
        %{type: :line, data: :s, channels: %{x: :x, y: :y}, style: "s"},
        %{type: :symbol, data: :s, channels: %{x: :x1, y: :y1}, style: "s"},
        %{type: :text, data: :s, channels: %{x: :x, y: :y1, value: :t}, style: "s"}
      ],
      # A label in the style too, of one line: a label's placement reads `text.baseline`,
      # `offset` and `angle` from its style (spec/14 §6.3), a text mark's from its label's.
      # The text mark's two-line value is what shows the line height (D-210).
      labels: [%{anchor: :title, text: ["one"], style: "s", frame: :main}]
    }
  end

  defp tree(style, mode) do
    {:ok, chart} = Chart.from_map(design(deep_merge(@base, style)))
    frame = Frame.new(chart, sources: %{s: @rows}, size: @size)
    Frame.generate(frame, sources: %{s: @rows}, resolve: mode)
  end

  defp deep_merge(a, b),
    do:
      Map.merge(a, b, fn _k, x, y -> if is_map(x) and is_map(y), do: deep_merge(x, y), else: y end)

  # -- the draws -------------------------------------------------------------------------

  # The state a draw is made in that its kind reads: a fill its fill style, a stroke its
  # stroke and line; both the transform, the alpha, the compositing, the shadow, the filter
  # and the clips. A text's draws are left out: the binary stream has no text (spec/09 §4.4).
  @common ~w(m globalAlpha globalCompositeOperation shadowColor shadowBlur shadowOffsetX
             shadowOffsetY filter clips)
  @read %{
    "fill" => ["fillStyle" | @common],
    "stroke" => ~w(strokeStyle lineWidth lineCap lineJoin lineDash) ++ @common
  }

  defp drawn(draws) do
    for %{"name" => name} = draw <- draws, Map.has_key?(@read, name) do
      {name, draw |> Map.take(@read[name]) |> Map.new(fn {k, v} -> {k, normal(v)} end)}
    end
  end

  # A color as its RGBA bytes, whatever its syntax; a gradient as its constructor, its
  # arguments and its stops; a pattern as its transform, its tile being a canvas of its own.
  defp normal(%{"gradient" => kind, "args" => args, "stops" => stops}),
    do: {kind, args, Enum.map(stops, fn [at, color] -> {at, normal(color)} end)}

  defp normal(%{"pattern" => _tile, "transform" => transform}), do: {:pattern, transform}

  defp normal(string) when is_binary(string) do
    case Visualize.Color.parse(string) do
      %Visualize.Color{} = color ->
        {r, g, b, a} = Visualize.Color.to_rgba(color)
        {r, g, b, round(a * 255)}

      nil ->
        string
    end
  end

  defp normal(other), do: other

  # Two draws' states alike, every number to within the f32 the binary stream carries.
  defp alike?(a, b) when is_number(a) and is_number(b), do: abs(a - b) <= 1.0e-2 * max(1, abs(a))

  defp alike?(a, b) when is_list(a) and is_list(b),
    do: length(a) == length(b) and Enum.all?(Enum.zip(a, b), fn {x, y} -> alike?(x, y) end)

  defp alike?(a, b) when is_tuple(a) and is_tuple(b),
    do: alike?(Tuple.to_list(a), Tuple.to_list(b))

  defp alike?(%{} = a, %{} = b),
    do: Map.keys(a) == Map.keys(b) and Enum.all?(a, fn {k, v} -> alike?(v, Map.fetch!(b, k)) end)

  defp alike?(a, b), do: a == b

  defp json(tree), do: IO.iodata_to_binary(Canvas.render_element(tree, format: :json))
  defp binary(tree), do: CanvasBinary.encode_element!(tree)
  defp svg_elements(tree), do: CanvasEncoders.svg_elements(tree)

  # A draw's color alphas times its global alpha, which it then leaves out: the SVG-element
  # encoder folds an element's opacities into its colors (spec/09 §4.7), the IR encoders set
  # the global alpha around the draw, and the two paint the same.
  defp folded(draws) do
    for {name, state} <- draws do
      {alpha, state} = Map.pop(state, "globalAlpha", 1)

      {name,
       Map.new(state, fn
         {k, {r, g, b, a}} when k in ["fillStyle", "strokeStyle"] ->
           {k, {r, g, b, a / 255 * alpha}}

         other ->
           other
       end)}
    end
  end

  describe "every style key the schema lists (spec/09 §4.8)" do
    test "has a row in spec/09 §4.8 and a sample here" do
      table = table()
      samples = samples()

      for key <- schema_keys() do
        assert row(table, key) != nil, "spec/09 §4.8 has no row for the style key #{key}"
        assert Map.has_key?(samples, key), "no sample for the style key #{key}"
      end

      assert Enum.sort(Map.keys(samples)) == Enum.sort(schema_keys()),
             "a sample names a key the schema does not list"
    end

    test "a defaults node takes the style's parts, so walking the style covers both" do
      parts = fn kind -> for spec <- Schema.describe(kind), do: spec.key end
      assert parts.(:kind_defaults) -- parts.(:style) == []
    end

    @tag :js
    test "draws on the binary canvas as on the :json canvas, or spec/09 says why not" do
      table = table()
      keys = schema_keys()

      cases =
        for key <- keys do
          {without, with} = Map.fetch!(samples(), key)

          assert Visualize.Render.to_string(tree(with, :css)) !=
                   Visualize.Render.to_string(tree(without, :css)),
                 "the sample of #{key} does not change the SVG"

          {key, row(table, key), tree(without, :literal), tree(with, :literal)}
        end

      for {key, {drawn, _on_svg}, without, with} <- cases do
        if drawn do
          assert binary(with) != binary(without),
                 "SVG draws #{key}; the binary stream does not carry it (spec/09 §4.8)"

          assert json(with) != json(without), "SVG draws #{key}; the :json canvas does not"
        else
          assert binary(with) == binary(without),
                 "spec/09 §4.8 says #{key} is not drawn on the binary canvas, but the stream carries it"
        end
      end

      # The SVG-element encoder, given the markup `from_ir/1` makes of the tree (D-211).
      for {key, {_drawn, on_svg}, without, with} <- cases do
        if on_svg do
          assert svg_elements(with) != svg_elements(without),
                 "SVG draws #{key}; the SVG-element stream does not carry it (spec/09 §4.8)"
        else
          assert svg_elements(with) == svg_elements(without),
                 "spec/09 §4.8 says #{key} is not drawn on the SVG-element stream, but it carries it"
        end
      end

      base = tree(%{}, :literal)
      trees = [base | for({_key, {true, _}, _without, with} <- cases, do: with)]
      names = ["the base style" | for({key, {true, _}, _, _} <- cases, do: key)]
      on_json = CanvasEncoders.draws(Canvas, trees)
      on_binary = CanvasEncoders.draws(CanvasBinary, trees)

      for {name, json_draws, binary_draws} <- Enum.zip([names, on_json, on_binary]) do
        {j, b} = {drawn(json_draws), drawn(binary_draws)}
        assert j != [], "#{name}: the :json canvas draws nothing"

        assert alike?(j, b),
               "#{name}: the binary canvas draws otherwise than the :json canvas\n" <>
                 "json:   #{inspect(j, limit: :infinity)}\nbinary: #{inspect(b, limit: :infinity)}"
      end

      trees = [base | for({_key, {_, true}, _without, with} <- cases, do: with)]
      names = ["the base style" | for({key, {_, true}, _, _} <- cases, do: key)]
      on_json = CanvasEncoders.draws(Canvas, trees)
      on_svg = CanvasEncoders.draws(CanvasBinary.SVG, trees)

      for {name, json_draws, svg_draws} <- Enum.zip([names, on_json, on_svg]) do
        {j, s} = {folded(drawn(json_draws)), folded(drawn(svg_draws))}

        assert alike?(j, s),
               "#{name}: the SVG-element stream draws otherwise than the :json canvas\n" <>
                 "json: #{inspect(j, limit: :infinity)}\nsvg:  #{inspect(s, limit: :infinity)}"
      end
    end
  end
end
