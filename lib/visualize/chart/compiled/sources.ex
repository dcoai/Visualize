defmodule Visualize.Chart.Compiled.Sources do
  @moduledoc false
  # A tick's sources as a chart reads them (spec/14 §12.5, D-232): the one function every
  # place a tick's data enters calls — `tick/3`, `step/3`, `render/2`, `svg/2` and `rows/3`
  # of `Visualize.Chart.Compiled`, and a board cell before it places its rows (spec/15
  # §8.3). Each source is read through the per-slot reader application binds with
  # (`Visualize.Chart.Template.read/2`), so a tick and an application cannot disagree: a
  # tensor and tuple rows named by the slot's declared fields (D-214), anything else as
  # given. A source its slot cannot read is a fault, never a raise here.

  alias Visualize.Chart.{Names, Template, Validator}
  alias Visualize.Data.Delivery

  @doc false
  # `{sources, faults}`: the sources by name — the design's spelling, a string (D-195) —
  # each as the chart reads it, a delivery keeping its wrapper with the source it carries
  # read; and every source the slots cannot read as `{[:sources, name], reason}`, in the
  # shape `Visualize.Chart.apply/2` reports, ordered by path. A faulted source is left out,
  # so it draws nothing (spec/14 §12.4). `slots` are the design's slot declarations, `nil`
  # for a design that declares none.
  @spec read(map() | nil, map()) :: {%{String.t() => term()}, [Validator.error()]}
  def read(slots, sources) when is_map(sources) do
    slots = if is_map(slots), do: slots, else: %{}

    {read, faults} =
      sources
      |> Names.keys()
      |> Enum.reduce({%{}, []}, fn {name, source}, {read, faults} ->
        case Template.read(Map.get(slots, name), Delivery.source(source)) do
          {:ok, carried} -> {Map.put(read, name, carrying(source, carried)), faults}
          {:error, reason} -> {read, [{[:sources, name], reason} | faults]}
        end
      end)

    {read, Enum.sort_by(faults, &elem(&1, 0))}
  end

  # A delivery carries the source as read; any other source is the source as read.
  defp carrying(%Delivery{} = delivery, source), do: %{delivery | rows: source}
  defp carrying(_source, source), do: source

  @doc false
  # The faults as the `ArgumentError` of a compiled chart's one-shot forms, which return
  # no chart to carry them (spec/14 §12.4, D-232).
  @spec raise!([Validator.error(), ...]) :: no_return()
  def raise!(faults) do
    raise ArgumentError,
          "a source cannot bind: " <>
            Enum.map_join(faults, "; ", &Validator.format/1) <>
            " (spec/14 §7.3) — tick/3 and step/3 carry this as Compiled.faults/1"
  end

  @doc false
  # The first slot among the sources whose delivery names a schema version other than the
  # one it was compiled with, `{slot, compiled_with, delivered}`, else `nil` (spec/14 §12.1,
  # D-136). `sources` are keyed by the design's spelling.
  @spec stale(%{String.t() => String.t() | nil}, map()) :: {term(), term(), term()} | nil
  def stale(versions, sources) do
    Enum.find_value(sources, fn
      {slot, %Delivery{schema: version}} ->
        compiled = Map.get(versions, slot)
        if version != compiled, do: {slot, compiled, version}

      _plain ->
        nil
    end)
  end

  @doc false
  # Raises for a stale delivery (D-136): not bad data but a chart to compile again.
  @spec fresh!(%{String.t() => String.t() | nil}, map()) :: :ok
  def fresh!(versions, sources) do
    case stale(versions, sources) do
      nil ->
        :ok

      {slot, compiled_with, delivered} ->
        raise ArgumentError,
              "slot #{inspect(slot)}'s delivery names schema version #{inspect(delivered)}, " <>
                "and the chart was compiled with #{inspect(compiled_with)}: a schema change " <>
                "recompiles (spec/14 §12.1) — compile again and carry/2 the state across"
    end
  end
end
