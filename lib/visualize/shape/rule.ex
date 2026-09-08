defmodule Visualize.Shape.Rule do
  @moduledoc """
  Rule generator: a vertical line at a domain x value, with an optional label
  (spec/04 §12, D-27).

  The x accessor yields a *domain* value that `scale/2` maps, so the rule stays aligned
  with the axis whatever the margins. Without a scale the value is a pixel coordinate.
  Each datum is one annotation; by default the datum is the value itself.

  ## Examples

      rule =
        Visualize.Shape.Rule.new()
        |> Visualize.Shape.Rule.scale(x_scale)
        |> Visualize.Shape.Rule.y1(height)
        |> Visualize.Shape.Rule.label("deploy")

      [group] = Visualize.Shape.Rule.generate(rule, [~U[2024-01-01 12:00:00Z]])

  """

  alias Visualize.IR.Element
  alias Visualize.Shape.{Annotation, Line}

  defstruct x: nil,
            scale: nil,
            y0: 0,
            y1: 100,
            label: nil

  @typedoc "An accessor whose value is text: a 1-arity function, an atom field, or a string."
  @type text_accessor :: (any() -> String.t() | nil) | atom() | String.t()
  @type t :: %__MODULE__{
          x: Line.accessor() | nil,
          scale: struct() | nil,
          y0: Line.accessor(),
          y1: Line.accessor(),
          label: (any() -> String.t() | nil) | nil
        }

  @line_style %{stroke: :current_color, stroke_width: 1}

  @doc "Creates a rule generator reading each datum as its x value, with extent 0 to 100"
  @spec new() :: t()
  def new, do: %__MODULE__{x: fn d -> d end}

  @doc "Sets the domain-value accessor"
  @spec x(t(), Line.accessor()) :: t()
  def x(%__MODULE__{} = rule, accessor), do: %{rule | x: Line.normalize_accessor(accessor)}

  @doc "Sets the x scale the values map through; `nil` means the values are pixels"
  @spec scale(t(), struct() | nil) :: t()
  def scale(%__MODULE__{} = rule, nil), do: %{rule | scale: nil}
  def scale(%__MODULE__{} = rule, scale) when is_struct(scale), do: %{rule | scale: scale}

  @doc "Sets the first vertical-extent accessor, in pixels"
  @spec y0(t(), Line.accessor()) :: t()
  def y0(%__MODULE__{} = rule, accessor), do: %{rule | y0: Line.normalize_accessor(accessor)}

  @doc "Sets the second vertical-extent accessor, in pixels"
  @spec y1(t(), Line.accessor()) :: t()
  def y1(%__MODULE__{} = rule, accessor), do: %{rule | y1: Line.normalize_accessor(accessor)}

  @doc "Sets the label accessor: function, atom field, or string constant; `nil` clears it"
  @spec label(t(), text_accessor() | nil) :: t()
  def label(%__MODULE__{} = rule, accessor), do: %{rule | label: Annotation.text(accessor)}

  @doc """
  Returns one `:group` element per datum: the line, then the label when there is one.
  """
  @spec generate(t(), Visualize.Data.Table.source()) :: [Element.t()]
  def generate(%__MODULE__{} = rule, data) do
    Enum.map(Visualize.Data.Table.rows(data), fn d ->
      px = Annotation.position(rule.scale, Annotation.value(rule.x, d))
      y0 = Annotation.value(rule.y0, d)
      y1 = Annotation.value(rule.y1, d)
      line = Element.line(px, y0, px, y1, @line_style)

      Element.group([line | Annotation.label(rule.label, d, px, min(y0, y1))],
        style: %{class: "rule"}
      )
    end)
  end
end
