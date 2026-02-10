defmodule Visualize.Backend do
  @moduledoc """
  Behaviour defining the interface for rendering backends.

  Backends convert the intermediate representation (IR) to their
  target output format (SVG strings, Canvas commands, etc.).

  ## Built-in Backends

  - `Visualize.Backend.SVG` - SVG string output (default)
  - `Visualize.Backend.Canvas` - Canvas 2D API commands

  ## Configuration

  Set the default backend in your config:

      config :visualize, default_backend: :svg

  Or specify at render time:

      Visualize.Render.to_string(element, backend: :canvas)

  ## Implementing a Custom Backend

  To implement a custom backend, define a module that implements this behaviour:

      defmodule MyApp.PDFBackend do
        @behaviour Visualize.Backend

        @impl true
        def path_data(path), do: ...

        @impl true
        def render_path(path, opts), do: ...

        @impl true
        def render_element(element, opts), do: ...

        @impl true
        def render_scene(elements, opts), do: ...
      end

  """

  alias Visualize.IR.{Path, Element}

  @type output :: iolist() | String.t() | map() | [tuple()]
  @type options :: keyword()

  @doc """
  Converts a Path IR to backend-specific path data.

  For SVG, this returns the `d` attribute string (e.g., "M10,20L100,200Z").
  For Canvas, this returns a list of drawing commands.
  """
  @callback path_data(Path.t()) :: String.t() | [tuple()]

  @doc """
  Renders a Path IR to the backend's output format.

  Options may include style information and other backend-specific settings.
  """
  @callback render_path(Path.t(), options()) :: output()

  @doc """
  Renders an Element IR tree to the backend's output format.
  """
  @callback render_element(Element.t(), options()) :: output()

  @doc """
  Renders a complete scene (list of elements) to output.
  """
  @callback render_scene([Element.t()], options()) :: output()

  @doc """
  Wraps content in a root container.

  For SVG, this wraps in `<svg>` tags. For Canvas, this may generate
  the canvas element and setup code.

  This callback is optional.
  """
  @callback wrap_root(output(), options()) :: output()

  @optional_callbacks [wrap_root: 2]

  # ============================================================
  # Backend Resolution
  # ============================================================

  @doc """
  Gets the configured default backend module.
  """
  @spec default() :: module()
  def default do
    Application.get_env(:visualize, :default_backend, Visualize.Backend.SVG)
    |> resolve()
  end

  @doc """
  Resolves a backend from various inputs.

  Accepts:
  - `nil` - returns the default backend
  - `:svg` - returns `Visualize.Backend.SVG`
  - `:canvas` - returns `Visualize.Backend.Canvas`
  - A module atom - returns the module directly
  """
  @spec resolve(atom() | nil) :: module()
  def resolve(nil), do: default()
  def resolve(:svg), do: Visualize.Backend.SVG
  def resolve(:canvas), do: Visualize.Backend.Canvas
  def resolve(module) when is_atom(module), do: module
end
