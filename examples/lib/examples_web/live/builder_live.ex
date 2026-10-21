defmodule ExamplesWeb.BuilderLive do
  @moduledoc """
  The chart builder page (#54): `Visualize.Chart.Builder` embedded in a host LiveView over a
  fixed stack of three fragments (spec/14 §18).

  The page is the host of the contract: it owns the route, the layers the builder starts
  with, the pool of sample sources the preview binds to, and the library — a tiny in-memory
  `Visualize.Chart.Builder.Store` — and it handles the one message the builder sends,
  `{:design_saved, id, structure}` and `{:design_deployed, id, design}` — keeping the one
  and applying the other. Nothing else crosses the boundary.

  The page starts the builder over three entries of its own library — a house design, a
  shared frame and a panel — as uses referring to them, so every row names something the
  library holds (spec/14 §19.9). A host may still seed bare fragments (§18.1, D-95); this
  one has a library, so it uses it.
  """
  use Phoenix.LiveView

  alias Visualize.Chart

  defmodule Library do
    @moduledoc """
    A `Visualize.Chart.Builder.Store` over `:persistent_term`, so the page can offer a
    library without a database (spec/14 §19.7). A real host keeps its entries wherever it
    keeps anything; this one keeps a map of id to entry and one counter per kind, and
    ignores the context because a demo page has nobody to attribute a save to.

    Ids are `{kind, n}`, issued here and never reused (§19.2, D-100): the counter only ever
    goes up, so a deleted entry's id stays vacant and a reference to it is a mask.
    """
    @behaviour Visualize.Chart.Builder.Store

    alias Visualize.Chart.Builder.Store
    alias Visualize.Chart.Fragment

    @key {__MODULE__, :library}

    @impl true
    def list(_context) do
      for {id, entry} <- entries(), do: %{id: id, name: entry.name, kind: entry.kind}
    end

    @impl true
    def get(id, _context) do
      case Map.fetch(entries(), id) do
        {:ok, entry} -> {:ok, Map.put(entry, :id, id)}
        :error -> :error
      end
    end

    # A map that is many things is no kind of fragment and is refused (spec/14 §19.8): the
    # thing that is many kinds is a composite, and the page seeds its own that way.
    @impl true
    def put(%{id: nil} = entry, context) do
      case Fragment.kind(entry.fragment) do
        nil -> {:error, :many_kinds}
        kind -> put(%{entry | id: {kind, next(kind)}, kind: kind}, context)
      end
    end

    def put(%{id: id} = entry, _context) do
      case Fragment.kind(entry.fragment) do
        nil ->
          {:error, :many_kinds}

        kind ->
          %{entries: entries, counters: counters} = state()
          stored = %{name: entry.name, kind: kind, fragment: entry.fragment}
          :persistent_term.put(@key, %{entries: Map.put(entries, id, stored), counters: counters})
          {:ok, id}
      end
    end

    @impl true
    def delete(id, _context) do
      %{entries: entries, counters: counters} = state()
      :persistent_term.put(@key, %{entries: Map.delete(entries, id), counters: counters})
      :ok
    end

    @impl true
    def import(bundle, context), do: Store.relocate(bundle, context, &put/2)

    # A per-kind sequence that only goes up.
    defp next(kind) do
      %{entries: entries, counters: counters} = state()
      n = Map.get(counters, kind, 0) + 1
      :persistent_term.put(@key, %{entries: entries, counters: Map.put(counters, kind, n)})
      n
    end

    defp entries, do: state().entries

    # The seeded library on first use. Names carry their place in the tree
    # (spec/14 §18.16); every fragment names what this page's stack declares, so adding
    # any of them changes something visible. The state is built whole and written once,
    # so a seed that fails leaves no half-seeded library behind for the BEAM's lifetime
    # (#272); a seed the page itself wrote and cannot store is a bug in the page, and says so.
    defp state do
      case :persistent_term.get(@key, nil) do
        nil ->
          seeded =
            Enum.reduce(seeds(), %{entries: %{}, counters: %{}}, fn {name, fragment}, state ->
              case Fragment.kind(fragment) do
                nil ->
                  raise ArgumentError, "the seed #{inspect(name)} is no one kind of fragment"

                kind ->
                  n = Map.get(state.counters, kind, 0) + 1
                  stored = %{name: name, kind: kind, fragment: fragment}

                  %{
                    entries: Map.put(state.entries, {kind, n}, stored),
                    counters: Map.put(state.counters, kind, n)
                  }
              end
            end)

          seeded = with_board(seeded)
          :persistent_term.put(@key, seeded)
          seeded

        state ->
          state
      end
    end

    # The `/board` page's board (spec/15 §10, spec/14 §22, D-152): its twelve components
    # seeded as `Boards::` composites, and the board itself with its cells' refs moved onto
    # the ids the seeding just issued, so opening it is the board mode. The `/board` page's
    # binding is the host's and is given to the builder as `board_bindings`, never stored.
    defp with_board(%{entries: entries, counters: counters}) do
      id = fn name ->
        Enum.find_value(entries, fn {id, entry} -> entry.name == name and id end) ||
          raise ArgumentError, "the board's component #{inspect(name)} is not seeded"
      end

      refs = Map.new(board_components(), fn {name, demo_id, _design} -> {demo_id, id.(name)} end)
      demo = Examples.BoardDemo.value()
      cells = Map.new(demo.cells, fn {name, cell} -> {name, %{cell | ref: refs[cell.ref]}} end)

      stored = %{
        name: "Boards::live board",
        kind: :board,
        fragment: %{board: Visualize.Board.to_map(%{demo | cells: cells})}
      }

      %{entries: Map.put(entries, {:board, 1}, stored), counters: Map.put(counters, :board, 1)}
    end

    # The `/board` page's components, each with the id the demo's own store gives it.
    defp board_components do
      store = Examples.BoardDemo.store()

      for {name, demo_id} <- [
            {"Boards::load", {:composite, 1}},
            {"Boards::wave", {:composite, 2}},
            {"Boards::metric", {:composite, 3}},
            {"Boards::by service", {:composite, 4}},
            {"Boards::services", {:composite, 5}},
            {"Boards::hosts", {:composite, 7}},
            {"Boards::weather", {:composite, 8}},
            {"Boards::latency", {:composite, 9}},
            {"Boards::status", {:composite, 10}},
            {"Boards::colored", {:composite, 12}},
            {"Boards::links", {:composite, 13}},
            {"Boards::wave bins", {:composite, 14}}
          ],
          do: {name, demo_id, Map.fetch!(store, demo_id)}
    end

    @doc "The id of the entry with a name, for a page that starts from its own library."
    def id_of(name) do
      Enum.find_value(list(nil), fn entry -> entry.name == name and entry.id end) ||
        raise ArgumentError,
              "the library holds no entry named #{inspect(name)}; it holds " <>
                inspect(list(nil) |> Enum.map(& &1.name) |> Enum.sort())
    end

    defp composite(document) do
      {uses, _labels} = Visualize.Chart.Composite.decompose(document)
      %{composite: %{uses: uses, vars: %{}}}
    end

    defp house,
      do: %{
        version: 2,
        meta: %{name: "Uptime"},
        theme: :default,
        styles: %{series: %{stroke: :series_1, stroke_width: 2, curve: :monotone_x}},
        frames: %{
          main: %{
            kind: :cartesian,
            margin: %{top: 24, right: 24, bottom: 32, left: 48}
          }
        }
      }

    defp shared,
      do: %{
        sources: %{primary: %{fields: [:hour, :value]}},
        frames: %{
          main: %{
            scales: %{
              hour: %{kind: :linear, domain: :auto},
              value: %{kind: :linear, domain: [0, :auto], nice: true}
            },
            axes: [
              %{scale: :hour, side: :bottom, ticks: 6},
              %{scale: :value, side: :left, ticks: 5, grid: true}
            ]
          }
        }
      }

    defp panel,
      do: %{
        vars: %{unit: %{default: "%"}},
        marks: [
          %{
            id: :series,
            type: :line,
            data: :primary,
            channels: %{x: :hour, y: :value},
            scales: %{x: :hour, y: :value},
            style: :series
          }
        ],
        labels: [%{id: :title, anchor: :title, text: ["Uptime — ", Chart.var(:unit)]}]
      }

    # Warm paper, ink and a serif face; the ramps and roles are the default's, so the meaning
    # holds and only the tones are the house's.
    defp house_theme do
      Visualize.Theme.new(
        name: :house,
        series: ~w(#2f5d8a #b5651d #a23b3b #3d7a6f #5b7f2e #8a6d1f #6d4f86 #a14d73),
        background: "#fbfaf6",
        surface: "#f1ede3",
        text: "#2b2924",
        axis: "#5f5a50",
        grid: "#e2dccf",
        font_family: "Georgia, serif"
      )
    end

    # The three hand-written maps are decomposed into composites of sites, one kind each
    # (spec/14 §18.12, §19.8): a map that is many things is not a fragment.
    defp seeds do
      [
        {"Uptime::house", composite(house())},
        {"Uptime::shared", composite(shared())},
        {"Uptime::panel", composite(panel())},
        {"Theme::dark", %{theme: :dark}},
        # A host's own theme, shipped as a value (spec/14 §9.3, D-139): a design that says
        # `theme: :house` previews in it, and opening it is the theme mode.
        {"Theme::house", Visualize.Chart.Theme.fragment(house_theme())},
        {"Frame:axes:no grid",
         %{frames: %{main: %{axes: [%{scale: :value, side: :left, grid: false}]}}}},
        {"Frame:axes:dense ticks",
         %{
           frames: %{
             main: %{
               axes: [
                 %{scale: :hour, side: :bottom, ticks: 12},
                 %{scale: :value, side: :left, ticks: 10}
               ]
             }
           }
         }},
        {"Frame:margin:wide", %{frames: %{main: %{margin: %{top: 900, bottom: 320}}}}},
        {"Frame:margin:roomy",
         %{frames: %{main: %{margin: %{top: 40, right: 40, bottom: 48, left: 64}}}}},
        # Bodies, not declarations: the composite says the name a style is declared under
        # (spec/14 §19.3), so a body serves any chart, whatever it calls its style.
        {"Styles::thick line", %{style: %{stroke_width: 5}}},
        {"Styles::stepped", %{style: %{curve: :step}}}
      ] ++ templates() ++ boards()
    end

    # The `/board` page's components, so its board opens over them (spec/14 §22).
    defp boards, do: for({name, _id, design} <- board_components(), do: {name, composite(design)})

    # A chart type is a template (spec/14 §18.16, #233): every gallery design and every
    # preset without one, as a composite under Charts::<title>.
    defp templates do
      for template <- Examples.Charts.Templates.all(),
          do: {template.name, composite(template.design)}
    end
  end

  defp rows do
    for hour <- 0..23,
        do: %{hour: hour, value: Float.round(92 + 6 * :math.sin(hour / 3.5), 2)}
  end

  # The connector catalog (spec/14 §22.8): the `/board` page's feeds, each by the name its
  # binding uses, to the schema its `describe` answers. A feed that cannot describe itself
  # now is left out of the catalog rather than offered blind.
  defp catalog do
    for {name, feed} <- Examples.BoardDemo.feeds(),
        {_version, schema, _capabilities} <- [Visualize.Feed.describe(feed)],
        into: %{},
        do: {name, schema}
  end

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       layers: Enum.map(~w(Uptime::house Uptime::shared Uptime::panel), &{&1, Library.id_of(&1)}),
       sources: Map.merge(Examples.Charts.Templates.pool(), %{primary: rows()}),
       catalog: catalog(),
       bindings: %{Library.id_of("Boards::live board") => Examples.BoardDemo.slots()},
       saved: nil
     )}
  end

  # The builder's two outputs (spec/14 §19.6). Save sends the structure — the stack of
  # sites — which a host keeps as what was built; this page only says how many sites it
  # holds. Deploy sends the flat design, and the host decides what deploying means — here,
  # applying it and reporting whether it drew.
  def handle_info({:design_saved, _id, %{composite: %{uses: uses}}}, socket) do
    {:noreply, assign(socket, :saved, "saved: a structure of #{length(uses)} site(s)")}
  end

  # A binding the builder made (spec/14 §22.8): the host's, kept by the board's id so the
  # board opens with it again, and never part of the board.
  def handle_info({:board_bound, _id, board_id, binding}, socket) do
    {:noreply,
     socket
     |> update(:bindings, &Map.put(&1, board_id, binding))
     |> assign(:saved, "bound: #{map_size(binding.slots)} slot(s) of the board to feeds")}
  end

  # The signals' tick (spec/14 §18.2): the builder schedules it here, the page forwards it.
  def handle_info({:visualize_chart_tick, id}, socket) do
    {:noreply, Visualize.Chart.Builder.tick(id, socket)}
  end

  def handle_info({:design_deployed, _id, design}, socket) do
    result =
      case Chart.apply(design, sources: socket.assigns.sources) do
        {:ok, _applied} ->
          "deployed: the design applies"

        {:error, errors} ->
          "not deployed: " <> Enum.map_join(errors, "; ", &Chart.Validator.format/1)
      end

    {:noreply, assign(socket, :saved, result)}
  end

  def render(assigns) do
    ~H"""
    <ExamplesWeb.SiteHeader.header tab={:builder} />
    <p class="builder-notice" role="note">
      <strong>In development:</strong>
      the Chart Builder is not fully functional and is likely far from its final form.
    </p>
    <div class="page-intro builder-intro">
      <h2>Chart builder</h2>
      <p>
        <code>Visualize.Chart.Builder</code>
        over three entries of this page's library — a house design, a shared frame and a
        panel — beside a template for every chart of the gallery under <em>Charts</em>. Click
        an entry to open it, drag one into the stack, edit a node, bind a variable, mask a
        key; <em>Save</em>
        keeps the structure and <em>Deploy</em>
        hands the page the flat
        design.
      </p>
      <p>
        <em>Theme</em>
        on the chart bar, a <em>Theme::</em>
        entry, or <em>New → theme</em>
        opens the theme mode: the theme's colors and fonts beside a sheet of sample charts
        drawn in it.
      </p>
      <p>
        <em>Boards::live board</em>
        or <em>New → board</em>
        opens the board mode: cells on a 12-column grid, dragged to place and resized by
        their edges, each a chart of the library, its sources bound to the feeds of the
        <a href="/board">live board</a>
        page — this page's connector catalog — and previewed
        over rows shaped like theirs; <em>Edit component</em>
        opens a cell's chart, and <em>Back to board</em>
        returns to the board.
      </p>
      <p :if={@saved} class="builder-saved">{@saved}</p>
    </div>
    <main>
      <.live_component
        module={Visualize.Chart.Builder}
        id="builder"
        layers={@layers}
        sources={@sources}
        store={Library}
        on_save={:design_saved}
        on_deploy={:design_deployed}
        catalog={@catalog}
        virtual_sources={[Examples.BoardDemo.Sources]}
        board_bindings={@bindings}
        on_bind={:board_bound}
      />
    </main>
    """
  end
end
