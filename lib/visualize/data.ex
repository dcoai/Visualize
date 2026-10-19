defmodule Visualize.Data do
  import Kernel, except: [min: 2, max: 2]

  @moduledoc """
  Data transformation and statistical utilities.

  Provides functions for summarizing data, computing statistics,
  and transforming data for visualization.

  ## Examples

      data = [
        %{category: "A", value: 10},
        %{category: "A", value: 20},
        %{category: "B", value: 15}
      ]

      Visualize.Data.extent(data, & &1.value)
      # => {10, 20}

      Visualize.Data.group(data, & &1.category)
      # => %{"A" => [...], "B" => [...]}

  """

  @doc """
  Returns the minimum value.

  ## Examples

      Visualize.Data.min([3, 1, 4, 1, 5])
      # => 1

      Visualize.Data.min(data, & &1.value)
      # => minimum value from data

  """
  @spec min([any()], (any() -> number()) | nil) :: number() | nil
  def min(data, accessor \\ nil)
  def min([], _), do: nil

  def min(data, nil) do
    Enum.min(data)
  end

  def min(data, accessor) when is_function(accessor, 1) do
    data
    |> Enum.map(accessor)
    |> Enum.min()
  end

  @doc """
  Returns the maximum value.
  """
  @spec max([any()], (any() -> number()) | nil) :: number() | nil
  def max(data, accessor \\ nil)
  def max([], _), do: nil

  def max(data, nil) do
    Enum.max(data)
  end

  def max(data, accessor) when is_function(accessor, 1) do
    data
    |> Enum.map(accessor)
    |> Enum.max()
  end

  @doc """
  Returns {min, max} as a tuple.

  ## Examples

      Visualize.Data.extent([3, 1, 4, 1, 5])
      # => {1, 5}

      Visualize.Data.extent(data, & &1.value)
      # => {min_value, max_value}

  """
  @spec extent([any()], (any() -> number()) | nil) :: {number(), number()} | nil
  def extent(data, accessor \\ nil)
  def extent([], _), do: nil

  def extent(data, nil) do
    Enum.min_max(data)
  end

  def extent(data, accessor) when is_function(accessor, 1) do
    data
    |> Enum.map(accessor)
    |> Enum.min_max()
  end

  @doc """
  Returns the sum of values.
  """
  @spec sum([any()], (any() -> number()) | nil) :: number()
  def sum(data, accessor \\ nil)
  def sum([], _), do: 0

  def sum(data, nil) do
    Enum.sum(data)
  end

  def sum(data, accessor) when is_function(accessor, 1) do
    data
    |> Enum.map(accessor)
    |> Enum.sum()
  end

  @doc """
  Returns the arithmetic mean.
  """
  @spec mean([any()], (any() -> number()) | nil) :: float() | nil
  def mean(data, accessor \\ nil)
  def mean([], _), do: nil

  def mean(data, nil) do
    sum(data) / length(data)
  end

  def mean(data, accessor) when is_function(accessor, 1) do
    values = Enum.map(data, accessor)
    Enum.sum(values) / length(values)
  end

  @doc """
  Returns the median value.
  """
  @spec median([any()], (any() -> number()) | nil) :: number() | nil
  def median(data, accessor \\ nil)
  def median([], _), do: nil

  def median(data, accessor) do
    values =
      case accessor do
        nil -> data
        f -> Enum.map(data, f)
      end
      |> Enum.sort()

    n = length(values)
    mid = div(n, 2)

    if rem(n, 2) == 0 do
      (Enum.at(values, mid - 1) + Enum.at(values, mid)) / 2
    else
      Enum.at(values, mid)
    end
  end

  @doc """
  Returns the p-quantile value.

  `p` should be between 0 and 1.
  """
  @spec quantile([any()], float(), (any() -> number()) | nil) :: number() | nil
  def quantile(data, p, accessor \\ nil)
  def quantile([], _, _), do: nil

  def quantile(data, p, accessor) when p >= 0 and p <= 1 do
    values =
      case accessor do
        nil -> data
        f -> Enum.map(data, f)
      end
      |> Enum.sort()

    n = length(values)

    if n == 0 do
      nil
    else
      i = (n - 1) * p
      i0 = trunc(i)
      i1 = Kernel.min(i0 + 1, n - 1)
      v0 = Enum.at(values, i0)
      v1 = Enum.at(values, i1)
      v0 + (v1 - v0) * (i - i0)
    end
  end

  @doc """
  Returns the variance of values.
  """
  @spec variance([any()], (any() -> number()) | nil) :: float() | nil
  def variance(data, accessor \\ nil)
  def variance([], _), do: nil
  def variance([_], _), do: nil

  def variance(data, accessor) do
    values =
      case accessor do
        nil -> data
        f -> Enum.map(data, f)
      end

    m = Enum.sum(values) / length(values)
    n = length(values)

    values
    |> Enum.map(fn v -> (v - m) * (v - m) end)
    |> Enum.sum()
    |> Kernel./(n - 1)
  end

  @doc """
  Returns the standard deviation.
  """
  @spec deviation([any()], (any() -> number()) | nil) :: float() | nil
  def deviation(data, accessor \\ nil) do
    case variance(data, accessor) do
      nil -> nil
      v -> :math.sqrt(v)
    end
  end

  @doc """
  Returns the least-squares slope of the points the elements read as (spec/08 §5.1).

  A `{x, y}` tuple is a point; a number `v` at index `i` is the point `{i, v}`, so a
  series of numbers gives its trend per sample. `nil` for fewer than two points, or when
  every `x` is the same.

  ## Examples

      iex> Visualize.Data.slope([1, 3, 5])
      2.0

      iex> Visualize.Data.slope([{0, 1}, {2, 2}, {4, 3}])
      0.5

      iex> Visualize.Data.slope([%{t: 10, load: 4}, %{t: 20, load: 2}], &{&1.t, &1.load})
      -0.2

      iex> Visualize.Data.slope([{1, 2}, {1, 5}])
      nil

  """
  @spec slope([any()], (any() -> number() | {number(), number()}) | nil) :: float() | nil
  def slope(data, accessor \\ nil)
  def slope([], _), do: nil
  def slope([_], _), do: nil

  def slope(data, accessor) when is_nil(accessor) or is_function(accessor, 1) do
    get = accessor || (& &1)

    points =
      data
      |> Enum.with_index()
      |> Enum.map(fn {element, i} ->
        case get.(element) do
          {x, y} -> {x, y}
          v when is_number(v) -> {i, v}
        end
      end)

    n = length(points)
    mx = Enum.sum_by(points, &elem(&1, 0)) / n
    my = Enum.sum_by(points, &elem(&1, 1)) / n

    {sxy, sxx} =
      Enum.reduce(points, {0.0, 0.0}, fn {x, y}, {sxy, sxx} ->
        dx = x - mx
        {sxy + dx * (y - my), sxx + dx * dx}
      end)

    if sxx == 0, do: nil, else: sxy / sxx
  end

  @doc """
  Returns the last value minus the first (spec/08 §5.1); `nil` for `[]`.

  ## Examples

      iex> Visualize.Data.delta([3, 8, 5])
      2

      iex> Visualize.Data.delta([%{v: 1.5}, %{v: 4.0}], & &1.v)
      2.5

      iex> Visualize.Data.delta([7])
      0

      iex> Visualize.Data.delta([])
      nil

  """
  @spec delta([any()], (any() -> number()) | nil) :: number() | nil
  def delta(data, accessor \\ nil)
  def delta([], _), do: nil

  def delta([first | _] = data, nil), do: List.last(data) - first

  def delta([first | _] = data, accessor) when is_function(accessor, 1),
    do: accessor.(List.last(data)) - accessor.(first)

  @doc """
  Groups data by a key function.

  Returns a map where keys are the result of the key function
  and values are lists of matching elements.

  ## Examples

      data = [%{cat: "A", val: 1}, %{cat: "A", val: 2}, %{cat: "B", val: 3}]
      Visualize.Data.group(data, & &1.cat)
      # => %{"A" => [%{cat: "A", val: 1}, %{cat: "A", val: 2}], "B" => [%{cat: "B", val: 3}]}

  """
  @spec group([any()], (any() -> any())) :: map()
  def group(data, key_fn) when is_function(key_fn, 1) do
    Enum.group_by(data, key_fn)
  end

  @doc """
  Groups data and applies a reducer to each group.

  ## Examples

      data = [%{cat: "A", val: 1}, %{cat: "A", val: 2}, %{cat: "B", val: 3}]
      Visualize.Data.rollup(data, & &1.cat, &length/1)
      # => %{"A" => 2, "B" => 1}

      Visualize.Data.rollup(data, & &1.cat, fn items ->
        Visualize.Data.sum(items, & &1.val)
      end)
      # => %{"A" => 3, "B" => 3}

  """
  @spec rollup([any()], (any() -> any()), ([any()] -> any())) :: map()
  def rollup(data, key_fn, reduce_fn) when is_function(key_fn, 1) and is_function(reduce_fn, 1) do
    data
    |> Enum.group_by(key_fn)
    |> Map.new(fn {k, v} -> {k, reduce_fn.(v)} end)
  end

  @doc """
  Creates histogram bins from continuous data.

  ## Options

  - `:thresholds` - number of bins or list of threshold values
  - `:domain` - [min, max] range to bin

  ## Examples

      Visualize.Data.bin([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], thresholds: 5)
      # Returns list of bins with :x0, :x1, :values keys

  """
  @spec bin([number()], keyword()) :: [map()]
  def bin(data, opts \\ []) do
    return_empty_bins(data, opts) || compute_bins(data, opts)
  end

  defp return_empty_bins([], _opts), do: []
  defp return_empty_bins(_data, _opts), do: nil

  defp compute_bins(data, opts) do
    {d0, d1} =
      case Keyword.get(opts, :domain) do
        [min, max] -> {min, max}
        nil -> Enum.min_max(data)
      end

    thresholds =
      case Keyword.get(opts, :thresholds, 10) do
        n when is_integer(n) -> compute_thresholds(d0, d1, n)
        ts when is_list(ts) -> ts
      end

    # Create bins
    bins =
      ([d0] ++ thresholds ++ [d1])
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [x0, x1] ->
        %{x0: x0, x1: x1, values: []}
      end)

    # Assign values to bins
    Enum.reduce(data, bins, fn value, bins ->
      bin_index = find_bin_index(value, bins)

      if bin_index do
        List.update_at(bins, bin_index, fn bin ->
          %{bin | values: [value | bin.values]}
        end)
      else
        bins
      end
    end)
    |> Enum.map(fn bin ->
      %{bin | values: Enum.reverse(bin.values)}
    end)
  end

  defp compute_thresholds(d0, d1, count) do
    step = (d1 - d0) / count

    1..(count - 1)//1
    |> Enum.map(fn i -> d0 + i * step end)
  end

  defp find_bin_index(value, bins) do
    Enum.find_index(bins, fn %{x0: x0, x1: x1} ->
      value >= x0 and value < x1
    end) ||
      if value == List.last(bins).x1 do
        length(bins) - 1
      end
  end

  @doc """
  Creates a cross product of two arrays.

  ## Examples

      Visualize.Data.cross([1, 2], ["a", "b"])
      # => [{1, "a"}, {1, "b"}, {2, "a"}, {2, "b"}]

  """
  @spec cross([any()], [any()], (any(), any() -> any()) | nil) :: [any()]
  def cross(a, b, combine_fn \\ nil)

  def cross(a, b, nil) do
    for x <- a, y <- b, do: {x, y}
  end

  def cross(a, b, combine_fn) when is_function(combine_fn, 2) do
    for x <- a, y <- b, do: combine_fn.(x, y)
  end

  @doc """
  Generates a range of numbers.

  ## Examples

      Visualize.Data.range(0, 5)
      # => [0, 1, 2, 3, 4]

      Visualize.Data.range(0, 1, 0.2)
      # => [0, 0.2, 0.4, 0.6, 0.8]

  """
  @spec range(number(), number(), number()) :: [number()]
  def range(start, stop, step \\ 1) when step != 0 do
    n = Kernel.max(0, ceil((stop - start) / step))

    Enum.map(0..(n - 1)//1, fn i -> start + i * step end)
  end

  @doc """
  Generates evenly-spaced tick values for a domain.

  Useful for creating axis ticks without a scale.
  """
  @spec ticks(number(), number(), integer()) :: [number()]
  def ticks(start, stop, _count) when start == stop, do: [start]
  def ticks(start, stop, count) when start > stop, do: ticks(stop, start, count) |> Enum.reverse()

  def ticks(start, stop, count) when count > 0 do
    step = tick_step(start, stop, count)

    if step == 0 do
      [start]
    else
      start_tick = ceil(start / step) * step
      stop_tick = floor(stop / step) * step
      # `//1`: no multiple of the step inside the domain makes `n` zero or negative, and a
      # bare `0..-1` would descend and emit two ticks outside the domain.
      n = round((stop_tick - start_tick) / step) + 1

      0..(n - 1)//1
      |> Enum.map(fn i ->
        (start_tick + i * step)
        |> Float.round(10)
      end)
    end
  end

  defp tick_step(start, stop, count) do
    span = abs(stop - start)
    # `Kernel.max/2` explicitly: this module's `import Kernel, except: [min: 2, max: 2]`
    # would otherwise resolve `max/2` to `Visualize.Data.max/2` and crash on a number.
    raw_step = span / Kernel.max(1, count)

    power = floor(:math.log10(raw_step))
    error = raw_step / :math.pow(10, power)

    step =
      cond do
        error >= :math.sqrt(50) -> 10
        error >= :math.sqrt(10) -> 5
        error >= :math.sqrt(2) -> 2
        true -> 1
      end

    step * :math.pow(10, power)
  end

  @doc """
  Sorts data by an accessor function.
  """
  @spec sort([any()], (any() -> any()), :asc | :desc) :: [any()]
  def sort(data, accessor, order \\ :asc)

  def sort(data, accessor, :asc) when is_function(accessor, 1) do
    Enum.sort_by(data, accessor)
  end

  def sort(data, accessor, :desc) when is_function(accessor, 1) do
    Enum.sort_by(data, accessor, :desc)
  end

  @doc """
  Returns unique values by accessor.
  """
  @spec unique([any()], (any() -> any()) | nil) :: [any()]
  def unique(data, accessor \\ nil)

  def unique(data, nil) do
    Enum.uniq(data)
  end

  def unique(data, accessor) when is_function(accessor, 1) do
    Enum.uniq_by(data, accessor)
  end

  # -- shape-preserving downsampling (spec/08 §5.2, #448) ---------------------------------

  @doc """
  Largest-Triangle-Three-Buckets: about `n` of the elements, chosen to keep the series'
  visual shape (spec/08 §5.2; Steinarsson 2013).

  The accessor returns `{x, y}`; without one the elements are `{x, y}` tuples. A datum
  whose `x` or `y` is not a number is a gap: the defined data are reduced run by run
  between the gaps, and each run of gaps keeps its first element in place, so a line over
  the result still breaks where the input broke. Input of `n` or fewer elements is
  returned unchanged; without gaps the result is exactly `n` elements, the first and the
  last among them. `n` must be at least 3.

  ## Examples

      iex> Visualize.Data.lttb([{0, 0}, {1, 1}, {2, 0}, {3, 5}, {4, 0}, {5, 1}, {6, 0}], 4)
      [{0, 0}, {2, 0}, {3, 5}, {6, 0}]

      iex> Visualize.Data.lttb([{0, 0}, {1, 3}, {2, nil}, {3, 4}, {4, 1}], 9)
      [{0, 0}, {1, 3}, {2, nil}, {3, 4}, {4, 1}]

  """
  @spec lttb([any()], pos_integer(), (any() -> {term(), term()}) | nil) :: [any()]
  def lttb(data, n, accessor \\ nil)

  def lttb(data, n, accessor)
      when is_list(data) and is_integer(n) and n >= 3 and
             (is_nil(accessor) or is_function(accessor, 1)) do
    if length(data) <= n do
      data
    else
      segments = data |> read(accessor) |> runs([], [])
      defined = Enum.sum(for {:run, len, _points} <- segments, do: len)
      Enum.flat_map(segments, &lttb_segment(&1, n, defined))
    end
  end

  defp lttb_segment({:gap, element}, _n, _defined), do: [element]

  defp lttb_segment({:run, len, points}, n, defined) do
    budget = Kernel.max(Kernel.min(len, 2), floor(n * len / defined))

    cond do
      budget >= len -> for {element, _x, _y} <- Tuple.to_list(points), do: element
      budget == 2 -> [element(points, 0), element(points, len - 1)]
      true -> lttb_run(points, len, budget)
    end
  end

  # The canonical algorithm over one run of `len > n >= 3` points: the two ends kept, the
  # interior split into `n - 2` buckets of `every` points, and from each bucket the point
  # forming the largest triangle with the point kept before it and the mean point of the
  # bucket after it. Every point is read twice — once as a candidate, once in a mean — so
  # the pass is O(len).
  defp lttb_run(points, len, n) do
    every = (len - 2) / (n - 2)
    middle = buckets(points, len, every, 0, n - 2, 0, [])
    [element(points, 0) | middle] ++ [element(points, len - 1)]
  end

  defp buckets(_points, _len, _every, count, count, _a, kept), do: :lists.reverse(kept)

  defp buckets(points, len, every, i, count, a, kept) do
    from = floor(i * every) + 1
    to = floor((i + 1) * every) + 1
    next_to = Kernel.min(floor((i + 2) * every) + 1, len)
    {cx, cy} = mean_point(points, to, next_to)
    {_element, ax, ay} = elem(points, a)
    chosen = largest(points, from, to, ax, ay, cx, cy, from, -1)
    buckets(points, len, every, i + 1, count, chosen, [element(points, chosen) | kept])
  end

  # The mean point of the indices `[from, to)`, never empty: the bucket after the last
  # holds at least the last point.
  defp mean_point(points, from, to), do: sum_point(points, from, to, 0, 0, to - from)

  defp sum_point(_points, to, to, sx, sy, count), do: {sx / count, sy / count}

  defp sum_point(points, j, to, sx, sy, count) do
    {_element, x, y} = elem(points, j)
    sum_point(points, j + 1, to, sx + x, sy + y, count)
  end

  # The index in `[j, to)` whose point makes the largest triangle with `a` and `c`; the
  # earliest on a tie. Twice the area is enough to compare.
  defp largest(_points, to, to, _ax, _ay, _cx, _cy, best, _area), do: best

  defp largest(points, j, to, ax, ay, cx, cy, best, best_area) do
    {_element, x, y} = elem(points, j)
    area = abs((ax - cx) * (y - ay) - (ax - x) * (cy - ay))

    if area > best_area,
      do: largest(points, j + 1, to, ax, ay, cx, cy, j, area),
      else: largest(points, j + 1, to, ax, ay, cx, cy, best, best_area)
  end

  @doc """
  M4: per pixel column, the first, last, least-`y` and greatest-`y` elements — the
  elements a line drawn `width` pixels wide needs to draw the same pixels as all of them
  (spec/08 §5.2; Jugel et al. 2014).

  The columns split the extent of the defined `x` readings evenly. The accessor, the gaps
  and the runs are as `lttb/3`'s: each run of gaps keeps its first element in place, and
  each stretch of one run in one column keeps at most four elements, deduplicated and in
  input order. `width` must be at least 1.

  ## Examples

      iex> Visualize.Data.m4([{0, 1}, {1, 5}, {2, 0}, {3, 2}, {4, 3}, {5, 9}, {6, 4}, {7, 6}], 2)
      [{0, 1}, {1, 5}, {2, 0}, {3, 2}, {4, 3}, {5, 9}, {7, 6}]

      iex> Visualize.Data.m4([{0, 1}, {1, 2}, {2, nil}, {3, nil}, {4, 3}], 1)
      [{0, 1}, {1, 2}, {2, nil}, {4, 3}]

  """
  @spec m4([any()], pos_integer(), (any() -> {term(), term()}) | nil) :: [any()]
  def m4(data, width, accessor \\ nil)

  def m4(data, width, accessor)
      when is_list(data) and is_integer(width) and width >= 1 and
             (is_nil(accessor) or is_function(accessor, 1)) do
    read = read(data, accessor)
    m4_walk(read, column_of(read, width), nil, [])
  end

  # A defined `x` to its column over the defined extent; every `x` is column 0 when the
  # extent is a point (or there is none).
  defp column_of(read, width) do
    extent =
      Enum.reduce(read, nil, fn
        {:gap, _element}, extent -> extent
        {_element, x, _y}, nil -> {x, x}
        {_element, x, _y}, {lo, hi} -> {Kernel.min(lo, x), Kernel.max(hi, x)}
      end)

    case extent do
      {lo, hi} when hi > lo ->
        fn x -> Kernel.min(width - 1, floor((x - lo) / (hi - lo) * width)) end

      _point_or_none ->
        fn _x -> 0 end
    end
  end

  # One pass: a column visit is `{column, count, first, low, high, last}` with `low` and
  # `high` as `{index, element, y}` within the visit; a gap or a new column flushes it.
  defp m4_walk([], _column, visit, kept), do: :lists.reverse(flush_visit(visit, kept))

  defp m4_walk([{:gap, element} | rest], column, visit, kept),
    do: m4_walk(skip_gaps(rest), column, nil, [element | flush_visit(visit, kept)])

  defp m4_walk([{element, x, y} | rest], column, visit, kept) do
    c = column.(x)

    case visit do
      {^c, i, first, {_, _, ly} = low, {_, _, hy} = high, _last} ->
        low = if y < ly, do: {i, element, y}, else: low
        high = if y > hy, do: {i, element, y}, else: high
        m4_walk(rest, column, {c, i + 1, first, low, high, element}, kept)

      _other_column_or_none ->
        start = {c, 1, element, {0, element, y}, {0, element, y}, element}
        m4_walk(rest, column, start, flush_visit(visit, kept))
    end
  end

  # A visit's first, earliest least, earliest greatest and last elements, deduplicated and
  # in input order, onto the reversed result.
  defp flush_visit(nil, kept), do: kept

  defp flush_visit({_c, count, first, {li, low, _}, {hi, high, _}, last}, kept) do
    [{0, first}, {li, low}, {hi, high}, {count - 1, last}]
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.dedup_by(&elem(&1, 0))
    |> Enum.reduce(kept, fn {_i, element}, kept -> [element | kept] end)
  end

  # The elements read once through the accessor: a defined datum as `{element, x, y}`, a
  # gap as `{:gap, element}` — the sizes differ, so no element is mistaken for the tag.
  defp read(data, accessor) do
    get = accessor || (& &1)

    Enum.map(data, fn element ->
      {x, y} = get.(element)
      if is_number(x) and is_number(y), do: {element, x, y}, else: {:gap, element}
    end)
  end

  # The read elements as segments in order: `{:run, length, points}` with the points a
  # tuple for the buckets' random access, and `{:gap, element}` for the first of each run
  # of gaps.
  defp runs([], run, segments), do: :lists.reverse(flush_run(run, segments))

  defp runs([{:gap, element} | rest], run, segments),
    do: runs(skip_gaps(rest), [], [{:gap, element} | flush_run(run, segments)])

  defp runs([point | rest], run, segments), do: runs(rest, [point | run], segments)

  defp flush_run([], segments), do: segments

  defp flush_run(run, segments),
    do: [{:run, length(run), run |> :lists.reverse() |> List.to_tuple()} | segments]

  defp skip_gaps([{:gap, _element} | rest]), do: skip_gaps(rest)
  defp skip_gaps(rest), do: rest

  defp element(points, i), do: points |> elem(i) |> elem(0)
end
