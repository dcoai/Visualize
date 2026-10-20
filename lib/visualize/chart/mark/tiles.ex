defmodule Visualize.Chart.Mark.Tiles do
  @moduledoc false
  # The `:tiles` mark (spec/14 §5.2, #475): a Web-Mercator basemap under a `:geo` frame —
  # one `:image` per tile of `Visualize.Geo.Tiles.cover/3` over the plot area, clipped to it
  # (D-209), and the attribution as text in the plot's bottom-right corner. It reads no
  # rows and never fetches anything: the browser loads each `href`.

  alias Visualize.Chart.{Frame, Schema, Style, Var}
  alias Visualize.Chart.Style.Defaults
  alias Visualize.Geo.Tiles
  alias Visualize.IR.Element

  # How far in from the plot's right and bottom edges the attribution sits (§5.2).
  @inset 4

  @doc false
  @spec generate(Frame.t(), map(), Visualize.Theme.mode()) :: Element.t()
  def generate(%Frame{} = frame, mark, mode) do
    node = provider(mark)
    projection = projection!(frame)
    max_zoom = Map.get(node, :max_zoom, Schema.default(:tiles, :max_zoom))
    subdomains = Map.get(node, :subdomains, Schema.default(:tiles, :subdomains))
    plot = frame.plot

    images =
      for tile <- Tiles.cover(projection, {plot.width, plot.height}, max_zoom: max_zoom) do
        Element.image(
          Tiles.url(node.url, tile, subdomains),
          tile.left,
          tile.top,
          tile.size,
          tile.size
        )
      end

    # Whole tiles reach past the plot's edges; the group is clipped to the plot so a
    # basemap paints inside its own frame alone (#826, D-209). The clip is on the group,
    # so it travels with both halves of a hybrid page's split (§12.4).
    Element.group(images ++ [attribution(frame, mark, node, mode)],
      style: %{class: class(frame, mark)}
    )
    |> Element.clip(Element.rect(0, 0, plot.width, plot.height), :inside)
  end

  # The attribution, always drawn (§5.2): the mark's style over the built-in `:label`,
  # anchored at its end in the plot's bottom-right corner.
  defp attribution(frame, mark, node, mode) do
    base = Defaults.at(frame, Map.get(mark, :defaults), :tiles)
    style_node = Style.over(base, frame.styles, [:label | List.wrap(Map.get(mark, :style))])

    style =
      style_node
      |> Style.resolve(frame.theme, mode)
      |> Map.merge(%{class: "mark-attribution", text_anchor: :end})

    Element.new(:text,
      attrs: %{x: frame.plot.width - @inset, y: frame.plot.height - @inset},
      style: style,
      content: node.attribution
    )
  end

  defp class(frame, mark) do
    case Map.get(Style.node(frame.styles, Map.get(mark, :style)), :class) do
      nil -> "mark mark-tiles"
      class -> "mark mark-tiles #{class}"
    end
  end

  defp provider(%{tiles: %Var{name: name}}), do: Style.unresolved!(name)
  defp provider(%{tiles: %{url: _, attribution: _} = node}), do: node

  defp provider(_mark) do
    raise ArgumentError, "a :tiles mark needs its tiles node: url and attribution (spec/14 §5.2)"
  end

  defp projection!(%Frame{projection: nil, kind: kind}) do
    raise ArgumentError,
          "a :tiles mark needs a :geo frame's Mercator projection, got a #{inspect(kind)} frame"
  end

  defp projection!(%Frame{projection: projection}), do: projection
end
