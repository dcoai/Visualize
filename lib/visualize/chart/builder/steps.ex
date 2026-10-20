if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Steps do
    @moduledoc """
    What a new chart still needs (spec/14 §18.4, #374): data, a mark, axes — the builder's
    steps, never the validator's faults, so none blocks Save or Deploy nor badges a root.
    `steps/1` reads the design; the preview draws them beneath the chart, each a button
    that does or opens the step.

    This module compiles only when `Phoenix.Component` is loaded (spec/10 §1.1, D-45, D-85).
    """

    alias Visualize.Chart.Fragment

    alias Visualize.Chart.Builder.Scales

    @typedoc "One step: where it stands, its words, and the event that does or opens it."
    @type step :: %{
            path: [atom()],
            words: String.t(),
            event: String.t(),
            values: %{String.t() => String.t()}
          }

    @doc """
    The steps a composite still has to take, in the order a person meets them: no source
    declared, no mark, a mark reading a position scale while no axis measures any.

        iex> Visualize.Chart.Builder.Steps.steps(%{frames: %{main: %{kind: :cartesian}}}) |> Enum.map(& &1.path)
        [[:sources], [:marks]]
        iex> design = Visualize.Chart.Migration.names(%{frames: %{main: %{kind: :cartesian}},
        ...>   sources: %{s: %{fields: [:t, :v]}}, marks: [%{type: :line, data: :s, channels: %{x: :t, y: :v}}]})
        iex> Visualize.Chart.Builder.Steps.steps(design) |> Enum.map(&{&1.path, &1.event})
        [{[:frames, "main", :axes], "select_node"}]
        iex> Visualize.Chart.Builder.Steps.steps(put_in(design, [:frames, "main", :axes], [%{scale: "x", side: :bottom}]))
        []
    """
    @spec steps(map()) :: [step()]
    def steps(design) when is_map(design) do
      sources = Map.get(design, :sources) || %{}
      marks = for mark <- List.wrap(Map.get(design, :marks, [])), is_map(mark), do: mark
      # A scale belongs to its frame (§4.3, #615): an axis measures `{frame, scale}`, and a
      # mark reads its scales in the frame it is drawn in.
      measured =
        for {frame, node} <- frames(design),
            %{scale: scale} <- List.wrap(Map.get(node, :axes)),
            do: {frame, scale}

      read_by = fn mark ->
        for scale <- Scales.position_scales(design, mark),
            do: {Fragment.frame_of(design, mark), scale}
      end

      # The first mark reading a position scale, when no axis measures any scale the
      # marks read: one axis is the way shown, the rest is the mark page's.
      read = Enum.flat_map(marks, read_by)

      unmeasured =
        if read != [] and Enum.all?(read, &(&1 not in measured)),
          do:
            marks
            |> Enum.with_index()
            |> Enum.find(fn {mark, _i} -> Scales.position_scales(design, mark) != [] end),
          else: nil

      List.flatten([
        if(map_size(sources) == 0,
          do: step([:sources], "add data — the columns the chart draws", "add_source", %{}),
          else: []
        ),
        if(marks == [],
          do:
            step([:marks], "add a mark — a line, bars, points … over the data", "place", %{
              "component" => "mark:line",
              "region" => "plot"
            }),
          else: []
        ),
        case unmeasured do
          {mark, i} ->
            step(
              [:frames, Fragment.frame_of(design, mark), :axes],
              "add axes — tick a side on the mark's page",
              "select_node",
              %{
                "node" => "marks[#{i}]"
              }
            )

          nil ->
            []
        end
      ])
    end

    defp frames(design) do
      case Map.get(design, :frames) do
        frames when is_map(frames) -> for {name, node} <- frames, is_map(node), do: {name, node}
        _none -> []
      end
    end

    defp step(path, words, event, values),
      do: %{path: path, words: words, event: event, values: values}
  end
end
