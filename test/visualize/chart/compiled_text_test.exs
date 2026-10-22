defmodule Visualize.Chart.CompiledTextTest do
  @moduledoc """
  A text draws the same through the compiled chart as through the frame (spec/14 §7.1,
  §12.4, #776, #926): every text the frame draws — a `:text` mark's, a mark's inline
  label, a frame label at each kind of anchor, a legend's title, a facet panel's title —
  with a newline, its own `line_height`, a `vertical_align` and a `text_angle`, through
  the one-string form, a board cell's step and the hybrid chart map's SVG layers with the
  labeled mark on every render target.
  """
  use ExUnit.Case, async: true

  alias Visualize.Backend.Canvas
  alias Visualize.Chart
  alias Visualize.Chart.Compiled
  alias Visualize.IR.Element
  alias Visualize.Render

  @size {300, 200}

  @styles %{
    tall: %{line_height: 2, vertical_align: :top, text_angle: -30},
    low: %{line_height: 1.6, vertical_align: :bottom, text_anchor: :end},
    mid: %{line_height: 1.4, vertical_align: :middle, text_angle: 15},
    dot: %{fill: {:field, :g}}
  }

  @rows [
    %{t: 1, v: 2, name: "first\nrow", g: "a"},
    %{t: 3, v: 4, name: "one line", g: "b"}
  ]

  # Every text feature on every kind of text a cartesian frame draws. `domain` is the
  # position scales' — fixed, so the labels are a static region, or inferred, so they are
  # dynamic and drawn per tick.
  defp cartesian(domain, render) do
    %{
      version: 2,
      sources: %{primary: %{fields: [:t, :v, :name, :g]}},
      styles: @styles,
      frames: %{
        main: %{
          kind: :cartesian,
          scales: %{
            x: %{kind: :linear, domain: domain},
            y: %{kind: :linear, domain: domain},
            color: %{kind: :ordinal}
          },
          axes: [%{scale: :x, side: :bottom}, %{scale: :y, side: :left}],
          legend: %{scale: :color, title: "Group\nby row"}
        }
      },
      marks: [
        %{type: :text, data: :primary, channels: %{x: :t, y: :v, value: :name}, style: :mid},
        %{
          type: :circle,
          data: :primary,
          channels: %{x: :t, y: :v},
          style: :dot,
          label: %{text: "at\n\#{field(:v)}", anchor: :top, style: :low},
          render: render
        }
      ],
      labels: [
        %{anchor: :title, text: "Two\nlines"},
        %{anchor: {:frame, :top_left}, text: "Summed\nsampled", style: :tall},
        %{anchor: {:frame, :bottom_right}, text: "low\nright", style: :low},
        %{anchor: {:axis, :y}, text: "load\n(%)", style: :mid},
        %{anchor: {:data, [2, 3]}, text: "here\nand there", style: :tall}
      ]
    }
  end

  defp facet do
    %{
      version: 2,
      sources: %{primary: %{fields: [:t, :v, :name, :g]}},
      styles: @styles,
      frames: %{
        main: %{
          kind: :facet,
          facet: %{by: :name, columns: 2},
          scales: %{x: %{kind: :linear, domain: [0, 5]}, y: %{kind: :linear, domain: [0, 5]}},
          axes: [%{scale: :x, side: :bottom}, %{scale: :y, side: :left}]
        }
      },
      marks: [%{type: :text, data: :primary, channels: %{x: :t, y: :v, value: :g}}],
      labels: [%{anchor: {:frame, :top_left}, text: "per\npanel", style: :tall}]
    }
  end

  defp polar do
    %{
      version: 2,
      sources: %{primary: %{fields: [:t, :v, :name, :g]}},
      styles: @styles,
      frames: %{
        main: %{
          kind: :polar,
          scales: %{angle: %{kind: :radial, domain: [0, 360]}, r: %{kind: :linear}},
          axes: [%{scale: :r, side: :top, ticks: 3}]
        }
      },
      marks: [
        %{
          type: :rose,
          data: :primary,
          channels: %{angle: :t, value: :v},
          label: %{text: "r\n\#{field(:v)}", style: :mid}
        }
      ],
      labels: [%{anchor: {:data, [90, 3]}, text: "east\nside", style: :low}]
    }
  end

  defp applied!(design) do
    {:ok, applied} = Chart.apply(design, sources: %{primary: @rows}, size: @size)
    applied
  end

  defp compiled!(applied) do
    {:ok, %{"main" => compiled}} = Chart.compile(applied)
    compiled
  end

  # The texts of a tree in drawing order, each as the SVG it writes.
  defp texts(%Element{type: :text} = text), do: [Render.to_string(text, backend: :svg)]
  defp texts(%Element{children: children}), do: Enum.flat_map(children, &texts/1)
  defp texts(elements) when is_list(elements), do: Enum.flat_map(elements, &texts/1)

  defp all_svg_designs do
    [
      {"cartesian, fixed", cartesian([0, 5], :svg)},
      {"cartesian, inferred", cartesian(:auto, :svg)},
      {"facet", facet()},
      {"polar", polar()}
    ]
  end

  test "the designs draw every text feature: lines, a line height, an alignment and an angle" do
    for {name, design} <- all_svg_designs() do
      svg = design |> applied!() |> Chart.render()
      assert svg =~ ~r/<tspan dy="[0-9.]+em" x=/, name
    end

    svg = [0, 5] |> cartesian(:svg) |> applied!() |> Chart.render()
    # The legend's title, a frame label's own line height, an alignment and an angle.
    assert svg =~ ~r/<tspan[^>]*>Group<\/tspan><tspan dy="1.2em"[^>]*>by row<\/tspan>/
    assert svg =~ ~r/dy="0.71em"[^>]*transform="rotate\(-30,4,4\)"[^>]*><tspan x="4">Summed/
    assert svg =~ ~r/<tspan dy="2em" x="4">sampled<\/tspan>/
    assert svg =~ ~r/<tspan dy="1.6em"[^>]*>right<\/tspan>/
    assert svg =~ ~r/<tspan dy="1.6em"[^>]*>2<\/tspan>/
    assert svg =~ ~r/<tspan dy="1.4em"[^>]*>row<\/tspan>/
  end

  test "the one-string form is the frame's, text and all" do
    for {name, design} <- all_svg_designs() do
      applied = applied!(design)
      compiled = compiled!(applied)
      assert Compiled.svg(compiled, applied.sources) == Chart.render(applied), name
    end
  end

  test "a board cell's step draws the one-string form" do
    for {name, design} <- all_svg_designs() do
      applied = applied!(design)
      compiled = compiled!(applied)
      {group, _compiled} = Compiled.step(compiled, applied.sources)
      assert Render.to_string(group, backend: :svg) == Chart.render(applied), name
    end
  end

  test "a canvas draws the compiled step's texts as the frame's, one fillText per line" do
    for {name, design} <- all_svg_designs() do
      applied = applied!(design)
      {group, _compiled} = applied |> compiled!() |> Compiled.step(applied.sources)
      frame = Chart.generate(applied)

      drawn = Canvas.render_element(group, format: :commands)
      assert drawn == Canvas.render_element(frame, format: :commands), name

      lines = for {:fillText, [line | _]} <- drawn, do: line
      refute Enum.any?(lines, &String.contains?(&1, "\n")), name
    end

    applied = applied!(cartesian([0, 5], :svg))
    {group, _compiled} = applied |> compiled!() |> Compiled.step(applied.sources)

    lines =
      for {:fillText, [line | _]} <- Canvas.render_element(group, format: :commands), do: line

    assert ["Summed", "sampled"] -- lines == []
    assert ["Group", "by row", "load", "(%)", "first", "row", "at", "2"] -- lines == []
  end

  test "the hybrid map's SVG layers draw the frame's texts, the labeled mark on every target" do
    for domain <- [[0, 5], :auto], render <- [:svg, :canvas, :binary] do
      applied = applied!(cartesian(domain, render))
      compiled = compiled!(applied)
      map = Compiled.render(compiled, applied.sources)

      # The static layer and the tick's: together every text the frame draws, in its order
      # within each layer, since text stays in the SVG layer whatever the target (§12.3).
      drawn = texts(map.static) ++ texts(map.dynamic_svg)
      frame = texts(Chart.generate(applied))

      assert Enum.sort(drawn) == Enum.sort(frame), "#{inspect(domain)}, #{render}"
      assert Enum.any?(drawn, &(&1 =~ "<tspan")), "#{inspect(domain)}, #{render}"

      # The canvas layer draws no text (§12.3).
      assert texts(map.dynamic || []) == [], "#{inspect(domain)}, #{render}"
    end
  end
end
