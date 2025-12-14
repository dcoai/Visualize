defmodule Examples.Charts.ChordDiagram do
  @moduledoc "Chord diagram showing relationships between groups"

  alias Visualize.Layout.Chord
  alias Visualize.SVG.Element
  alias Examples.ColorPalettes
  @group_names ["Asia", "Europe", "Americas", "Africa", "Oceania"]

  # Migration flow matrix (rows = from, columns = to)
  @matrix [
    [11975,  5871, 8916, 2868, 1200],
    [ 1951, 10048, 2060, 6171,  950],
    [ 8010, 16145, 8090, 8045, 1500],
    [ 1013,   990,  940, 6907,  800],
    [  500,   800,  600,  400, 2000]
  ]

  def title, do: "Chord Diagram"
  def description, do: "Inter-regional migration flows"

  def render(opts \\ []) do
    width = opts[:width] || 500
    height = opts[:height] || 500
    animation_tick = opts[:animation_tick]

    matrix = if animation_tick do
      generate_animated_matrix(animation_tick)
    else
      opts[:matrix] || @matrix
    end

    palette = opts[:palette] || :default
    colors = ColorPalettes.colors(palette)

    outer_radius = min(width, height) / 2 - 40
    inner_radius = outer_radius - 20

    # Generate chord layout
    chord = Chord.new()
      |> Chord.pad_angle(0.05)

    result = Chord.generate(chord, matrix)

    # Draw group arcs
    group_arcs = Enum.map(result.groups, fn group ->
      color = Enum.at(colors, rem(group.index, length(colors)))
      path_d = Chord.arc_path(group, inner_radius, outer_radius)

      Element.g(%{})
      |> Element.append(
        Element.path(%{
          d: path_d,
          fill: color,
          stroke: "white",
          stroke_width: 1
        })
      )
      |> Element.append(
        # Add label
        create_group_label(group, outer_radius + 10)
      )
    end)

    # Draw chords (ribbons)
    ribbons = Enum.map(result.chords, fn chord_data ->
      source_color = Enum.at(colors, rem(chord_data.source.index, length(colors)))
      path_d = Chord.ribbon_path(chord_data, inner_radius)

      Element.path(%{
        d: path_d,
        fill: source_color,
        fill_opacity: 0.6,
        stroke: source_color,
        stroke_width: 0.5
      })
    end)

    # Compose SVG
    chart_group = Element.g(%{transform: "translate(#{width / 2},#{height / 2})"})
      |> Element.append(ribbons)
      |> Element.append(group_arcs)

    Element.svg(%{width: width, height: height, viewBox: "0 0 #{width} #{height}"})
    |> Element.append(chart_group)
  end

  defp create_group_label(group, radius) do
    mid_angle = (group.start_angle + group.end_angle) / 2
    x = radius * :math.sin(mid_angle)
    y = -radius * :math.cos(mid_angle)

    rotation = mid_angle * 180 / :math.pi()
    text_anchor = if mid_angle > :math.pi(), do: "end", else: "start"
    rotation = if text_anchor == "end", do: rotation - 180, else: rotation

    name = Enum.at(@group_names, group.index, "Group #{group.index}")

    Element.text(%{
      x: x,
      y: y,
      text_anchor: text_anchor,
      font_size: 11,
      fill: "#333",
      transform: "rotate(#{rotation},#{x},#{y})"
    })
    |> Element.content(name)
  end

  # Animation: vary migration flow values
  defp generate_animated_matrix(tick) do
    phase = tick * 0.05

    # Base matrix with animated variations
    [
      [animate_val(11975, phase, 0, 2000), animate_val(5871, phase, 0.5, 1200), animate_val(8916, phase, 1.0, 1800), animate_val(2868, phase, 1.5, 700), animate_val(1200, phase, 2.0, 300)],
      [animate_val(1951, phase, 2.5, 500), animate_val(10048, phase, 3.0, 2000), animate_val(2060, phase, 3.5, 500), animate_val(6171, phase, 4.0, 1400), animate_val(950, phase, 4.5, 250)],
      [animate_val(8010, phase, 5.0, 1600), animate_val(16145, phase, 5.5, 3000), animate_val(8090, phase, 6.0, 1600), animate_val(8045, phase, 6.5, 1600), animate_val(1500, phase, 7.0, 350)],
      [animate_val(1013, phase, 7.5, 300), animate_val(990, phase, 8.0, 250), animate_val(940, phase, 8.5, 250), animate_val(6907, phase, 9.0, 1400), animate_val(800, phase, 9.5, 200)],
      [animate_val(500, phase, 10.0, 150), animate_val(800, phase, 10.5, 200), animate_val(600, phase, 11.0, 150), animate_val(400, phase, 11.5, 100), animate_val(2000, phase, 12.0, 500)]
    ]
  end

  defp animate_val(base, phase, offset, amplitude) do
    trunc(max(100, base + :math.sin(phase + offset) * amplitude))
  end

  def sample_code do
    ~S"""
    alias Visualize.Layout.Chord

    matrix = [
      [11975, 5871, 8916, 2868],
      [ 1951, 10048, 2060, 6171],
      # ... flow from group i to group j
    ]

    chord = Chord.new()
      |> Chord.pad_angle(0.05)

    result = Chord.generate(chord, matrix)

    # result.groups - arcs for each group
    # result.chords - ribbons connecting groups
    # Chord.arc_path(group, inner_r, outer_r)
    # Chord.ribbon_path(chord, radius)
    """
  end
end
