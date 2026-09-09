defmodule Visualize.BuilderFixture do
  @moduledoc false
  # The fixed set of layers every builder panel golden is rendered over (spec/14 §18): a
  # house layer with the theme and the styles, a shared frame layer with the scales and the
  # axes, and a panel layer with the mark, the label and the variable. Each is named, so the
  # inspector and the parameters form report a name rather than a position.
  #
  # The goldens themselves live in `test/support/builder/`; `write!/0` regenerates them and
  # is here rather than in the test file because only `test/support` is compiled by
  # `mix run`:
  #
  #     MIX_ENV=test mix run -e 'Visualize.BuilderFixture.write!()'

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Visualize.Chart
  alias Visualize.Chart.Builder
  alias Visualize.Chart.Builder.{Document, Editor, Inspector, Layers, Params, Preview}

  @dir "test/support/builder"

  @doc false
  # The three layers in precedence order, the higher later, as `Visualize.Chart.stack/1`
  # reads them.
  def layers do
    [
      {:house,
       %{
         version: 1,
         theme: :default,
         styles: %{series: %{stroke: :series_1, stroke_width: 2}},
         frame: %{
           kind: :cartesian,
           size: %{width: 400, height: 200},
           margin: %{top: 20, right: 20, bottom: 30, left: 40}
         }
       }},
      {:shared,
       %{
         sources: %{primary: %{fields: [:t, :v]}},
         frame: %{
           scales: %{
             x: %{kind: :linear, domain: :auto},
             y: %{kind: :linear, domain: [0, :auto]}
           },
           axes: [%{scale: :x, side: :bottom, ticks: 3}, %{scale: :y, side: :left, ticks: 3}]
         }
       }},
      {:panel,
       %{
         vars: %{unit: %{default: "%"}},
         marks: [
           %{
             id: :series,
             type: :line,
             data: :primary,
             channels: %{x: :t, y: :v},
             style: :series
           }
         ],
         labels: [%{anchor: :title, text: ["Uptime — ", Chart.var(:unit)]}]
       }}
    ]
  end

  @doc false
  # The pool the layers' one slot binds to.
  def sources do
    %{primary: [%{t: 0, v: 1}, %{t: 1, v: 4}, %{t: 2, v: 2}, %{t: 3, v: 3}]}
  end

  @doc false
  # A stack that does not apply: the panel layer without the two layers under it, so its
  # mark names a source and a style nothing declares — the normal state of a design being
  # built, and what the preview lists by path.
  def incomplete do
    [
      {:panel,
       %{
         version: 1,
         frame: %{kind: :cartesian},
         marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v}, style: :series}]
       }}
    ]
  end

  # A store with two names, one of which holds nothing: the builder's library under test.
  defmodule Library do
    @moduledoc false
    @behaviour Visualize.Chart.Builder.Store

    @impl true
    def list, do: [:baseline, :missing]

    @impl true
    def get(:baseline), do: {:ok, %{version: 1, frame: %{kind: :cartesian}}}
    def get(_name), do: :error

    @impl true
    def put(_name, _fragment), do: :ok
  end

  # A store that refuses every write, so the notice path has a subject.
  defmodule Refusing do
    @moduledoc false
    @behaviour Visualize.Chart.Builder.Store

    @impl true
    def list, do: []

    @impl true
    def get(_name), do: :error

    @impl true
    def put(_name, _fragment), do: {:error, :read_only}
  end

  @doc false
  # Every panel golden: a name, the component and the assigns it is rendered over.
  def cases do
    [
      preview: {&Preview.panel/1, %{design: Chart.stack(layers()), sources: sources()}},
      preview_errors: {&Preview.panel/1, %{design: Chart.stack(incomplete()), sources: %{}}},
      # The golden is a record of the builder's *markup*, so the fixture renders it without
      # the stylesheet: the stylesheet is six hundred lines that would swamp the file and
      # churn it on every rule, and it has its own assertions (spec/14 §18.13, D-94).
      builder: {Builder, %{id: "builder", layers: layers(), sources: sources(), styles: false}},
      builder_store:
        {Builder,
         %{
           id: "builder",
           layers: layers(),
           sources: sources(),
           store: Library,
           styles: false
         }},
      editor_design: {&Editor.panel/1, %{kind: :design, node: layer(:house), path: []}},
      layers: {&Layers.panel/1, %{id: "b-layers", layers: layers()}},
      layers_disabled:
        {&Layers.panel/1,
         %{id: "b-layers", layers: layers(), selected: 2, disabled: MapSet.new([0])}},
      inspector: {&Inspector.panel/1, %{id: "b-inspector", layers: layers()}},
      inspector_overrides: {&Inspector.panel/1, %{id: "b-inspector", layers: overriding()}},
      params: {&Params.panel/1, %{layers: parameterised()}},
      params_bound:
        {&Params.panel/1, %{layers: parameterised(), vars: %{unit: "mg/hr", ticks: 6}}},
      document: {&Document.panel/1, %{design: Chart.stack(layers())}},
      document_errors: {&Document.panel/1, %{design: %{marks: [%{type: :line}]}}},
      editor_mark:
        {&Editor.panel/1,
         %{
           kind: :mark,
           node: mark(),
           path: [:marks, 0],
           facet: :channel
         }},
      editor_style_errors:
        {&Editor.panel/1,
         %{
           kind: :style,
           node: %{stroke: :series_1, stroke_width: 2},
           path: [:styles, :series],
           errors: [
             {[:styles, :series, :stroke], {:undeclared, :slot, :series_1}},
             {[:styles, :series, :curve], {:enum, [:linear, :step]}},
             {[:marks, 0, :style], {:undeclared, :style, :series}}
           ]
         }}
    ]
  end

  @doc false
  # The three layers with a fourth over them that overrides two values the lower layers set,
  # so the inspector has something in its `overrode` column.
  def overriding do
    layers() ++
      [
        {:override,
         %{
           frame: %{size: %{width: 640}},
           styles: %{series: %{stroke: :series_2, stroke_width: 3}}
         }}
      ]
  end

  @doc false
  # The three layers with a fourth that opens two more variables of different expectations:
  # a `{:ref, :style}` where a mark's style stands and an `:integer` where an axis's tick
  # count does, so the parameters form has three widgets to choose between.
  def parameterised do
    layers() ++
      [
        {:params,
         %{
           vars: %{accent: %{}, ticks: %{default: 3}},
           styles: %{series: %{stroke: :series_1, stroke_width: 2}},
           frame: %{axes: [%{scale: :x, side: :bottom, ticks: Chart.var(:ticks)}]},
           marks: [
             %{
               id: :series,
               type: :line,
               data: :primary,
               channels: %{x: :t, y: :v},
               style: Chart.var(:accent)
             }
           ]
         }}
      ]
  end

  @doc false
  # One named layer's fragment.
  def layer(name), do: layers() |> Keyword.fetch!(name)

  @doc false
  # The panel layer's one mark, the node `editor_mark` edits.
  def mark, do: :panel |> layer() |> Map.fetch!(:marks) |> hd()

  @doc false
  def dir, do: @dir

  @doc false
  def render_case({component, assigns}), do: render_component(component, assigns)

  @doc false
  def golden(name), do: File.read!(Path.join(@dir, "#{name}.html"))

  @doc false
  def write! do
    File.mkdir_p!(@dir)

    Enum.each(cases(), fn {name, c} ->
      File.write!(Path.join(@dir, "#{name}.html"), render_case(c))
    end)
  end
end
