defmodule Visualize.Render.Raster do
  @moduledoc false
  # The one module in lib/ that names `Resvg` (spec/09 §9, D-118), behind
  # `Visualize.Render.to_png/2`. The package is optional: the calls stay direct, read
  # availability at the call, and the compiler is told not to warn about them in a
  # consumer that never fetched it (D-50).
  #
  # The suite has the package and cannot unload it, so availability is an argument
  # (spec/09 §9.4): `Visualize.Render` passes `available?/0`, a test passes `false`.
  #
  # Fonts (spec/09 §9.6, §9.7): a font database per font configuration, cached in
  # `:persistent_term` with the family names it holds, and every family list the SVG names
  # resolved against those names, since resvg drops text in a family it lacks silently.

  alias Visualize.IR.Element
  alias Visualize.Render.Raster.Families

  @compile {:no_warn_undefined, Resvg}

  @font_keys [:font_dirs, :system_fonts, :generic_families]
  # The options `to_png/2` reads; every other option of an IR input reaches the SVG backend.
  @keys [:scale, :background, :font_family | @font_keys]

  # resvg's own generic families (spec/09 §9.2), in the order the cache key holds them.
  @generic_defaults [
    serif: "Times New Roman",
    sans_serif: "Arial",
    monospace: "Courier New",
    cursive: "Comic Sans MS",
    fantasy: "Impact"
  ]

  @doc false
  @spec available?() :: boolean()
  def available?, do: Code.ensure_loaded?(Resvg)

  @doc false
  @spec to_png(Element.t() | String.t(), keyword(), boolean()) ::
          {:ok, binary(), [Families.warning()]} | {:error, Visualize.Render.png_error()}
  def to_png(input, opts, available) when is_list(opts) and is_boolean(available) do
    {raster, rest} = Keyword.split(opts, @keys)
    scale = scale!(Keyword.get(raster, :scale, 1))
    background = background!(Keyword.get(raster, :background))
    family = font_family!(Keyword.get(raster, :font_family, "sans-serif"))
    config = config!(raster)
    svg = svg!(input, rest)

    cond do
      not available -> {:error, :no_rasterizer}
      String.contains?(svg, "var(--") -> {:error, :css_references}
      true -> rasterize(Families.with_default(svg, family), scale, background, config)
    end
  end

  @doc false
  @spec to_png!(Element.t() | String.t(), keyword(), boolean()) :: binary()
  def to_png!(input, opts, available) do
    case to_png(input, opts, available) do
      {:ok, png, []} -> png
      {:ok, _png, warnings} -> raise "PNG drawn without some text: #{inspect(warnings)}"
      {:error, reason} -> raise "Failed to rasterise to PNG: #{inspect(reason)}"
    end
  end

  @doc false
  # The cached font database of a font configuration and the family names it holds
  # (spec/09 §9.6), built on the first call for that configuration.
  @spec fonts(keyword()) :: %{db: reference(), families: MapSet.t(String.t())}
  def fonts(opts) when is_list(opts), do: opts |> config!() |> cached()

  defp rasterize(svg, scale, background, config) do
    %{db: db, families: families} = cached(config)
    {_dirs, _system, generics} = config
    opts = [zoom: scale * 1.0, resources_dir: System.tmp_dir!(), fontdb: db]
    opts = if background, do: [{:background, background} | opts], else: opts

    case Resvg.svg_string_to_png_binary(svg, opts) do
      {:ok, png} -> {:ok, png, Families.missing(svg, families, generics)}
      {:error, message} -> {:error, {:rasterizer, message}}
    end
  end

  defp cached(config) do
    key = {__MODULE__, :fonts, config}

    case :persistent_term.get(key, nil) do
      nil ->
        fonts = build(config)
        :persistent_term.put(key, fonts)
        fonts

      fonts ->
        fonts
    end
  end

  defp build({dirs, system, generics}) do
    opts =
      [resources_dir: System.tmp_dir!(), font_dirs: dirs, skip_system_fonts: not system] ++
        Enum.map(generics, fn {key, family} -> {:"#{key}_family", family} end)

    {:ok, db} = Resvg.init_fontdb(opts)
    {:ok, listing} = Resvg.list_fonts(opts)
    %{db: db, families: Families.from_listing(listing)}
  end

  # The normalised font configuration, the cache's key (spec/09 §9.6).
  defp config!(opts) do
    dirs = font_dirs!(Keyword.get(opts, :font_dirs, []))
    system = system_fonts!(Keyword.get(opts, :system_fonts, true))
    generics = generics!(Keyword.get(opts, :generic_families, []))
    {dirs, system, generics}
  end

  defp font_dirs!(dirs) when is_list(dirs) do
    dirs
    |> Enum.map(fn
      dir when is_binary(dir) ->
        expanded = Path.expand(dir)

        File.dir?(expanded) ||
          raise ArgumentError, ":font_dirs names no directory: #{inspect(dir)}"

        expanded

      dir ->
        raise ArgumentError, ":font_dirs must be a list of strings, got: #{inspect(dir)}"
    end)
    |> Enum.sort()
    |> Enum.uniq()
  end

  defp font_dirs!(dirs),
    do: raise(ArgumentError, ":font_dirs must be a list of strings, got: #{inspect(dirs)}")

  defp system_fonts!(system) when is_boolean(system), do: system

  defp system_fonts!(system),
    do: raise(ArgumentError, ":system_fonts must be a boolean, got: #{inspect(system)}")

  defp generics!(given) when is_list(given) do
    Enum.each(given, fn
      {key, family} when is_binary(family) ->
        Keyword.has_key?(@generic_defaults, key) ||
          raise ArgumentError,
                ":generic_families takes #{inspect(Keyword.keys(@generic_defaults))}, got: #{inspect(key)}"

      other ->
        raise ArgumentError, ":generic_families must map keys to strings, got: #{inspect(other)}"
    end)

    Enum.map(@generic_defaults, fn {key, default} -> {key, Keyword.get(given, key, default)} end)
  end

  defp generics!(given),
    do: raise(ArgumentError, ":generic_families must be a keyword list, got: #{inspect(given)}")

  defp font_family!(family) when is_binary(family), do: family

  defp font_family!(family),
    do: raise(ArgumentError, ":font_family must be a string, got: #{inspect(family)}")

  # A PNG is a whole document: a root element, or the SVG string one renders to.
  defp svg!(%Element{type: :root} = root, svg_opts),
    do: Visualize.Render.to_svg_string(root, svg_opts)

  defp svg!(svg, []) when is_binary(svg), do: svg

  defp svg!(svg, unknown) when is_binary(svg) do
    raise ArgumentError,
          "an SVG string takes only #{inspect(@keys)}, got #{inspect(Keyword.keys(unknown))}"
  end

  defp scale!(scale) when is_number(scale) and scale > 0, do: scale

  defp scale!(scale),
    do: raise(ArgumentError, ":scale must be a positive number, got: #{inspect(scale)}")

  defp background!(background) when is_nil(background) or is_binary(background), do: background

  defp background!(background),
    do: raise(ArgumentError, ":background must be a colour string, got: #{inspect(background)}")
end
