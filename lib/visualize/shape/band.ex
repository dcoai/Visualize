defmodule Visualize.Shape.Band do
  @moduledoc """
  Band generator: a state timeline of one rectangle per datum (spec/04 §11, D-26).

  Each datum spans `x0` to `x1` at `y`, `height` tall, filled per datum. The coordinates
  are pixel accessors, so the caller applies the x scale inside `x0`/`x1` exactly as for
  `Visualize.Shape.Line` and `Visualize.Shape.Area`.

  ## Examples

      states = [
        %{from: ~U[2024-01-01 00:00:00Z], to: ~U[2024-01-01 06:00:00Z], state: :ok},
        %{from: ~U[2024-01-01 06:00:00Z], to: ~U[2024-01-01 09:00:00Z], state: :down}
      ]

      band =
        Visualize.Shape.Band.new()
        |> Visualize.Shape.Band.x0(fn d -> Visualize.Scale.apply(x_scale, d.from) end)
        |> Visualize.Shape.Band.x1(fn d -> Visualize.Scale.apply(x_scale, d.to) end)
        |> Visualize.Shape.Band.y(20)
        |> Visualize.Shape.Band.height(12)
        |> Visualize.Shape.Band.fill(fn d -> colour(d.state) end)

      rects = Visualize.Shape.Band.generate(band, states)

  """

  alias Visualize.IR.{Element, Path}
  alias Visualize.Shape.{Annotation, Line}

  defstruct x0: nil,
            x1: nil,
            y: 0,
            height: 10,
            fill: nil

  @type accessor :: (any() -> number()) | atom() | number()
  @typedoc "An accessor whose value is text: a 1-arity function, an atom field, or a string."
  @type text_accessor :: (any() -> String.t() | nil) | atom() | String.t()
  @type t :: %__MODULE__{
          x0: accessor() | nil,
          x1: accessor() | nil,
          y: accessor(),
          height: accessor(),
          fill: text_accessor() | nil
        }

  @doc "Creates a band generator reading tuple elements 0 and 1 as `x0`/`x1`"
  @spec new() :: t()
  def new do
    %__MODULE__{x0: fn d -> elem(d, 0) end, x1: fn d -> elem(d, 1) end}
  end

  @doc "Sets the start-edge accessor, in pixels"
  @spec x0(t(), accessor()) :: t()
  def x0(%__MODULE__{} = band, accessor), do: %{band | x0: Line.normalize_accessor(accessor)}

  @doc "Sets the end-edge accessor, in pixels"
  @spec x1(t(), accessor()) :: t()
  def x1(%__MODULE__{} = band, accessor), do: %{band | x1: Line.normalize_accessor(accessor)}

  @doc "Sets the top accessor, in pixels"
  @spec y(t(), accessor()) :: t()
  def y(%__MODULE__{} = band, accessor), do: %{band | y: Line.normalize_accessor(accessor)}

  @doc "Sets the height accessor, in pixels"
  @spec height(t(), accessor()) :: t()
  def height(%__MODULE__{} = band, accessor) do
    %{band | height: Line.normalize_accessor(accessor)}
  end

  @doc "Sets the fill accessor: a 1-arity function, an atom field, or a string constant"
  @spec fill(t(), text_accessor() | nil) :: t()
  def fill(%__MODULE__{} = band, accessor), do: %{band | fill: Annotation.text(accessor)}

  @doc """
  Returns one `:rect` element per datum, in data order.

  The rectangle is normalised so `x` is the lesser edge and `width` is non-negative; the
  style is `%{class: "band"}` plus `fill:` when the fill accessor yields a value.
  """
  @spec generate(t(), [any()]) :: [Element.t()]
  def generate(%__MODULE__{} = band, data) do
    Enum.map(data, fn d ->
      {x, y, w, h} = box(band, d)
      Element.rect(x, y, w, h, Annotation.fill_style(%{class: "band"}, band.fill, d))
    end)
  end

  @doc """
  Returns one `IR.Path` of closed rectangles, in data order, for a uniformly filled band.
  """
  @spec generate_path(t(), [any()]) :: Path.t()
  def generate_path(%__MODULE__{} = band, data) do
    commands =
      Enum.flat_map(data, fn d ->
        {x, y, w, h} = box(band, d)
        [{:M, x, y}, {:H, x + w}, {:V, y + h}, {:H, x}, :Z]
      end)

    %Path{commands: commands}
  end

  # {x, y, width, height} with the edges ordered.
  defp box(%__MODULE__{x0: x0, x1: x1, y: y, height: height}, d) do
    a = Line.normalize_accessor(x0).(d)
    b = Line.normalize_accessor(x1).(d)
    {min(a, b), Line.normalize_accessor(y).(d), abs(b - a), Line.normalize_accessor(height).(d)}
  end
end
