defmodule Visualize.Board.Snapshot do
  @moduledoc """
  A board frozen at one instant: the board, its window and its now, every cell's
  component and the data it was drawn from, and the theme, as one value (spec/15 §12.2,
  D-150).

  A snapshot draws every cell exactly as the cell would draw the same data — through the
  same steps (`views/2`) — with no store, no feed and no process, so it can be written to
  a file, sent to someone and reopened anywhere. It carries **data**: a bundle
  (spec/15 §11) carries a board's *definitions*, by id, to be imported into a store and
  edited; a snapshot carries each cell's component already resolved and prepared, with
  the rows it showed, to be looked at. A snapshot is never imported into a store.

  Take one from a running board with `Visualize.Board.Server.snapshot/1`, or purely from
  the board, the store and the cells' pools with `realise/4`, the snapshot form of
  `Visualize.Board.realise/4`. `Visualize.Board.Export` draws it as one SVG document, a
  PNG or printed pages.

  The value has a map form (`to_map/1`, `from_map/2`) and a JSON form (`to_json/1`,
  `from_json/2`) stamped `"$version"`, read under the version policy and the sanity
  limits of spec/14 §9.1–§9.2 as a board is (spec/15 §2.3).

  ## Fields

    * `version` - the schema version it was written at
    * `board` - the `%Visualize.Board{}`
    * `now` - the board's now when it was taken, a UTC `DateTime`, or `nil`
    * `window` - the window resolved at now, `{from, to}` in UTC, or `nil`
    * `width` - the container width the board was drawn at
    * `theme` - the `%Visualize.Theme{}` the cells were drawn in
    * `cells` - by name: `chart`, the prepared component (`Visualize.Board.components/3`);
      `vars`, its variables; `slots`, each slot's `%{delivery, schema, status}` as the
      board handed them to the cell, or `nil` before any data; and `crashed`, `nil`, or
      the words of the reason a cell's process had died
  """

  # Jason is optional (spec/14 §11.1, D-50).
  @compile {:no_warn_undefined, Jason}

  alias Visualize.Board
  alias Visualize.Board.{Draw, State, View}
  alias Visualize.Board.Snapshot.{Codec, Reader}
  alias Visualize.Chart
  alias Visualize.Chart.Codec.Tags
  alias Visualize.Chart.{Limits, Migration}
  alias Visualize.Chart.Theme, as: ChartTheme
  alias Visualize.Data.{Delivery, Table}

  defstruct version: Migration.current(),
            board: nil,
            now: nil,
            window: nil,
            width: 1200,
            theme: %Visualize.Theme{},
            cells: %{}

  @typedoc "What a snapshot holds of one slot: as the board hands it to a cell (spec/15 §8.2)."
  @type slot :: %{
          delivery: Delivery.t() | nil,
          schema: Visualize.Data.Schema.t() | nil,
          status: :loading | :live | :stale | {:down, String.t()}
        }

  @typedoc "What a snapshot holds of one cell."
  @type cell :: %{
          chart: Chart.t(),
          vars: %{atom() => term()},
          slots: %{atom() => slot()} | nil,
          crashed: String.t() | nil
        }

  @type t :: %__MODULE__{
          version: pos_integer(),
          board: Board.t(),
          now: DateTime.t() | nil,
          window: {DateTime.t(), DateTime.t()} | nil,
          width: number(),
          theme: Visualize.Theme.t(),
          cells: %{atom() => cell()}
        }

  # -- taking one ---------------------------------------------------------------------------

  @doc false
  # A snapshot of what a board holds (spec/15 §12.2): the runtime's and `realise/4`'s one
  # constructor. `cells` maps a name to its `chart`, `vars`, `slots` and `crashed` reason
  # as the holder has them; each slot is normalised here — rows as a list, a status as one
  # of the four a snapshot keeps, a down reason and a crash as their words — so a snapshot
  # holds only what its codecs write.
  @spec new(keyword()) :: t()
  def new(fields) do
    cells =
      Map.new(Keyword.fetch!(fields, :cells), fn {name, cell} ->
        {name,
         %{
           chart: cell.chart,
           vars: cell.vars,
           slots: slots(cell.slots),
           crashed: crashed(cell.crashed)
         }}
      end)

    %__MODULE__{
      board: Keyword.fetch!(fields, :board),
      now: Keyword.get(fields, :now),
      window: Keyword.get(fields, :window),
      width: Keyword.fetch!(fields, :width),
      theme: Keyword.fetch!(fields, :theme),
      cells: cells
    }
  end

  defp slots(nil), do: nil

  defp slots(slots) do
    Map.new(slots, fn {slot, %{delivery: delivery, schema: schema, status: status}} ->
      {slot, %{delivery: delivery(delivery), schema: schema, status: status(status)}}
    end)
  end

  defp delivery(nil), do: nil
  defp delivery(%Delivery{} = d), do: %{d | rows: Table.rows(d)}

  defp status({:down, reason}) when is_binary(reason), do: {:down, reason}
  defp status({:down, reason}), do: {:down, State.reason(reason)}
  defp status(status) when status in [:loading, :live, :stale], do: status
  defp status(nil), do: :loading

  defp crashed(nil), do: nil
  defp crashed(reason) when is_binary(reason), do: reason
  defp crashed(reason), do: inspect(reason, limit: 5, printable_limit: 200)

  @doc "As `realise/4` with `[]` options."
  @spec realise(Board.t(), Board.store(), %{atom() => map()}) ::
          {:ok, t()} | {:error, [Board.error(), ...]}
  def realise(board, store, pools), do: realise(board, store, pools, [])

  @doc """
  A snapshot of a board realised purely (spec/15 §6, §12.2): `Visualize.Board.realise/4`
  over the same arguments, every fault of it as it reports them, and on success each
  cell's prepared component, its variables and its pool's sources as deliveries, with the
  schema application found for each slot.

  The options are `realise/4`'s — `width:` (default `1200`), `theme:` (default
  `Visualize.Theme.default/0`), `now:`, `schemas:`, `describe:` and `limits:`. With `now:`
  the window is the board's resolved at it; without, a fixed window is kept and a trailing
  one resolves to `nil`.
  """
  @spec realise(Board.t(), Board.store(), %{atom() => map()}, keyword()) ::
          {:ok, t()} | {:error, [Board.error(), ...]}
  def realise(%Board{} = board, store, pools, opts) do
    theme = Keyword.get_lazy(opts, :theme, &Visualize.Theme.default/0)
    width = Keyword.get(opts, :width, 1200)
    now = Keyword.get(opts, :now)
    opts = Keyword.merge(opts, theme: theme, width: width)

    with {:ok, applied, _cache} <- Board.realise(board, store, pools, opts),
         {:ok, components} <-
           Board.components(board, store, Keyword.take(opts, [:limits, :generators])) do
      cells =
        Map.new(components, fn {name, %{chart: chart, vars: vars}} ->
          # The sources application bound each slot to: its pool's entry, by the slot's
          # name or its default (spec/14 §7.2).
          %{schemas: schemas, sources: bound} = Map.fetch!(applied, name)

          slots =
            Map.new(chart.sources, fn {slot, _node} ->
              source = Map.fetch!(bound, slot)

              {slot,
               %{
                 delivery: as_delivery(source),
                 schema: Map.get(schemas, slot),
                 status: :live
               }}
            end)

          {name, %{chart: chart, vars: vars, slots: slots, crashed: nil}}
        end)

      window = if now, do: Board.window(board, now), else: fixed(board.window)
      {:ok, new(board: board, now: now, window: window, width: width, theme: theme, cells: cells)}
    end
  end

  # A pool's source as a delivery: a delivery as it is, any other source as its rows.
  defp as_delivery(%Delivery{} = delivery), do: delivery
  defp as_delivery(source), do: Delivery.new(Table.rows(source))

  defp fixed(%{from: from, to: to}), do: {from, to}
  defp fixed(_window), do: nil

  # -- drawing ------------------------------------------------------------------------------

  @doc """
  Every cell drawn, purely (spec/15 §12.2): `%{name => %Visualize.Board.View{}}`, each
  the view a cell process draws of the same data as its first frame — its component
  applied at its box, compiled and stepped once, the state decided and drawn — or, for a
  cell that had crashed, its crashed panel.

  ## Options

    * `:width` - the container width (default the snapshot's): each cell is drawn at its
      box there (`Visualize.Board.boxes/2`), so a snapshot redraws at any width
    * `:theme` - the theme to draw in (default the snapshot's), such as
      `Visualize.Theme.print/0` for paper
    * `:system` - the unit system the cells' measures are shown in (default
      `:as_posted`): the reader's, so a snapshot does not record it (spec/14 §4.4, D-156)
    * `:generators`, `:assigns` - the generator modules the cells' frames call, beside
      `config :visualize, generators:`, and the host's assigns their context carries
      (default `[]` and `%{}`): the board's own, so the cells draw what the board draws for
      its viewer (spec/14 §3.13, spec/15 §12.2, D-181). A snapshot holds data, not modules
      or a viewer, so it records neither
  """
  @spec views(t(), keyword()) :: %{atom() => View.t()}
  def views(%__MODULE__{} = snapshot, opts \\ []) do
    width = Keyword.get(opts, :width, snapshot.width)
    theme = Keyword.get(opts, :theme, snapshot.theme)
    boxes = Board.boxes(snapshot.board, width)

    drawing = %{
      system: Keyword.get(opts, :system, :as_posted),
      generators: Keyword.get(opts, :generators, []),
      assigns: Keyword.get(opts, :assigns, %{})
    }

    Map.new(snapshot.cells, fn {name, cell} ->
      {_x, _y, w, h} = Map.fetch!(boxes, name)
      {name, view(snapshot, name, cell, {w, h}, theme, drawing)}
    end)
  end

  defp view(snapshot, name, %{crashed: reason}, size, theme, _drawing) when is_binary(reason) do
    crashed = {:crashed, reason}

    %View{
      cell: name,
      title: title(snapshot, name),
      state: crashed,
      size: size,
      note: State.render(crashed, theme, size)
    }
  end

  defp view(snapshot, name, cell, size, theme, drawing) do
    Draw.once(%{
      name: name,
      title: title(snapshot, name),
      chart: cell.chart,
      vars: cell.vars,
      size: size,
      theme: theme,
      system: drawing.system,
      generators: drawing.generators,
      assigns: drawing.assigns,
      now: snapshot.now,
      stale_after: snapshot.board.stale_after,
      slots: cell.slots
    })
  end

  defp title(snapshot, name), do: snapshot.board.cells |> Map.fetch!(name) |> Map.get(:title)

  # -- the map form ---------------------------------------------------------------------------

  @doc """
  The snapshot as a map of plain data (spec/15 §12.3): `version`, `board` in its map
  form, `now`, `window` as `nil` or `%{from, to}`, `width`, `theme` as a theme node
  (`Visualize.Chart.Theme.node/1`), and `cells`, each with its `chart` in a design's map
  form, its `vars`, its `slots` — each a delivery's `rows`, `window`, `resolution`,
  `capped`, `reduced_by` and `version`, the schema's fields as `schema`, and the `status`
  — and `crashed`.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = s) do
    %{
      version: s.version,
      board: Board.to_map(s.board),
      now: s.now,
      window: with({from, to} <- s.window, do: %{from: from, to: to}),
      width: s.width,
      theme: ChartTheme.node(s.theme),
      cells:
        Map.new(s.cells, fn {name, cell} ->
          {name,
           %{
             chart: Chart.to_map(cell.chart),
             vars: cell.vars,
             slots: slots_map(cell.slots),
             crashed: cell.crashed
           }}
        end)
    }
  end

  defp slots_map(nil), do: nil

  defp slots_map(slots) do
    Map.new(slots, fn {slot, %{delivery: d, schema: schema, status: status}} ->
      delivery =
        case d do
          nil -> %{rows: nil}
          %Delivery{} -> Map.take(d, [:rows, :window, :resolution, :capped, :reduced_by])
        end

      {slot,
       Map.merge(delivery, %{
         version: d && d.schema,
         schema: schema && schema.fields,
         status: status
       })}
    end)
  end

  @doc """
  The snapshot of a map (spec/15 §12.3), or every fault of it by path: the version gate
  first (spec/14 §9.1), then the `depth` and `items` limits under `limits:`, then every
  key — the board read by `Visualize.Board.from_map/2`, the theme by
  `Visualize.Chart.Theme.from_map/2`, each cell's component by
  `Visualize.Chart.from_map/2` and each schema by `Visualize.Data.Schema.new/1`, with
  their faults under their own paths. Every cell of the board must be in `cells`, and
  `cells` must name no other.
  """
  @spec from_map(term(), keyword()) :: {:ok, t()} | {:error, [Board.error(), ...]}
  def from_map(map, opts \\ []) do
    limits = opts |> Keyword.get(:limits, []) |> Limits.new()

    with :ok <- readable(Map.get(map_or_empty(map), :version), [:version]),
         :ok <- Reader.done(Limits.structure(map, limits)) do
      Reader.read(map, limits)
    end
  end

  defp map_or_empty(map) when is_map(map) and not is_struct(map), do: map
  defp map_or_empty(_other), do: %{}

  defp readable(v, path) do
    with {:error, reason} <- Migration.readable(v), do: {:error, [{path, reason}]}
  end

  # -- the JSON form --------------------------------------------------------------------------

  @doc """
  The snapshot as a JSON document stamped `"$version"` (spec/15 §12.3), or
  `{:error, {:missing_dependency, :jason}}`. `from_json(to_json(s))` is `{:ok, s}`.

  A row's field names are kept as they were spelt, an atom or a string, by writing the
  rows column by column; every value is a tagged term of spec/14 §11.2.
  """
  @spec to_json(t()) :: {:ok, String.t()} | {:error, {:missing_dependency, :jason}}
  def to_json(%__MODULE__{} = snapshot) do
    if Code.ensure_loaded?(Jason) do
      {:ok, json} = snapshot |> to_map() |> Codec.encode() |> Jason.encode()
      {:ok, json}
    else
      {:error, {:missing_dependency, :jason}}
    end
  end

  @doc """
  The snapshot of a JSON document (spec/15 §12.3), with `limits:` as `from_map/2` takes
  them: `"$version"` checked and the structural limits applied before a key is decoded,
  then read as `from_map/2` reads. A document that does not parse, or is not an object, is
  `{:error, [{[], {:json, message}}]}`.
  """
  @spec from_json(String.t(), keyword()) ::
          {:ok, t()} | {:error, [Board.error(), ...] | {:missing_dependency, :jason}}
  def from_json(json, opts \\ []) when is_binary(json) do
    if Code.ensure_loaded?(Jason) do
      limits = opts |> Keyword.get(:limits, []) |> Limits.new()

      case Jason.decode(json) do
        {:ok, term} when is_map(term) ->
          {stamp, term} = Map.pop(term, Codec.stamp())

          with :ok <- readable(stamp, [Codec.stamp()]),
               :ok <- Reader.done(Limits.structure(term, limits)),
               {:ok, term} <- Tags.read(term, stamp) do
            map = Codec.decode(term)
            Reader.read(if(stamp == nil, do: map, else: Map.put(map, :version, stamp)), limits)
          end

        {:ok, other} ->
          {:error, [{[], {:json, "a snapshot is an object, got #{inspect(other)}"}}]}

        {:error, error} ->
          {:error, [{[], {:json, Exception.message(error)}}]}
      end
    else
      {:error, {:missing_dependency, :jason}}
    end
  end

  @doc """
  One fault as a line a person reads, the root named `snapshot`, in the words of
  `Visualize.Chart.Validator.format/1`.
  """
  @spec format_error(Board.error()) :: String.t()
  def format_error({[], reason}),
    do: "snapshot: " <> Visualize.Chart.Validator.Words.words(reason)

  def format_error(error), do: Visualize.Chart.Validator.format(error)
end
