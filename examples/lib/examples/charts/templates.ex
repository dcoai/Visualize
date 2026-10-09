defmodule Examples.Charts.Templates do
  @moduledoc """
  Every chart of the gallery written as a design, and every preset without one, as a
  **template** for the builder's library (spec/14 §18.16, #233).

  A chart type is a composition — a frame, its scales, its marks — so the builder offers
  one as a library entry under `Charts::<title>`. `all/0` reads the gallery: every
  `Examples.Charts.*` module exporting `design/1` is a template by construction, and the
  presets of `Visualize.Chart.Presets` stand in for the charts the gallery has not yet
  rebuilt (`tree_diagram`, `treemap_chart`). Each template's sources are renamed with the
  chart's slug — `bar_chart_bars` — and its marks' `data` rewritten to match, so every
  template's sample rows sit together in one pool (`pool/0`) without colliding.
  """

  alias Examples.Charts.Design
  alias Visualize.Chart.Presets

  @typedoc "A template: its library name, the design and the rows its sources bind."
  @type t :: %{name: String.t(), slug: atom(), design: map(), sources: %{atom() => [map()]}}

  # The presets whose chart the gallery does not draw as a design yet, with the assigns
  # their designs need: a small hierarchy for the two hierarchy charts.
  @hierarchy %{
    name: "Flare",
    children: [
      %{
        name: "Analytics",
        children: [
          %{name: "Cluster", value: 8500},
          %{name: "Graph", value: 7500},
          %{name: "Optimization", value: 6200}
        ]
      },
      %{
        name: "Animate",
        children: [
          %{name: "Easing", value: 4200},
          %{name: "Interpolate", value: 5800},
          %{name: "Transition", value: 3900}
        ]
      },
      %{
        name: "Data",
        children: [%{name: "Converters", value: 3100}, %{name: "Schema", value: 2400}]
      }
    ]
  }

  @presets [
    {:tree_diagram, "Tree Diagram", "A tree of nodes and links", %{data: @hierarchy}},
    {:treemap_chart, "Treemap", "Nested rectangles sized by value", %{data: @hierarchy}}
  ]

  @doc "Every template, the gallery's designs first in title order, then the presets."
  @spec all() :: [t()]
  def all, do: gallery() ++ presets()

  @doc "The union of every template's sample rows, keyed by the renamed source names."
  @spec pool() :: %{atom() => [map()]}
  def pool,
    do: Enum.reduce(all(), %{}, fn template, pool -> Map.merge(pool, template.sources) end)

  @doc "The gallery's chart modules that are designs, in title order."
  @spec gallery_modules() :: [module()]
  def gallery_modules do
    {:ok, modules} = :application.get_key(:examples, :modules)

    modules
    |> Enum.filter(&String.starts_with?(Atom.to_string(&1), "Elixir.Examples.Charts."))
    |> Enum.filter(&Design.design?/1)
    |> Enum.sort_by(& &1.title())
  end

  defp gallery do
    for module <- gallery_modules() do
      {design, sources} = module.design([])

      template(
        slug(module),
        module.title(),
        module.description(),
        design,
        sources
      )
    end
  end

  # A preset stands in only while the gallery has no design of that title.
  defp presets do
    drawn = gallery_modules() |> Enum.map(& &1.title()) |> MapSet.new()

    for {name, title, description, assigns} <- @presets, not MapSet.member?(drawn, title) do
      template(
        name,
        title,
        description,
        Presets.design(name, assigns),
        Presets.sources(name, assigns)
      )
    end
  end

  defp template(slug, title, description, design, sources) do
    renames = Map.new(Map.keys(sources), &{&1, :"#{slug}_#{&1}"})

    %{
      name: "Charts::#{title}",
      slug: slug,
      design:
        design
        |> Map.put(:meta, %{name: title, description: description})
        |> rename_sources(renames),
      sources: Map.new(sources, fn {name, rows} -> {Map.fetch!(renames, name), rows} end)
    }
  end

  # The slug of a chart module: `Examples.Charts.BarChart` is `:bar_chart`.
  defp slug(module) do
    module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> String.to_atom()
  end

  # The design's source slots, every mark's `data` and a projection's `fit` source (spec/14
  # §4.6, #476) under the renamed names; a slot's `default` is dropped, since the pool
  # binds by the slot's own name.
  defp rename_sources(design, renames) do
    design
    |> Map.update(:sources, %{}, fn slots ->
      Map.new(slots, fn {name, slot} ->
        {Map.fetch!(renames, name), Map.delete(slot, :default)}
      end)
    end)
    |> Map.update(:marks, [], fn marks -> Enum.map(marks, &rename_data(&1, renames)) end)
    |> Map.update(:frames, %{}, fn frames ->
      Map.new(frames, fn {name, node} -> {name, rename_fit(node, renames)} end)
    end)
  end

  defp rename_fit(%{projection: %{fit: %{data: name} = fit} = projection} = node, renames)
       when is_atom(name) do
    fit = %{fit | data: Map.get(renames, name, name)}
    %{node | projection: %{projection | fit: fit}}
  end

  defp rename_fit(node, _renames), do: node

  defp rename_data(%{data: name} = mark, renames) when is_atom(name),
    do: %{mark | data: Map.get(renames, name, name)}

  # A data node names its source, and a graph step in it may name a second — its node
  # table under `nodes` (spec/14 §5.4.3) — which is renamed the same way.
  defp rename_data(%{data: %{source: name} = data} = mark, renames) when is_atom(name) do
    data = %{data | source: Map.get(renames, name, name)}

    data =
      Map.update(data, :transforms, [], fn steps ->
        Enum.map(steps, fn
          %{nodes: nodes} = step -> %{step | nodes: Map.get(renames, nodes, nodes)}
          step -> step
        end)
      end)

    %{mark | data: data}
  end

  defp rename_data(mark, _renames), do: mark
end
