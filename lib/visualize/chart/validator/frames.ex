defmodule Visualize.Chart.Validator.Frames do
  @moduledoc false
  # What the validator asks of a design's frames as nodes (spec/14 §2.9, §4.3, §5.2): the
  # frame a `:tiles` mark stands in, the frame a sync group or a brush reads, and a scale
  # read through its adoptions to the node that declares it.

  alias Visualize.Chart.Schema

  # The faults of a `:tiles` mark's frame: not `:geo`, or a projection that is not
  # tile-aligned. A frame the mark cannot be placed in, or a variable where the
  # projection's keys would be, is another check's to report.
  @doc false
  @spec tiles_frame(term(), list()) :: [{list(), tuple()}]
  def tiles_frame(%{kind: :geo} = frame, path) do
    case Map.get(frame, :projection) || %{} do
      %{} = projection when not is_struct(projection) ->
        case tiles_projection(projection) do
          :ok -> []
          what -> [{path, {:tiles, :projection, what}}]
        end

      _var ->
        []
    end
  end

  def tiles_frame(%{kind: kind}, path) when is_atom(kind) and kind != nil,
    do: [{path, {:tiles, :projection, kind}}]

  def tiles_frame(_frame, _path), do: []

  defp tiles_projection(projection) do
    type = Map.get(projection, :type, :mercator)

    cond do
      is_atom(type) and type != :mercator -> type
      match?([_, lat] when is_number(lat) and lat != 0, Map.get(projection, :center)) -> :center
      tilted?(Map.get(projection, :rotate)) -> :rotate
      true -> :ok
    end
  end

  defp tilted?([_lambda | rest]) when is_list(rest),
    do: Enum.any?(rest, &(is_number(&1) and &1 != 0))

  defp tilted?(_rotate), do: false

  # The frame a sync group reads: the one `frame` names, else the first by name — the frame
  # `Visualize.Chart.Applied` holds as `frame`. A name no frame carries is the reference
  # check's fault, not this one's.
  # The faults of the frame a sync group or a brush reads, as `{what, kind}`: not cartesian,
  # or an `x` that is not linear or time.
  @doc false
  @spec linear_x(atom() | nil, map()) :: [tuple()]
  def linear_x(name, frames) do
    case sync_frame(name, frames) do
      %{kind: :cartesian} = frame ->
        case sync_x_kind(frame, frames, []) do
          kind when kind in [:linear, :time] -> []
          kind -> [{:x_scale, kind}]
        end

      # A kind that is no frame kind is its own fault, reported on the frame.
      %{kind: kind} ->
        {:enum, kinds} = Schema.key(:frame, :kind).type
        if kind in kinds, do: [{:frame_kind, kind}], else: []

      _none ->
        []
    end
  end

  defp sync_frame(nil, frames) when is_map(frames) and map_size(frames) > 0,
    do: frames |> Enum.min_by(fn {name, _node} -> name end) |> elem(1)

  defp sync_frame(name, frames) when is_map_key(frames, name), do: Map.fetch!(frames, name)
  defp sync_frame(_name, _frames), do: nil

  # The kind of a frame's `x`, read through any adoption to the node that declares it
  # (spec/14 §4.3); `nil` for none, and for a cycle, which is reported where it closes.
  defp sync_x_kind(frame, frames, seen) do
    case declared(nested(frame, [:scales, "x"]), frames, seen) do
      %{kind: kind} -> kind
      _other -> nil
    end
  end

  # A scale as the node that declares it, read through any adoption (spec/14 §4.3): `nil`
  # for none, and for a cycle, which is reported where it closes.
  defp declared({:frame, f, s} = ref, frames, seen) when is_map(frames) do
    if ref in seen,
      do: nil,
      else: declared(nested(Map.get(frames, f), [:scales, s]), frames, [ref | seen])
  end

  defp declared({:frame, _f, _s}, _frames, _seen), do: nil
  defp declared(node, _frames, _seen), do: node

  defp nested(map, []), do: map
  defp nested(map, [k | rest]) when is_map(map) and not is_struct(map), do: nested(map[k], rest)
  defp nested(_, _), do: nil
end
