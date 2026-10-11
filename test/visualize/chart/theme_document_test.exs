defmodule Visualize.Chart.ThemeDocumentTest do
  @moduledoc """
  A theme as a document (spec/14 §9.3, D-139): its map and JSON forms, stamped with the
  schema version and read back through the version gate, the limits, the migration,
  per-kind validity and the contracts, every fault in the validator's shape.
  """
  use ExUnit.Case, async: true

  alias Visualize.Chart.{Fragment, Validator}
  alias Visualize.Chart.Theme, as: Document
  alias Visualize.Theme

  doctest Visualize.Chart.Theme

  @house Theme.new(
           name: :house,
           series: ~w(#2f5d8a #b5651d #a23b3b),
           background: "#fbfaf6",
           font_family: "Georgia, serif",
           ramps: %{status: ~w(#5996d6 #cd6012 #b92931)},
           roles: %{info: "#2f5d8a"}
         )

  @themes [Theme.default(), Theme.dark(), Theme.colour_safe(), @house]

  describe "round trips" do
    test "every built-in theme and a host theme read back as themselves, in both forms" do
      for theme <- @themes do
        assert Document.from_map(Document.to_map(theme)) == {:ok, theme}
        assert {:ok, json} = Document.to_json(theme)
        assert Document.from_json(json) == {:ok, theme}
      end
    end

    test "the map form is stamped with the current version and holds every field" do
      %{version: version, theme: node} = Document.to_map(@house)
      assert version == Visualize.Chart.Migration.current()
      assert node.ramps == @house.ramps
      assert node.roles == @house.roles
      assert Map.keys(node) |> Enum.sort() == Map.keys(Map.from_struct(@house)) |> Enum.sort()
    end

    test "the JSON form is the stamped fragment document" do
      {:ok, json} = Document.to_json(@house)
      decoded = Jason.decode!(json)
      assert decoded["$version"] == Visualize.Chart.Migration.current()
      assert decoded["theme"]["name"] == "house"
      assert decoded["theme"]["ramps"]["status"] == ~w(#5996d6 #cd6012 #b92931)
    end

    test "the store's fragment is a theme fragment and reads as the current version" do
      fragment = Document.fragment(@house)
      assert Fragment.kind(fragment) == :theme
      assert Validator.validate(fragment, :theme) == :ok
      assert Document.from_map(fragment) == {:ok, @house}
    end

    test "a name reads as the built-in theme, any other name is not a theme" do
      assert Document.from_map(%{theme: :colour_safe}) == {:ok, Theme.colour_safe()}

      assert Document.from_map(%{theme: :house}) ==
               {:error, [{[:theme], {:unknown_theme, :house}}]}

      assert Validator.format({[:theme], {:unknown_theme, :house}}) =~
               "names the theme :house, which is not built-in"
    end

    test "a partial node names only what it changes; the rest is the default's" do
      {:ok, theme} = Document.from_map(%{theme: %{axis: "#111111"}})
      assert theme == Theme.new(axis: "#111111")
    end
  end

  describe "reading under the version policy (§9.1)" do
    test "a newer document is refused by name before a key is read" do
      assert Document.from_map(%{version: 3, theme: %{nonsense: 1}}) ==
               {:error, [{[:version], {:newer_schema, 3, 2}}]}

      assert Document.from_json(~s({"$version": 3, "theme": {"never_an_atom_4c1": 1}})) ==
               {:error, [{[:version], {:newer_schema, 3, 2}}]}
    end

    test "an older document migrates" do
      assert {:ok, theme} = Document.from_map(%{version: 1, theme: %{grid: "#dddddd"}})
      assert theme.grid == "#dddddd"

      assert {:ok, theme} = Document.from_json(~s({"$version": 1, "theme": {"grid": "#dddddd"}}))
      assert theme.grid == "#dddddd"
    end

    test "a version below one, or not an integer, is refused" do
      assert Document.from_map(%{version: 0, theme: %{}}) ==
               {:error, [{[:version], {:unsupported_version, 0}}]}

      assert Document.from_map(%{version: "2", theme: %{}}) ==
               {:error, [{[:version], {:type, :integer}}]}
    end

    test "the limits are applied to the document as given" do
      node = %{series: List.duplicate("#3b6fa8", 6)}

      assert Document.from_map(%{theme: node}, limits: [items: 5]) ==
               {:error, [{[:theme, :series], {:limit, :items, 5, 6}}]}

      {:ok, json} = Fragment.to_json(%{theme: node})

      assert {:error, [{path, {:limit, :items, 5, 6}}]} =
               Document.from_json(json, limits: [items: 5])

      assert Validator.format({path, {:limit, :items, 5, 6}}) =~ "theme.series"
    end
  end

  describe "validity and the contracts" do
    test "a ramp that breaks its contract is the contract fault at its path" do
      assert {:error, [{[:theme, :ramps, :status], {:contract, message}}]} =
               Document.from_map(%{theme: %{ramps: %{status: ~w(#c23238 #bd7407 #4ca34b)}}})

      assert message =~ "good (0) must be green or blue"
    end

    test "a variable is not a theme's: nothing applies a theme document" do
      assert Document.from_map(%{theme: %{axis: Visualize.Chart.var(:ink)}}) ==
               {:error, [{[:theme, :axis], {:unresolved, :var, :ink}}]}
    end

    test "an unknown key, a key beside the theme, and a map that is no theme are refused" do
      assert {:error, [{[:theme, :ink], :unknown_key}]} =
               Document.from_map(%{theme: %{ink: "#000000"}})

      assert Document.from_map(%{theme: %{}, styles: %{}}) ==
               {:error, [{[:styles], :unknown_key}]}

      assert Document.from_map(%{axis: "#000000"}) == {:error, [{[], {:type, {:node, :theme}}}]}
      assert Document.from_map(@house) == {:error, [{[], {:type, {:node, :theme}}}]}
    end

    test "JSON that does not parse is a fault in the same shape" do
      assert {:error, [{[], {:json, _message}}]} = Document.from_json("not json")
    end
  end

  describe "Fragment.read_json/2" do
    test "returns the stamp, and the current version for an unstamped document" do
      assert Fragment.read_json(~s({"$version": 1, "theme": {}})) == {:ok, %{theme: %{}}, 1}
      assert Fragment.read_json(~s({"theme": {}})) == {:ok, %{theme: %{}}, 2}
    end
  end
end
