defmodule Visualize.IR.Element do
  @moduledoc """
  Backend-agnostic element representation for building scene graphs.

  Elements represent visual primitives that can be rendered by any backend.
  The structure separates concerns:
  - `type`: The kind of element (:path, :rect, :circle, etc.)
  - `attrs`: Geometric attributes (x, y, width, height, cx, cy, r, etc.)
  - `style`: Visual styling (fill, stroke, opacity, etc.)
  - `transform`: Transformation to apply
  - `children`: Child elements (for groups)
  - `content`: Text content (for text elements)
  - `path`: Path IR (for path elements)

  ## Examples

      iex> alias Visualize.IR.{Element, Path, Transform}
      iex> path = Path.new() |> Path.move_to(0, 0) |> Path.line_to(100, 100)
      iex> Element.path(path, %{stroke: "blue", fill: :none})
      %Visualize.IR.Element{type: :path, path: path, style: %{stroke: "blue", fill: :none}, ...}

  """

  alias Visualize.IR.{Path, Transform}

  defstruct [
    :type,
    attrs: %{},
    style: %{},
    transform: nil,
    children: [],
    content: nil,
    path: nil
  ]

  @type element_type ::
          :path
          | :rect
          | :circle
          | :ellipse
          | :line
          | :polyline
          | :polygon
          | :text
          | :group
          | :image
          | :defs
          | :clip_path
          | :linear_gradient
          | :radial_gradient
          | :stop
          | :root

  @type style :: %{
          optional(:fill) => String.t() | :none | :current_color,
          optional(:stroke) => String.t() | :none | :current_color,
          optional(:stroke_width) => number(),
          optional(:stroke_linecap) => :butt | :round | :square,
          optional(:stroke_linejoin) => :miter | :round | :bevel,
          optional(:stroke_dasharray) => String.t(),
          optional(:opacity) => number(),
          optional(:fill_opacity) => number(),
          optional(:stroke_opacity) => number(),
          optional(:font_size) => number() | String.t(),
          optional(:font_family) => String.t(),
          optional(:font_weight) => String.t() | number(),
          optional(:text_anchor) => :start | :middle | :end,
          optional(:dominant_baseline) => atom(),
          optional(:class) => String.t()
        }

  @type t :: %__MODULE__{
          type: element_type(),
          attrs: map(),
          style: style(),
          transform: Transform.t() | nil,
          children: [t()],
          content: String.t() | nil,
          path: Path.t() | nil
        }

  @doc """
  Creates a new element of the specified type.
  """
  @spec new(element_type(), keyword()) :: t()
  def new(type, opts \\ []) do
    %__MODULE__{
      type: type,
      attrs: Keyword.get(opts, :attrs, %{}),
      style: Keyword.get(opts, :style, %{}),
      transform: Keyword.get(opts, :transform),
      children: Keyword.get(opts, :children, []),
      content: Keyword.get(opts, :content),
      path: Keyword.get(opts, :path)
    }
  end

  # ============================================================
  # Element Constructors
  # ============================================================

  @doc """
  Creates a path element from a Path IR.
  """
  @spec path(Path.t(), style()) :: t()
  def path(%Path{} = path_ir, style \\ %{}) do
    new(:path, path: path_ir, style: style)
  end

  @doc """
  Creates a group element.
  """
  @spec group([t()], keyword()) :: t()
  def group(children \\ [], opts \\ []) do
    new(:group,
      children: children,
      style: Keyword.get(opts, :style, %{}),
      transform: Keyword.get(opts, :transform),
      attrs: Keyword.get(opts, :attrs, %{})
    )
  end

  @doc """
  Creates a rectangle element.
  """
  @spec rect(number(), number(), number(), number(), style()) :: t()
  def rect(x, y, width, height, style \\ %{}) do
    new(:rect, attrs: %{x: x, y: y, width: width, height: height}, style: style)
  end

  @doc """
  Creates a circle element.
  """
  @spec circle(number(), number(), number(), style()) :: t()
  def circle(cx, cy, r, style \\ %{}) do
    new(:circle, attrs: %{cx: cx, cy: cy, r: r}, style: style)
  end

  @doc """
  Creates an ellipse element.
  """
  @spec ellipse(number(), number(), number(), number(), style()) :: t()
  def ellipse(cx, cy, rx, ry, style \\ %{}) do
    new(:ellipse, attrs: %{cx: cx, cy: cy, rx: rx, ry: ry}, style: style)
  end

  @doc """
  Creates a line element.
  """
  @spec line(number(), number(), number(), number(), style()) :: t()
  def line(x1, y1, x2, y2, style \\ %{}) do
    new(:line, attrs: %{x1: x1, y1: y1, x2: x2, y2: y2}, style: style)
  end

  @doc """
  Creates a polyline element.
  Points should be a list of {x, y} tuples.
  """
  @spec polyline([{number(), number()}], style()) :: t()
  def polyline(points, style \\ %{}) do
    new(:polyline, attrs: %{points: points}, style: style)
  end

  @doc """
  Creates a polygon element.
  Points should be a list of {x, y} tuples.
  """
  @spec polygon([{number(), number()}], style()) :: t()
  def polygon(points, style \\ %{}) do
    new(:polygon, attrs: %{points: points}, style: style)
  end

  @doc """
  Creates a text element.
  """
  @spec text(String.t(), number(), number(), style()) :: t()
  def text(content, x, y, style \\ %{}) do
    new(:text, attrs: %{x: x, y: y}, style: style, content: content)
  end

  @doc """
  Creates a text element with dx/dy offsets (useful for tick labels).
  """
  @spec text(String.t(), keyword()) :: t()
  def text(content, opts) when is_list(opts) do
    attrs =
      opts
      |> Keyword.take([:x, :y, :dx, :dy])
      |> Map.new()

    style = Keyword.get(opts, :style, %{})

    new(:text, attrs: attrs, style: style, content: content)
  end

  @doc """
  Creates an image element.
  """
  @spec image(String.t(), number(), number(), number(), number(), style()) :: t()
  def image(href, x, y, width, height, style \\ %{}) do
    new(:image, attrs: %{href: href, x: x, y: y, width: width, height: height}, style: style)
  end

  @doc """
  Creates a defs element (for gradients, patterns, etc.).
  """
  @spec defs([t()]) :: t()
  def defs(children \\ []) do
    new(:defs, children: children)
  end

  @doc """
  Creates a clip path element.
  """
  @spec clip_path(String.t(), [t()]) :: t()
  def clip_path(id, children) do
    new(:clip_path, attrs: %{id: id}, children: children)
  end

  @doc """
  Creates a linear gradient element.
  """
  @spec linear_gradient(String.t(), keyword()) :: t()
  def linear_gradient(id, opts \\ []) do
    attrs =
      %{id: id}
      |> Map.merge(Map.new(Keyword.take(opts, [:x1, :y1, :x2, :y2])))

    children = Keyword.get(opts, :stops, [])
    new(:linear_gradient, attrs: attrs, children: children)
  end

  @doc """
  Creates a radial gradient element.
  """
  @spec radial_gradient(String.t(), keyword()) :: t()
  def radial_gradient(id, opts \\ []) do
    attrs =
      %{id: id}
      |> Map.merge(Map.new(Keyword.take(opts, [:cx, :cy, :r, :fx, :fy])))

    children = Keyword.get(opts, :stops, [])
    new(:radial_gradient, attrs: attrs, children: children)
  end

  @doc """
  Creates a gradient stop element.
  """
  @spec stop(String.t(), String.t(), keyword()) :: t()
  def stop(offset, color, opts \\ []) do
    style = %{stop_color: color}
    style = if opts[:opacity], do: Map.put(style, :stop_opacity, opts[:opacity]), else: style
    new(:stop, attrs: %{offset: offset}, style: style)
  end

  @doc """
  Creates a root SVG element.

  ## Options

    * `:view_box` - the `viewBox` (default `"0 0 <width> <height>"`)
    * `:children` - the child elements (default `[]`)
    * `:preserve_aspect_ratio` - the `preserveAspectRatio` attribute; absent by default
    * `:responsive` - when true, `preserveAspectRatio="xMidYMid meet"` (unless given) and
      `style="width:100%;height:auto"`, so the `<svg>` fills its container's width at the
      drawing's aspect ratio while `width` and `height` stay its intrinsic size (D-54)
  """
  @spec root(number(), number(), keyword()) :: t()
  def root(width, height, opts \\ []) do
    view_box = Keyword.get(opts, :view_box, "0 0 #{width} #{height}")
    responsive = Keyword.get(opts, :responsive, false)
    default_ratio = if responsive, do: "xMidYMid meet"
    ratio = Keyword.get(opts, :preserve_aspect_ratio, default_ratio)

    attrs =
      %{width: width, height: height, view_box: view_box}
      |> put_unless_nil(:preserve_aspect_ratio, ratio)
      |> put_unless_nil(:style, if(responsive, do: "width:100%;height:auto"))

    new(:root, attrs: attrs, children: Keyword.get(opts, :children, []))
  end

  defp put_unless_nil(map, _key, nil), do: map
  defp put_unless_nil(map, key, value), do: Map.put(map, key, value)

  # ============================================================
  # Element Manipulation
  # ============================================================

  @doc """
  Appends a child element.
  """
  @spec append(t(), t() | [t()]) :: t()
  def append(%__MODULE__{children: children} = parent, %__MODULE__{} = child) do
    %{parent | children: children ++ [child]}
  end

  def append(%__MODULE__{children: children} = parent, new_children) when is_list(new_children) do
    %{parent | children: children ++ new_children}
  end

  @doc """
  Prepends a child element.
  """
  @spec prepend(t(), t() | [t()]) :: t()
  def prepend(%__MODULE__{children: children} = parent, %__MODULE__{} = child) do
    %{parent | children: [child | children]}
  end

  def prepend(%__MODULE__{children: children} = parent, new_children)
      when is_list(new_children) do
    %{parent | children: new_children ++ children}
  end

  @doc """
  Sets the transform on an element.
  """
  @spec set_transform(t(), Transform.t()) :: t()
  def set_transform(%__MODULE__{} = element, %Transform{} = transform) do
    %{element | transform: transform}
  end

  @doc """
  Adds a translation transform.
  """
  @spec translate(t(), number(), number()) :: t()
  def translate(%__MODULE__{transform: nil} = element, x, y) do
    %{element | transform: Transform.translate(x, y)}
  end

  def translate(%__MODULE__{transform: t} = element, x, y) do
    %{element | transform: Transform.translate(t, x, y)}
  end

  @doc """
  Sets style properties on an element, merging with existing style.
  """
  @spec set_style(t(), style()) :: t()
  def set_style(%__MODULE__{style: existing} = element, new_style) do
    %{element | style: Map.merge(existing, new_style)}
  end

  @doc """
  Sets attributes on an element, merging with existing attrs.
  """
  @spec set_attrs(t(), map()) :: t()
  def set_attrs(%__MODULE__{attrs: existing} = element, new_attrs) do
    %{element | attrs: Map.merge(existing, new_attrs)}
  end

  @doc """
  Sets the text content of an element.
  """
  @spec set_content(t(), String.t()) :: t()
  def set_content(%__MODULE__{} = element, content) do
    %{element | content: content}
  end

  @doc """
  Wraps element(s) in a group with a translation transform.
  """
  @spec translate_group(t() | [t()], number(), number()) :: t()
  def translate_group(elements, x, y) do
    children = if is_list(elements), do: elements, else: [elements]
    group(children, transform: Transform.translate(x, y))
  end
end
