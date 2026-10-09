defmodule Examples.LabelInkTest do
  @moduledoc """
  The gallery's labels on fills read (#486, D-123): every label a chart draws on a fill is
  inked `:contrast`, and holds WCAG AA — 4.5:1 — against the fill of the element it sits
  on, in every palette and in both render modes; a label that does not fit its element is
  dropped or shortened, so none runs over another; and the gallery's themes carry a font
  stack rather than the bare generic family.
  """
  use ExUnit.Case, async: true

  alias Examples.Charts.Design
  alias Examples.ColorPalettes
  alias Visualize.{Chart, Color}
  alias Visualize.IR.Element

  # Every gallery chart that draws a label on the element it labels.
  @on_fills [
    Examples.Charts.PieChart,
    Examples.Charts.TreemapChart,
    Examples.Charts.CirclePacking,
    Examples.Charts.SunburstChart,
    Examples.Charts.ForceGraph
  ]

  # The fit each chart's labels take (D-123): a slice or a node too small for its name
  # draws none; a cell, a packed circle or a sector shortens it.
  @fits %{
    Examples.Charts.PieChart => :hide,
    Examples.Charts.ForceGraph => :hide,
    Examples.Charts.TreemapChart => :truncate,
    Examples.Charts.CirclePacking => :truncate,
    Examples.Charts.SunburstChart => :truncate
  }

  @aa 4.5

  defp tree(module, palette, mode, label_change \\ & &1) do
    {design, sources} = module.design([])

    design =
      Map.update!(design, :marks, fn marks ->
        Enum.map(marks, fn
          %{label: label} = mark when is_map(label) -> %{mark | label: label_change.(label)}
          mark -> mark
        end)
      end)

    {:ok, applied} =
      Chart.apply(design,
        sources: sources,
        theme: ColorPalettes.theme(palette),
        size: Design.size(module, [])
      )

    Chart.generate(applied, resolve: mode)
  end

  # Every labelled mark's {element, its group's style, label} triples, in drawing order.
  defp labelled(%Element{
         children: [
           %Element{style: %{class: "mark-elements"} = group, children: elements},
           %Element{style: %{class: "mark-labels"}, children: labels}
         ]
       }) do
    texts = Enum.filter(labels, &(&1.type == :text))
    assert length(elements) == length(texts)
    Enum.zip_with(elements, texts, &{&1, group, &2})
  end

  defp labelled(%Element{children: children}), do: Enum.flat_map(children, &labelled/1)

  # Every text of the labels' groups, however many of its elements' labels are drawn.
  defp texts(%Element{style: %{class: "mark-labels"}, children: labels}),
    do: Enum.filter(labels, &(&1.type == :text))

  defp texts(%Element{children: children}), do: Enum.flat_map(children, &texts/1)

  # The literal a fill is drawn in, composited over the background by its opacities.
  defp under(element, group, background) do
    fill = Map.get(element.style, :fill, Map.get(group, :fill))
    colour = fill |> literal() |> Color.parse()
    assert colour, "an unreadable fill #{inspect(fill)}"

    alpha =
      Map.get(element.style, :fill_opacity, Map.get(group, :fill_opacity, 1)) *
        Map.get(element.style, :opacity, Map.get(group, :opacity, 1))

    Color.interpolate_rgb(Color.parse(background), colour, alpha)
  end

  defp literal("var(" <> rest) do
    [_name, fallback] = String.split(rest, ",", parts: 2)
    fallback |> String.trim() |> String.replace_suffix(")", "")
  end

  defp literal(colour) when is_binary(colour), do: colour

  test "every gallery chart that labels a fill inks its labels by contrast, with a fit" do
    for module <- @on_fills do
      {design, _sources} = module.design([])
      [label] = for %{label: label} when is_map(label) <- design.marks, do: label
      assert label.fit == Map.fetch!(@fits, module), inspect(module)
      assert Map.fetch!(design.styles, label.style).fill == :contrast, inspect(module)
    end
  end

  test "every label on a fill holds 4.5:1 against its element, in every palette and both modes" do
    for module <- @on_fills, palette <- ColorPalettes.list_palettes(), mode <- [:css, :literal] do
      theme = ColorPalettes.theme(palette)
      # Every element labelled — `fit: :none` — so no label is excused by being hidden.
      all = module |> tree(palette, mode, &Map.put(&1, :fit, :none)) |> labelled()
      assert all != [], "#{inspect(module)}: no labels"

      for {element, group, text} <- all do
        under = under(element, group, theme.background)
        ink = Color.parse(text.style.fill)
        ratio = Color.contrast(ink, under)

        assert ratio >= @aa,
               "#{inspect(module)} #{palette} #{mode}: #{text.content} in #{text.style.fill} " <>
                 "on #{Color.to_hex(under)} is #{Float.round(ratio, 2)}:1"
      end

      # The gallery's own drawing, fitted, draws a subset of those, inked alike.
      inks = MapSet.new(all, fn {_e, _g, text} -> {text.content, text.style.fill} end)
      shown = module |> tree(palette, mode) |> texts()

      for text <- shown, not String.ends_with?(text.content, "…") do
        assert {text.content, text.style.fill} in inks, "#{inspect(module)} #{palette}"
      end
    end
  end

  test "the pale palette's labels are dark: the sunrise treemap is legible" do
    theme = ColorPalettes.theme(:sunrise)

    # The palette's own dark text, or black where a deep orange holds neither slot to AA.
    inks =
      for text <- Examples.Charts.TreemapChart |> tree(:sunrise, :css) |> texts(),
          do: text.style.fill

    assert inks != [] and Enum.all?(inks, &(&1 in [theme.text, "#000000"]))
    assert theme.text in inks
    refute theme.background in inks
  end

  # A label's box by the estimate `fit` makes (spec/14 §5.5): 0.6 em a character, one em
  # tall, about its anchor.
  defp box(%Element{attrs: %{x: x, y: y}, content: content, style: style}) do
    size = Map.get(style, :font_size, 12)
    w = 0.6 * size * String.length(content)

    left =
      case Map.get(style, :text_anchor, :start) do
        :middle -> x - w / 2
        :end -> x - w
        _start -> x
      end

    {left, y - size / 2, w, size}
  end

  defp overlap?({x1, y1, w1, h1}, {x2, y2, w2, h2}),
    do: x1 < x2 + w2 and x2 < x1 + w1 and y1 < y2 + h2 and y2 < y1 + h1

  test "no two labels drawn on fills overlap: the pie's small slices drop theirs" do
    for module <- @on_fills do
      boxes =
        for text <- module |> tree(:default, :literal) |> texts(), do: box(text)

      for {a, i} <- Enum.with_index(boxes), {b, j} <- Enum.with_index(boxes), i < j do
        refute overlap?(a, b), "#{inspect(module)}: #{inspect(a)} over #{inspect(b)}"
      end
    end

    names =
      for text <- Examples.Charts.PieChart |> tree(:default, :literal) |> texts(),
          do: text.content

    assert "Chrome" in names and "Safari" in names
    refute "Firefox" in names or "Opera" in names
  end

  test "the gallery's themes carry a font stack, and it reaches the SVG" do
    for palette <- ColorPalettes.list_palettes() do
      assert ColorPalettes.theme(palette).font_family =~ ~r/^Inter, system-ui, .*sans-serif$/
    end

    assert Examples.Charts.PieChart.render([]) =~
             "font-family=\"var(--vis-font-family, Inter, system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif)\""
  end
end
