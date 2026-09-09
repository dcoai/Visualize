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
  alias Visualize.Chart.Builder.Preview

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
      builder: {Builder, %{id: "builder", layers: layers(), sources: sources()}},
      builder_store:
        {Builder, %{id: "builder", layers: layers(), sources: sources(), store: Library}}
    ]
  end

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
