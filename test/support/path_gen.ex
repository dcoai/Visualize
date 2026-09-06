defmodule Visualize.PathGen do
  @moduledoc """
  StreamData generators for random `Visualize.IR.Path` values: every command kind, absolute
  and relative, with float coordinates and 0/1 arc flags. Shared by the transform and
  binary round-trip properties.
  """

  import StreamData

  alias Visualize.IR.Path

  @doc "A coordinate in the ordinary pixel range."
  def coord, do: float(min: -1000.0, max: 1000.0)

  @doc "One path command of any kind."
  def command do
    radius = float(min: 1.0, max: 50.0)
    angle = float(min: 0.0, max: 180.0)
    flag = member_of([0, 1])

    one_of([
      tuple({constant(:M), coord(), coord()}),
      tuple({constant(:m), coord(), coord()}),
      tuple({constant(:L), coord(), coord()}),
      tuple({constant(:l), coord(), coord()}),
      tuple({constant(:H), coord()}),
      tuple({constant(:h), coord()}),
      tuple({constant(:V), coord()}),
      tuple({constant(:v), coord()}),
      tuple({constant(:C), coord(), coord(), coord(), coord(), coord(), coord()}),
      tuple({constant(:c), coord(), coord(), coord(), coord(), coord(), coord()}),
      tuple({constant(:S), coord(), coord(), coord(), coord()}),
      tuple({constant(:s), coord(), coord(), coord(), coord()}),
      tuple({constant(:Q), coord(), coord(), coord(), coord()}),
      tuple({constant(:q), coord(), coord(), coord(), coord()}),
      tuple({constant(:T), coord(), coord()}),
      tuple({constant(:t), coord(), coord()}),
      tuple({constant(:A), radius, radius, angle, flag, flag, coord(), coord()}),
      tuple({constant(:a), radius, radius, angle, flag, flag, coord(), coord()}),
      constant(:Z)
    ])
  end

  @doc "A path of up to `max_length` random commands."
  def path(max_length \\ 12),
    do: map(list_of(command(), max_length: max_length), &%Path{commands: &1})

  @doc "A path that is one `M` followed by `L` commands — the compact binary form."
  def polyline do
    bind(tuple({coord(), coord()}), fn {x, y} ->
      map(list_of(tuple({constant(:L), coord(), coord()}), max_length: 10), fn rest ->
        %Path{commands: [{:M, x, y} | rest]}
      end)
    end)
  end
end
