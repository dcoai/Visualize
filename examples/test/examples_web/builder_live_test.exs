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
      assert Library.id_of(name) != nil
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

  describe "a chart type is a template in the library (spec/14 §18.16, #233)" do
    alias Examples.Charts.Templates

    test "every gallery design and every preset without one is a Charts:: entry" do
      names = Enum.map(Templates.all(), & &1.name)

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
        assert Library.id_of(name) != nil, "#{name} is not in the library"

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
end
