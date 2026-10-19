if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Boards do
    @moduledoc """
    The board mode's editor (spec/14 §22, D-152): the pure writes of a board — a cell
    placed, a field read from a control — and the inspector panel that makes them.

    A board chart holds a `%Visualize.Board{}`, not a stack of uses. Every write goes
    through a function here that builds the board it would make, and the mode validates
    that board alone before it keeps it (`Visualize.Board.validate/1`), so the board the
    builder holds always reads and a client can never place a cell over another or off the
    grid (§22.2, §22.3). Each cell previews alone through `Visualize.Board.realize/4`
    (`preview/3`, §22.6).

    This module compiles only when `Phoenix.Component` is loaded (spec/10 §1.1, D-45, D-85).
    """

    use Phoenix.Component

    alias Visualize.{Board, Chart}
    alias Visualize.Board.State
    alias Visualize.Board.Validator, as: BoardValidator

    # A new cell's size, in squares: a third of the grid across, two rows down (§22.3).
    @new_w 4
    @new_h 2

    # The width a preview is realized at: the runtime's default (spec/15 §6).
    @width 1200
    # The fault panel's box: the cell-state drawing is responsive, so this is its aspect.
    @fault_size {600, 240}

    # -- placing (§22.3) -------------------------------------------------------------------

    @doc """
    The board with a cell at a rectangle, `{:ok, board}`, or `{:error, errors}`: every fault
    of the board the placement would make, alone — `{:off_grid, 12}` for a cell that runs
    past the grid, `{:overlap, other}` for one that shares a square, a type fault for a key
    that is not an integer of the right sign (spec/14 §22.3, spec/15 §3.1). The board is the
    server's: whatever rectangle a client sends, this is the one place it is written.

        iex> board = Visualize.Board.from_map!(%{cells: %{
        ...>   a: %{x: 0, y: 0, w: 6, h: 2, ref: {:composite, 1}},
        ...>   b: %{x: 6, y: 0, w: 6, h: 2, ref: {:composite, 1}}
        ...> }})
        iex> {:ok, moved} = Visualize.Chart.Builder.Boards.place(board, :b, %{x: 6, y: 2, w: 6, h: 3})
        iex> Map.take(moved.cells.b, [:x, :y, :w, :h])
        %{x: 6, y: 2, w: 6, h: 3}
        iex> Visualize.Chart.Builder.Boards.place(board, :b, %{x: 4, y: 0, w: 6, h: 2})
        {:error, [{[:cells, :b], {:overlap, :a}}]}
        iex> Visualize.Chart.Builder.Boards.place(board, :b, %{x: 8, y: 4, w: 6, h: 2})
        {:error, [{[:cells, :b], {:off_grid, 12}}]}
    """
    @spec place(Board.t(), atom(), Board.rect()) :: {:ok, Board.t()} | {:error, [Board.error()]}
    def place(%Board{cells: cells} = board, cell, %{x: _, y: _, w: _, h: _} = rect) do
      placed = Map.merge(Map.fetch!(cells, cell), Map.take(rect, [:x, :y, :w, :h]))
      checked(%{board | cells: Map.put(cells, cell, placed)})
    end

    @doc """
    The first place in reading order — the first row, then the first column — where a
    `w`-by-`h` rectangle overlaps no cell of the board (spec/14 §22.3).

        iex> board = Visualize.Board.from_map!(%{cells: %{
        ...>   a: %{x: 0, y: 0, w: 8, h: 2, ref: {:composite, 1}}
        ...> }})
        iex> Visualize.Chart.Builder.Boards.free(board, 4, 2)
        {8, 0}
        iex> Visualize.Chart.Builder.Boards.free(board, 6, 1)
        {0, 2}
    """
    @spec free(Board.t(), pos_integer(), pos_integer()) :: {non_neg_integer(), non_neg_integer()}
    def free(%Board{cells: cells}, w, h) do
      rects = Map.values(cells)
      bottom = Enum.reduce(rects, 0, &max(&1.y + &1.h, &2))

      Enum.find_value(0..bottom, fn y ->
        Enum.find_value(0..(Board.columns() - w), fn x ->
          rect = %{x: x, y: y, w: w, h: h}
          if Enum.any?(rects, &BoardValidator.overlaps?(&1, rect)), do: nil, else: {x, y}
        end)
      end)
    end

    @doc false
    # A new cell of a component at the first free place, named `cell_<n>` for the least `n`
    # no cell has: a cell's name is its identity, and no atom is made of a person's text.
    def added(%Board{cells: cells} = board, ref) do
      taken = cells |> Map.keys() |> MapSet.new(&Atom.to_string/1)
      n = Enum.find(Stream.iterate(1, &(&1 + 1)), &("cell_#{&1}" not in taken))
      # A name the board makes, one per cell it has, never one a client sent.
      name = String.to_atom("cell_#{n}")
      {x, y} = free(board, @new_w, @new_h)
      cell = %{x: x, y: y, w: @new_w, h: @new_h, ref: ref}

      with {:ok, board} <- checked(%{board | cells: Map.put(cells, name, cell)}),
           do: {:ok, board, name}
    end

    @doc false
    # The board without a cell.
    def removed(%Board{cells: cells} = board, cell), do: %{board | cells: Map.delete(cells, cell)}

    defp checked(board) do
      case Board.validate(board) do
        :ok -> {:ok, board}
        {:error, errors} -> {:error, errors}
      end
    end

    # -- reading a control (§22.4) -----------------------------------------------------------

    @doc false
    # The board with one control of the *board* form written, or `:error` for a value that
    # does not read. The written board is validated by the caller.
    def changed(%Board{meta: meta} = board, field, value) when field in ["name", "description"] do
      key = String.to_existing_atom(field)
      {:ok, %{board | meta: optional(meta, key, String.trim(value))}}
    end

    def changed(board, "window", kind), do: {:ok, %{board | window: window(board.window, kind)}}

    def changed(board, "last", value) do
      with {:ok, n} <- number(value), do: {:ok, %{board | window: %{last: n}}}
    end

    def changed(%Board{window: %{from: from, to: to}} = board, end_, value)
        when end_ in ["from", "to"] do
      with {:ok, time} <- utc(value) do
        window = if end_ == "from", do: %{from: time, to: to}, else: %{from: from, to: time}
        {:ok, %{board | window: window}}
      end
    end

    def changed(board, "zone", value), do: {:ok, %{board | zone: String.trim(value)}}

    def changed(board, "sync", value) do
      {:ok, %{board | sync: if(String.trim(value) == "", do: nil, else: String.trim(value))}}
    end

    def changed(board, "stale_after", value) do
      case String.trim(value) do
        "" -> {:ok, %{board | stale_after: nil}}
        text -> with {:ok, n} <- number(text), do: {:ok, %{board | stale_after: n}}
      end
    end

    def changed(%Board{layout: layout} = board, field, value)
        when field in ["breakpoint", "row_height", "gap"] do
      key = String.to_existing_atom(field)

      case String.trim(value) do
        "" ->
          {:ok, %{board | layout: Map.delete(layout, key)}}

        text ->
          with {:ok, n} <- number(text), do: {:ok, %{board | layout: Map.put(layout, key, n)}}
      end
    end

    def changed(_board, _field, _value), do: :error

    @doc false
    # The selected cell with one control of the *cell* form written, or `:error`.
    def cell_changed(cell, "title", value), do: {:ok, optional(cell, :title, String.trim(value))}

    def cell_changed(cell, "ref", value) do
      case Visualize.Chart.Builder.Store.decode_id(value) do
        {:ok, id} -> {:ok, Map.put(cell, :ref, id)}
        :error -> :error
      end
    end

    def cell_changed(cell, "sync", value), do: {:ok, Map.put(cell, :sync, value == "true")}
    def cell_changed(_cell, _field, _value), do: :error

    @doc false
    # A variables map with one value written: a number when it reads as one, else the text;
    # an empty box removes the value, so the cascade falls through (spec/15 §5).
    def var_written(vars, name, value) do
      case String.trim(value) do
        "" -> Map.delete(vars, name)
        text -> Map.put(vars, name, value(text))
      end
    end

    defp value(text) do
      case number(text) do
        {:ok, n} -> n
        :error -> text
      end
    end

    # *none*, *last* or *fixed*; a window already of the kind is kept, *last* starts at an
    # hour and *fixed* at the last whole hour before now (§22.4).
    defp window(_window, "none"), do: nil
    defp window(%{last: _} = window, "last"), do: window
    defp window(_window, "last"), do: %{last: 3600}
    defp window(%{from: _, to: _} = window, "fixed"), do: window

    defp window(_window, "fixed") do
      to = %{DateTime.utc_now() | minute: 0, second: 0, microsecond: {0, 0}}
      %{from: DateTime.add(to, -3600, :second), to: to}
    end

    defp window(window, _kind), do: window

    defp optional(map, key, ""), do: Map.delete(map, key)
    defp optional(map, key, value), do: Map.put(map, key, value)

    defp number(text) do
      text = String.trim(text)

      case Integer.parse(text) do
        {n, ""} ->
          {:ok, n}

        _other ->
          case Float.parse(text) do
            {n, ""} -> {:ok, n}
            _not -> :error
          end
      end
    end

    # A `datetime-local` value read as UTC (§22.4): minutes, or seconds too.
    defp utc(value) do
      text = String.trim(value)
      text = if byte_size(text) == 16, do: text <> ":00", else: text

      case NaiveDateTime.from_iso8601(text) do
        {:ok, naive} -> {:ok, DateTime.from_naive!(naive, "Etc/UTC")}
        {:error, _reason} -> :error
      end
    end

    @doc false
    # A UTC time as a `datetime-local` control shows it.
    def local(%DateTime{} = time),
      do:
        time
        |> DateTime.to_naive()
        |> NaiveDateTime.truncate(:second)
        |> NaiveDateTime.to_iso8601()

    def local(_other), do: ""

    # -- components and their variables (§22.4) ----------------------------------------------

    @doc """
    The variables a component declares, from its flattened design, sorted (spec/14 §22.4):
    the names a cell's variables may take. `[]` for a component the store does not hold, or
    one that reaches itself.

        iex> fetch = fn {:composite, 1} -> {:ok, %{vars: %{unit: %{default: "%"}, host: %{}}}} end
        iex> Visualize.Chart.Builder.Boards.declared({:composite, 1}, fetch)
        [:host, :unit]
    """
    @spec declared(term(), (term() -> {:ok, map()} | :error)) :: [atom()]
    def declared(ref, fetch) do
      with {:ok, fragment} <- fetch.(ref),
           {:ok, design, _report} <- Chart.flatten(fragment, fetch) do
        design |> Map.get(:vars, %{}) |> Map.keys() |> Enum.sort()
      else
        _none -> []
      end
    end

    @doc false
    # A name from the page as one of the given atoms, or `nil`: no atom is made of it.
    def named(names, text), do: Enum.find(names, &(Atom.to_string(&1) == text))

    # -- feeds and their samples (§22.6, §22.8) ------------------------------------------------

    @doc false
    # A feed as the page prints it and sends it back: its name for an atom or a string,
    # else its inspected form. A feed from the page is matched against the bindable feeds
    # by this, and never made a term of its own.
    def feed_key(feed) when is_atom(feed), do: Atom.to_string(feed)
    def feed_key(feed) when is_binary(feed), do: feed
    def feed_key(feed), do: inspect(feed)

    @doc """
    Sixty rows made from a schema, for a preview where the host gave none of a feed's
    (spec/14 §22.6): a `:time` field a second apart and ending at `now`, a `:number` window
    field (`window: true`, D-154) its row's place, `0` to `59`, as a tick counts, any other
    `:number` field a slow sine, a `:category` field its `order` in turn — else `"a"`, `"b"`
    and `"c"` — and a `:text` field its own name. The rows are shaped like the feed's, not
    its values.

        iex> schema = Visualize.Data.Schema.new!(%{t: %{type: :time}, v: %{type: :number},
        ...>   state: %{type: :category, order: ["ok", "warn"]}})
        iex> rows = Visualize.Chart.Builder.Boards.sample(schema, ~U[2026-10-11 12:00:00Z])
        iex> {length(rows), List.last(rows).t, Enum.map(Enum.take(rows, 3), & &1.state)}
        {60, ~U[2026-10-11 12:00:00Z], ["ok", "warn", "ok"]}
    """
    @spec sample(Visualize.Data.Schema.t(), DateTime.t()) :: [map()]
    def sample(%Visualize.Data.Schema{fields: fields}, %DateTime{} = now) do
      fields = Enum.sort_by(fields, fn {name, _description} -> to_string(name) end)

      for i <- 0..59 do
        fields
        |> Enum.with_index()
        |> Map.new(fn {{name, description}, k} ->
          {name, sampled(description, name, i, k, now)}
        end)
      end
    end

    defp sampled(%{type: :time}, _name, i, _k, now), do: DateTime.add(now, i - 59, :second)
    defp sampled(%{type: :number, window: true}, _name, i, _k, _now), do: i

    defp sampled(%{type: :number}, _name, i, k, _now),
      do: Float.round(50 + 40 * :math.sin(i / 8 + k), 3)

    defp sampled(%{type: :category} = description, _name, i, _k, _now) do
      order = Map.get(description, :order, ["a", "b", "c"])
      Enum.at(order, rem(i, length(order)))
    end

    defp sampled(_text, name, _i, _k, _now), do: to_string(name)

    # -- the preview (§22.6) -------------------------------------------------------------------

    @doc """
    Each cell realized alone (spec/14 §22.6): `Visualize.Board.realize/4` of a board holding
    that one cell and the board's shared state, at a container width of 1200, so one cell
    that cannot apply leaves every other drawn. `%{cell => {:ok, svg} | {:error, lines}}`,
    the chart a responsive root titled with the cell's title, the faults in
    `Visualize.Board.format_error/1`'s words.

    ## Options

      * `:pools` - each cell's pool, by its name (default none)
      * `:theme` - as `Visualize.Chart.apply/2` takes it
      * `:describe` - `({cell, slot} -> {:ok, schema} | {:error, reason})`, as
        `Visualize.Board.realize/4` takes it: the schema of a slot's feed
      * `:refused` - each cell the binding's type check refused, by its name, with its
        faults (D-153): it is not realized, and is drawn as the fault panel
      * `:id` - the stem of each cell's root id, `<id>-<cell>` (default
        `vis-builder-board`), so two cells drawing one design never share a root's ids or
        its dark-mode rule (D-188)

    A cell whose binding has the wrong type — refused, or reporting a `{:type_mismatch, …}`
    from application — is `{:fault, svg, lines}`: the board runtime's cell-state panel of
    `{:invalid, errors}` and every fault's words (spec/14 §18.4, §22.6).
    """
    @spec preview(Board.t(), Board.store(), keyword()) :: %{
            atom() =>
              {:ok, String.t()} | {:error, [String.t()]} | {:fault, String.t(), [String.t()]}
          }
    def preview(%Board{cells: cells} = board, fetch, opts) do
      pools = Keyword.get(opts, :pools, %{})
      refused = Keyword.get(opts, :refused, %{})
      theme = Keyword.get(opts, :theme) || Visualize.Theme.default()
      stem = Keyword.get(opts, :id, "vis-builder-board")
      shared = [width: @width] ++ Keyword.take(opts, [:theme, :describe])

      Map.new(cells, fn {name, cell} ->
        drawn =
          case Map.fetch(refused, name) do
            {:ok, errors} ->
              fault(errors, theme, "#{stem}-#{name}")

            :error ->
              alone = %{board | cells: %{name => cell}}
              realized(alone, name, cell, fetch, Map.get(pools, name, %{}), shared, theme, stem)
          end

        {name, drawn}
      end)
    end

    # The cell applied alone and drawn; one whose application reports a type fault is the
    # fault panel, any other fault its lines.
    defp realized(alone, name, cell, fetch, pool, shared, theme, stem) do
      case Board.realize(alone, fetch, %{name => pool}, shared) do
        {:ok, %{^name => applied}, _cache} ->
          {:ok,
           Chart.render(applied,
             root: true,
             id: "#{stem}-#{name}",
             responsive: true,
             title: Map.get(cell, :title) || Atom.to_string(name)
           )}

        {:error, errors} ->
          if Enum.any?(errors, &match?({_path, {:type_mismatch, _, _, _, _}}, &1)),
            do: fault(errors, theme, "#{stem}-#{name}"),
            else: {:error, Enum.map(errors, &Board.format_error/1)}
      end
    end

    # The fault panel stands where the cell's chart would, under its root id (#722).
    defp fault(errors, theme, id) do
      {:fault, State.render({:invalid, errors}, theme, @fault_size, id: id),
       Enum.map(errors, &Board.format_error/1)}
    end

    # -- the virtual sources (§22.9) -------------------------------------------------------------

    @doc """
    The board mode's view of its virtual sources (spec/14 §22.9): each source's dotted
    path, its state, its function's text — a draft the checker refused in place of the
    stored text, with the draft's faults — its faults inline, and its preview rows, from
    `%{run: run, drafts: drafts}`, the sources' run over the preview's data and the drafts
    by path.
    """
    @spec sources(%{run: map(), drafts: map()}) :: [map()]
    def sources(%{run: %{sources: views}, drafts: drafts}) do
      for view <- views do
        rows = for row <- view.rows, do: Enum.map(view.fields, &cell_text(Map.get(row, &1)))
        fields = Enum.map(view.fields, &to_string/1)

        case Map.fetch(drafts, view.path) do
          {:ok, %{text: text, faults: faults}} ->
            %{view | text: text, faults: faults}
            |> Map.merge(%{draft?: true, columns: fields, cells: rows})

          :error ->
            Map.merge(view, %{draft?: false, columns: fields, cells: rows})
        end
      end
    end

    defp cell_text(nil), do: ""
    defp cell_text(value) when is_binary(value), do: value
    defp cell_text(value) when is_atom(value) or is_number(value), do: to_string(value)
    defp cell_text(%DateTime{} = value), do: DateTime.to_iso8601(value)
    defp cell_text(value), do: inspect(value)

    # -- the panel (§22.4) -----------------------------------------------------------------------

    attr(:id, :string, required: true, doc: "the panel's id")

    attr(:mode, :map,
      required: true,
      doc:
        "the board mode's assigns, as the builder derives them for the open board (spec/14 §22)"
    )

    attr(:target, :any, default: nil, doc: "the `phx-target` of every control")

    @doc """
    The inspector of the board mode (spec/14 §22.4): the selected cell — its title, its
    component, whether it joins the sync group, its variables, *Edit component* and *Remove*
    — then *add a cell*, the board's name, its window and zone, its sync group and
    staleness, its layout, its variables, and its faults given the store (§22.5).
    """
    def panel(assigns) do
      ~H"""
      <div id={@id} class="vis-builder-board-panel">
        <form
          :if={@mode.selected}
          id={@id <> "-cell"}
          class="vis-builder-board"
          phx-change="board_cell"
          phx-submit="submitted"
          phx-target={@target}
        >
          <fieldset class="vis-builder-board-section">
            <legend>cell {@mode.selected.name}</legend>
            <label class="vis-builder-board-row">
              <span class="vis-builder-control-label">title</span>
              <input type="text" name="title" value={@mode.selected.title || ""} />
            </label>
            <label class="vis-builder-board-row">
              <span class="vis-builder-control-label">component</span>
              <select name="ref">
                <option :if={not @mode.selected.listed?} value={@mode.selected.ref} selected>{@mode.selected.ref}</option>
                <option :for={{name, id} <- @mode.components} value={id} selected={id == @mode.selected.ref}>{name}</option>
              </select>
            </label>
            <label class="vis-builder-board-row">
              <input type="hidden" name="sync" value="false" />
              <input type="checkbox" name="sync" value="true" checked={@mode.selected.sync} />
              <span class="vis-builder-control-label">joins the sync group</span>
            </label>
          </fieldset>
        </form>
        <form
          :if={@mode.selected}
          id={@id <> "-cell-vars"}
          class="vis-builder-board"
          phx-change="board_cell_var"
          phx-submit="submitted"
          phx-target={@target}
        >
          <fieldset class="vis-builder-board-section">
            <legend>cell variables</legend>
            <p :if={@mode.selected.vars == []} class="vis-builder-board-note">its component declares no variable</p>
            <label :for={{name, value} <- @mode.selected.vars} class="vis-builder-board-row">
              <span class="vis-builder-control-label">{name}</span>
              <input type="text" name={"var." <> name} value={value} placeholder="the board's, else the default" />
            </label>
          </fieldset>
        </form>
        <form
          :if={@mode.selected}
          id={@id <> "-cell-sources"}
          class="vis-builder-board"
          phx-change="board_bind"
          phx-submit="submitted"
          phx-target={@target}
        >
          <fieldset class="vis-builder-board-section">
            <legend>sources — {if @mode.catalog?, do: "the host's feeds", else: "the sample pool"}</legend>
            <p :if={@mode.selected.slots == []} class="vis-builder-board-note">its component reads no source</p>
            <div :for={slot <- @mode.selected.slots} class={"vis-builder-board-slot" <> if(slot.faults != [], do: " vis-builder-board-slot-faulty", else: "")}>
              <label class="vis-builder-board-row">
                <span class="vis-builder-control-label">{slot.name}</span>
                <select name={"slot." <> slot.name}>
                  <option value="" selected={slot.feed == nil}>unbound</option>
                  <option :for={{label, key} <- @mode.feeds} value={key} selected={key == slot.feed}>{label}</option>
                </select>
              </label>
              <ul :if={slot.faults != []} class="vis-builder-errors">
                <li :for={line <- slot.faults} class="vis-builder-error">{line}</li>
              </ul>
            </div>
          </fieldset>
        </form>
        <div :if={@mode.selected} class="vis-builder-board-actions">
          <button
            type="button"
            class="vis-builder-board-edit"
            phx-click="board_edit_component"
            phx-value-cell={@mode.selected.name}
            phx-target={@target}
            title="open this cell's component in the chart builder; Back to board returns"
          >Edit component</button>
          <button
            type="button"
            class="vis-builder-board-remove"
            phx-click="board_remove"
            phx-value-cell={@mode.selected.name}
            phx-target={@target}
          >Remove</button>
        </div>
        <form id={@id <> "-add"} class="vis-builder-board" phx-submit="board_add" phx-target={@target}>
          <fieldset class="vis-builder-board-section">
            <legend>add a cell</legend>
            <p :if={@mode.components == []} class="vis-builder-board-note">the library holds no composite to show</p>
            <select :if={@mode.components != []} name="ref" aria-label="the new cell's component">
              <option :for={{name, id} <- @mode.components} value={id}>{name}</option>
            </select>
            <button :if={@mode.components != []} type="submit" class="vis-builder-board-add">Add</button>
          </fieldset>
        </form>
        <form id={@id <> "-board"} class="vis-builder-board" phx-change="board_edit" phx-submit="submitted" phx-target={@target}>
          <fieldset class="vis-builder-board-section">
            <legend>board</legend>
            <label class="vis-builder-board-row">
              <span class="vis-builder-control-label">name</span>
              <input type="text" name="name" value={Map.get(@mode.board.meta, :name, "")} />
            </label>
            <label class="vis-builder-board-row">
              <span class="vis-builder-control-label">description</span>
              <input type="text" name="description" value={Map.get(@mode.board.meta, :description, "")} />
            </label>
          </fieldset>
          <fieldset class="vis-builder-board-section">
            <legend>window</legend>
            <label class="vis-builder-board-row">
              <span class="vis-builder-control-label">window</span>
              <select name="window">
                <option :for={kind <- ~w(none last fixed)} value={kind} selected={kind == @mode.window.kind}>{kind}</option>
              </select>
            </label>
            <label :if={@mode.window.kind == "last"} class="vis-builder-board-row">
              <span class="vis-builder-control-label">last, seconds</span>
              <input type="number" name="last" value={@mode.window.last} min="1" step="any" />
            </label>
            <label :if={@mode.window.kind == "fixed"} class="vis-builder-board-row">
              <span class="vis-builder-control-label">from, UTC</span>
              <input type="datetime-local" name="from" value={@mode.window.from} step="1" />
            </label>
            <label :if={@mode.window.kind == "fixed"} class="vis-builder-board-row">
              <span class="vis-builder-control-label">to, UTC</span>
              <input type="datetime-local" name="to" value={@mode.window.to} step="1" />
            </label>
            <label class="vis-builder-board-row">
              <span class="vis-builder-control-label">shown in zone</span>
              <input type="text" name="zone" value={@mode.board.zone} />
            </label>
          </fieldset>
          <fieldset class="vis-builder-board-section">
            <legend>sharing</legend>
            <label class="vis-builder-board-row">
              <span class="vis-builder-control-label">sync group</span>
              <input type="text" name="sync" value={@mode.board.sync || ""} placeholder="none" />
            </label>
            <label class="vis-builder-board-row">
              <span class="vis-builder-control-label">stale after, seconds</span>
              <input type="number" name="stale_after" value={@mode.board.stale_after} min="0" step="any" placeholder="never" />
            </label>
          </fieldset>
          <fieldset class="vis-builder-board-section">
            <legend>layout</legend>
            <label :for={{key, value} <- @mode.layout} class="vis-builder-board-row">
              <span class="vis-builder-control-label">{String.replace(to_string(key), "_", " ")}, px</span>
              <input type="number" name={to_string(key)} value={value} min="0" step="1" />
            </label>
          </fieldset>
        </form>
        <form id={@id <> "-vars"} class="vis-builder-board" phx-change="board_var" phx-submit="submitted" phx-target={@target}>
          <fieldset class="vis-builder-board-section">
            <legend>variables</legend>
            <p :if={@mode.vars == []} class="vis-builder-board-note">no cell's component declares a variable</p>
            <label :for={var <- @mode.vars} class={"vis-builder-board-row" <> if(var.declared?, do: "", else: " vis-builder-board-row-stale")}>
              <span class="vis-builder-control-label">{var.name}</span>
              <input type="text" name={"var." <> var.name} value={var.value} placeholder="each component's default" />
              <span :if={not var.declared?} class="vis-builder-board-note">no component declares it; empty it to remove</span>
            </label>
          </fieldset>
        </form>
        <section :if={@mode.sources != [] or @mode.source_errors != []} class="vis-builder-board-sources">
          <h3 class="vis-builder-control-label">virtual sources</h3>
          <ul :if={@mode.source_errors != []} class="vis-builder-errors">
            <li :for={line <- @mode.source_errors} class="vis-builder-error">{line}</li>
          </ul>
          <form
            :for={source <- @mode.sources}
            id={@id <> "-source-" <> source.path}
            class="vis-builder-board"
            phx-change="board_source"
            phx-submit="submitted"
            phx-target={@target}
          >
            <fieldset class="vis-builder-board-section" data-board-source={source.path}>
              <legend>{source.path} — {source.state}{if source.draft?, do: " (draft not written)", else: ""}</legend>
              <input type="hidden" name="source" value={source.path} />
              <textarea
                :if={source.stored?}
                name="elixir"
                class="vis-builder-board-source-text"
                spellcheck="false"
                phx-debounce="400"
              >{source.text}</textarea>
              <pre :if={not source.stored?} class="vis-builder-board-source-text" title="the host's own function, edited where it lives">{source.text}</pre>
              <ul :if={source.faults != []} class="vis-builder-errors">
                <li :for={line <- source.faults} class="vis-builder-error">{line}</li>
              </ul>
              <table :if={source.cells != []} class="vis-builder-board-source-rows">
                <thead><tr><th :for={column <- source.columns}>{column}</th></tr></thead>
                <tbody><tr :for={row <- source.cells}><td :for={value <- row}>{value}</td></tr></tbody>
              </table>
              <p :if={source.cells == []} class="vis-builder-board-note">no rows yet</p>
            </fieldset>
          </form>
        </section>
        <section class="vis-builder-board-validity">
          <h3 class="vis-builder-control-label">validity</h3>
          <ul :if={@mode.faults != []} class="vis-builder-errors">
            <li :for={line <- @mode.faults} class="vis-builder-error">{line}</li>
          </ul>
          <p :if={@mode.faults == []} class="vis-builder-board-valid">a valid board — Save to library keeps it</p>
        </section>
      </div>
      """
    end
  end
end
