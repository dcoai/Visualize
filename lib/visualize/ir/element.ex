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

      iex> alias Visualize.IR.{Element, Path}
      iex> path = Path.new() |> Path.move_to(0, 0) |> Path.line_to(100, 100)
      iex> element = Element.path(path, %{stroke: "blue", fill: :none})
      iex> element.type
      :path
      iex> element.style
      %{stroke: "blue", fill: :none}
      iex> element.path
      %Visualize.IR.Path{commands: [{:M, 0, 0}, {:L, 100, 100}]}

  """

  alias Visualize.IR.{Path, Transform}

  defstruct [
    :type,
    attrs: %{},
    style: %{},
    transform: nil,
    children: [],
    content: nil,
    path: nil,
    clip: nil
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
          | :filter
          | :fe_drop_shadow
          | :fe_gaussian_blur
          | :root
          | :title
          | :desc

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
          optional(:font_weight) => String.t() | number() | :normal | :bold,
          optional(:font_style) => :normal | :italic,
          optional(:text_anchor) => :start | :middle | :end,
          optional(:dominant_baseline) => atom(),
          optional(:class) => String.t(),
          optional(:blend) => atom(),
          optional(:effect) => :none | :shadow | :blur,
          optional(:effect_radius) => number()
        }

  @typedoc """
  Where an element is drawn (spec/02 §2.1): only where the shape is, or only where it is
  not — how a stroke is kept inside or outside an edge (spec/14 §5.6).
  """
  @type clip :: %{shape: t(), keep: :inside | :outside}

  @type t :: %__MODULE__{
          type: element_type(),
          attrs: map(),
          style: style(),
          transform: Transform.t() | nil,
          children: [t()],
          content: String.t() | nil,
          path: Path.t() | nil,
          clip: clip() | nil
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
  A filter (spec/02 §2.1): its id and its primitives, for an element's `effect`.
  """
  @spec filter(String.t(), [t()]) :: t()
  def filter(id, children) when is_binary(id) and is_list(children) do
    new(:filter, attrs: %{id: id}, children: children)
  end

  @doc "A drop shadow primitive of the offset and the blur radius, at 0.35 opacity."
  @spec drop_shadow(number(), number(), number()) :: t()
  def drop_shadow(dx, dy, radius) do
    new(:fe_drop_shadow, attrs: %{dx: dx, dy: dy, std_deviation: radius, flood_opacity: 0.35})
  end

  @doc "A Gaussian blur primitive of the radius."
  @spec gaussian_blur(number()) :: t()
  def gaussian_blur(radius), do: new(:fe_gaussian_blur, attrs: %{std_deviation: radius})

  @doc """
  Creates a title element: the accessible name of the element it is the first child of.
  """
  @spec title(String.t()) :: t()
  def title(text) when is_binary(text), do: new(:title, content: text)

  @doc """
  Creates a desc element: the accessible description of its parent.
  """
  @spec desc(String.t()) :: t()
  def desc(text) when is_binary(text), do: new(:desc, content: text)

  @doc """
  Creates a root SVG element, `role="img"`.

  ## Options

    * `:view_box` - the `viewBox` (default `"0 0 <width> <height>"`)
    * `:children` - the child elements (default `[]`)
    * `:preserve_aspect_ratio` - the `preserveAspectRatio` attribute; absent by default
    * `:responsive` - when true, `preserveAspectRatio="xMidYMid meet"` (unless given) and
      `style="width:100%;height:auto"`, so the `<svg>` fills its container's width at the
      drawing's aspect ratio while `width` and `height` stay its intrinsic size (D-54)
    * `:title`, `:description` - the accessible name and description (D-56): a `<title>`
      and a `<desc>` become the first children, each with an id, and `aria-labelledby`
      names them
    * `:id` - the root's id and the prefix of the two child ids (`<id>-title`,
      `<id>-desc`); defaults to `vis-` and a hash of the two texts, and is only set when
      a title or description is given
  """
  @spec root(number(), number(), keyword()) :: t()
  def root(width, height, opts \\ []) do
    view_box = Keyword.get(opts, :view_box, "0 0 #{width} #{height}")
    responsive = Keyword.get(opts, :responsive, false)
    default_ratio = if responsive, do: "xMidYMid meet"
    ratio = Keyword.get(opts, :preserve_aspect_ratio, default_ratio)
    title = Keyword.get(opts, :title)
    description = Keyword.get(opts, :description)
    ids = label_ids(Keyword.get(opts, :id), title, description)

    attrs =
      %{width: width, height: height, view_box: view_box, role: "img"}
      |> put_unless_nil(:preserve_aspect_ratio, ratio)
      |> put_unless_nil(:style, if(responsive, do: "width:100%;height:auto"))
      |> put_unless_nil(:id, ids.root)
      |> put_unless_nil(:aria_labelledby, ids.labelledby)

    labels =
      Enum.reject(
        [
          title && set_attrs(title(title), %{id: ids.title}),
          description && set_attrs(desc(description), %{id: ids.desc})
        ],
        &is_nil/1
      )

    new(:root, attrs: attrs, children: labels ++ Keyword.get(opts, :children, []))
  end

  @doc false
  # The ids of a root's accessible name and description (D-56): `nil` for each text that
  # is absent, and `nil` throughout when both are; `labelledby` is the `aria-labelledby`
  # value naming the ids present. The prefix is the given id or `vis-` plus a base-36
  # hash of the two texts, so equal charts share ids and different ones do not.
  def label_ids(_id, nil, nil), do: %{root: nil, title: nil, desc: nil, labelledby: nil}

  def label_ids(id, title, description) do
    prefix =
      id || "vis-" <> String.downcase(Integer.to_string(:erlang.phash2({title, description}), 36))

    title_id = if title, do: prefix <> "-title"
    desc_id = if description, do: prefix <> "-desc"
    labelledby = Enum.join(Enum.reject([title_id, desc_id], &is_nil/1), " ")
    %{root: prefix, title: title_id, desc: desc_id, labelledby: labelledby}
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
  The element drawn only where `shape` is (`:inside`) or only where it is not
  (`:outside`) (spec/02 §2.1). The shape's style is ignored by every backend.

      iex> square = Visualize.IR.Element.rect(0, 0, 10, 10)
      iex> Visualize.IR.Element.clip(square, square, :inside).clip.keep
      :inside
  """
  @spec clip(t(), t(), :inside | :outside) :: t()
  def clip(%__MODULE__{} = element, %__MODULE__{} = shape, keep)
      when keep in [:inside, :outside] do
    # The shape is geometry alone: its style, its own clip and its data attributes go.
    geometry = %{
      shape
      | style: %{},
        clip: nil,
        attrs: Map.filter(shape.attrs, fn {k, _} -> is_atom(k) end)
    }

    %{element | clip: %{shape: geometry, keep: keep}}
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
  Writes a datum's fields onto the element as the data attributes `TooltipHook` reads
  (spec/10 §12.2, D-75).

  `fields` is a map — written in `Enum.sort/1` order — or a keyword list, in its order.
  `data-datum` lists the field names; `data-datum-<field>` carries `to_string/1` of each
  value, with every `_` in the name as `-`, and a `nil` value writes no attribute. The keys
  are strings, so no atom is created from a row's names.

  ## Examples

      iex> Visualize.IR.Element.circle(1, 2, 3)
      ...> |> Visualize.IR.Element.datum(at: ~U[2024-01-01 00:00:00Z], big_v: 4, gap: nil)
      ...> |> Map.fetch!(:attrs)
      %{
        "data-datum" => "at big_v gap",
        "data-datum-at" => "2024-01-01 00:00:00Z",
        "data-datum-big-v" => "4",
        cx: 1,
        cy: 2,
        r: 3
      }

  """
  @spec datum(t(), map() | keyword()) :: t()
  def datum(%__MODULE__{} = element, fields) when is_map(fields) or is_list(fields) do
    pairs = if is_map(fields), do: Enum.sort(fields), else: fields
    names = Enum.map_join(pairs, " ", fn {field, _value} -> to_string(field) end)

    attrs =
      for {field, value} <- pairs, value != nil, into: %{"data-datum" => names} do
        {"data-datum-" <> String.replace(to_string(field), "_", "-"), to_string(value)}
      end

    set_attrs(element, attrs)
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
