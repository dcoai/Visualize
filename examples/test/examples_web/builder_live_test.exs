defmodule ExamplesWeb.BuilderLiveTest do
  @moduledoc """
  The builder page starts from its own library (spec/14 §19.9): every row names an entry,
  the two verbs report differently, and the drag diagnostics are gone.
  """
  use ExUnit.Case, async: true

  import Phoenix.ConnTest

  alias ExamplesWeb.BuilderLive
  alias ExamplesWeb.BuilderLive.Library
  alias Phoenix.LiveView.Socket
  alias Visualize.Chart

  @endpoint ExamplesWeb.Endpoint

  setup do
    {:ok, _} = Application.ensure_all_started(:examples)
    :ok
  end

  test "every row on the start screen names a library entry" do
    html = build_conn() |> get("/builder") |> html_response(200)

    for name <- ~w(Uptime::house Uptime::shared Uptime::panel) do
      assert html =~ ~s(<span class="vis-builder-layer-name">#{name}</span>)
      # `id_of/1` raises for a name the library lacks; a tagged id is what it returns.
      assert {_kind, n} = Library.id_of(name)
      assert is_integer(n)
    end

    refute html =~ "drag diagnostics"
    refute html =~ "builder-diagnostics"

    # The library is seeded whole, and a name it does not hold is a named failure rather
    # than a nil layer (#272).
    names = Library.list(nil) |> Enum.map(& &1.name)
    assert Enum.all?(~w(Uptime::house Uptime::shared Uptime::panel Theme::dark), &(&1 in names))

    assert_raise ArgumentError, ~r/holds no entry named "nope"; it holds \[/, fn ->
      Library.id_of("nope")
    end

    assert html =~ ~s(<button type="submit" class="vis-builder-new-submit">New</button>)
    assert html =~ ~s(class="vis-builder-deploy")
  end

  describe "the theme mode (spec/14 §20, D-139)" do
    alias Examples.Charts.Templates
    alias Visualize.Chart.Builder.Themes

    test "the page offers it, and the library ships a host theme as a value" do
      html = build_conn() |> get("/builder") |> html_response(200)

      assert html =~ ~s(class="vis-builder-theme-open")
      assert html =~ "In development:"

      assert {:ok, %Visualize.Theme{name: "house"}} =
               Visualize.Chart.Builder.Store.theme(Library, :house)
    end

    test "a theme made in the builder renders every gallery chart" do
      {:ok, dark} = Themes.derive_source("builtin:dark", Library)

      node =
        Enum.reduce(
          [{"axis", "#c0c4cc"}, {"series.0", "#ffb000"}, {"font_family", "Georgia, serif"}],
          Themes.derived(%{name: :night}, dark),
          fn {field, value}, node ->
            {:ok, node} = Themes.change(node, field, value)
            node
          end
        )

      theme = Themes.effective(node, Library)
      assert theme.name == "night" and theme.axis == "#c0c4cc"
      pool = Templates.pool()

      for template <- Templates.all() do
        assert {:ok, applied} = Chart.apply(template.design, sources: pool, theme: theme),
               template.name

        assert Chart.render(applied, resolve: :literal) =~ "<", template.name
      end
    end
  end

  describe "a chart type is a template in the library (spec/14 §18.16, #233)" do
    alias Examples.Charts.Templates

    test "every gallery design and every preset without one is a Charts:: entry" do
      names = Enum.map(Templates.all(), & &1.name)

      # Composition among them: the builder holds a design-level `defaults` and a list-
      # valued style (#713).
      for module <- Templates.gallery_modules() do
        assert "Charts::#{module.title()}" in names
      end

      assert "Charts::Tree Diagram" in names and "Charts::Treemap" in names
      assert Enum.sort(Enum.uniq(names)) == Enum.sort(names)

      # The presets stand in only while the gallery has no design of that title.
      drawn = Enum.map(Templates.gallery_modules(), & &1.title())
      refute "Tree Diagram" in drawn

      html = build_conn() |> get("/builder") |> html_response(200)

      for name <- names do
        assert {_kind, _n} = Library.id_of(name)

        assert html =~
                 ~s(<span class="vis-builder-fragment">#{String.replace(name, "Charts::", "")}</span>)
      end
    end

    test "each template is one kind per site, flattens back to its design, and binds the pool" do
      pool = Templates.pool()

      for template <- Templates.all() do
        assert Chart.Validator.validate(template.design) == :ok, template.name
        {:ok, entry} = Library.get(Library.id_of(template.name), nil)

        {:ok, flat, %{missing: [], keyless: []}} =
          Chart.flatten(entry.fragment, fn _ -> :error end)

        assert Map.delete(flat, :version) == Map.delete(template.design, :version), template.name

        # Its sources are named for it and every one binds from the pool.
        for name <- Map.keys(template.design.sources) do
          assert String.starts_with?(to_string(name), "#{template.slug}_"),
                 "#{template.name}: #{name}"

          assert Map.has_key?(pool, name)
        end

        {:ok, chart} = Chart.from_map(template.design)
        assert {:ok, applied} = Chart.apply(chart, sources: pool), template.name
        svg = Chart.render(applied)

        for %{type: type} <- template.design.marks do
          assert svg =~ ~s(class="mark mark-#{type}"), "#{template.name} drew no #{type}"
        end
      end
    end

    test "the page's pool is every template's rows beside its own" do
      {:ok, socket} = BuilderLive.mount(%{}, %{}, %Socket{})
      assert Map.has_key?(socket.assigns.sources, :primary)

      for {name, rows} <- Templates.pool() do
        assert socket.assigns.sources[name] == rows
      end
    end
  end

  test "save keeps structure; deploy applies the design and says so" do
    {:ok, socket} = BuilderLive.mount(%{}, %{}, %Socket{})

    structure = %{
      composite: %{
        uses: Enum.map(socket.assigns.layers, fn {_name, id} -> Chart.Use.new(id) end),
        vars: %{}
      }
    }

    {:noreply, saved} = BuilderLive.handle_info({:design_saved, "b", structure}, socket)
    assert saved.assigns.saved == "saved: a structure of 3 site(s)"

    fetch = fn id ->
      case Library.get(id, nil) do
        {:ok, entry} -> {:ok, entry.fragment}
        :error -> :error
      end
    end

    {:ok, design, %{missing: []}} = Chart.flatten(structure, fetch)
    {:noreply, deployed} = BuilderLive.handle_info({:design_deployed, "b", design}, socket)
    assert deployed.assigns.saved == "deployed: the design applies"
  end

  describe "the board mode (spec/14 §22, D-152)" do
    alias Visualize.Chart.Builder.Stack

    test "the page tells of it, and the library holds a board over gallery charts" do
      html = build_conn() |> get("/builder") |> html_response(200)
      assert html =~ "opens the board mode"
      assert html =~ "In development:"
      assert html =~ ~s(<option value="board">board</option>)

      {:ok, entry} = Library.get(Library.id_of("Boards::live board"), nil)
      assert entry.kind == :board
      assert {:ok, board} = Visualize.Board.from_map(entry.fragment.board)
      assert Visualize.Board.validate(board, Stack.fetch(Library)) == :ok
    end

    # The builder over the page's own assigns, the board opened as a click on it opens it.
    defp board_mode do
      {:ok, page} = BuilderLive.mount(%{}, %{}, %Socket{})

      host =
        page.assigns
        |> Map.take([:layers, :sources, :catalog])
        |> Map.merge(%{
          id: "builder",
          store: Library,
          on_bind: :board_bound,
          board_bindings: page.assigns.bindings,
          virtual_sources: [Examples.BoardDemo.Sources]
        })

      {:ok, s} = Visualize.Chart.Builder.mount(%Socket{})
      {:ok, s} = Visualize.Chart.Builder.update(host, s)
      id = Visualize.Chart.Builder.Store.encode_id(Library.id_of("Boards::live board"))
      {:noreply, s} = Visualize.Chart.Builder.handle_event("add_layer", %{"name" => id}, s)
      {page, s}
    end

    test "the catalog is the /board page's feeds, and its binding opens the board" do
      {page, s} = board_mode()

      assert page.assigns.catalog |> Map.keys() |> MapSet.new() ==
               MapSet.new([
                 "examples.vm.memory",
                 "examples.vm.run_queue",
                 :dial,
                 :load,
                 :offline,
                 :wave,
                 :requests,
                 :errors,
                 :latest,
                 :hosts,
                 :weather,
                 :latency,
                 :status
               ])

      assert s.assigns.binding == Examples.BoardDemo.slots()

      mode = Visualize.Chart.Builder.Editing.editing(s.assigns).board_mode
      assert mode.catalog?
      assert map_size(mode.board.cells) == 13
      assert mode.faults == []

      # Every cell previews over rows shaped like its feed's, the hosts cell over the
      # fields the board's virtual sources join, which the builder runs (spec/14 §22.9).
      for cell <- mode.cells do
        assert {:ok, "<svg" <> _} = cell.preview, "#{cell.name}: #{inspect(cell.preview)}"
      end
    end

    test "a binding the builder makes is kept by the page, by the board's id" do
      {page, s} = board_mode()

      {:noreply, _s} =
        Visualize.Chart.Builder.handle_event(
          "board_bind",
          %{"_target" => ["slot.points"], "slot.points" => ""},
          Phoenix.Component.assign(s, :board_cell, "wave")
        )

      assert_received {:board_bound, "builder", board_id, binding}
      assert Visualize.Board.Binding.fetch(binding, :wave, :points) == :error

      {:noreply, page} =
        BuilderLive.handle_info({:board_bound, "builder", board_id, binding}, page)

      assert page.assigns.bindings[board_id] == binding
      assert page.assigns.saved =~ "bound: 13 slot(s)"
    end

    # A wrong binding is a fault panel, never a crash (spec/14 §18.4, §22.6, D-153): every
    # component of the library in a cell, its slots bound to each of the page's feeds in turn.
    test "any component binds to any feed without taking the builder down" do
      alias Visualize.Chart.Builder
      alias Visualize.Chart.Builder.{Boards, Editing, Store}
      require Phoenix.LiveViewTest

      {page, s} = board_mode()
      event = fn s, name, params -> elem(Builder.handle_event(name, params, s), 1) end

      s =
        Enum.reduce(Map.keys(s.assigns.board.cells) -- ["wave"], s, fn cell, s ->
          event.(s, "board_remove", %{"cell" => to_string(cell)})
        end)

      s = event.(s, "board_select", %{"cell" => "wave"})
      feeds = Map.keys(page.assigns.catalog)

      bind = fn s, feed ->
        slots = Editing.editing(s.assigns).board_mode.selected.slots

        Enum.reduce(slots, s, fn %{name: slot}, s ->
          key = "slot." <> slot
          event.(s, "board_bind", %{"_target" => [key], key => Boards.feed_key(feed)})
        end)
      end

      shown =
        for %{kind: :composite, id: id} <- Library.list(nil),
            s = event.(s, "board_cell", %{"_target" => ["ref"], "ref" => Store.encode_id(id)}),
            s.assigns.board.cells["wave"].ref == id,
            reduce: [] do
          shown ->
            {s, previews} =
              Enum.reduce(feeds, {s, []}, fn feed, {s, previews} ->
                s = bind.(s, feed)
                [cell] = Editing.editing(s.assigns).board_mode.cells
                {s, [elem(cell.preview, 0) | previews]}
              end)

            # The page draws, whatever the last binding was.
            html =
              s.assigns
              |> Map.drop([:__changed__, :flash, :myself])
              |> Map.put(:layers, Map.get(s.assigns, :host_layers, []))
              |> then(&Phoenix.LiveViewTest.render_component(Builder, &1))

            assert html =~ ~s(data-board-cell="wave")
            previews ++ shown
        end

      assert :fault in shown
      assert :ok in shown
    end
  end
end
