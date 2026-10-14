defmodule Visualize.Board.View do
  @moduledoc """
  What a cell shows, as its process sends it to the board's subscribers (spec/15 §8.3,
  D-146): `{:visualize_board, board, {:cell, name, view}}`.

  A view is never blank. `svg` is the chart's frame, an accessible SVG root, or `nil`
  where no chart is drawn; `note` is the state's own drawing (`Visualize.Board.State`):
  the whole cell when `svg` is `nil`, a banner over the chart when the state is not
  `:live`, and `nil` when it is. `crosshair` and `keyboard` are the attribute maps of
  `CrosshairHook` and `KeyboardHook` for the frame (spec/10 §13.2, §17.2), `%{}` where
  there are none; `size` is the cell's box and `frames` the chart frames its process
  has drawn. `drawn` is the token of the drawing `svg` is, new at each frame the process
  draws, which a click carries back so the cell resolves it against that drawing alone
  (spec/15 §9.2, D-170); `nil` without one, and for a snapshot's view.
  """

  @enforce_keys [:cell, :state, :size]
  defstruct [
    :cell,
    :title,
    :state,
    :size,
    svg: nil,
    note: nil,
    crosshair: %{},
    keyboard: %{},
    frames: 0,
    drawn: nil
  ]

  @type t :: %__MODULE__{
          cell: atom(),
          title: String.t() | nil,
          state: Visualize.Board.State.t(),
          size: {number(), number()},
          svg: String.t() | nil,
          note: String.t() | nil,
          crosshair: %{String.t() => String.t()},
          keyboard: %{String.t() => String.t()},
          frames: non_neg_integer(),
          drawn: String.t() | nil
        }
end
