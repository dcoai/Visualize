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
         version: 2,
         theme: :default,
         styles: %{series: %{stroke: :series_1, stroke_width: 2}},
         frames: %{
           main: %{
             kind: :cartesian,
             margin: %{top: 20, right: 20, bottom: 30, left: 40}
           }
         }
       }},
      {:shared,
       %{
         sources: %{primary: %{fields: [:t, :v]}},
         frames: %{
           main: %{
             scales: %{
               x: %{kind: :linear, domain: :auto},
               y: %{kind: :linear, domain: [0, :auto]}
             },
             axes: [%{scale: :x, side: :bottom, ticks: 3}, %{scale: :y, side: :left, ticks: 3}]
           }
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
  # Two frames side by side, neither of them `main` — the shape the gallery's *Load* and
  # *Context* templates have (spec/14 §18.4, #386) — over the fixture's pool.
  def two_frames do
    scales = %{x: %{kind: :linear, domain: :auto}, y: %{kind: :linear, domain: :auto}}

    [
      {:two,
       %{
         version: 2,
         sources: %{primary: %{fields: [:t, :v]}},
         frames: %{
           history: %{
             kind: :cartesian,
             box: [0, 0, 0.5, 1],
             scales: scales,
             axes: [%{scale: :x, side: :bottom}]
           },
           now: %{kind: :cartesian, box: [0.5, 0, 0.5, 1], scales: scales}
         },
         marks: [
           %{type: :line, frame: :history, data: :primary, channels: %{x: :t, y: :v}},
           %{type: :line, frame: :now, data: :primary, channels: %{x: :t, y: :v}}
         ]
       }}
    ]
  end

  @doc false
  # Three columns and two rows: `history` over the left two columns, `now` the top of
  # the third.
  def gridded_frames do
    [{name, layer}] = two_frames()

    layer =
      layer
      |> Map.put(:layout, %{columns: [1, 1, 1], rows: [1, 1]})
      |> update_in(
        [:frames, :history],
        &(&1 |> Map.delete(:box) |> Map.merge(%{cell: [0, 0], span: [2, 2]}))
      )
      |> update_in([:frames, :now], &(&1 |> Map.delete(:box) |> Map.put(:cell, [2, 0])))

    [{name, layer}]
  end

  @doc false
  # The pool the layers' one slot binds to.
  def sources do
    %{primary: [%{t: 0, v: 1}, %{t: 1, v: 4}, %{t: 2, v: 2}, %{t: 3, v: 3}]}
  end

  @doc false
  # The tree's rows for the fixture layers as the panel takes them (spec/14 §18.8, #380):
  # three objects at the top, none a group.
  def rows do
    for {name, _fragment} <- layers() do
      %{
        name: to_string(name),
        depth: 0,
        parent: nil,
        group?: false,
        count: 0,
        open?: false,
        kind: nil,
        id: nil,
        state: :inline
      }
    end
  end

  @doc false
  # A stack that does not apply: the panel layer without the two layers under it, so its
  # mark names a source and a style nothing declares — the normal state of a design being
  # built, and what the preview lists by path.
  def incomplete do
    [
      {:panel,
       %{
         version: 2,
         frames: %{main: %{kind: :cartesian}},
         marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v}, style: :series}]
       }}
    ]
  end

  # A store with two entries listed, one of which the store no longer holds — the mask of
  # spec/14 §19.2 — so the builder's library under test has both a hit and a miss.
  defmodule Library do
    @moduledoc false
    @behaviour Visualize.Chart.Builder.Store

    # A baseline chart is a composite of one frame site: design is not a kind (§19.8).
    @baseline {:composite, 1}
    @missing {:composite, 2}

    def baseline_id, do: @baseline
    def missing_id, do: @missing

    @impl true
    def list(_context) do
      [
        %{id: @baseline, name: "baseline", kind: :composite},
        %{id: @missing, name: "missing", kind: :composite}
      ]
    end

    @impl true
    def get(@baseline, _context) do
      {:ok,
       %{
         id: @baseline,
         name: "baseline",
         kind: :composite,
         fragment: %{
           composite: %{
             uses: [
               %Visualize.Chart.Use{
                 id: {:use, 1},
                 ref: nil,
                 local: %{frames: %{main: %{kind: :cartesian}}}
               }
             ],
             vars: %{}
           }
         }
       }}
    end

    def get(_id, _context), do: :error

    @impl true
    def put(%{id: nil}, _context), do: {:ok, {:composite, 3}}
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
      layers: {&Layers.panel/1, %{id: "b-layers", rows: rows()}},
      layers_disabled:
        {&Layers.panel/1, %{id: "b-layers", rows: rows(), selected: 2, disabled: MapSet.new([0])}},
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
           frames: %{main: %{margin: %{top: 640, bottom: 200}}},
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
           frames: %{main: %{axes: [%{scale: :x, side: :bottom, ticks: Chart.var(:ticks)}]}},
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

  # -- every form carries an id (spec/10 §15.3, #444, #461) --------------------------------
  #
  # LiveView's own check — "Detected a form with phx-change but missing id", and its
  # duplicate-id check — runs only as `Phoenix.LiveViewTest` parses a page driven through
  # `live/2` or `live_isolated/3`. `render_component/2` returns a string nothing parses, so
  # the library's suite can never see either warning; these hold the rules instead.

  @doc false
  # The opening tags of the rendered forms that LiveView recovers or submits and that carry
  # no id.
  def forms_without_id(html) do
    for [tag] <- Regex.scan(~r/<form\b[^>]*>/, html),
        tag =~ ~r/\sphx-(change|submit)="/,
        not (tag =~ ~r/\sid="[^"]+"/),
        do: tag
  end

  @doc false
  # Every id that appears more than once in one rendered page.
  def duplicate_ids(html) do
    ~r/\sid="([^"]*)"/
    |> Regex.scan(html, capture: :all_but_first)
    |> List.flatten()
    |> Enum.frequencies()
    |> Enum.filter(fn {_id, count} -> count > 1 end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.sort()
  end

  @doc false
  # The opening tag of every `<form` the library's source writes in a template, read up to
  # the `>` that closes it outside any `{…}` expression, with its file — so a form no
  # rendered state reaches is held too. A form named in a doc (after a backtick) is not one.
  def source_forms(root \\ "lib") do
    for path <- Path.wildcard(Path.join(root, "**/*.ex")),
        source = File.read!(path),
        {at, _} <- :binary.matches(source, "<form"),
        :binary.at(source, at + 5) in [?\s, ?\n],
        at == 0 or :binary.at(source, at - 1) != ?`,
        tag = open_tag(binary_part(source, at, byte_size(source) - at), 0, ""),
        do: {path, tag}
  end

  defp open_tag(<<?>, _::binary>>, 0, acc), do: acc <> ">"
  defp open_tag(<<?{, rest::binary>>, depth, acc), do: open_tag(rest, depth + 1, acc <> "{")
  defp open_tag(<<?}, rest::binary>>, depth, acc), do: open_tag(rest, depth - 1, acc <> "}")

  defp open_tag(<<c::utf8, rest::binary>>, depth, acc),
    do: open_tag(rest, depth, acc <> <<c::utf8>>)

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
    {host, state} = Keyword.split(opts, [:store, :sources, :vars, :theme, :on_save, :on_deploy])

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
    |> Stack.all()
    |> Enum.map(&{&1.use, &1.index})
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
  # The names of every row of the tree, in flat order (spec/14 §18.8, #380).
  def names(%Socket{assigns: assigns}) do
    for %{use: use} <- Stack.all(assigns.uses), do: atomised(Stack.label(assigns.labels, use))
  end

  @doc """
  An empty object of a kind put after the selected site, as a library drop of an empty
  fragment would put it (spec/14 §18.17): what the `+` menu of #209 did, for tests that
  need a site of a kind without a store.
  """
  def with_object(%Socket{assigns: assigns} = socket, kind, label \\ nil) do
    use = %{Visualize.Chart.Use.new(nil, assigns.uses) | ref: nil, local: Stack.empty(kind)}

    Phoenix.Component.assign(socket,
      uses: Stack.insert(assigns.uses, assigns.selected, use),
      labels: Map.put(assigns.labels, use.id, label || "new #{kind}"),
      selected: use.id,
      node_label: "design",
      facet: nil,
      field: nil,
      context: :inspect,
      notice: nil
    )
  end

  @doc "The `style` value at the selected layer's first mark."
  def style_at(socket) do
    {_name, fragment} = socket |> layers() |> Enum.at(selected(socket))
    fragment |> Map.fetch!(:marks) |> hd() |> Map.get(:style)
  end

  @doc "A fragment's id under the fixture Library, for tests that click or drop it."
  def encoded(id), do: Store.encode_id(id)
end
