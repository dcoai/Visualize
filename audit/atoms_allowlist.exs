# The sites in lib/ allowed to make an atom from a string (spec/12 §3, D-195), read by
# `mix vis.atoms`. Each entry is one file, a fragment of the lines it allows, how many lines
# of the file hold that fragment, the site's class and why:
#
#   (a)      a closed library vocabulary — the bound is the vocabulary's size
#   (a-host) a vocabulary host code registers — the bound is the host's registry
#   (d)      bounded by the library — the bound is stated
#
# A name a document or a client declares (b), or one derived from such names (c), is a
# string (D-195) and has no entry here: the task refuses one. An entry that matches no
# line, or a different number of lines, fails the task too.
[
  # -- the builder ------------------------------------------------------------------------
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
  },
  %{
    file: "lib/visualize/virtual_source/sandbox/names.ex",
    match: ~S|:"sandbox_v#{n}"|,
    count: 1,
    class: :d,
    reason: "the stored functions' variable pool, 256 names made when the library compiles"
  },
  %{
    file: "lib/visualize/virtual_source/sandbox/names.ex",
    match: ~S|:"_sandbox_v#{n}"|,
    count: 1,
    class: :d,
    reason: "the pool of the variables a stored function marks unused, 256, at compile time"
  }
]
