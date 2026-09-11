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

  # A store with two entries listed, one of which the store no longer holds — the mask of
  # spec/14 §19.2 — so the builder's library under test has both a hit and a miss.
  defmodule Library do
    @moduledoc false
    @behaviour Visualize.Chart.Builder.Store

    @baseline {:design, 1}
    @missing {:design, 2}

    def baseline_id, do: @baseline
    def missing_id, do: @missing

    @impl true
    def list(_context) do
      [
        %{id: @baseline, name: "baseline", kind: :design},
        %{id: @missing, name: "missing", kind: :design}
      ]
    end

    @impl true
    def get(@baseline, _context) do
      {:ok,
       %{
         id: @baseline,
         name: "baseline",
         kind: :design,
         fragment: %{version: 1, frame: %{kind: :cartesian}}
       }}
    end

    def get(_id, _context), do: :error

    @impl true
    def put(%{id: nil}, _context), do: {:ok, {:design, 3}}
    def put(%{id: id}, _context), do: {:ok, id}

    @impl true
    def delete(_id, _context), do: :ok

    @impl true
    def import(bundle, context),
      do: Visualize.Chart.Builder.Store.relocate(bundle, context, &put/2)
  end

  # A store that refuses every write, so the notice path has a subject.
  defmodule Refusing do
    @moduledoc false
    @behaviour Visualize.Chart.Builder.Store

    @impl true
    def list(_context), do: []

    @impl true
    def get(_id, _context), do: :error

    @impl true
    def put(_entry, _context), do: {:error, :read_only}

    @impl true
    def delete(_id, _context), do: {:error, :read_only}

    @impl true
    def import(_bundle, _context), do: {:error, :read_only}
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

  # -- the builder's state, in the shapes the tests have always read it in ---------------
  #
  # The builder's state is a stack of use sites (spec/14 §19.3); the panels read resolved
  # layers, an index and a set derived from it. These read the same things the same way,
  # so a test says what it means — "the second layer is disabled" — and not how it is kept.

  alias Phoenix.LiveView.Socket
  alias Visualize.Chart.Builder
  alias Visualize.Chart.Builder.{Stack, Store}

  @doc "A builder socket over host layers, seeded as the component seeds them, with options."
  def socket(layers, opts \\ []) do
    {host, state} = Keyword.split(opts, [:store, :sources, :vars, :theme, :on_save])

    host =
      host
      |> Keyword.put_new(:sources, sources())
      |> Keyword.put(:id, "b")
      |> Keyword.put(:layers, layers)
      |> Map.new()

    {:ok, socket} = Builder.mount(%Socket{})
    {:ok, socket} = Builder.update(host, socket)

    Enum.reduce(state, socket, fn
      {:selected, index}, socket ->
        case Enum.at(socket.assigns.uses, index) do
          nil -> socket
          use -> Phoenix.Component.assign(socket, :selected, use.id)
        end

      {:disabled, indexes}, socket ->
        uses =
          socket.assigns.uses
          |> Enum.with_index()
          |> Enum.map(fn {use, i} -> if i in indexes, do: %{use | mask: :all}, else: use end)

        Phoenix.Component.assign(socket, :uses, uses)

      {:bindings, bindings}, socket ->
        Phoenix.Component.assign(socket, :bindings, bindings)

      {key, value}, socket ->
        Phoenix.Component.assign(socket, key, value)
    end)
  end

  @doc "The resolved layers as `{name, fragment}`, the name an atom where one exists."
  def layers(%Socket{assigns: assigns}) do
    {resolved, _missing} = Stack.resolve(assigns.uses, assigns.labels, Stack.fetch(assigns.store))
    for {label, fragment} <- resolved, do: {atomised(label), fragment}
  end

  # The fixture's own layers are named by atoms; a label that is one of them reads back as
  # the atom, so a test compares against `layers/0` unchanged. Any other label is its string.
  @named ~w(house shared panel imported only params)a
  defp atomised(label) do
    Enum.find(@named, label, &(Atom.to_string(&1) == label))
  end

  @doc "The selected layer's position, or `nil`."
  def selected(%Socket{assigns: assigns}), do: Stack.index_of(assigns.uses, assigns.selected)

  @doc """
  The builder rendered in a socket's state: `render_component/2` over its assigns, with the
  host's layers already seeded so the state — an opened entry, a moved layer — is what draws.
  """
  def render(%Socket{assigns: assigns}) do
    assigns
    |> Map.drop([:__changed__, :flash, :myself])
    |> Map.merge(%{styles: false, layers: Map.get(assigns, :host_layers, [])})
    |> then(&render_component(Builder, &1))
  end

  @doc "The disabled positions, as a set."
  def disabled(%Socket{assigns: assigns}) do
    assigns.uses
    |> Enum.with_index()
    |> Enum.reject(fn {use, _i} -> Stack.enabled?(use) end)
    |> MapSet.new(fn {_use, i} -> i end)
  end

  @doc "The design the stack stands for: what saving sends, flattened."
  def design(%Socket{assigns: assigns}) do
    {:ok, design, _missing} =
      Stack.design(assigns.uses, assigns.stack_vars, Stack.fetch(assigns.store))

    design
  end

  @doc "The layer names, as strings, in stack order."
  def names(%Socket{assigns: assigns}) do
    Enum.map(assigns.uses, &atomised(Stack.label(assigns.labels, &1)))
  end

  @doc "The `style` value at the selected layer's first mark."
  def style_at(socket) do
    {_name, fragment} = socket |> layers() |> Enum.at(selected(socket))
    fragment |> Map.fetch!(:marks) |> hd() |> Map.get(:style)
  end

  @doc "A fragment's id under the fixture Library, for tests that click or drop it."
  def encoded(id), do: Store.encode_id(id)
end
