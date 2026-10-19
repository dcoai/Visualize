defmodule Visualize.Board.Validator do
  @moduledoc false
  # A board's validation (spec/15 §3, D-141): alone — keys, types, placement, the window —
  # and given a store, where each cell's component is resolved and read as a design. Every
  # fault is `{path, reason}` in the shape of spec/14 §10.1, so
  # `Visualize.Chart.Validator.format/1` words a board's faults as it words a design's.

  alias Visualize.Chart
  alias Visualize.Chart.{Composite, Migration, Validator, Var}
  alias Visualize.Scale.Time
  alias Visualize.VirtualSource

  @columns 12

  # Boards were introduced at schema version 2 (spec/15 §2.3): there is no older board.
  @first 2

  @board_keys [
    :version,
    :meta,
    :cells,
    :window,
    :zone,
    :vars,
    :sync,
    :layout,
    :stale_after,
    :links,
    :virtual_sources
  ]
  @cell_keys [:x, :y, :w, :h, :ref, :title, :vars, :sync, :drill, :virtual_sources]
  @drill_keys [:board, :vars]
  @cell_required [:x, :y, :w, :h, :ref]
  @meta_keys [:name, :description]
  @layout_keys [:breakpoint, :row_height, :gap]

  @doc false
  def columns, do: @columns

  @doc false
  def first_version, do: @first

  @doc false
  def board_keys, do: @board_keys

  @doc false
  def cell_keys, do: @cell_keys

  @doc false
  def drill_keys, do: @drill_keys

  @doc false
  def meta_keys, do: @meta_keys

  @doc false
  def layout_keys, do: @layout_keys

  # -- alone (spec/15 §3.1) --------------------------------------------------------------

  @doc false
  @spec validate(term()) :: :ok | {:error, [Validator.error(), ...]}
  def validate(map) when is_map(map) and not is_struct(map) do
    errors =
      unknown(map, @board_keys, []) ++
        version(Map.get(map, :version)) ++
        meta(Map.get(map, :meta, %{})) ++
        cells(Map.get(map, :cells, %{})) ++
        window(Map.get(map, :window)) ++
        zone(Map.get(map, :zone, "Etc/UTC")) ++
        vars(Map.get(map, :vars, %{}), [:vars]) ++
        sync(Map.get(map, :sync)) ++
        layout(Map.get(map, :layout, %{})) ++
        stale_after(Map.get(map, :stale_after)) ++
        links(Map.get(map, :links, %{})) ++
        virtual_sources(Map.get(map, :virtual_sources, %{}), [:virtual_sources])

    done(errors)
  end

  def validate(_other), do: {:error, [{[], {:type, :board}}]}

  @doc false
  def done([]), do: :ok
  def done(errors), do: {:error, Enum.sort_by(errors, &elem(&1, 0))}

  defp unknown(map, keys, path) do
    for key <- Map.keys(map), key not in keys, do: {path ++ [key], :unknown_key}
  end

  defp version(nil), do: []

  defp version(v) when is_integer(v) and v > 0 do
    case Migration.readable(v) do
      {:error, reason} -> [{[:version], reason}]
      :ok when v < @first -> [{[:version], {:unsupported_version, v}}]
      :ok -> []
    end
  end

  defp version(v) when is_integer(v), do: [{[:version], {:unsupported_version, v}}]
  defp version(_v), do: [{[:version], {:type, :integer}}]

  defp meta(meta) when is_map(meta) and not is_struct(meta) do
    unknown(meta, @meta_keys, [:meta]) ++
      for {key, value} <- meta,
          key in @meta_keys,
          not is_binary(value),
          do: {[:meta, key], {:type, :string}}
  end

  defp meta(_meta), do: [{[:meta], {:type, {:node, :meta}}}]

  # -- cells and their placement ---------------------------------------------------------

  defp cells(cells) when is_map(cells) and not is_struct(cells) do
    each =
      Enum.flat_map(cells, fn
        {name, cell} when is_atom(name) and not is_boolean(name) and not is_nil(name) ->
          cell(name, cell)

        {name, _cell} ->
          [{[:cells, name], {:type, :name}}]
      end)

    each ++ placement(cells)
  end

  defp cells(_cells), do: [{[:cells], {:type, {:map, {:node, :cell}}}}]

  defp cell(name, cell) when is_map(cell) and not is_struct(cell) do
    path = [:cells, name]

    unknown(cell, @cell_keys, path) ++
      for(key <- @cell_required, not Map.has_key?(cell, key), do: {path ++ [key], :required}) ++
      Enum.flat_map(cell, fn {key, value} -> cell_key(key, value, path ++ [key]) end)
  end

  defp cell(name, _cell), do: [{[:cells, name], {:type, {:node, :cell}}}]

  defp cell_key(key, v, _path) when key in [:x, :y] and is_integer(v) and v >= 0, do: []
  defp cell_key(key, _v, path) when key in [:x, :y], do: [{path, {:type, :non_neg_integer}}]
  defp cell_key(key, v, _path) when key in [:w, :h] and is_integer(v) and v > 0, do: []
  defp cell_key(key, _v, path) when key in [:w, :h], do: [{path, {:type, :pos_integer}}]
  defp cell_key(:ref, ref, path), do: ref(ref, path)
  defp cell_key(:title, title, _path) when is_binary(title) or is_nil(title), do: []
  defp cell_key(:title, _title, path), do: [{path, {:type, :string}}]
  defp cell_key(:vars, vars, path), do: vars(vars, path)
  defp cell_key(:sync, sync, _path) when is_boolean(sync), do: []
  defp cell_key(:sync, _sync, path), do: [{path, {:type, :boolean}}]
  defp cell_key(:drill, drill, path), do: drill(drill, path)
  defp cell_key(:virtual_sources, sources, path), do: virtual_sources(sources, path)
  defp cell_key(_key, _value, _path), do: []

  # A component is a composite id (spec/15 §1.3); an id of another kind is refused by its
  # tag before anything resolves it, as a design's validator refuses one (spec/14 §19.7).
  defp ref({:composite, n}, _path) when is_integer(n) and n > 0, do: []

  defp ref({kind, n}, path) when is_atom(kind) and is_integer(n) and n > 0,
    do: [{path, {:ref_kind, :composite, kind}}]

  defp ref(_ref, path), do: [{path, {:type, {:id, :composite}}}]

  defp placement(cells) do
    rects =
      for {name, cell} <- cells, is_atom(name), rect = rect(cell), into: %{}, do: {name, rect}

    off =
      for {name, %{x: x, w: w}} <- rects,
          x + w > @columns,
          do: {[:cells, name], {:off_grid, @columns}}

    names = rects |> Map.keys() |> Enum.sort()

    overlaps =
      for {a, i} <- Enum.with_index(names),
          b <- Enum.drop(names, i + 1),
          overlaps?(Map.fetch!(rects, a), Map.fetch!(rects, b)),
          do: {[:cells, b], {:overlap, a}}

    off ++ overlaps
  end

  # A cell's rectangle, once its four keys are integers of the right sign.
  defp rect(%{x: x, y: y, w: w, h: h} = cell)
       when is_integer(x) and x >= 0 and is_integer(y) and y >= 0 and is_integer(w) and w > 0 and
              is_integer(h) and h > 0,
       do: Map.take(cell, [:x, :y, :w, :h])

  defp rect(_cell), do: nil

  @doc false
  def overlaps?(a, b),
    do: a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h

  # -- shared state ------------------------------------------------------------------------

  defp window(nil), do: []

  defp window(%{last: _} = window) when is_map_key(window, :from) or is_map_key(window, :to),
    do: [{[:window], {:window, :both}}]

  defp window(%{last: last} = window) when not is_struct(window),
    do: unknown(window, [:last], [:window]) ++ last(last)

  defp window(window) when is_map(window) and not is_struct(window) and map_size(window) > 0 do
    present =
      for key <- [:from, :to], Map.has_key?(window, key), do: key

    unknown(window, [:from, :to], [:window]) ++
      for(key <- [:from, :to] -- present, present != [], do: {[:window, key], :required}) ++
      Enum.flat_map(present, &utc(Map.fetch!(window, &1), [:window, &1])) ++
      inverted(window)
  end

  defp window(_window), do: [{[:window], {:type, :window}}]

  defp last(s) when is_number(s) and s > 0, do: []
  defp last(_s), do: [{[:window, :last], {:type, :positive}}]

  defp utc(%DateTime{time_zone: "Etc/UTC"}, _path), do: []
  defp utc(_value, path), do: [{path, {:type, :utc_datetime}}]

  defp inverted(%{
         from: %DateTime{time_zone: "Etc/UTC"} = from,
         to: %DateTime{time_zone: "Etc/UTC"} = to
       }) do
    if DateTime.compare(from, to) == :lt, do: [], else: [{[:window], {:window, :inverted}}]
  end

  defp inverted(_window), do: []

  # The display zone, checked as a time scale's is (spec/14 §4.3, D-115).
  defp zone(zone) when is_binary(zone) do
    case Time.check_zone(zone) do
      :ok -> []
      {:error, reason} -> [{[:zone], {:zone, zone, reason}}]
    end
  end

  defp zone(_zone), do: [{[:zone], {:type, :string}}]

  # A board's and a cell's variables are values: a name each, and never a variable, since
  # resolution is single level (spec/14 §7.1).
  defp vars(vars, path) when is_map(vars) and not is_struct(vars) do
    Enum.flat_map(vars, fn
      {name, _value} when not is_atom(name) or is_boolean(name) or is_nil(name) ->
        [{path ++ [name], {:type, :name}}]

      {name, %Var{}} ->
        [{path ++ [name], {:var_binding, name}}]

      {_name, _value} ->
        []
    end)
  end

  defp vars(_vars, path), do: [{path, {:type, {:map, :term}}}]

  # How old a cell's newest reading may be before it is stale (spec/15 §8.4), seconds.
  defp stale_after(nil), do: []
  defp stale_after(s) when is_number(s) and s > 0, do: []
  defp stale_after(_s), do: [{[:stale_after], {:type, :positive}}]

  # Fields that mean one thing under two names (spec/15 §13.2): a name to a name.
  defp links(links) when is_map(links) and not is_struct(links) do
    for {field, link} <- links,
        not (name?(field) and name?(link)),
        do: {[:links, field], {:type, :name}}
  end

  defp links(_links), do: [{[:links], {:type, {:map, :name}}}]

  # Each virtual source read as `Visualize.VirtualSource.new/1` reads it, with its id, its
  # faults under it (spec/15 §3.1, spec/08 §10.5.5). What its inputs name is checked when
  # the board starts, where its feeds are known.
  defp virtual_sources(sources, path) when is_map(sources) and not is_struct(sources) do
    Enum.flat_map(sources, fn
      {id, source} when is_atom(id) and id not in [nil, true, false] and is_map(source) ->
        case VirtualSource.new(Map.put(source, :id, id)) do
          {:ok, _source} -> []
          {:error, errors} -> for {at, reason} <- errors, do: {path ++ [id | at], reason}
        end

      {id, _source} when is_atom(id) and id not in [nil, true, false] ->
        [{path ++ [id], {:type, {:node, :virtual_source}}}]

      {id, _source} ->
        [{path ++ [id], {:type, :name}}]
    end)
  end

  defp virtual_sources(_sources, path), do: [{path, {:type, {:map, {:node, :virtual_source}}}}]

  defp name?(name), do: is_atom(name) and not is_boolean(name) and not is_nil(name)

  # A cell's drill target (spec/15 §13.3): a board ref and the variables it is opened
  # with, each a field of the datum or a value.
  defp drill(nil, _path), do: []

  defp drill(drill, path) when is_map(drill) and not is_struct(drill) do
    unknown(drill, @drill_keys, path) ++
      if(Map.has_key?(drill, :board),
        do: board_ref(drill.board, path ++ [:board]),
        else: [{path ++ [:board], :required}]
      ) ++
      drill_vars(Map.get(drill, :vars, %{}), path ++ [:vars])
  end

  defp drill(_drill, path), do: [{path, {:type, {:node, :drill}}}]

  defp board_ref(ref, _path) when is_binary(ref) and ref != "", do: []
  defp board_ref(ref, _path) when is_integer(ref) and ref > 0, do: []

  defp board_ref(ref, path) do
    if name?(ref), do: [], else: [{path, {:type, :board_ref}}]
  end

  defp drill_vars(vars, path) when is_map(vars) and not is_struct(vars) do
    vars(vars, path) ++
      for {name, {:datum, field}} <- vars, not name?(field), do: {path ++ [name], {:type, :field}}
  end

  defp drill_vars(vars, path), do: vars(vars, path)

  defp sync(nil), do: []

  defp sync(sync) when is_binary(sync) and sync != "", do: []
  defp sync(_sync), do: [{[:sync], {:type, :string}}]

  defp layout(layout) when is_map(layout) and not is_struct(layout) do
    unknown(layout, @layout_keys, [:layout]) ++
      Enum.flat_map(layout, fn
        {key, v} when key in [:breakpoint, :row_height] and is_integer(v) and v > 0 ->
          []

        {key, _v} when key in [:breakpoint, :row_height] ->
          [{[:layout, key], {:type, :pos_integer}}]

        {:gap, v} when is_integer(v) and v >= 0 ->
          []

        {:gap, _v} ->
          [{[:layout, :gap], {:type, :non_neg_integer}}]

        {_key, _v} ->
          []
      end)
  end

  defp layout(_layout), do: [{[:layout], {:type, {:node, :layout}}}]

  # -- given a store (spec/15 §3.2) ----------------------------------------------------------

  @doc false
  # The fetch resolution reads: a function as given, a map of id to fragment by
  # `Map.fetch/2`.
  def fetch(store) when is_function(store, 1), do: store
  def fetch(store) when is_map(store), do: &Map.fetch(store, &1)

  @doc false
  # Each cell's component as a chart, or the faults that kept it from being read, by path
  # under the cell's ref: the entry fetched, flattened through the same store and read
  # through `Visualize.Chart.from_map/2` with the board reader's options: its `limits:` and
  # the `generators:` its names are checked against (spec/14 §3.13).
  @spec components(map(), (term() -> {:ok, map()} | :error), keyword()) ::
          {%{atom() => Chart.t()}, [Validator.error()]}
  def components(cells, fetch, read) do
    Enum.reduce(Enum.sort(cells), {%{}, []}, fn {name, cell}, {charts, errors} ->
      case component(cell.ref, fetch, read) do
        {:ok, chart} ->
          {Map.put(charts, name, chart), errors}

        {:error, faults} ->
          {charts,
           errors ++ Enum.map(faults, fn {path, r} -> {[:cells, name, :ref | path], r} end)}
      end
    end)
  end

  defp component(ref, fetch, read) do
    case fetch.(ref) do
      :error ->
        {:error, [{[], {:dangling, ref}}]}

      {:ok, fragment} ->
        case Composite.flatten(fragment, fetch) do
          {:ok, flat, _report} -> Chart.from_map(flat, read)
          {:error, {:cycle, chain}} -> {:error, [{[], {:cycle, chain}}]}
        end
    end
  end

  @doc false
  # The faults of a valid board that only its components show: a cell variable the
  # component does not declare, and a cell that cannot join the board's group.
  def given(map, charts) do
    cells = Map.get(map, :cells, %{})
    group = Map.get(map, :sync)

    Enum.flat_map(charts, fn {name, chart} ->
      cell = Map.fetch!(cells, name)
      declared = declared(chart)

      undeclared =
        for var <- Map.keys(Map.get(cell, :vars, %{})),
            var not in declared,
            do: {[:cells, name, :vars, var], {:undeclared, :var, var}}

      undeclared ++ unsyncable(name, cell, chart, group)
    end)
  end

  @doc false
  # The faults of each cell's drill target given the boards a drill may name (spec/15
  # §13.3): a ref the host does not hold, a variable the target does not declare, and a
  # datum field the cell's component's sources do not declare. `boards` is a fetch, or
  # `nil` when none was given, and then only a `:self` target is checked.
  def drills(map, charts, boards) do
    map
    |> Map.get(:cells, %{})
    |> Enum.sort()
    |> Enum.flat_map(fn
      {name, %{drill: %{board: ref} = drill}} ->
        path = [:cells, name, :drill]
        vars = Map.get(drill, :vars, %{})

        target(ref, map, boards, path) ++
          declared_by(target_vars(ref, map, boards), vars, path) ++
          datum_fields(Map.get(charts, name), vars, path)

      {_name, _cell} ->
        []
    end)
  end

  defp target(:self, _map, _boards, _path), do: []
  defp target(_ref, _map, nil, _path), do: []

  defp target(ref, _map, boards, path) do
    case boards.(ref) do
      {:ok, _board} -> []
      :error -> [{path ++ [:board], {:no_board, ref}}]
    end
  end

  # The variables the target declares, the keys of its `vars`; `nil` when it is not known.
  defp target_vars(:self, map, _boards), do: Map.keys(Map.get(map, :vars, %{}))
  defp target_vars(_ref, _map, nil), do: nil

  defp target_vars(ref, _map, boards) do
    case boards.(ref) do
      {:ok, board} -> board |> Map.get(:vars, %{}) |> Map.keys()
      :error -> nil
    end
  end

  defp declared_by(nil, _vars, _path), do: []

  defp declared_by(declared, vars, path) do
    for var <- vars |> Map.keys() |> Enum.sort(),
        var not in declared,
        do: {path ++ [:vars, var], {:undeclared, :var, var}}
  end

  # A datum field must be one the component's sources declare, when they declare any.
  defp datum_fields(nil, _vars, _path), do: []

  defp datum_fields(%Chart{sources: sources}, vars, path) do
    fields =
      for {_slot, node} <- sources || %{},
          field <- Map.get(node, :fields, []),
          is_atom(field),
          uniq: true,
          do: field

    if fields == [] do
      []
    else
      for {var, {:datum, field}} <- Enum.sort(vars),
          field not in fields,
          do: {path ++ [:vars, var], {:undeclared, :field, field}}
    end
  end

  @doc false
  # The variables a component declares.

  def declared(%Chart{vars: vars}) when is_map(vars) and not is_struct(vars), do: Map.keys(vars)
  def declared(_chart), do: []

  defp unsyncable(_name, _cell, _chart, nil), do: []

  defp unsyncable(name, cell, chart, group) do
    if Map.get(cell, :sync, true) do
      case chart |> joined(group) |> Chart.to_map() |> Validator.validate() do
        :ok ->
          []

        {:error, errors} ->
          for {_path, {:sync, _, _} = r} <- errors, do: {[:cells, name, :sync], r}
      end
    else
      []
    end
  end

  @doc false
  # The chart with the board's group written into its `interaction.sync`: the board's group
  # replaces a design's own, since the board is the page (spec/15 §1.5).
  def joined(%Chart{interaction: interaction} = chart, group)
      when is_map(interaction) and not is_struct(interaction),
      do: %{chart | interaction: Map.put(interaction, :sync, group)}

  def joined(%Chart{} = chart, group), do: %{chart | interaction: %{sync: group}}
end
