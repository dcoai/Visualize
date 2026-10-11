defmodule Visualize.Chart.BuilderThemeTest do
  @moduledoc """
  Themes in the builder (spec/14 §2.5, §9.3, D-139): a theme stored in the library as a
  value, found by the name a design gives it.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Visualize.BuilderFixture
  alias Visualize.Chart.Builder
  alias Visualize.Chart.Builder.{Stack, Themes, ThemeSheet}
  alias Visualize.Theme

  doctest Visualize.Chart.Builder.Themes
  doctest Visualize.Chart.Builder.ThemeSheet

  # A library holding one host theme, shipped as a value.
  defmodule Looks do
    @moduledoc false
    @behaviour Visualize.Chart.Builder.Store

    @house Theme.new(name: :house, axis: "#5a4a3a", text: "#2b2924")

    def house, do: @house

    @impl true
    def list(_context) do
      [
        %{id: {:theme, 1}, name: "Looks::house", kind: :theme},
        %{id: {:composite, 1}, name: "Charts::uptime", kind: :composite}
      ]
    end

    @impl true
    def get({:theme, 1}, _context) do
      {:ok,
       %{
         id: {:theme, 1},
         name: "Looks::house",
         kind: :theme,
         fragment: Visualize.Chart.Theme.fragment(@house)
       }}
    end

    def get({:composite, 1}, _context) do
      {uses, _labels} =
        Visualize.Chart.Composite.decompose(Visualize.Chart.stack(BuilderFixture.layers()))

      {:ok,
       %{
         id: {:composite, 1},
         name: "Charts::uptime",
         kind: :composite,
         fragment: %{composite: %{uses: uses, vars: %{}}}
       }}
    end

    def get(_id, _context), do: :error

    @impl true
    def put(%{id: id}, _context), do: {:ok, id || {:theme, 2}}

    @impl true
    def delete(_id, _context), do: :ok

    @impl true
    def import(_bundle, _context), do: {:error, :read_only}
  end

  defp named(theme) do
    [{:house, house}, shared, panel] = BuilderFixture.layers()
    [{:house, %{house | theme: theme}}, shared, panel]
  end

  describe "a design that names a stored theme (spec/14 §2.5, D-139)" do
    test "previews in the store's theme" do
      html = named(:house) |> BuilderFixture.socket(store: Looks) |> BuilderFixture.render()

      assert html =~ "#5a4a3a"
      assert html =~ "vis-builder-chart"
    end

    test "a built-in name is the built-in theme, whatever the store holds" do
      html = named(:dark) |> BuilderFixture.socket(store: Looks) |> BuilderFixture.render()

      assert html =~ Theme.dark().axis
      refute html =~ "#5a4a3a"
    end

    test "the host's theme still wins" do
      host = Theme.new(axis: "#123456")

      html =
        named(:house)
        |> BuilderFixture.socket(store: Looks, theme: host)
        |> BuilderFixture.render()

      assert html =~ "#123456"
      refute html =~ "#5a4a3a"
    end
  end

  # -- the theme mode (spec/14 §20) ------------------------------------------------------

  defp event(socket, name, params \\ %{}) do
    {:noreply, socket} = Builder.handle_event(name, params, socket)
    socket
  end

  defp edit(socket, field, value),
    do: event(socket, "theme_edit", %{"_target" => [field], field => value})

  # The theme the open theme chart holds, as the editor writes it.
  defp theme_node(socket) do
    %{uses: uses, selected: selected} = socket.assigns
    Themes.site(uses, selected).local.theme
  end

  defp new_theme do
    BuilderFixture.layers()
    |> BuilderFixture.socket(store: Looks)
    |> event("new_fragment", %{"kind" => "theme"})
  end

  describe "entering the mode (spec/14 §20.1)" do
    test "New → theme opens a theme chart in the mode: the editor and the sheet, no node form" do
      socket = new_theme()
      assert socket.assigns.open.kind == :theme

      html = BuilderFixture.render(socket)
      assert html =~ ~s(class="vis-builder-theme-panel")
      assert html =~ ~s(class="vis-builder-theme-sheet")
      refute html =~ ~s(class="vis-builder-inspect")
      refute html =~ "has no chart to look at"

      for %{id: id} <- ThemeSheet.samples(), do: assert(html =~ ~s(data-sample="#{id}"))
    end

    test "a composite chart is not in the mode, and offers Theme on its bar" do
      html =
        BuilderFixture.layers() |> BuilderFixture.socket(store: Looks) |> BuilderFixture.render()

      refute html =~ "vis-builder-theme-panel"
      assert html =~ ~s(class="vis-builder-theme-open")
    end

    test "Theme opens the chart's own built-in theme as a new theme of its whole node" do
      socket =
        BuilderFixture.layers() |> BuilderFixture.socket(store: Looks) |> event("open_theme")

      assert socket.assigns.open == %{id: nil, name: nil, kind: :theme}
      assert theme_node(socket) == Visualize.Chart.Theme.node(Theme.default())
      assert length(socket.assigns.charts) == 2
    end

    test "Theme opens the stored entry when the design names a stored theme" do
      [{:house, house}, shared, panel] = BuilderFixture.layers()

      socket =
        [{:house, %{house | theme: :house}}, shared, panel]
        |> BuilderFixture.socket(store: Looks)
        |> event("open_theme")

      assert socket.assigns.open == %{id: {:theme, 1}, name: "Looks::house", kind: :theme}
      assert Themes.effective(theme_node(socket), Looks) == Looks.house()
    end

    test "opening a theme entry from the library is the mode" do
      socket =
        BuilderFixture.layers()
        |> BuilderFixture.socket(store: Looks)
        |> event("add_layer", %{"name" => "theme:1"})

      assert socket.assigns.open.kind == :theme
      assert BuilderFixture.render(socket) =~ "vis-builder-theme-panel"
    end
  end

  describe "the editor (spec/14 §20.2)" do
    test "a chrome colour, a series colour, the name and a font write the theme node" do
      socket =
        new_theme()
        |> edit("axis", "#aa0000")
        |> edit("series.2", "#00aa00")
        |> edit("name", "night")
        |> edit("font_family", "Georgia, serif")
        |> edit("title_size", "20")

      theme = Themes.effective(theme_node(socket), nil)
      assert theme.axis == "#aa0000"
      assert Enum.at(theme.series, 2) == "#00aa00"
      assert theme.name == :night
      assert theme.font_family == "Georgia, serif"
      assert theme.title_size == 20
    end

    test "a value that does not read leaves the theme as it was" do
      socket = new_theme() |> edit("axis", "#aa0000")
      before = theme_node(socket)

      for {field, value} <- [
            {"axis", "not a colour"},
            {"font_size", "-3"},
            {"name", " "},
            {"series.99", "#000000"}
          ] do
        assert socket |> edit(field, value) |> theme_node() == before
      end
    end

    test "a built-in name becomes its whole node at the first edit" do
      socket = BuilderFixture.layers() |> BuilderFixture.socket(store: Looks)
      socket = event(socket, "add_layer", %{"name" => "theme:1"})
      [use] = socket.assigns.uses
      dark = %{use | local: %{theme: :dark}}

      socket =
        Phoenix.Component.assign(socket, uses: [dark], selected: dark.id)
        |> edit("grid", "#444444")

      assert theme_node(socket) == %{Visualize.Chart.Theme.node(Theme.dark()) | grid: "#444444"}
    end

    test "series colours are added and removed; the last one stays" do
      socket = new_theme() |> event("theme_series_add")
      assert length(Themes.effective(theme_node(socket), nil).series) == 11

      socket =
        Enum.reduce(1..12, socket, fn _, s ->
          event(s, "theme_series_remove", %{"index" => "0"})
        end)

      assert length(Themes.effective(theme_node(socket), nil).series) == 1
    end

    test "derive from takes every value of the theme and keeps the name" do
      socket =
        new_theme() |> edit("name", "night") |> event("theme_derive", %{"from" => "builtin:dark"})

      theme = Themes.effective(theme_node(socket), nil)

      assert theme.name == :night
      assert theme.background == Theme.dark().background
      assert theme.ramps == Theme.dark().ramps

      socket = event(socket, "theme_derive", %{"from" => "theme:1"})
      assert Themes.effective(theme_node(socket), nil).axis == Looks.house().axis
      assert Themes.effective(theme_node(socket), nil).name == :night

      socket = event(socket, "theme_derive", %{"from" => "builtin:nonsense"})
      assert socket.assigns.notice =~ "not a built-in theme"
    end

    test "the derive choices are the built-ins, then the store's themes" do
      assert Themes.derive_choices(Looks) == [
               {"default", "builtin:default"},
               {"dark", "builtin:dark"},
               {"colour_safe", "builtin:colour_safe"},
               {"Looks::house", "theme:1"}
             ]
    end

    test "a theme site that refers to the library is read-only" do
      socket = new_theme()
      [use] = socket.assigns.uses
      locked = %{use | ref: {:theme, 1}}
      socket = Phoenix.Component.assign(socket, uses: [locked]) |> edit("axis", "#aa0000")

      assert socket.assigns.notice =~ "is from the library"
    end

    test "a valid theme says it can be saved, and Save to library keeps it" do
      socket = new_theme() |> edit("name", "night")
      assert BuilderFixture.render(socket) =~ "a valid theme"

      socket = event(socket, "put_design", %{"name" => "Looks::night"})
      assert socket.assigns.notice == nil
      assert socket.assigns.open.id == {:theme, 2}
    end
  end

  describe "the preview sheet (spec/14 §20.3)" do
    test "draws every sample through the theme being edited" do
      socket = new_theme() |> edit("background", "#102030") |> edit("series.0", "#fe0000")
      html = BuilderFixture.render(socket)

      # Every sample's frame paints the edited background, and the series sample draws in
      # the edited first colour; literals only, so no stylesheet re-points a slot.
      assert length(String.split(html, ~s(fill="#102030"))) - 1 >= length(ThemeSheet.samples())
      assert html =~ ~s(stroke="#fe0000")
      sheet = html |> String.split("vis-builder-theme-sheet") |> Enum.at(1)
      refute sheet =~ "var(--vis-"
    end

    test "the status sample is coloured by the five roles" do
      theme = Theme.colour_safe()
      html = render_component(&ThemeSheet.sheet/1, %{id: "s", theme: theme})

      for role <- Theme.role_names() do
        assert html =~ ~s(fill="#{Theme.resolve(theme, role, :literal)}"), inspect(role)
      end
    end

    test "a theme with an undrawable ramp still draws" do
      theme = %{Theme.default() | ramps: %{thermal: ["#nope", "#ffffff"]}, series: []}
      html = render_component(&ThemeSheet.sheet/1, %{id: "s", theme: theme})

      refute html =~ "vis-builder-error"
      assert html =~ ~s(data-sample="thermal")
    end

    test "a design from the store is added to the sheet, drawn in the theme, and taken off" do
      socket = new_theme() |> edit("axis", "#aa0000")
      html = BuilderFixture.render(socket)
      assert html =~ ~s(<option value="composite:1">Charts::uptime</option>)

      socket = event(socket, "theme_design_add", %{"id" => "composite:1"})
      html = BuilderFixture.render(socket)
      assert html =~ ~s(data-sample="composite:1")
      assert html =~ "Charts::uptime"

      socket = event(socket, "theme_design_remove", %{"id" => "composite:1"})
      refute BuilderFixture.render(socket) =~ ~s(data-sample="composite:1")
    end

    test "every sample applies under every built-in theme" do
      for theme <- [Theme.default(), Theme.dark(), Theme.colour_safe()],
          %{design: design, sources: sources, title: title} <- ThemeSheet.samples() do
        assert {:ok, _applied} = Visualize.Chart.apply(design, sources: sources, theme: theme),
               title
      end
    end
  end

  test "the stack of a theme chart is one inline theme site" do
    socket = new_theme()
    assert [%{ref: nil, local: %{theme: %{}}}] = socket.assigns.uses
    assert Stack.kinds() |> Enum.member?(:theme)
  end
end
