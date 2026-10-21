defmodule ExamplesWeb.BuilderBoard do
  @moduledoc """
  The builder over the builder page's own assigns in board mode (spec/14 §22), opened as a
  click on the page opens the board: what the page's board-mode tests share (#838).
  """

  alias ExamplesWeb.BuilderLive
  alias ExamplesWeb.BuilderLive.Library
  alias Phoenix.LiveView.Socket
  alias Visualize.Chart.Builder
  alias Visualize.Chart.Builder.{Boards, Editing, Store}

  @doc "The page mounted, and the builder over its assigns with the live board open."
  def board_mode do
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

    {:ok, s} = Builder.mount(%Socket{})
    {:ok, s} = Builder.update(host, s)
    id = Store.encode_id(Library.id_of("Boards::live board"))
    {:noreply, s} = Builder.handle_event("add_layer", %{"name" => id}, s)
    {page, s}
  end

  @doc "One builder event, as the LiveView routes it: the socket after it."
  def event(s, name, params), do: elem(Builder.handle_event(name, params, s), 1)

  @doc """
  The board down to its `wave` cell, selected and showing the library component `id`:
  the socket, and whether the cell took the component.
  """
  def one_cell(s, id) do
    s =
      Enum.reduce(Map.keys(s.assigns.board.cells) -- ["wave"], s, fn cell, s ->
        event(s, "board_remove", %{"cell" => to_string(cell)})
      end)

    s = event(s, "board_select", %{"cell" => "wave"})
    s = event(s, "board_cell", %{"_target" => ["ref"], "ref" => Store.encode_id(id)})
    {s, s.assigns.board.cells["wave"].ref == id}
  end

  @doc "The selected cell's slots, each bound to `feed` by its own event."
  def bind(s, feed) do
    slots = Editing.editing(s.assigns).board_mode.selected.slots

    Enum.reduce(slots, s, fn %{name: slot}, s ->
      key = "slot." <> slot
      event(s, "board_bind", %{"_target" => [key], key => Boards.feed_key(feed)})
    end)
  end

  @doc """
  One feed of each kind in a catalog, the first by its printed name: a kind is the shape
  of the feed's schema — its fields' names and types, which attributes each gives, and its
  identity — whatever the attributes' values (spec/12 §6, #838). Feeds of one kind take
  the same path through the binding check and the preview.
  """
  def feed_kinds(catalog) do
    catalog
    |> Enum.group_by(fn {_feed, schema} -> kind(schema) end, fn {feed, _schema} -> feed end)
    |> Enum.map(fn {_kind, feeds} -> Enum.min_by(feeds, &Boards.feed_key/1) end)
    |> Enum.sort_by(&Boards.feed_key/1)
  end

  defp kind(%Visualize.Data.Schema{fields: fields, identity: identity}) do
    {Map.new(fields, fn {name, spec} -> {name, {spec.type, spec |> Map.keys() |> Enum.sort()}} end),
     Enum.sort(identity)}
  end
end
