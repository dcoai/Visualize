defmodule Visualize.Chart.Placements do
  @moduledoc false
  # One placement pass per update (spec/14 §21.5, #811, D-202): every data mark of a
  # cartesian frame, its rows and their pixels, placed once for the drawing and for the
  # keyboard. `Visualize.Chart.generate/2` and `Visualize.Chart.Summary.points/2` both
  # read it, so a chart drawn with its keyboard does not place its items twice.
  #
  # An entry holds the mark it placed and the rows it read. A reader uses the pixels only
  # for that same mark over those same rows — a term compared with itself is one
  # comparison, not a walk — and places anything else itself, so a placement is a saving
  # and never a different answer.

  alias Visualize.Chart.{Applied, Frame, Mark}
  alias Visualize.Chart.Mark.Channels

  @type entry :: %{mark: map(), rows: [map()], pixels: [Channels.pixel_row()]}
  @type t :: %{optional({term(), non_neg_integer()}) => entry()}

  # The marks the keyboard reads no point from, as `Visualize.Chart.Summary` skips them.
  @auxiliary [:rule, :band, :x_band, :text, :tiles]

  @doc false
  # Each realized frame's placed marks by `{frame name, the mark's zero-based position}`:
  # the rows `Visualize.Chart.Mark.rows/3` gives and `Channels.pixels/1` of them, in the
  # frame the mark draws in (its color scale as `Mark.generate/3` lays it). A faceted
  # frame, which places per panel, and a frame that is not cartesian are not placed.
  @spec new(Applied.t()) :: t()
  def new(%Applied{sources: sources} = applied) do
    for %Frame{kind: :cartesian, facet: nil} = frame <- realized(applied),
        {mark, position} <- Enum.with_index(frame.marks),
        Map.get(mark, :type) not in [:choose | @auxiliary],
        into: %{} do
      rows = Mark.rows(frame, mark, sources)
      drawn = Mark.colored(frame, mark)
      pixels = Channels.pixels(%{frame: drawn, mark: mark, rows: rows})
      {{frame.name, position}, %{mark: mark, rows: rows, pixels: pixels}}
    end
  end

  @doc false
  # The entry of the mark at `position` in `frame`, when it placed this mark; else `nil`.
  @spec fetch(t() | nil, Frame.t(), map(), non_neg_integer()) :: entry() | nil
  def fetch(nil, _frame, _mark, _position), do: nil

  def fetch(placements, %Frame{name: name}, mark, position) do
    case Map.get(placements, {name, position}) do
      %{mark: ^mark} = entry -> entry
      _other -> nil
    end
  end

  defp realized(%Applied{frames: frames, frame: frame}) when frames == %{} or is_nil(frames),
    do: [frame]

  defp realized(%Applied{frames: frames}), do: Map.values(frames)
end
