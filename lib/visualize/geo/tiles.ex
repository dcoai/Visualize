defmodule Visualize.Geo.Tiles do
  @moduledoc """
  The arithmetic of a Web-Mercator basemap (spec/07 §8, #475): the zoom level whose
  256-pixel tiles match a Mercator projection, the tiles covering a plot, where each
  goes in plot pixels, and its URL.

  It never fetches anything: it computes URLs and rectangles, and the browser loads each
  tile as it loads any `<image href>`.

  ## Examples

      iex> proj =
      ...>   Visualize.Geo.Projection.new(:mercator)
      ...>   |> Visualize.Geo.Projection.scale(256 / (2 * :math.pi()))
      ...>   |> Visualize.Geo.Projection.translate(128, 128)
      iex> Visualize.Geo.Tiles.zoom(proj)
      0
      iex> [tile] = Visualize.Geo.Tiles.cover(proj, {256, 256})
      iex> {tile.z, tile.x, tile.y, Float.round(tile.left, 6), Float.round(tile.size, 6)}
      {0, 0, 0, 0.0, 256.0}
      iex> Visualize.Geo.Tiles.url("https://{s}.tile.example/{z}/{x}/{y}.png", tile, ["a", "b"])
      "https://a.tile.example/0/0/0.png"

  """

  alias Visualize.Geo.Projection

  @tile 256
  @default_max_zoom 19

  @typedoc "One tile of the covering set: its address and its square in plot pixels."
  @type tile :: %{
          z: non_neg_integer(),
          x: non_neg_integer(),
          y: non_neg_integer(),
          left: float(),
          top: float(),
          size: float()
        }

  @doc """
  `:ok` when the projection is tile-aligned — `:mercator`, a zero centre latitude, no
  tilt or roll — else `{:error, reason}` (spec/07 §8.1).

      iex> Visualize.Geo.Tiles.aligned(Visualize.Geo.Projection.new(:mercator))
      :ok
      iex> Visualize.Geo.Tiles.aligned(Visualize.Geo.Projection.new(:orthographic))
      {:error, {:type, :orthographic}}
  """
  @spec aligned(Projection.t()) :: :ok | {:error, {:type, atom()} | :center | :rotate}
  def aligned(%Projection{type: type}) when type != :mercator, do: {:error, {:type, type}}
  def aligned(%Projection{center: {_lon, lat}}) when lat != 0, do: {:error, :center}

  def aligned(%Projection{rotate: {_lambda, phi, gamma}}) when phi != 0 or gamma != 0,
    do: {:error, :rotate}

  def aligned(%Projection{}), do: :ok

  @doc "As `zoom/2` with no options."
  @spec zoom(Projection.t()) :: non_neg_integer()
  def zoom(%Projection{} = proj), do: zoom(proj, [])

  @doc """
  The zoom level whose 256-pixel tiles are nearest the projection's scale (spec/07 §8.2):
  `round(log2(2πk / 256))`, clamped to `[0, max_zoom]`.

  ## Options

    * `:max_zoom` - the deepest level the provider serves (default `19`)
  """
  @spec zoom(Projection.t(), keyword()) :: non_neg_integer()
  def zoom(%Projection{scale: k}, opts) do
    max_zoom = Keyword.get(opts, :max_zoom, @default_max_zoom)
    z = round(:math.log2(world(k) / @tile))
    z |> max(0) |> min(max_zoom)
  end

  @doc "As `cover/3` with no options."
  @spec cover(Projection.t(), {number(), number()}) :: [tile()]
  def cover(%Projection{} = proj, size), do: cover(proj, size, [])

  @doc """
  The tiles covering a plot of `{width, height}` pixels (spec/07 §8.3), in row-then-column
  order, each with its wrapped column `x`, its row `y` and its square in plot pixels.

  Raises `ArgumentError` for a projection that is not tile-aligned (`aligned/1`).

  ## Options

    * `:max_zoom` - as `zoom/2`
  """
  @spec cover(Projection.t(), {number(), number()}, keyword()) :: [tile()]
  def cover(%Projection{} = proj, {width, height}, opts) do
    aligned!(proj)
    z = zoom(proj, opts)
    n = Integer.pow(2, z)
    w = world(proj.scale)
    t = w / n
    {x0, y0} = origin(proj, w)

    columns = floor(-x0 / t)..(ceil((width - x0) / t) - 1)//1
    rows = max(0, floor(-y0 / t))..min(n - 1, ceil((height - y0) / t) - 1)//1

    for j <- rows, i <- columns do
      %{z: z, x: Integer.mod(i, n), y: j, left: x0 + i * t, top: y0 + j * t, size: t}
    end
  end

  @doc """
  A tile's URL (spec/07 §8.4): `{z}`, `{x}` and `{y}` replaced by its address and `{s}`
  by `subdomains[rem(x + y, n)]`. Raises `ArgumentError` for `{s}` with no subdomains.
  """
  @spec url(String.t(), %{z: integer(), x: integer(), y: integer()}, [String.t()]) ::
          String.t()
  def url(template, %{z: z, x: x, y: y}, subdomains) when is_binary(template) do
    template
    |> String.replace("{z}", Integer.to_string(z))
    |> String.replace("{x}", Integer.to_string(x))
    |> String.replace("{y}", Integer.to_string(y))
    |> subdomain(x + y, subdomains)
  end

  defp subdomain(url, index, subdomains) do
    cond do
      not String.contains?(url, "{s}") ->
        url

      subdomains == [] ->
        raise ArgumentError, "a tile URL with {s} needs at least one subdomain"

      true ->
        String.replace(url, "{s}", Enum.at(subdomains, rem(index, length(subdomains))))
    end
  end

  # The world's width in plot pixels: one radian of longitude is `k` pixels (spec/07 §1.1).
  defp world(k), do: 2 * :math.pi() * k

  # The plot pixel of the world's top-left corner, longitude −180° and the latitude whose
  # Mercator ordinate is π (spec/07 §8.3): the central meridian is the rotation's lambda
  # plus the centre's longitude.
  defp origin(%Projection{translate: {tx, ty}, center: {lon, _}, rotate: {lambda, _, _}}, w) do
    m = lambda + lon
    {tx - w * (m + 180) / 360, ty - w / 2}
  end

  defp aligned!(proj) do
    case aligned(proj) do
      :ok ->
        :ok

      {:error, reason} ->
        raise ArgumentError,
              "tiles need a tile-aligned Mercator projection (spec/07 §8.1), got: " <>
                inspect(reason)
    end
  end
end
