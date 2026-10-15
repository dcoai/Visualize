defmodule Visualize.Render do
  @moduledoc """
  Main entry point for rendering visualizations.

  ## Backend Selection

  Backends are selected in two ways (in order of precedence):

  1. Explicit parameter: `Visualize.Render.render(element, backend: :canvas)`
  2. Application config: `config :visualize, default_backend: :svg`

  There is deliberately no ambient, per-process override: a backend chosen at a
  distance is invisible at the call site, and restoring it needs a `try/after`.
  Thread the backend through as an option instead.

  ## Examples

      # Render to SVG (default)
      svg_string = Visualize.Render.to_string(element)

      # Render to Canvas
      canvas_js = Visualize.Render.to_string(element, backend: :canvas)

      # Render to iolist for efficiency
      iolist = Visualize.Render.render(element)

  """

  alias Visualize.Backend
  alias Visualize.IR.{Element, Path}
  alias Visualize.Render.Raster

  @type renderable :: Path.t() | Element.t() | [Element.t()]

  @typedoc """
  A warning of `to_png/2` (spec/09 §9.7): a font-family list no font resolves, its text not
  drawn, or another line resvg printed.
  """
  @type png_warning :: {:missing_family, String.t()} | {:rasterizer, String.t()}

  @typedoc "Why `to_png/2` produced no PNG (spec/09 §9.3)."
  @type png_error ::
          :no_rasterizer
          | :css_references
          | :timeout
          | {:rasterizer_version, String.t(), String.t()}
          | {:rasterizer, String.t()}

  @doc """
  Renders IR to the specified backend, returning an iolist.

  ## Options

    * `:backend` - The backend to use (`:svg`, `:canvas`, or a module). Defaults to configured default.
    * Other options are passed through to the backend.

  """
  @spec render(renderable(), keyword()) :: iolist()
  def render(ir, opts \\ []) do
    backend = resolve_backend(opts)
    do_render(ir, backend, opts)
  end

  @doc """
  Renders IR to a string.

  ## Options

    * `:backend` - The backend to use (`:svg`, `:canvas`, or a module). Defaults to configured default.
    * Other options are passed through to the backend.

  """
  @spec to_string(renderable(), keyword()) :: String.t()
  def to_string(ir, opts \\ []) do
    ir
    |> render(opts)
    |> IO.iodata_to_binary()
  end

  @doc """
  Convenience function for SVG rendering.

  Equivalent to `render(ir, backend: :svg)`.
  """
  @spec to_svg(renderable(), keyword()) :: iolist()
  def to_svg(ir, opts \\ []) do
    render(ir, Keyword.put(opts, :backend, :svg))
  end

  @doc """
  Convenience function for SVG string rendering.

  Equivalent to `to_string(ir, backend: :svg)`.
  """
  @spec to_svg_string(renderable(), keyword()) :: String.t()
  def to_svg_string(ir, opts \\ []) do
    to_string(ir, Keyword.put(opts, :backend, :svg))
  end

  @doc """
  Convenience function for Canvas rendering.

  Equivalent to `render(ir, backend: :canvas)`.
  """
  @spec to_canvas(renderable(), keyword()) :: iolist() | [tuple()]
  def to_canvas(ir, opts \\ []) do
    render(ir, Keyword.put(opts, :backend, :canvas))
  end

  @doc """
  Convenience function for Canvas string rendering.

  Equivalent to `to_string(ir, backend: :canvas)`.
  """
  @spec to_canvas_string(renderable(), keyword()) :: String.t()
  def to_canvas_string(ir, opts \\ []) do
    to_string(ir, Keyword.put(opts, :backend, :canvas))
  end

  @doc """
  Returns the path data string for the current backend.

  For SVG, this returns the `d` attribute value.
  For Canvas, this returns a list of drawing commands.
  """
  @spec path_data(Path.t(), keyword()) :: String.t() | [tuple()]
  def path_data(%Path{} = path, opts \\ []) do
    backend = resolve_backend(opts)
    backend.path_data(path)
  end

  @doc """
  Rasterizes a chart to a PNG through the resvg command-line tool, run as a port (spec/09
  §9, D-121).

  The input is a whole document: a root `Visualize.IR.Element` (`Visualize.IR.Element.root/3`,
  or `Visualize.Chart.generate/2` with `root: true`), rendered with `to_svg_string/2`, or the
  SVG string such an element renders to (`Visualize.Chart.render/2` with `root: true`).

  The SVG must carry literal colors: resvg paints a `var(--…)` theme reference black, so a
  chart meant for a PNG is generated with `resolve: :literal`, and an SVG holding one
  returns `{:error, :css_references}`.

      applied
      |> Visualize.Chart.generate(root: true, resolve: :literal)
      |> Visualize.Render.to_png(scale: 2, background: "#ffffff")

  ## The resvg binary

  PNG output takes no Hex dependency: the host installs resvg 0.45 or later (Debian and
  Ubuntu `apt install resvg`, the upstream release tarball, or `cargo install resvg`) and
  names it, or leaves it on the `PATH`:

      config :visualize, :resvg, "/usr/local/bin/resvg"

  A configured path is used as given, never replaced by the `PATH`'s. Its version is read
  once from `resvg --version`.

  ## Options

    * `:scale` - the device pixel ratio, a positive number (default `1`); the PNG is the
      root's width and height times it
    * `:background` - a CSS color painted under the document (default `nil`: transparent)
    * `:font_dirs` - directories whose fonts are loaded (default `[]`)
    * `:system_fonts` - whether the system fonts are loaded as well (default `true`)
    * `:generic_families` - the family each generic keyword names, over `:serif`,
      `:sans_serif`, `:monospace`, `:cursive` and `:fantasy` (default resvg's: `Times New
      Roman`, `Arial`, `Courier New`, `Comic Sans MS`, `Impact`)
    * `:font_family` - the family list of text that names none, as the theme's
      `font_family` (default `"sans-serif"`)
    * `:timeout` - milliseconds the render may take, a positive integer (default `30_000`)
    * Other options of an IR input pass through to the SVG backend; an SVG string takes no
      other option.

  ## Results

    * `{:ok, png, warnings}` - the PNG binary and resvg's warnings: one
      `{:missing_family, list}` per font-family list no font resolves, whose text resvg
      left out, and `{:rasterizer, line}` for any other line it printed; `[]` when there
      are none
    * `{:error, :no_rasterizer}` - no resvg binary is configured or on the `PATH`
    * `{:error, {:rasterizer_version, found, required}}` - the binary is older than the
      supported minimum
    * `{:error, :css_references}` - the SVG holds a `var(--` reference
    * `{:error, :timeout}` - the render took longer than `:timeout`; resvg was killed
    * `{:error, {:rasterizer, message}}` - resvg refused the document or an option

  ## Fonts

  The fonts are loaded by resvg on every call, a few milliseconds for one font directory and
  more with the system's fonts, so a font added to a directory is seen by the next render.
  resvg never substitutes a family, so a host whose system lacks Arial maps `sans-serif` to
  a family it has:

      Visualize.Render.to_png(root,
        font_dirs: ["/srv/app/fonts"],
        system_fonts: false,
        generic_families: [sans_serif: "DejaVu Sans"]
      )

  ## Scheduling

  The render runs in its own OS process. The calling process waits in a `receive`, so no
  scheduler is held, and a crash in resvg is an error value rather than a fault in the VM.
  """
  @spec to_png(Element.t() | String.t(), keyword()) ::
          {:ok, binary(), [png_warning()]} | {:error, png_error()}
  def to_png(input, opts \\ []), do: Raster.to_png(input, opts, Raster.available?())

  @doc """
  As `to_png/2`, returning the PNG binary of `{:ok, png, []}`: raises on the `{:error, _}`
  branch, and when there is a warning, so the result is a complete picture or none.
  """
  @spec to_png!(Element.t() | String.t(), keyword()) :: binary()
  def to_png!(input, opts \\ []), do: Raster.to_png!(input, opts, Raster.available?())

  # ============================================================
  # Private Functions
  # ============================================================

  defp resolve_backend(opts) do
    case Keyword.get(opts, :backend) do
      nil -> Backend.default()
      backend -> Backend.resolve(backend)
    end
  end

  defp do_render(%Path{} = path, backend, opts) do
    backend.render_path(path, opts)
  end

  defp do_render(%Element{} = element, backend, opts) do
    backend.render_element(element, opts)
  end

  defp do_render(elements, backend, opts) when is_list(elements) do
    backend.render_scene(elements, opts)
  end
end
