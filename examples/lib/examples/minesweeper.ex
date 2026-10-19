defmodule Examples.Minesweeper do
  @moduledoc """
  The game behind the `/minesweeper` page (#758), as data and pure functions: the host's
  state, which the page draws through a chart design and changes on each click.

  A game is a grid of `rows × cols` cells, `mines` of them mined. **The mines are placed on
  the first reveal**, away from the cell revealed and its neighbors, so the first click is
  always safe and opens an area. The placement is drawn from the game's `seed` alone, so a
  seed and a first click are one layout every time — which is what lets a test play a game
  to its end. A revealed cell with no mine around it reveals its neighbors, and they
  theirs, until the area is bordered by counts (the flood fill). A flag marks a hidden
  cell as a mine: it cannot be revealed while it stands, and it counts against the mines
  left. Revealing every safe cell wins, and every mine is flagged; revealing a mine loses,
  and every mine is shown, the one revealed marked.

      iex> game = Examples.Minesweeper.new(seed: 7)
      iex> game = Examples.Minesweeper.reveal(game, {4, 4})
      iex> game.status
      :playing
      iex> Examples.Minesweeper.mines_left(game)
      10
  """

  @typedoc "A cell: `{row, col}`, both from zero."
  @type cell :: {non_neg_integer(), non_neg_integer()}

  @typedoc "Where a game is: before its first reveal, under way, or over."
  @type status :: :ready | :playing | :won | :lost

  @typedoc """
  What a cell shows: `:hidden`, `:flagged` or `:revealed` while the game goes on; when it
  is over, `:mine` for a mine that was neither flagged nor revealed, `:exploded` for the
  one revealed, and `:misflagged` for a flag that stood on a safe cell.
  """
  @type state :: :hidden | :flagged | :revealed | :mine | :exploded | :misflagged

  @type t :: %__MODULE__{
          rows: pos_integer(),
          cols: pos_integer(),
          mines: non_neg_integer(),
          seed: integer(),
          mined: MapSet.t(cell()) | nil,
          revealed: MapSet.t(cell()),
          flagged: MapSet.t(cell()),
          status: status(),
          hit: cell() | nil
        }

  @enforce_keys [:rows, :cols, :mines, :seed]
  defstruct [
    :rows,
    :cols,
    :mines,
    :seed,
    mined: nil,
    revealed: MapSet.new(),
    flagged: MapSet.new(),
    status: :ready,
    hit: nil
  ]

  @doc """
  A new game, nothing mined yet: a 9 × 9 grid with 10 mines (the beginner's board) unless
  `rows:`, `cols:` and `mines:` say otherwise, its layout drawn from `seed:` (a random one
  when absent). Raises `ArgumentError` for more mines than the cells a first click leaves.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    rows = Keyword.get(opts, :rows, 9)
    cols = Keyword.get(opts, :cols, 9)
    mines = Keyword.get(opts, :mines, 10)
    seed = Keyword.get_lazy(opts, :seed, fn -> :rand.uniform(1_000_000_000) end)

    if mines > rows * cols - 1 do
      raise ArgumentError, "#{mines} mines do not fit a #{rows} × #{cols} grid beside a safe cell"
    end

    %__MODULE__{rows: rows, cols: cols, mines: mines, seed: seed}
  end

  @doc "Every cell of the grid, row by row."
  @spec cells(t()) :: [cell()]
  def cells(%__MODULE__{rows: rows, cols: cols}),
    do: for(r <- 0..(rows - 1), c <- 0..(cols - 1), do: {r, c})

  @doc "The cells around `cell` on the grid, up to eight."
  @spec neighbors(t(), cell()) :: [cell()]
  def neighbors(%__MODULE__{rows: rows, cols: cols}, {r, c}) do
    for dr <- -1..1,
        dc <- -1..1,
        {dr, dc} != {0, 0},
        (r + dr) in 0..(rows - 1),
        (c + dc) in 0..(cols - 1),
        do: {r + dr, c + dc}
  end

  @doc """
  The mines a game with nothing mined yet places for a first reveal at `first`: `mines`
  cells drawn by the seed from those outside `first` and its neighbors — outside `first`
  alone where the grid is too small to spare the neighbors.
  """
  @spec layout(t(), cell()) :: MapSet.t(cell())
  def layout(%__MODULE__{mines: mines, seed: seed} = game, first) do
    spared = [first | neighbors(game, first)]
    open = cells(game) -- spared
    candidates = if length(open) >= mines, do: open, else: cells(game) -- [first]
    state = :rand.seed_s(:exsss, seed)

    {picked, _rest, _state} =
      Enum.reduce(1..mines//1, {[], candidates, state}, fn _i, {picked, left, state} ->
        {i, state} = :rand.uniform_s(length(left), state)
        {cell, left} = List.pop_at(left, i - 1)
        {[cell | picked], left, state}
      end)

    MapSet.new(picked)
  end

  @doc "The mines around `cell`: 0 to 8, a mine's own cell aside. Zero before the mines are placed."
  @spec count(t(), cell()) :: 0..8
  def count(%__MODULE__{mined: nil}, _cell), do: 0
  def count(game, cell), do: Enum.count(neighbors(game, cell), &MapSet.member?(game.mined, &1))

  @doc "Whether `cell` holds a mine; `false` before the mines are placed."
  @spec mine?(t(), cell()) :: boolean()
  def mine?(%__MODULE__{mined: nil}, _cell), do: false
  def mine?(%__MODULE__{mined: mined}, cell), do: MapSet.member?(mined, cell)

  @doc """
  The game with `cell` revealed. The first reveal places the mines. A mine loses; a cell
  with no mine around it reveals its area; revealing every safe cell wins. A flagged cell,
  a revealed one and any cell of a game that is over are left as they are.
  """
  @spec reveal(t(), cell()) :: t()
  def reveal(%__MODULE__{status: status} = game, _cell) when status in [:won, :lost], do: game

  def reveal(%__MODULE__{mined: nil} = game, cell),
    do: reveal(%{game | mined: layout(game, cell), status: :playing}, cell)

  def reveal(game, cell) do
    cond do
      MapSet.member?(game.flagged, cell) or MapSet.member?(game.revealed, cell) -> game
      mine?(game, cell) -> %{game | status: :lost, hit: cell}
      true -> game |> flood([cell]) |> settle()
    end
  end

  # Reveal the cells of `stack`, and the neighbors of each that has no mine around it; a
  # flag is never revealed through, and a cell is revealed once.
  defp flood(game, []), do: game

  defp flood(game, [cell | stack]) do
    if MapSet.member?(game.revealed, cell) or MapSet.member?(game.flagged, cell) do
      flood(game, stack)
    else
      game = %{game | revealed: MapSet.put(game.revealed, cell)}
      next = if count(game, cell) == 0, do: neighbors(game, cell), else: []
      flood(game, next ++ stack)
    end
  end

  # Every safe cell revealed is a win, and every mine is then flagged.
  defp settle(game) do
    if MapSet.size(game.revealed) == game.rows * game.cols - game.mines,
      do: %{game | status: :won, flagged: game.mined},
      else: game
  end

  @doc """
  The game with the flag on a hidden `cell` put or taken away. A revealed cell, a game
  not yet begun and a game that is over are left as they are: the first move is a reveal.
  """
  @spec toggle_flag(t(), cell()) :: t()
  def toggle_flag(%__MODULE__{status: :playing} = game, cell) do
    cond do
      MapSet.member?(game.revealed, cell) -> game
      MapSet.member?(game.flagged, cell) -> %{game | flagged: MapSet.delete(game.flagged, cell)}
      true -> %{game | flagged: MapSet.put(game.flagged, cell)}
    end
  end

  def toggle_flag(game, _cell), do: game

  @doc "The mines not yet flagged: the mines less the flags, which may go below zero."
  @spec mines_left(t()) :: integer()
  def mines_left(game), do: game.mines - MapSet.size(game.flagged)

  @doc "Whether the game is over, won or lost."
  @spec over?(t()) :: boolean()
  def over?(%__MODULE__{status: status}), do: status in [:won, :lost]

  @doc "What `cell` shows (`t:state/0`)."
  @spec state(t(), cell()) :: state()
  def state(%__MODULE__{status: :lost} = game, cell) do
    flagged? = MapSet.member?(game.flagged, cell)

    cond do
      cell == game.hit -> :exploded
      flagged? and not mine?(game, cell) -> :misflagged
      flagged? -> :flagged
      mine?(game, cell) -> :mine
      MapSet.member?(game.revealed, cell) -> :revealed
      true -> :hidden
    end
  end

  def state(game, cell) do
    cond do
      MapSet.member?(game.revealed, cell) -> :revealed
      MapSet.member?(game.flagged, cell) -> :flagged
      true -> :hidden
    end
  end

  @doc """
  The grid as the rows a chart draws, one per cell, row by row: `row` and `col` (its
  identity), `state`, `count` — the number the cell shows, the mines around a revealed
  cell with any, else `nil`: a hidden cell's neighborhood never reaches the page, and a
  revealed zero shows nothing — and `glyph`, what is drawn on the cell: `:flag` on a flag
  that stands (or stood on a mine), `:bomb` on a mine shown at a loss and `:cross` on a
  flag that stood on a safe cell, else `nil`.
  """
  @spec rows(t()) :: [map()]
  def rows(game) do
    for {r, c} = cell <- cells(game) do
      state = state(game, cell)

      %{
        row: r,
        col: c,
        state: state,
        count: shown(state, count(game, cell)),
        glyph: glyph(state)
      }
    end
  end

  defp shown(:revealed, count) when count > 0, do: count
  defp shown(_state, _count), do: nil

  defp glyph(:flagged), do: :flag
  defp glyph(:misflagged), do: :cross
  defp glyph(state) when state in [:mine, :exploded], do: :bomb
  defp glyph(_state), do: nil

  @doc """
  The grid as text, a row a line: `*` a mine, a digit the mines around a safe cell, `.`
  for none. Before the mines are placed every cell is `.`. For tests and for reading a
  layout.
  """
  @spec picture(t()) :: String.t()
  def picture(game) do
    Enum.map_join(0..(game.rows - 1), "\n", fn r ->
      Enum.map_join(0..(game.cols - 1), fn c ->
        cond do
          mine?(game, {r, c}) -> "*"
          count(game, {r, c}) == 0 -> "."
          true -> Integer.to_string(count(game, {r, c}))
        end
      end)
    end)
  end
end
