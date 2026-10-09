defmodule Visualize.Render.Raster do
  @moduledoc false
  # The one module in lib/ that names `Resvg` (spec/09 §9, D-118), behind
  # `Visualize.Render.to_png/2`. The package is optional: the calls stay direct, read
  # availability at the call, and the compiler is told not to warn about them in a
  # consumer that never fetched it (D-50).
  #
  # The suite has the package and cannot unload it, so availability is an argument
  # (spec/09 §9.4): `Visualize.Render` passes `available?/0`, a test passes `false`.

  alias Visualize.IR.Element

  @compile {:no_warn_undefined, Resvg}

  # The options `to_png/2` reads; every other option of an IR input reaches the SVG backend.
  @keys [:scale, :background]

  @doc false
  @spec available?() :: boolean()
  def available?, do: Code.ensure_loaded?(Resvg)

  @doc false
  @spec to_png(Element.t() | String.t(), keyword(), boolean()) ::
          {:ok, binary()} | {:error, Visualize.Render.png_error()}
  def to_png(input, opts, available) when is_list(opts) and is_boolean(available) do
    {raster, rest} = Keyword.split(opts, @keys)
    scale = scale!(Keyword.get(raster, :scale, 1))
    background = background!(Keyword.get(raster, :background))
    svg = svg!(input, rest)

    cond do
      not available -> {:error, :no_rasterizer}
      String.contains?(svg, "var(--") -> {:error, :css_references}
      true -> rasterize(svg, scale, background)
    end
  end

  @doc false
  @spec to_png!(Element.t() | String.t(), keyword(), boolean()) :: binary()
  def to_png!(input, opts, available) do
    case to_png(input, opts, available) do
      {:ok, png} -> png
      {:error, reason} -> raise "Failed to rasterise to PNG: #{inspect(reason)}"
    end
  end

  defp rasterize(svg, scale, background) do
    opts = [zoom: scale * 1.0, resources_dir: System.tmp_dir!()]
    opts = if background, do: [{:background, background} | opts], else: opts

    case Resvg.svg_string_to_png_binary(svg, opts) do
      {:ok, png} -> {:ok, png}
      {:error, message} -> {:error, {:rasterizer, message}}
    end
  end

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
