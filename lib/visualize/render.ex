defmodule Visualize.Render do
  @moduledoc """
  Main entry point for rendering visualizations.

  ## Backend Selection

  Backends can be selected in three ways (in order of precedence):

  1. Explicit parameter: `Visualize.Render.render(element, backend: :canvas)`
  2. Process dictionary: `Visualize.Render.with_backend(:canvas, fn -> ... end)`
  3. Application config: `config :visualize, default_backend: :svg`

  ## Examples

      # Render to SVG (default)
      svg_string = Visualize.Render.to_string(element)

      # Render to Canvas
      canvas_js = Visualize.Render.to_string(element, backend: :canvas)

      # Render to iolist for efficiency
      iolist = Visualize.Render.render(element)

      # With temporary backend override
      Visualize.Render.with_backend(:canvas, fn ->
        canvas_output = Visualize.Render.to_string(element)
        # ...
      end)

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
  Executes a function with a specific backend set as the default.

  The backend is stored in the process dictionary and restored after
  the function returns.

  ## Example

      Visualize.Render.with_backend(:canvas, fn ->
        # All render calls in here will use Canvas backend
        element1 |> Visualize.Render.to_string()
        element2 |> Visualize.Render.to_string()
      end)

  """
  @spec with_backend(atom() | module(), (-> result)) :: result when result: any()
  def with_backend(backend, fun) when is_function(fun, 0) do
    old = Process.get(:visualize_backend)
    Process.put(:visualize_backend, backend)

    try do
      fun.()
    after
      if old do
        Process.put(:visualize_backend, old)
      else
        Process.delete(:visualize_backend)
      end
    end
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
    cond do
      backend = Keyword.get(opts, :backend) -> Backend.resolve(backend)
      backend = Process.get(:visualize_backend) -> Backend.resolve(backend)
      true -> Backend.default()
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
