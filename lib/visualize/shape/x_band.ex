defmodule Visualize.Shape.XBand do
  @moduledoc """
  X-band generator: a shaded region between two domain x values, with an optional label
  (spec/04 §13, D-27).

  The edge accessors yield *domain* values that `scale/2` maps; without a scale they are
  pixels. Each datum is one annotation; by default a `{start, stop}` tuple.

  ## Examples

      band =
        Visualize.Shape.XBand.new()
        |> Visualize.Shape.XBand.scale(x_scale)
        |> Visualize.Shape.XBand.y1(height)
        |> Visualize.Shape.XBand.label("incident")

      [group] = Visualize.Shape.XBand.generate(band, [{t0, t1}])

  """

  alias Visualize.IR.Element
  alias Visualize.Shape.{Annotation, Line}

  defstruct x0: nil,
            x1: nil,
            scale: nil,
            y0: 0,
            y1: 100,
            fill: nil,
            label: nil

  @typedoc "An accessor whose value is text or a fill: a 1-arity function, an atom field, or a string."
  @type text_accessor :: (any() -> String.t() | nil) | atom() | String.t()
  @type t :: %__MODULE__{
          x0: Line.accessor() | nil,
          x1: Line.accessor() | nil,
          scale: struct() | nil,
          y0: Line.accessor(),
          y1: Line.accessor(),
          fill: (any() -> String.t() | nil) | nil,
          label: (any() -> String.t() | nil) | nil
        }

  # The brush selection's fill (spec/10 §6.2), so a recorded window reads like a live one.
  @default_fill "rgba(119, 119, 119, 0.2)"

  @doc "Creates an x-band generator reading tuple elements 0 and 1 as its edges"
  @spec new() :: t()
  def new do
    %__MODULE__{
      x0: fn d -> elem(d, 0) end,
      x1: fn d -> elem(d, 1) end,
      fill: Annotation.text(@default_fill)
    }
  end

  @doc "Sets the first-edge domain-value accessor"
  @spec x0(t(), Line.accessor()) :: t()
  def x0(%__MODULE__{} = band, accessor), do: %{band | x0: Line.normalize_accessor(accessor)}

  @doc "Sets the second-edge domain-value accessor"
  @spec x1(t(), Line.accessor()) :: t()
  def x1(%__MODULE__{} = band, accessor), do: %{band | x1: Line.normalize_accessor(accessor)}

  @doc "Sets the x scale the edges map through; `nil` means the values are pixels"
  @spec scale(t(), struct() | nil) :: t()
  def scale(%__MODULE__{} = band, nil), do: %{band | scale: nil}
  def scale(%__MODULE__{} = band, scale) when is_struct(scale), do: %{band | scale: scale}

  @doc "Sets the first vertical-extent accessor, in pixels"
  @spec y0(t(), Line.accessor()) :: t()
  def y0(%__MODULE__{} = band, accessor), do: %{band | y0: Line.normalize_accessor(accessor)}

  @doc "Sets the second vertical-extent accessor, in pixels"
  @spec y1(t(), Line.accessor()) :: t()
  def y1(%__MODULE__{} = band, accessor), do: %{band | y1: Line.normalize_accessor(accessor)}

  @doc "Sets the fill accessor: function, atom field, or string constant"
  @spec fill(t(), text_accessor() | nil) :: t()
  def fill(%__MODULE__{} = band, accessor), do: %{band | fill: Annotation.text(accessor)}

  @doc "Sets the label accessor: function, atom field, or string constant; `nil` clears it"
  @spec label(t(), text_accessor() | nil) :: t()
  def label(%__MODULE__{} = band, accessor), do: %{band | label: Annotation.text(accessor)}

  @doc """
  Returns one `:group` element per datum: the rectangle, then the label when there is one.
  """
  @spec generate(t(), Visualize.Data.Table.source()) :: [Element.t()]
  def generate(%__MODULE__{} = band, data) do
    Enum.map(Visualize.Data.Table.rows(data), fn d ->
      p0 = Annotation.position(band.scale, Annotation.value(band.x0, d))
      p1 = Annotation.position(band.scale, Annotation.value(band.x1, d))
      y0 = Annotation.value(band.y0, d)
      y1 = Annotation.value(band.y1, d)
      left = min(p0, p1)
      top = min(y0, y1)

      rect =
        Element.rect(
          left,
          top,
          abs(p1 - p0),
          abs(y1 - y0),
          Annotation.fill_style(%{}, band.fill, d)
        )

      Element.group([rect | Annotation.label(band.label, d, left, top)],
        style: %{class: "x-band"}
      )
    end)
  end
end
