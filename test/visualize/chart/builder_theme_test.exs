defmodule Visualize.Chart.BuilderThemeTest do
  @moduledoc """
  Themes in the builder (spec/14 §2.5, §9.3, D-139): a theme stored in the library as a
  value, found by the name a design gives it.
  """
  use ExUnit.Case, async: true

  alias Visualize.BuilderFixture
  alias Visualize.Theme

  # A library holding one host theme, shipped as a value.
  defmodule Themes do
    @moduledoc false
    @behaviour Visualize.Chart.Builder.Store

    @house Theme.new(name: :house, axis: "#5a4a3a", text: "#2b2924")

    def house, do: @house

    @impl true
    def list(_context), do: [%{id: {:theme, 1}, name: "Looks::house", kind: :theme}]

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
      html = named(:house) |> BuilderFixture.socket(store: Themes) |> BuilderFixture.render()

      assert html =~ "#5a4a3a"
      assert html =~ "vis-builder-chart"
    end

    test "a built-in name is the built-in theme, whatever the store holds" do
      html = named(:dark) |> BuilderFixture.socket(store: Themes) |> BuilderFixture.render()

      assert html =~ Theme.dark().axis
      refute html =~ "#5a4a3a"
    end

    test "the host's theme still wins" do
      host = Theme.new(axis: "#123456")

      html =
        named(:house)
        |> BuilderFixture.socket(store: Themes, theme: host)
        |> BuilderFixture.render()

      assert html =~ "#123456"
      refute html =~ "#5a4a3a"
    end
  end
end
