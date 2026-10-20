defmodule Visualize.Chart.Words do
  @moduledoc false
  # The library's own words, and a value outside any schema read by them (spec/14 §9.4,
  # D-195). A category value — a variable's default, a datum anchor's position, a term — is
  # the library's atom when one of its vocabularies spells it (a schema key, an
  # enumeration's member, a mark type, a slot, a unit, a theme, a projection) and a string
  # otherwise, and a term's map key is a schema key's atom or a string. JSON and Elixir
  # input are read by the one rule — the codec from strings, `Migration.canonical/1` from
  # atoms — so a design is the same map whichever it was written in, and no atom is made.

  alias Visualize.Chart.{Fragment, Limits, Migration, Schema, Var}
  alias Visualize.{Theme, Vocabulary}

  # A composite's own keys stand beside the schema's (spec/14 §19.3).
  @key_names Schema.key_names() ++
               Migration.legacy_keys() ++ Fragment.wrapper_keys() ++ [:uses, :ref]
  @keys Vocabulary.table(@key_names)
  @words Vocabulary.table(
           Enum.uniq(
             # The tags of a term's tuples, which a literal the builder reads spells (§11.2).
             @key_names ++
               Schema.enum_members() ++
               Schema.mark_types() ++
               Schema.transform_ops() ++
               Schema.scale_kinds() ++
               Theme.library_color_names() ++
               Theme.ramp_names() ++
               Theme.builtins() ++
               Visualize.Theme.Palette.fixed_names() ++
               Fragment.kinds() ++
               Visualize.Data.Schema.attributes() ++
               Visualize.Data.Schema.words() ++
               Visualize.Units.units() ++
               Visualize.Geo.Projection.types() ++
               Visualize.Chart.Transform.Data.units() ++
               [:auto, :none, :contrast, :cue, :under, :min, :max, :self] ++
               [:field, :scale, :axis, :frame, :data, :color, :ramp, :series, :paint, :generate] ++
               [:keys, :blend, :identity, :feed, :use, :datum, :window] ++
               Visualize.Color.Typed.ops()
           )
         )
  @series_slot ~r/^series_[1-9]\d*$/
  @style_series ~r/^style_[1-9]\d*$/
  # A series slot is a word up to the default `items` bound: a theme holds no more series
  # than a list holds entries, so `series_1` … `series_100000` is the whole set (class (d)).
  @series_bound Limits.defaults().items

  @doc false
  # The schema keys a document's keys are read in: every node kind's, an earlier version's
  # and a fragment's wrappers.
  @spec keys() :: Vocabulary.table()
  def keys, do: @keys

  @doc false
  # A word read from a string: the library's atom of that spelling, or the string.
  @spec word(String.t()) :: atom() | String.t()
  def word(string) when is_binary(string) do
    case Vocabulary.fetch(@words, string) do
      {:ok, atom} -> atom
      :error -> series_slot(string)
    end
  end

  @doc false
  # A series slot `series_k` within the bound as its atom, any other string as it is.
  @spec series_slot(String.t()) :: atom() | String.t()
  def series_slot("series_" <> digits = string) do
    with true <- Regex.match?(@series_slot, string),
         {k, ""} when k <= @series_bound <- Integer.parse(digits) do
      Theme.series_atom(k)
    else
      _other -> string
    end
  end

  # A palette's style series `style_k`, bounded as a series slot is.
  def series_slot("style_" <> digits = string) do
    with true <- Regex.match?(@style_series, string),
         {k, ""} when k <= @series_bound <- Integer.parse(digits) do
      Visualize.Theme.Palette.series_name(k)
    else
      _other -> string
    end
  end

  def series_slot(string), do: string

  @doc false
  # A term's map key read from a string: a schema key's atom, or the string.
  @spec key(String.t()) :: atom() | String.t()
  def key(string) when is_binary(string), do: Vocabulary.read(@keys, string)

  @doc false
  # A term from Elixir input read by the same rule: an atom the library has no word for is
  # its string, a map's key a schema key or a string; a variable's name is its string.
  @spec term(term()) :: term()
  def term(%Var{name: name} = var) when is_atom(name) and name not in [nil, true, false],
    do: %{var | name: Atom.to_string(name)}

  def term(%_{} = struct), do: struct

  def term(atom) when is_atom(atom) and atom not in [nil, true, false],
    do: atom |> Atom.to_string() |> word()

  def term(list) when is_list(list), do: Enum.map(list, &term/1)

  def term(map) when is_map(map),
    do: Map.new(map, fn {k, v} -> {term_key(k), term(v)} end)

  def term(other), do: other

  defp term_key(k) when is_atom(k) and k not in [nil, true, false],
    do: k |> Atom.to_string() |> key()

  defp term_key(k), do: k
end
