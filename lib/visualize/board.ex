defmodule Visualize.Board do
  @moduledoc """
  A dashboard as data: designs laid out on a 12-column grid, sharing a time window,
  variables and a sync group, but never geometry (spec/15, D-141).

  A composite flattens into one chart (spec/14 §19.6); a board **never flattens**. Each
  cell is a placement `{x, y, w, h}` and a reference to a component in the store — a
  composite id, whose entry holds a composite or a flat design — and is applied, rendered
  and updated as its own chart. The board names no feed: its sources are the aggregate of
  its cells' slots, namespaced per cell (`required_sources/3`), and a connector fills them
  with a separate `Visualize.Board.Binding`.

  The board is a value. `from_map/2` and `to_map/1` are exact inverses, and `from_json/2`
  and `to_json/1` the same round trip over JSON, stamped `"$version"` and read under the
  version policy and sanity limits of spec/14 §9.1–9.2. `validate/1` checks a board alone
  and `validate/3` given a store; `realise/4` applies every cell, purely. The processes
  that keep a board live are the runtime's (#540).

  ## Examples

      iex> {:ok, board} =
      ...>   Visualize.Board.from_map(%{
      ...>     cells: %{
      ...>       latency: %{x: 0, y: 0, w: 8, h: 4, ref: {:composite, 1}},
      ...>       errors: %{x: 8, y: 0, w: 4, h: 4, ref: {:composite, 1}, vars: %{unit: "%"}}
      ...>     },
      ...>     window: %{last: 3600},
      ...>     vars: %{service: "api"}
      ...>   })
      iex> Visualize.Board.vars(board, :errors)
      %{service: "api", unit: "%"}
      iex> Visualize.Board.arrange(board, 400)
      [latency: %{x: 0, y: 0, w: 12, h: 4}, errors: %{x: 0, y: 4, w: 12, h: 4}]
      iex> Visualize.Board.from_map(%{cells: %{a: %{x: 6, y: 0, w: 8, h: 2, ref: {:style, 3}}}})
      {:error, [{[:cells, :a], {:off_grid, 12}}, {[:cells, :a, :ref], {:ref_kind, :composite, :style}}]}

  """

  # Jason is optional (spec/14 §11.1, D-50): the JSON functions answer its absence as a
  # value, as `Visualize.Chart`'s do.
  @compile {:no_warn_undefined, Jason}

  alias Visualize.Board.{Codec, Validator}
  alias Visualize.Chart
  alias Visualize.Chart.{Limits, Migration}
  alias Visualize.Chart.Validator, as: ChartValidator
  alias Visualize.Chart.Validator.Words
  alias Visualize.Data.Schema.Cache

  @layout %{breakpoint: 768, row_height: 80, gap: 8}

  defstruct version: Migration.current(),
            meta: %{},
            cells: %{},
            window: nil,
            zone: "Etc/UTC",
            vars: %{},
            sync: nil,
            layout: %{},
            stale_after: nil,
            links: %{}

  @typedoc "A cell (spec/15 §1.3): a placement and a component reference."
  @type cell :: %{
          required(:x) => non_neg_integer(),
          required(:y) => non_neg_integer(),
          required(:w) => pos_integer(),
          required(:h) => pos_integer(),
          required(:ref) => {:composite, pos_integer()},
          optional(:title) => String.t() | nil,
          optional(:vars) => %{atom() => term()},
          optional(:sync) => boolean(),
          optional(:drill) => drill() | nil
        }

  @typedoc """
  A cell's drill target (spec/15 §13.3): the board a click on a datum opens — `:self`, or
  the host's name for a board — and its variables, each a field of the datum or a value.
  """
  @type drill :: %{
          required(:board) => atom() | String.t() | pos_integer(),
          optional(:vars) => %{atom() => {:datum, atom()} | term()}
        }

  @typedoc "The time window (spec/15 §1.5)."
  @type window :: nil | %{last: number()} | %{from: DateTime.t(), to: DateTime.t()}

  @type t :: %__MODULE__{
          version: pos_integer(),
          meta: map(),
          cells: %{atom() => cell()},
          window: window(),
          zone: String.t(),
          vars: %{atom() => term()},
          sync: String.t() | nil,
          layout: map(),
          stale_after: number() | nil,
          links: %{atom() => atom()}
        }

  @typedoc "A placement on the grid."
  @type rect :: %{x: non_neg_integer(), y: non_neg_integer(), w: pos_integer(), h: pos_integer()}

  @typedoc """
  What resolution reads (spec/14 §19.6): a fetch function, or a map from id to fragment.
  """
  @type store :: (term() -> {:ok, map()} | :error) | %{term() => map()}

  @typedoc "A fault: the path from the board to the value, and why (spec/14 §10.1)."
  @type error :: {list(), term()}

  @doc "The board's width in grid columns: `12` (spec/15 §1.4)."
  @spec columns() :: pos_integer()
  def columns, do: Validator.columns()

  # -- the map form (spec/15 §2.1, §2.3) ---------------------------------------------------

  @doc """
  The board of a map, or every fault of it (spec/15 §2.1).

  A version newer than this library reads is refused first, before anything else is read
  (spec/14 §9.1); then the map is held to the `depth` and `items` limits — `limits:` as
  `Visualize.Chart.from_map/2` takes them, the defaults when absent — and validated alone
  (spec/15 §3.1). A map with no `version` reads as the current one.

      iex> Visualize.Board.from_map(%{version: 3})
      {:error, [{[:version], {:newer_schema, 3, 2}}]}
  """
  @spec from_map(term(), keyword()) :: {:ok, t()} | {:error, [error(), ...]}
  def from_map(map, opts \\ []) do
    limits = opts |> Keyword.get(:limits, []) |> Limits.new()

    with :ok <- readable(map),
         :ok <- Validator.done(Limits.structure(map, limits)) do
      read(map)
    end
  end

  defp readable(%{version: v}) do
    with {:error, reason} <- Migration.readable(v), do: {:error, [{[:version], reason}]}
  end

  defp readable(_map), do: :ok

  defp read(map) when is_map(map) and not is_struct(map) do
    map = Map.put_new(map, :version, Migration.current())

    with :ok <- Validator.validate(map) do
      {:ok, struct(__MODULE__, Map.take(map, Validator.board_keys()))}
    end
  end

  defp read(other), do: Validator.validate(other)

  @doc "As `from_map/2`, raising `ArgumentError` with every fault formatted."
  @spec from_map!(term(), keyword()) :: t()
  def from_map!(map, opts \\ []) do
    case from_map(map, opts) do
      {:ok, board} ->
        board

      {:error, errors} ->
        raise ArgumentError,
              "invalid board:\n" <> Enum.map_join(errors, "\n", &("  " <> format_error(&1)))
    end
  end

  @doc "The board as a map: every key of spec/15 §1.2, `version` included."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = board), do: Map.from_struct(board)

  # -- the JSON form (spec/15 §2.2) --------------------------------------------------------

  @doc """
  The board of a JSON document (spec/15 §2.2), with `limits:` as `from_map/2` takes them.

  The document's `"$version"` is checked, and its nesting and the size of its lists and
  maps held to the limits, **before** a key is decoded, so a newer or an oversized board
  makes no atom and a path in such an error holds the document's own key strings. A key
  the board does not know stays a string and is `:unknown_key` at its own spelling. A
  document that does not parse, or is not an object, is `{:error, [{[], {:json, message}}]}`;
  without Jason the result is `{:error, {:missing_dependency, :jason}}`.

      iex> Visualize.Board.from_json(~s({"$version": 9, "cells": {}}))
      {:error, [{["$version"], {:newer_schema, 9, 2}}]}
  """
  @spec from_json(String.t(), keyword()) ::
          {:ok, t()} | {:error, [error(), ...] | {:missing_dependency, :jason}}
  def from_json(json, opts \\ []) when is_binary(json) do
    if Code.ensure_loaded?(Jason) do
      limits = opts |> Keyword.get(:limits, []) |> Limits.new()

      case Jason.decode(json) do
        {:ok, term} when is_map(term) -> read_json(term, limits)
        {:ok, other} -> {:error, [{[], {:json, "a board is an object, got #{inspect(other)}"}}]}
        {:error, error} -> {:error, [{[], {:json, Exception.message(error)}}]}
      end
    else
      {:error, {:missing_dependency, :jason}}
    end
  end

  defp read_json(term, limits) do
    {stamp, term} = Map.pop(term, Codec.stamp())

    with :ok <- stamped(stamp),
         :ok <- Validator.done(Limits.structure(term, limits)) do
      map = Codec.decode(term)
      read(if stamp == nil, do: map, else: Map.put(map, :version, stamp))
    end
  end

  defp stamped(stamp) do
    with {:error, reason} <- Migration.readable(stamp),
         do: {:error, [{[Codec.stamp()], reason}]}
  end

  @doc """
  The board as a JSON document stamped `"$version"` (spec/15 §2.2), or
  `{:error, {:missing_dependency, :jason}}`. `from_json(to_json(board))` is `{:ok, board}`.
  """
  @spec to_json(t()) :: {:ok, String.t()} | {:error, {:missing_dependency, :jason}}
  def to_json(%__MODULE__{} = board) do
    if Code.ensure_loaded?(Jason) do
      {:ok, json} = board |> to_map() |> Codec.encode() |> Jason.encode()
      {:ok, json}
    else
      {:error, {:missing_dependency, :jason}}
    end
  end

  # -- validation (spec/15 §3) -------------------------------------------------------------

  @doc """
  `:ok`, or every fault of a board — or a board map — alone (spec/15 §3.1): its keys and
  types, cells off the grid or overlapping, the window, the zone, and component references
  of the wrong kind.

      iex> Visualize.Board.validate(%{cells: %{
      ...>   a: %{x: 0, y: 0, w: 6, h: 2, ref: {:composite, 1}},
      ...>   b: %{x: 4, y: 1, w: 6, h: 2, ref: {:composite, 2}}
      ...> }})
      {:error, [{[:cells, :b], {:overlap, :a}}]}
  """
  @spec validate(t() | map()) :: :ok | {:error, [error(), ...]}
  def validate(%__MODULE__{} = board), do: board |> to_map() |> Validator.validate()
  def validate(map), do: Validator.validate(map)

  @doc "As `validate/3` with `[]` options."
  @spec validate(t() | map(), store()) :: :ok | {:error, [error(), ...]}
  def validate(board, store), do: validate(board, store, [])

  @doc """
  `:ok`, or every fault of the board alone and then given the store (spec/15 §3.2).

  Each cell's component is fetched, flattened through the store and read through
  `Visualize.Chart.from_map/2` with `limits:`. An id the store does not hold is
  `{:dangling, id}` and a component that reaches itself `{:cycle, chain}`, at the cell's
  `ref`; a component that is not a design has its faults under the ref; a cell variable
  its component does not declare is `{:undeclared, :var, name}`; and a cell that cannot
  join the board's sync group has the component's `{:sync, …}` fault at its `sync`.

  A cell's drill target (spec/15 §13.3) is checked against `boards:` — a map from a ref
  to a board, or a fetch `(ref -> {:ok, board} | :error)`: a ref it does not hold is
  `{:no_board, ref}`, a variable the target does not declare `{:undeclared, :var, name}`,
  and a `{:datum, field}` whose field the component's sources do not declare
  `{:undeclared, :field, field}`. A `:self` target is checked against this board with or
  without `boards:`.
  """
  @spec validate(t() | map(), store(), keyword()) :: :ok | {:error, [error(), ...]}
  def validate(board, store, opts) do
    with :ok <- validate(board) do
      map = if is_struct(board, __MODULE__), do: to_map(board), else: board
      {_charts, errors} = resolved(map, store, opts)
      Validator.done(errors)
    end
  end

  # Every cell's component, and every fault given the store.
  defp resolved(map, store, opts) do
    limits = Keyword.get(opts, :limits, [])

    {charts, errors} =
      Validator.components(Map.get(map, :cells, %{}), Validator.fetch(store), limits)

    boards = if Keyword.has_key?(opts, :boards), do: Validator.fetch(opts[:boards])

    {charts, errors ++ Validator.given(map, charts) ++ Validator.drills(map, charts, boards)}
  end

  @doc """
  One fault as a line a person reads, in the words of `Visualize.Chart.Validator.format/1`
  and with the root named `board`.

      iex> Visualize.Board.format_error({[:cells, :b], {:overlap, :a}})
      "cells.b: overlaps cell :a"
      iex> Visualize.Board.format_error({[], {:type, :board}})
      "board: must be a board map"
  """
  @spec format_error(error()) :: String.t()
  def format_error({[], reason}), do: "board: " <> Words.words(reason)
  def format_error(error), do: ChartValidator.format(error)

  # -- layout (spec/15 §1.6) ---------------------------------------------------------------

  @doc """
  The effective layout: the board's `layout` over `breakpoint: 768`, `row_height: 80` and
  `gap: 8`, metresis's grid.
  """
  @spec layout(t()) :: %{
          breakpoint: pos_integer(),
          row_height: pos_integer(),
          gap: non_neg_integer()
        }
  def layout(%__MODULE__{layout: layout}), do: Map.merge(@layout, layout)

  @doc """
  Each cell's placement at a container width, in reading order — by `y`, then `x`, then
  name (spec/15 §1.6). At the breakpoint or wider, every cell is where it was placed;
  narrower, the cells stack in that order, each across all 12 columns and keeping its
  height.
  """
  @spec arrange(t(), number()) :: [{atom(), rect()}]
  def arrange(%__MODULE__{cells: cells} = board, width) when is_number(width) do
    ordered =
      cells
      |> Enum.map(fn {name, cell} -> {name, Map.take(cell, [:x, :y, :w, :h])} end)
      |> Enum.sort_by(fn {name, %{x: x, y: y}} -> {y, x, name} end)

    if width >= layout(board).breakpoint do
      ordered
    else
      {stacked, _row} =
        Enum.map_reduce(ordered, 0, fn {name, %{h: h}}, row ->
          {{name, %{x: 0, y: row, w: columns(), h: h}}, row + h}
        end)

      stacked
    end
  end

  @doc """
  Each cell's box in pixels at a container width, `{x, y, w, h}`, after reflow (spec/15
  §1.6): a column is `(width − 11 × gap) / 12` wide and a row `row_height` high, a cell
  spanning its columns and rows and the gaps between them, as a CSS grid with that gap
  draws it.

      iex> board = Visualize.Board.from_map!(%{cells: %{a: %{x: 6, y: 1, w: 6, h: 2, ref: {:composite, 1}}}})
      iex> Visualize.Board.boxes(board, 1288)
      %{a: {648.0, 88, 640.0, 168}}
  """
  @spec boxes(t(), number()) :: %{atom() => {number(), number(), number(), number()}}
  def boxes(%__MODULE__{} = board, width) when is_number(width) do
    %{row_height: row, gap: gap} = layout(board)
    column = (width - (columns() - 1) * gap) / columns()

    Map.new(arrange(board, width), fn {name, %{x: x, y: y, w: w, h: h}} ->
      {name,
       {x * (column + gap), y * (row + gap), w * column + (w - 1) * gap, h * row + (h - 1) * gap}}
    end)
  end

  # -- shared state (spec/15 §1.5, §5) -----------------------------------------------------

  @doc """
  The window resolved at `now` (spec/15 §1.5): `{from, to}` as UTC `DateTime`s, or `nil`
  for a board with no window. Now is the caller's — the board's — never a feed's.

      iex> board = Visualize.Board.from_map!(%{window: %{last: 3600}})
      iex> Visualize.Board.window(board, ~U[2026-10-11 12:00:00Z])
      {~U[2026-10-11 11:00:00Z], ~U[2026-10-11 12:00:00Z]}
  """
  @spec window(t(), DateTime.t()) :: {DateTime.t(), DateTime.t()} | nil
  def window(%__MODULE__{window: nil}, _now), do: nil
  def window(%__MODULE__{window: %{from: from, to: to}}, _now), do: {from, to}

  def window(%__MODULE__{window: %{last: seconds}}, %DateTime{} = now) do
    to = DateTime.shift_zone!(now, "Etc/UTC")
    {back(to, seconds), to}
  end

  defp back(to, seconds) when is_integer(seconds), do: DateTime.add(to, -seconds, :second)
  defp back(to, seconds), do: DateTime.add(to, -round(seconds * 1_000_000), :microsecond)

  @doc """
  A resolved window as a person reads it, in the board's zone (spec/15 §1.5, §9.1): each
  end shifted from UTC into `zone` by the host's time-zone database and written
  `YYYY-MM-DD HH:MM:SS`, then the zone's name; `nil` for no window. A zone the database
  does not know leaves the ends in UTC. The board component's header and an export's
  (§12.1) both print it.

      iex> Visualize.Board.window_text({~U[2026-10-11 11:00:00Z], ~U[2026-10-11 12:00:00Z]}, "Etc/UTC")
      "2026-10-11 11:00:00 – 2026-10-11 12:00:00 (Etc/UTC)"
      iex> Visualize.Board.window_text(nil, "Etc/UTC")
      nil
  """
  @spec window_text({DateTime.t(), DateTime.t()} | nil, String.t()) :: String.t() | nil
  def window_text(nil, _zone), do: nil
  def window_text({from, to}, zone), do: "#{clock(from, zone)} – #{clock(to, zone)} (#{zone})"

  defp clock(instant, zone) do
    local =
      case DateTime.shift_zone(instant, zone) do
        {:ok, local} -> local
        {:error, _reason} -> instant
      end

    Calendar.strftime(local, "%Y-%m-%d %H:%M:%S")
  end

  @doc """
  One cell's variables before they are narrowed to its component's (spec/15 §5): the
  board's, with the cell's over them. A component's declared default is the third layer,
  applied by `Visualize.Chart.apply/2`.
  """
  @spec vars(t(), atom()) :: %{atom() => term()}
  def vars(%__MODULE__{vars: vars, cells: cells}, cell) do
    Map.merge(vars, cells |> Map.fetch!(cell) |> Map.get(:vars, %{}))
  end

  # -- interaction (spec/15 §13) ------------------------------------------------------------

  @doc """
  The name a field links to through the board's `links` (spec/15 §13.2), or the field
  itself when `links` does not name it. A link is one step.

      iex> board = Visualize.Board.from_map!(%{links: %{name: :service}})
      iex> {Visualize.Board.link(board, :name), Visualize.Board.link(board, :host)}
      {:service, :host}
  """
  @spec link(t(), atom()) :: atom()
  def link(%__MODULE__{links: links}, field), do: Map.get(links, field, field)

  @doc """
  Every field that links to the same name as `field`, itself and that name included, in
  name order (spec/15 §13.2): the fields a cell reads a selection at.

      iex> board = Visualize.Board.from_map!(%{links: %{name: :service, svc: :service}})
      iex> Visualize.Board.linked(board, :name)
      [:name, :service, :svc]
  """
  @spec linked(t(), atom()) :: [atom()]
  def linked(%__MODULE__{links: links} = board, field) do
    to = link(board, field)

    links
    |> Enum.flat_map(fn {from, link} -> if link == to, do: [from], else: [] end)
    |> then(&[to, field | &1])
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  A cell's drill target with its variables taken from a datum (spec/15 §13.3):
  `{:ok, %{board: ref, vars: vars}}`, `:none` for a cell with no `drill`, or `{:error,
  errors}` for a `{:datum, field}` the row has no value for.

      iex> board = Visualize.Board.from_map!(%{vars: %{service: "api"}, cells: %{a: %{x: 0, y: 0,
      ...>   w: 4, h: 2, ref: {:composite, 1}, drill: %{board: :self, vars: %{service: {:datum, :name}}}}}})
      iex> Visualize.Board.drill(board, :a, %{name: "db", v: 3})
      {:ok, %{board: :self, vars: %{service: "db"}}}
      iex> Visualize.Board.drill(board, :a, %{v: 3})
      {:error, [{[:cells, :a, :drill, :vars, :service], {:missing, :datum, :name}}]}
  """
  @spec drill(t(), atom(), map()) ::
          {:ok, %{board: term(), vars: map()}} | :none | {:error, [error(), ...]}
  def drill(%__MODULE__{cells: cells}, cell, row) when is_map(row) do
    case cells |> Map.fetch!(cell) |> Map.get(:drill) do
      nil -> :none
      %{board: ref} = drill -> drilled(cell, ref, Map.get(drill, :vars, %{}), row)
    end
  end

  defp drilled(cell, ref, vars, row) do
    {vars, errors} =
      vars
      |> Enum.sort()
      |> Enum.reduce({%{}, []}, fn
        {var, {:datum, field}}, {vars, errors} ->
          case Visualize.Data.Table.get(row, field) do
            nil ->
              {vars, [{[:cells, cell, :drill, :vars, var], {:missing, :datum, field}} | errors]}

            value ->
              {Map.put(vars, var, value), errors}
          end

        {var, value}, {vars, errors} ->
          {Map.put(vars, var, value), errors}
      end)

    case errors do
      [] -> {:ok, %{board: ref, vars: vars}}
      errors -> Validator.done(errors)
    end
  end

  # -- sources (spec/15 §4.1) --------------------------------------------------------------

  @doc "As `required_sources/3` with `[]` options."
  @spec required_sources(t(), store()) ::
          {:ok, %{{atom(), atom()} => Visualize.Board.Binding.need()}} | {:error, [error(), ...]}
  def required_sources(board, store), do: required_sources(board, store, [])

  @doc """
  The board's sources: every cell's component's slots, keyed `{cell, slot}`, each with
  its `fields`, its `types` and its `requires` contract — the slot's own with every
  attribute a fact of it reads, as `Visualize.Chart.contract/1` gives it (spec/15 §4.1,
  D-136). One design used in two cells is two sets of slots, bound independently.

  Components are resolved through the store as `validate/3` resolves them, with
  `limits:`; the faults that keep one from being read are `{:error, errors}`.
  """
  @spec required_sources(t(), store(), keyword()) ::
          {:ok, %{{atom(), atom()} => Visualize.Board.Binding.need()}} | {:error, [error(), ...]}
  def required_sources(%__MODULE__{cells: cells}, store, opts) do
    limits = Keyword.get(opts, :limits, [])

    case Validator.components(cells, Validator.fetch(store), limits) do
      {charts, []} -> {:ok, Enum.reduce(charts, %{}, &slots/2)}
      {_charts, errors} -> Validator.done(errors)
    end
  end

  defp slots({cell, %Chart{sources: sources} = chart}, acc) do
    contract = Chart.contract(chart)

    Enum.reduce(sources, acc, fn {slot, node}, acc ->
      need = %{
        fields: Map.get(node, :fields, []),
        types: Map.get(node, :types, %{}),
        requires: Map.get(contract, slot, %{})
      }

      Map.put(acc, {cell, slot}, need)
    end)
  end

  # -- realising (spec/15 §6) --------------------------------------------------------------

  @doc "As `realise/4` with `[]` options."
  @spec realise(t(), store(), %{atom() => map()}) ::
          {:ok, %{atom() => Chart.Applied.t()}, Cache.t()} | {:error, [error(), ...]}
  def realise(board, store, pools), do: realise(board, store, pools, [])

  @doc """
  Every cell applied, purely (spec/15 §6): `{:ok, %{cell => applied}, cache}`, or every
  fault, each under its cell.

  `pools` maps a cell's name to its pool, as `Visualize.Board.Binding.pools/2` makes it.
  For each cell its component is resolved through the store; its variables are the
  board's with the cell's over them, narrowed to those it declares; with the board's
  `sync` set and the cell's true, the board's group is written into its
  `interaction.sync`; and it is applied with `Visualize.Chart.apply/2` at its box's size.
  The board's own faults, alone and given the store, are reported before any cell is
  applied.

  ## Options

    * `:width` - the board's container width in pixels (default `1200`); each cell is
      applied at its box's size there (`boxes/2`)
    * `:theme`, `:now` - as `Visualize.Chart.apply/2` takes them
    * `:schemas` - the schema cache (default empty), threaded from cell to cell and
      returned grown
    * `:describe` - `({cell, slot} -> {:ok, schema} | {:error, reason})`: the connector
      maps the cell's slot to its feed through its binding
    * `:limits` - the limits each component's design is read under
  """
  @spec realise(t(), store(), %{atom() => map()}, keyword()) ::
          {:ok, %{atom() => Chart.Applied.t()}, Cache.t()} | {:error, [error(), ...]}
  def realise(%__MODULE__{} = board, store, pools, opts) when is_map(pools) do
    with {:ok, components} <- components(board, store, opts) do
      apply_cells(board, components, pools, opts)
    end
  end

  defp apply_cells(board, components, pools, opts) do
    boxes = boxes(board, Keyword.get(opts, :width, 1200))
    shared = Keyword.take(opts, [:theme, :now])
    cache = Keyword.get_lazy(opts, :schemas, &Cache.new/0)

    {applied, cache, errors} =
      components
      |> Enum.sort()
      |> Enum.reduce({%{}, cache, []}, fn {name, %{chart: chart, vars: vars}},
                                          {applied, cache, errors} ->
        {_x, _y, w, h} = Map.fetch!(boxes, name)

        options =
          shared ++
            [
              sources: Map.get(pools, name, %{}),
              vars: vars,
              size: {w, h},
              schemas: cache,
              describe: describe(opts[:describe], name)
            ]

        case Chart.apply(chart, options) do
          {:ok, done} ->
            {Map.put(applied, name, done), done.cache, errors}

          {:error, faults} ->
            {applied, cache, errors ++ Enum.map(faults, fn {p, r} -> {[:cells, name | p], r} end)}
        end
      end)

    case errors do
      [] -> {:ok, applied, cache}
      errors -> Validator.done(errors)
    end
  end

  @doc "As `components/3` with `[]` options."
  @spec components(t(), store()) ::
          {:ok, %{atom() => %{chart: Chart.t(), vars: map()}}} | {:error, [error(), ...]}
  def components(board, store), do: components(board, store, [])

  @doc """
  Every cell's component prepared for application, purely (spec/15 §6): `{:ok, %{cell =>
  %{chart: chart, vars: vars}}}`, or every fault of the board alone and given the store.

  Each component is resolved through the store and read with `limits:`; with the board's
  `sync` set and the cell's true, the board's group is written into its
  `interaction.sync`; the board's zone is written into every `:time` scale that names no
  zone of its own (spec/15 §1.5); and `vars` is the cascade of spec/15 §5 narrowed to the
  variables the component declares. `realise/4` applies each; the runtime applies each in
  its cell's process (spec/15 §8).
  """
  @spec components(t(), store(), keyword()) ::
          {:ok, %{atom() => %{chart: Chart.t(), vars: map()}}} | {:error, [error(), ...]}
  def components(%__MODULE__{} = board, store, opts) do
    with :ok <- validate(board),
         {charts, []} <- resolved(to_map(board), store, opts) do
      {:ok,
       Map.new(charts, fn {name, chart} ->
         cell = Map.fetch!(board.cells, name)

         prepared =
           chart
           |> synced(cell, board.sync)
           |> zoned(board.zone)

         {name,
          %{chart: prepared, vars: board |> vars(name) |> Map.take(Validator.declared(chart))}}
       end)}
    else
      {:error, errors} -> {:error, errors}
      {_charts, errors} -> Validator.done(errors)
    end
  end

  # The board's zone on every time scale that names none (spec/15 §1.5): UTC is a time
  # scale's own default, so it writes nothing.
  defp zoned(chart, "Etc/UTC"), do: chart

  defp zoned(%Chart{frames: frames} = chart, zone) when is_map(frames) do
    %{chart | frames: Map.new(frames, fn {name, frame} -> {name, zoned_frame(frame, zone)} end)}
  end

  defp zoned(chart, _zone), do: chart

  defp zoned_frame(%{scales: scales} = frame, zone) when is_map(scales) do
    scales =
      Map.new(scales, fn
        {name, %{kind: :time} = scale} when not is_map_key(scale, :zone) ->
          {name, Map.put(scale, :zone, zone)}

        pair ->
          pair
      end)

    %{frame | scales: scales}
  end

  defp zoned_frame(frame, _zone), do: frame

  defp synced(chart, _cell, nil), do: chart

  defp synced(chart, cell, group) do
    if Map.get(cell, :sync, true), do: Validator.joined(chart, group), else: chart
  end

  defp describe(nil, _cell), do: nil
  defp describe(describe, cell) when is_function(describe, 1), do: &describe.({cell, &1})
end
