defmodule Visualize.Layout.Chord do
  @moduledoc """
  Chord diagram layout for visualizing relationships between groups.

  Chord diagrams display flows or connections between entities arranged
  in a circle. The outer arcs represent groups, and the chords connecting
  them represent relationships.

  ## Examples

      # Matrix where matrix[i][j] is the flow from group i to group j
      matrix = [
        [11975,  5871, 8916, 2868],
        [ 1951, 10048, 2060, 6171],
        [ 8010, 16145, 8090, 8045],
        [ 1013,   990,  940, 6907]
      ]

      chord = Visualize.Layout.Chord.new()
        |> Visualize.Layout.Chord.pad_angle(0.05)

      result = Visualize.Layout.Chord.generate(chord, matrix)

      # result.groups - list of group arcs with start_angle, end_angle, value, index
      # result.chords - list of chords with source/target containing start_angle, end_angle, index

  """

  defstruct pad_angle: 0,
            sort_groups: nil,
            sort_subgroups: nil,
            sort_chords: nil

  @type group :: %{
          index: non_neg_integer(),
          start_angle: float(),
          end_angle: float(),
          value: number()
        }

  @type chord_end :: %{
          index: non_neg_integer(),
          start_angle: float(),
          end_angle: float(),
          value: number()
        }

  @type chord :: %{
          source: chord_end(),
          target: chord_end()
        }

  @type result :: %{
          groups: [group()],
          chords: [chord()]
        }

  @type t :: %__MODULE__{
          pad_angle: number(),
          sort_groups: (group(), group() -> boolean()) | nil,
          sort_subgroups: (number(), number() -> boolean()) | nil,
          sort_chords: (chord(), chord() -> boolean()) | nil
        }

  @doc "Creates a new chord layout"
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Sets the padding angle between groups in radians"
  @spec pad_angle(t(), number()) :: t()
  def pad_angle(%__MODULE__{} = chord, angle) when is_number(angle) do
    %{chord | pad_angle: angle}
  end

  @doc "Sets the comparator for sorting groups"
  @spec sort_groups(t(), (group(), group() -> boolean()) | nil) :: t()
  def sort_groups(%__MODULE__{} = chord, func) do
    %{chord | sort_groups: func}
  end

  @doc "Sets the comparator for sorting subgroups within each group"
  @spec sort_subgroups(t(), (number(), number() -> boolean()) | nil) :: t()
  def sort_subgroups(%__MODULE__{} = chord, func) do
    %{chord | sort_subgroups: func}
  end

  @doc "Sets the comparator for sorting chords"
  @spec sort_chords(t(), (chord(), chord() -> boolean()) | nil) :: t()
  def sort_chords(%__MODULE__{} = chord, func) do
    %{chord | sort_chords: func}
  end

  @doc """
  Generates the chord layout from a matrix.

  The matrix should be a list of lists where matrix[i][j] represents
  the flow from group i to group j.

  Returns a map with :groups and :chords.
  """
  @spec generate(t(), [[number()]]) :: result()
  def generate(%__MODULE__{} = chord, matrix) do
    n = length(matrix)

    if n == 0 do
      %{groups: [], chords: []}
    else
      # Compute group totals
      group_totals =
        matrix
        |> Enum.with_index()
        |> Enum.map(fn {row, i} ->
          outgoing = Enum.sum(row)
          incoming = matrix |> Enum.map(&Enum.at(&1, i)) |> Enum.sum()
          {i, outgoing + incoming}
        end)

      # Sort groups if comparator provided
      sorted_indices =
        if chord.sort_groups do
          group_totals
          |> Enum.sort(fn {_i1, v1}, {_i2, v2} -> chord.sort_groups.(%{value: v1}, %{value: v2}) end)
          |> Enum.map(fn {i, _} -> i end)
        else
          Enum.map(0..(n - 1), & &1)
        end

      # Total of all values (each edge counted once for angle calculation)
      total = matrix |> List.flatten() |> Enum.sum()

      # Total padding
      total_padding = chord.pad_angle * n

      # Angle per unit value
      k = if total > 0, do: (2 * :math.pi() - total_padding) / total, else: 0

      # Compute group angles
      {groups, group_angles, _} =
        Enum.reduce(sorted_indices, {[], %{}, 0}, fn i, {groups_acc, angles_acc, angle} ->
          # Group value is sum of row (outgoing)
          row = Enum.at(matrix, i)
          value = Enum.sum(row)
          end_angle = angle + value * k

          group = %{
            index: i,
            start_angle: angle,
            end_angle: end_angle,
            value: value
          }

          # Store subgroup angles for chord generation
          subgroup_angles = compute_subgroup_angles(row, angle, k, chord.sort_subgroups)

          {
            [group | groups_acc],
            Map.put(angles_acc, i, subgroup_angles),
            end_angle + chord.pad_angle
          }
        end)

      groups = Enum.reverse(groups)

      # Generate chords
      chords = generate_chords(matrix, group_angles, n)

      # Sort chords if comparator provided
      chords =
        if chord.sort_chords do
          Enum.sort(chords, chord.sort_chords)
        else
          chords
        end

      %{groups: groups, chords: chords}
    end
  end

  defp compute_subgroup_angles(row, start_angle, k, sort_fn) do
    indexed_values = Enum.with_index(row)

    sorted =
      if sort_fn do
        Enum.sort(indexed_values, fn {v1, _}, {v2, _} -> sort_fn.(v1, v2) end)
      else
        indexed_values
      end

    {angles, _} =
      Enum.map_reduce(sorted, start_angle, fn {value, j}, angle ->
        end_angle = angle + value * k
        {{j, {angle, end_angle}}, end_angle}
      end)

    Map.new(angles)
  end

  defp generate_chords(matrix, group_angles, n) do
    # Generate a chord for each non-zero matrix entry
    # Only generate once per pair (i < j for asymmetric, both for symmetric)
    for i <- 0..(n - 1),
        j <- 0..(n - 1),
        i <= j,
        value_ij = matrix |> Enum.at(i) |> Enum.at(j),
        value_ji = matrix |> Enum.at(j) |> Enum.at(i),
        value_ij > 0 or value_ji > 0 do

      source_angles = Map.get(group_angles, i, %{})
      target_angles = Map.get(group_angles, j, %{})

      {src_start, src_end} = Map.get(source_angles, j, {0, 0})
      {tgt_start, tgt_end} = Map.get(target_angles, i, {0, 0})

      %{
        source: %{
          index: i,
          start_angle: src_start,
          end_angle: src_end,
          value: value_ij
        },
        target: %{
          index: j,
          start_angle: tgt_start,
          end_angle: tgt_end,
          value: value_ji
        }
      }
    end
    |> Enum.filter(fn chord ->
      chord.source.value > 0 or chord.target.value > 0
    end)
  end

  @doc """
  Generates an SVG path for a chord ribbon.

  The ribbon connects the source and target arcs with bezier curves.
  """
  @spec ribbon_path(chord(), number()) :: String.t()
  def ribbon_path(chord, radius) do
    sa0 = chord.source.start_angle
    sa1 = chord.source.end_angle
    ta0 = chord.target.start_angle
    ta1 = chord.target.end_angle

    # Source arc endpoints
    sx0 = radius * :math.sin(sa0)
    sy0 = -radius * :math.cos(sa0)
    sx1 = radius * :math.sin(sa1)
    sy1 = -radius * :math.cos(sa1)

    # Target arc endpoints
    tx0 = radius * :math.sin(ta0)
    ty0 = -radius * :math.cos(ta0)
    tx1 = radius * :math.sin(ta1)
    ty1 = -radius * :math.cos(ta1)

    # Large arc flags
    source_large = if sa1 - sa0 > :math.pi(), do: 1, else: 0
    target_large = if ta1 - ta0 > :math.pi(), do: 1, else: 0

    if chord.source.index == chord.target.index do
      # Self-referencing chord (loop)
      "M#{sx0},#{sy0}" <>
      "A#{radius},#{radius} 0 #{source_large},1 #{sx1},#{sy1}" <>
      "Q0,0 #{sx0},#{sy0}" <>
      "Z"
    else
      # Regular chord connecting two groups
      "M#{sx0},#{sy0}" <>
      "A#{radius},#{radius} 0 #{source_large},1 #{sx1},#{sy1}" <>
      "Q0,0 #{tx0},#{ty0}" <>
      "A#{radius},#{radius} 0 #{target_large},1 #{tx1},#{ty1}" <>
      "Q0,0 #{sx0},#{sy0}" <>
      "Z"
    end
  end

  @doc """
  Generates an SVG path for a group arc.
  """
  @spec arc_path(group(), number(), number()) :: String.t()
  def arc_path(group, inner_radius, outer_radius) do
    a0 = group.start_angle
    a1 = group.end_angle

    # Inner arc endpoints
    ix0 = inner_radius * :math.sin(a0)
    iy0 = -inner_radius * :math.cos(a0)
    ix1 = inner_radius * :math.sin(a1)
    iy1 = -inner_radius * :math.cos(a1)

    # Outer arc endpoints
    ox0 = outer_radius * :math.sin(a0)
    oy0 = -outer_radius * :math.cos(a0)
    ox1 = outer_radius * :math.sin(a1)
    oy1 = -outer_radius * :math.cos(a1)

    large_arc = if a1 - a0 > :math.pi(), do: 1, else: 0

    "M#{ix0},#{iy0}" <>
    "A#{inner_radius},#{inner_radius} 0 #{large_arc},1 #{ix1},#{iy1}" <>
    "L#{ox1},#{oy1}" <>
    "A#{outer_radius},#{outer_radius} 0 #{large_arc},0 #{ox0},#{oy0}" <>
    "Z"
  end
end
