defmodule Visualize.VirtualSource.Sandbox.Allowlist do
  @moduledoc """
  What a stored virtual-source function may call (spec/08 §10.5.2, D-194): the allowlist
  #643 decided on 2026-10-15, as **explicit** `{function, arity}` lists — never "a module
  minus a few".

  Each module's allowed list and its excluded list together are exactly its exports on
  Elixir 1.20.4 and OTP 29; the test suite holds them to it, so a function a new Elixir
  adds fails that test until it is reviewed and listed. `Visualize.Data` (#769) is the
  library's own and held the same way: a function added to it is listed before a stored
  function may call it.
  """

  @modules [Enum, Map, Keyword, String, Integer, Float, :math, Visualize.Data]

  @enum [
    all?: 1,
    all?: 2,
    any?: 1,
    any?: 2,
    at: 2,
    at: 3,
    chunk_by: 2,
    chunk_every: 2,
    chunk_every: 3,
    chunk_every: 4,
    chunk_while: 4,
    concat: 1,
    concat: 2,
    count: 1,
    count: 2,
    count_until: 2,
    count_until: 3,
    dedup: 1,
    dedup_by: 2,
    drop: 2,
    drop_every: 2,
    drop_while: 2,
    each: 2,
    empty?: 1,
    fetch: 2,
    fetch!: 2,
    filter: 2,
    find: 2,
    find: 3,
    find_index: 2,
    find_value: 2,
    find_value: 3,
    flat_map: 2,
    flat_map_reduce: 3,
    frequencies: 1,
    frequencies_by: 2,
    group_by: 2,
    group_by: 3,
    intersperse: 2,
    into: 2,
    into: 3,
    join: 1,
    join: 2,
    map: 2,
    map_every: 3,
    map_intersperse: 3,
    map_join: 2,
    map_join: 3,
    map_reduce: 3,
    max: 1,
    max: 2,
    max: 3,
    max_by: 2,
    max_by: 3,
    max_by: 4,
    member?: 2,
    min: 1,
    min: 2,
    min: 3,
    min_by: 2,
    min_by: 3,
    min_by: 4,
    min_max: 1,
    min_max: 2,
    min_max: 3,
    min_max_by: 2,
    min_max_by: 3,
    min_max_by: 4,
    product: 1,
    product_by: 2,
    reduce: 2,
    reduce: 3,
    reduce_while: 3,
    reject: 2,
    reverse: 1,
    reverse: 2,
    reverse_slice: 3,
    scan: 2,
    scan: 3,
    slice: 2,
    slice: 3,
    slide: 3,
    sort: 1,
    sort: 2,
    sort_by: 2,
    sort_by: 3,
    split: 2,
    split_while: 2,
    split_with: 2,
    sum: 1,
    sum_by: 2,
    take: 2,
    take_every: 2,
    take_while: 2,
    to_list: 1,
    uniq: 1,
    uniq_by: 2,
    unzip: 1,
    with_index: 1,
    with_index: 2,
    zip: 1,
    zip: 2,
    zip_reduce: 3,
    zip_reduce: 4,
    zip_with: 2,
    zip_with: 3
  ]

  @map [
    delete: 2,
    drop: 2,
    equal?: 2,
    fetch: 2,
    fetch!: 2,
    filter: 2,
    from_keys: 2,
    from_struct: 1,
    get: 2,
    get: 3,
    get_and_update: 3,
    get_and_update!: 3,
    get_lazy: 3,
    has_key?: 2,
    intersect: 2,
    intersect: 3,
    keys: 1,
    merge: 2,
    merge: 3,
    new: 0,
    new: 1,
    new: 2,
    pop: 2,
    pop: 3,
    pop!: 2,
    pop_lazy: 3,
    put: 3,
    put_new: 3,
    put_new_lazy: 3,
    reject: 2,
    replace: 3,
    replace!: 3,
    replace_lazy: 3,
    split: 2,
    split_with: 2,
    take: 2,
    to_list: 1,
    update: 4,
    update!: 3,
    values: 1
  ]

  @keyword [
    delete: 2,
    delete_first: 2,
    drop: 2,
    equal?: 2,
    fetch: 2,
    fetch!: 2,
    filter: 2,
    from_keys: 2,
    get: 2,
    get: 3,
    get_and_update: 3,
    get_and_update!: 3,
    get_lazy: 3,
    get_values: 2,
    has_key?: 2,
    intersect: 2,
    intersect: 3,
    keys: 1,
    keyword?: 1,
    merge: 2,
    merge: 3,
    new: 0,
    new: 1,
    new: 2,
    pop: 2,
    pop: 3,
    pop!: 2,
    pop_first: 2,
    pop_first: 3,
    pop_lazy: 3,
    pop_values: 2,
    put: 3,
    put_new: 3,
    put_new_lazy: 3,
    reject: 2,
    replace: 3,
    replace!: 3,
    replace_lazy: 3,
    split: 2,
    split_with: 2,
    take: 2,
    to_list: 1,
    update: 4,
    update!: 3,
    validate: 2,
    validate!: 2,
    values: 1
  ]

  @string [
    at: 2,
    bag_distance: 2,
    byte_slice: 3,
    capitalize: 1,
    capitalize: 2,
    chunk: 2,
    codepoints: 1,
    contains?: 2,
    count: 2,
    downcase: 1,
    downcase: 2,
    duplicate: 2,
    ends_with?: 2,
    equivalent?: 2,
    first: 1,
    graphemes: 1,
    jaro_distance: 2,
    last: 1,
    length: 1,
    match?: 2,
    myers_difference: 2,
    next_codepoint: 1,
    next_grapheme: 1,
    next_grapheme_size: 1,
    normalize: 2,
    pad_leading: 2,
    pad_leading: 3,
    pad_trailing: 2,
    pad_trailing: 3,
    printable?: 1,
    printable?: 2,
    replace: 3,
    replace: 4,
    replace_invalid: 1,
    replace_invalid: 2,
    replace_leading: 3,
    replace_prefix: 3,
    replace_suffix: 3,
    replace_trailing: 3,
    reverse: 1,
    slice: 2,
    slice: 3,
    split: 1,
    split: 2,
    split: 3,
    split_at: 2,
    splitter: 2,
    splitter: 3,
    starts_with?: 2,
    to_charlist: 1,
    to_float: 1,
    to_integer: 1,
    to_integer: 2,
    trim: 1,
    trim: 2,
    trim_leading: 1,
    trim_leading: 2,
    trim_trailing: 1,
    trim_trailing: 2,
    upcase: 1,
    upcase: 2,
    valid?: 1,
    valid?: 2
  ]

  @integer [
    ceil_div: 2,
    digits: 1,
    digits: 2,
    extended_gcd: 2,
    floor_div: 2,
    gcd: 2,
    is_even: 1,
    is_odd: 1,
    mod: 2,
    parse: 1,
    parse: 2,
    popcount: 1,
    pow: 2,
    to_charlist: 1,
    to_charlist: 2,
    to_string: 1,
    to_string: 2,
    undigits: 1,
    undigits: 2
  ]

  @float [
    ceil: 1,
    ceil: 2,
    floor: 1,
    floor: 2,
    max_finite: 0,
    min_finite: 0,
    parse: 1,
    pow: 2,
    ratio: 1,
    round: 1,
    round: 2,
    to_charlist: 1,
    to_string: 1
  ]

  @math [
    acos: 1,
    acosh: 1,
    asin: 1,
    asinh: 1,
    atan: 1,
    atan2: 2,
    atanh: 1,
    ceil: 1,
    cos: 1,
    cosh: 1,
    erf: 1,
    erfc: 1,
    exp: 1,
    floor: 1,
    fmod: 2,
    log: 1,
    log10: 1,
    log2: 1,
    pi: 0,
    pow: 2,
    sin: 1,
    sinh: 1,
    sqrt: 1,
    tan: 1,
    tanh: 1,
    tau: 0
  ]

  # The library's statistics, grouping and shaping (spec/08 §5, #769): every export.
  @data [
    bin: 1,
    bin: 2,
    cross: 2,
    cross: 3,
    delta: 1,
    delta: 2,
    deviation: 1,
    deviation: 2,
    extent: 1,
    extent: 2,
    group: 2,
    lttb: 2,
    lttb: 3,
    m4: 2,
    m4: 3,
    max: 1,
    max: 2,
    mean: 1,
    mean: 2,
    median: 1,
    median: 2,
    min: 1,
    min: 2,
    quantile: 2,
    quantile: 3,
    range: 2,
    range: 3,
    rollup: 3,
    slope: 1,
    slope: 2,
    sort: 2,
    sort: 3,
    sum: 1,
    sum: 2,
    ticks: 3,
    unique: 1,
    unique: 2,
    variance: 1,
    variance: 2
  ]

  # The decided exclusions (#643, 2026-10-15) and every deprecated export (D-194).
  @excluded %{
    Enum => [
      {{:random, 1}, :nondeterministic},
      {{:shuffle, 1}, :nondeterministic},
      {{:take_random, 2}, :nondeterministic},
      {{:chunk, 2}, :deprecated},
      {{:chunk, 3}, :deprecated},
      {{:chunk, 4}, :deprecated},
      {{:filter_map, 3}, :deprecated},
      {{:partition, 2}, :deprecated},
      {{:uniq, 2}, :deprecated},
      {{:__in__, 2}, :internal}
    ],
    Map => [{{:map, 2}, :deprecated}, {{:size, 1}, :deprecated}],
    Keyword => [
      {{:delete, 3}, :deprecated},
      {{:map, 2}, :deprecated},
      {{:size, 1}, :deprecated}
    ],
    String => [
      {{:to_atom, 1}, :atoms},
      {{:to_existing_atom, 1}, :atoms},
      {{:to_char_list, 1}, :deprecated},
      {{:strip, 1}, :deprecated},
      {{:strip, 2}, :deprecated},
      {{:lstrip, 1}, :deprecated},
      {{:lstrip, 2}, :deprecated},
      {{:rstrip, 1}, :deprecated},
      {{:rstrip, 2}, :deprecated},
      {{:ljust, 2}, :deprecated},
      {{:ljust, 3}, :deprecated},
      {{:rjust, 2}, :deprecated},
      {{:rjust, 3}, :deprecated},
      {{:valid_character?, 1}, :deprecated}
    ],
    Integer => [{{:to_char_list, 1}, :deprecated}, {{:to_char_list, 2}, :deprecated}],
    Float => [
      {{:to_char_list, 1}, :deprecated},
      {{:to_char_list, 2}, :deprecated},
      {{:to_string, 2}, :deprecated}
    ],
    :math => [],
    Visualize.Data => []
  }

  @allowed %{
    Enum => @enum,
    Map => @map,
    Keyword => @keyword,
    String => @string,
    Integer => @integer,
    Float => @float,
    :math => @math,
    Visualize.Data => @data
  }

  @is_guards [
    is_atom: 1,
    is_binary: 1,
    is_bitstring: 1,
    is_boolean: 1,
    is_exception: 1,
    is_exception: 2,
    is_float: 1,
    is_function: 1,
    is_function: 2,
    is_integer: 1,
    is_list: 1,
    is_map: 1,
    is_map_key: 2,
    is_nil: 1,
    is_non_struct_map: 1,
    is_number: 1,
    is_pid: 1,
    is_port: 1,
    is_reference: 1,
    is_struct: 1,
    is_struct: 2,
    is_tuple: 1
  ]

  # Kernel's operators and functions a function may call, and the guard-safe part.
  @guard_safe [
                +: 1,
                +: 2,
                -: 1,
                -: 2,
                *: 2,
                /: 2,
                ==: 2,
                !=: 2,
                ===: 2,
                !==: 2,
                <: 2,
                >: 2,
                <=: 2,
                >=: 2,
                and: 2,
                or: 2,
                not: 1,
                in: 2,
                ..: 2,
                ..//: 3,
                div: 2,
                rem: 2,
                abs: 1,
                round: 1,
                trunc: 1,
                min: 2,
                max: 2
              ] ++ @is_guards

  @functions @guard_safe ++
               [
                 &&: 2,
                 ||: 2,
                 !: 1,
                 ..: 0,
                 <>: 2,
                 ++: 2,
                 --: 2,
                 |>: 2,
                 **: 2,
                 if: 2,
                 unless: 2,
                 # String interpolation's call (#769).
                 to_string: 1
               ]

  # The special forms, at `Kernel.SpecialForms`' own arities (a variadic form's is `1`).
  @special_forms [
    case: 2,
    cond: 1,
    with: 1,
    for: 1,
    fn: 1,
    =: 2,
    ^: 1,
    &: 1,
    __block__: 1,
    {}: 1,
    %{}: 1,
    <<>>: 1,
    "::": 2
  ]

  @doc "The modules a stored function may call, in order (spec/08 §10.5.2)."
  @spec modules() :: [module()]
  def modules, do: @modules

  @doc "A module's allowed `{function, arity}` list; `[]` for a module not on the list."
  @spec allowed(module()) :: [{atom(), arity()}]
  def allowed(module), do: Map.get(@allowed, module, [])

  @doc """
  A module's excluded `{{function, arity}, reason}` list, `reason` one of
  `:nondeterministic`, `:deprecated`, `:atoms` and `:internal`.
  """
  @spec excluded(module()) :: [{{atom(), arity()}, atom()}]
  def excluded(module), do: Map.get(@excluded, module, [])

  @doc """
  The `{function, arity}` of every `Kernel` function and operator, and every special form
  at `Kernel.SpecialForms`' arity, a stored function may use.
  """
  @spec kernel() :: [{atom(), arity()}]
  def kernel, do: @functions ++ @special_forms

  @doc false
  # Whether `module.function/arity` may be called; `Access.get/2` is `row[:key]`.
  def remote?(Access, :get, 2), do: true
  def remote?(Kernel, name, arity), do: {name, arity} in @functions
  def remote?(module, name, arity), do: {name, arity} in allowed(module)

  @doc false
  def local?(name, arity), do: {name, arity} in @functions

  @doc false
  def guard?(name, arity), do: {name, arity} in @guard_safe

  @doc false
  def module_name?(module), do: module in @modules or module in [Access, Kernel]
end
