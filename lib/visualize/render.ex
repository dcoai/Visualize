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

  alias Visualize.IR.{Path, Element}
  alias Visualize.Backend

  @type renderable :: Path.t() | Element.t() | [Element.t()]

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
