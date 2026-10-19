# The sites in lib/ allowed to make an atom from a string (spec/12 §3, D-195), read by
# `mix vis.atoms`. Each entry is one file, a fragment of the lines it allows, how many lines
# of the file hold that fragment, the site's class and why:
#
#   (a)      a closed library vocabulary — the bound is the vocabulary's size
#   (a-host) a vocabulary host code registers — the bound is the host's registry
#   (b)      a name a document or a client declares
#   (c)      a name derived from names a document declares
#   (d)      bounded by the library — the bound is stated
#
# Every (b) and (c) entry is pending #778's representation work items (names a document
# declares become strings); the last of them leaves only (a), (a-host) and (d) here. An
# entry that matches no line, or a different number of lines, fails the task.
[
  # -- codecs ------------------------------------------------------------------------------
  %{
    file: "lib/visualize/chart/codec.ex",
    match: "defp atom(k) when is_binary(k)",
    count: 1,
    class: :b,
    reason: "pending #778 representation: a name-keyed map's key and a term's keys"
  },
  %{
    file: "lib/visualize/chart/codec.ex",
    match: "%Var{name: String.to_atom(name)}",
    count: 2,
    class: :b,
    reason: "pending #778 representation: a variable's name ($var)"
  },
  %{
    file: "lib/visualize/chart/codec.ex",
    match: "{:field, String.to_atom(f)}",
    count: 2,
    class: :b,
    reason: "pending #778 representation: a field's name ($field)"
  },
  %{
    file: "lib/visualize/chart/codec.ex",
    match: "{:generate, String.to_atom(name)",
    count: 1,
    class: :"a-host",
    reason:
      "pending #778 representation: a generator's name, plain words only (#645), " <>
        "to be looked up in the host's registry"
  },
  %{
    file: "lib/visualize/chart/codec.ex",
    match: "{:paint, String.to_atom(name)}",
    count: 1,
    class: :b,
    reason: "pending #778 representation: a paint's name ($paint)"
  },
  %{
    file: "lib/visualize/chart/codec.ex",
    match: "read(:counterpart, name) when is_binary(name), do: String.to_atom(name)",
    count: 1,
    class: :"a-host",
    reason:
      "pending #778 representation: a theme's counterpart — a built-in or a host-stored theme"
  },
  %{
    file: "lib/visualize/chart/codec.ex",
    match: "{:color, String.to_atom(name)}",
    count: 1,
    class: :b,
    reason:
      "pending #778 representation: a color's name, plain words only (#664) — a theme's own colors"
  },
  %{
    file: "lib/visualize/chart/codec.ex",
    match: "do: String.to_atom(v)",
    count: 2,
    class: :b,
    reason:
      "pending #778 representation: a :name, :field or :channel value, and a reference to a declared name"
  },
  %{
    file: "lib/visualize/chart/codec.ex",
    match: "{:frame, String.to_atom(f), String.to_atom(s)}",
    count: 1,
    class: :b,
    reason: "pending #778 representation: an adopted scale's frame and scale ($adopted)"
  },
  %{
    file: "lib/visualize/chart/codec.ex",
    match: "{:axis, String.to_atom(s)}",
    count: 1,
    class: :b,
    reason: "pending #778 representation: an anchor's scale ($axis)"
  },
  %{
    file: "lib/visualize/chart/codec.ex",
    match: "%Fact{source: String.to_atom(s), field: String.to_atom(f)",
    count: 1,
    class: :b,
    reason:
      "pending #778 representation: a fact's slot and field ($fact; its attribute is looked up)"
  },
  %{
    file: "lib/visualize/chart/codec.ex",
    match: "do: String.to_atom(a)",
    count: 1,
    class: :b,
    reason: "pending #778 representation: a category value ($atom), a string by spelling after"
  },
  %{
    file: "lib/visualize/chart/codec.ex",
    match: "defp read_key(key) when is_binary(key), do: String.to_atom(key)",
    count: 1,
    class: :b,
    reason: "pending #778 representation: a use site's key"
  },
  %{
    file: "lib/visualize/board/codec.ex",
    match: "{:datum, String.to_atom(field)}",
    count: 1,
    class: :b,
    reason: "pending #778 representation: a drill variable's datum field ($datum)"
  },
  %{
    file: "lib/visualize/board/codec.ex",
    match: "defp atom(key) when is_binary(key)",
    count: 1,
    class: :b,
    reason: "pending #778 representation: a cell's, variable's, link's or virtual source's name"
  },
  %{
    file: "lib/visualize/board/snapshot/codec.ex",
    match: "defp atom(key) when is_binary(key)",
    count: 1,
    class: :b,
    reason: "pending #778 representation: a cell's, variable's or slot's name"
  },
  %{
    file: "lib/visualize/virtual_source/codec.ex",
    match: "{:function, String.to_atom(value)}",
    count: 1,
    class: :"a-host",
    reason:
      "pending #778 representation: a defsource function's name, to be looked up in the registry"
  },
  %{
    file: "lib/visualize/virtual_source/join.ex",
    match: ~S|String.to_atom("#{source.id}.#{field}")|,
    count: 1,
    class: :c,
    reason: "pending #778 representation: a joined field, source id × field"
  },
  %{
    file: "lib/visualize/chart/text.ex",
    match: "wrap.(String.to_atom(word))",
    count: 1,
    class: :b,
    reason: "pending #778 representation: a text hole's name (var, field, fact)"
  },

  # -- derived names -----------------------------------------------------------------------
  %{
    file: "lib/visualize/chart/composite.ex",
    match: ~S|:"#{key}_#{name}"|,
    count: 1,
    class: :c,
    reason: "pending #778 representation: a use site's frame, key × frame name"
  },
  %{
    file: "lib/visualize/chart/composite.ex",
    match: ~S|:"#{key}_#{id}"|,
    count: 1,
    class: :c,
    reason: "pending #778 representation: a use site's mark id, key × id"
  },

  # -- the builder (event params any client of the LiveView sends) -------------------------
  %{
    file: "lib/visualize/chart/builder/events/data.ex",
    match: "String.to_atom(",
    count: 12,
    class: :b,
    reason: "pending #778 representation: source and column names from event params"
  },
  %{
    file: "lib/visualize/chart/builder/events/data.ex",
    match: ~S|:"source_#{&1}"|,
    count: 1,
    class: :d,
    reason: "a fresh source's name source_<n>; n is at most the sources one design holds (items)"
  },
  %{
    file: "lib/visualize/chart/builder/events/form.ex",
    match: "String.to_atom(scale)",
    count: 2,
    class: :b,
    reason: "pending #778 representation: a scale's name from event params"
  },
  %{
    file: "lib/visualize/chart/builder/events/form.ex",
    match: "Enum.map(&String.to_atom/1)",
    count: 1,
    class: :b,
    reason: "pending #778 representation: ticked columns from event params"
  },
  %{
    file: "lib/visualize/chart/builder/events/variables.ex",
    match: ~S[Enum.map_join("_", &to_string/1) |> String.to_atom()],
    count: 1,
    class: :d,
    reason: "a variable named for a schema key path; bounded by the schema's paths"
  },
  %{
    file: "lib/visualize/chart/builder/events/variables.ex",
    match: ~S|:"#{key}_#{n}"|,
    count: 1,
    class: :c,
    reason: "pending #778 representation: a fresh variable name <key>_<n>"
  },
  %{
    file: "lib/visualize/chart/builder/editor.ex",
    match: "String.to_atom(",
    count: 4,
    class: :b,
    reason: "pending #778 representation: names, fields, slots and channels the person types"
  },
  %{
    file: "lib/visualize/chart/builder/themes.ex",
    match: "String.to_atom(name)",
    count: 1,
    class: :b,
    reason: "pending #778 representation: a theme's name the person types"
  },
  %{
    file: "lib/visualize/chart/builder/stack.ex",
    match: ~S|:"#{name}_#{&1}"|,
    count: 1,
    class: :c,
    reason: "pending #778 representation: a fresh name <name>_<k>"
  },
  %{
    file: "lib/visualize/chart/builder/boards.ex",
    match: ~S|String.to_atom("cell_#{n}")|,
    count: 1,
    class: :d,
    reason: "a fresh cell's name cell_<n>; n is at most the cells one board holds (items)"
  },
  %{
    file: "lib/visualize/chart/builder/place.ex",
    match: ~S|String.to_atom("frame_#{&1}")|,
    count: 1,
    class: :d,
    reason: "a fresh frame's name frame_<n>; n is at most the frames one design holds (items)"
  },
  %{
    file: "lib/visualize/chart/builder/place.ex",
    match: ~S|:"mark:#{type}"|,
    count: 1,
    class: :a,
    reason: "one per mark type of the schema (spec/14 §5.2)"
  },
  %{
    file: "lib/visualize/chart/builder/picker.ex",
    match: ~S|:"series_#{&1}"|,
    count: 1,
    class: :d,
    reason: "a theme's series slots series_<k>; k is at most the theme's series (items)"
  },
  %{
    file: "lib/visualize/chart/builder/picker.ex",
    match: "Enum.map(Visualize.Color.named_colors(), &String.to_atom/1)",
    count: 1,
    class: :a,
    reason: "the CSS named colors, a fixed list of about 148"
  },

  # -- bounded by the library --------------------------------------------------------------
  %{
    file: "lib/visualize/theme.ex",
    match: "@css_names Enum.map(Color.named_colors(), &String.to_atom/1)",
    count: 1,
    class: :a,
    reason: "the CSS named colors, at compile time"
  },
  %{
    file: "lib/visualize/theme.ex",
    match: ~S|:"series_#{k}"|,
    count: 1,
    class: :d,
    reason:
      "series slots series_<k>; k ≤ a theme's series ≤ items, and the codec reads k ≤ 100_000"
  },
  %{
    file: "lib/visualize/theme/palette.ex",
    match: ~S|:"style_#{k}"|,
    count: 2,
    class: :d,
    reason: "style series names style_<k>; k ≤ a palette's series ≤ items"
  },
  %{
    file: "lib/visualize/chart/refs.ex",
    match: ~S|:"#{kind}:#{n}"|,
    count: 1,
    class: :d,
    reason:
      "a store id's key <kind>:<n>; only ids that resolve to a stored body (the store's entries)"
  },
  %{
    file: "lib/visualize/chart/frame/scales.ex",
    match: ~S|:"#{family}_offset"|,
    count: 1,
    class: :a,
    reason: "x_offset and y_offset: the family is a channel family of the library"
  },
  %{
    file: "lib/visualize/chart/style/parts.ex",
    match: ~S|:"#{prefix}opacity"|,
    count: 1,
    class: :a,
    reason: "fill_opacity and stroke_opacity: the prefix is the library's"
  },
  %{
    file: "lib/visualize/chart/build/generate.ex",
    match: ~S|:"#{kind}_scale"|,
    count: 1,
    class: :a,
    reason: "<kind>_scale for a scale kind the validator has held to the schema's enum"
  }
]
