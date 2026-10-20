defmodule Visualize.Chart.Names do
  @moduledoc false
  # A name a design declares is a string (spec/14 §1.4, D-195): a source, field, variable,
  # frame, scale, style, paint or Use key. Elixir input may spell one as an atom, which is
  # read as the string of the same spelling — `Atom.to_string/1`, which makes no atom — and
  # a category value is matched by spelling, so `:ok` and `"ok"` are one value.

  @not_names [nil, true, false]

  @doc false
  # A name in a guard: a string, or an atom Elixir input spells one with.
  defguard is_name(v) when is_binary(v) or (is_atom(v) and v not in [nil, true, false])

  @doc false
  # A name as the design holds it: an atom's spelling, a string as it is, anything else
  # (a library id `{kind, n}`, a malformed value the validator names) untouched.
  @spec name(term()) :: term()
  def name(name) when is_atom(name) and name not in @not_names, do: Atom.to_string(name)
  def name(name), do: name

  @doc false
  # Whether a value is a name: a non-empty string (an atom is one before `name/1` reads it).
  @spec name?(term()) :: boolean()
  def name?(name) when is_binary(name), do: name != ""
  def name?(name) when is_atom(name), do: name not in @not_names
  def name?(_name), do: false

  @doc false
  # A category value as it is compared (spec/14 §9.4): an atom other than a boolean or `nil`
  # by its spelling, anything else as it is.
  @spec category(term()) :: term()
  def category(value) when is_atom(value) and value not in @not_names, do: Atom.to_string(value)
  def category(value), do: value

  @doc false
  # Whether two category values are one: equal, or the same spelling.
  @spec same?(term(), term()) :: boolean()
  def same?(a, a), do: true
  def same?(a, b), do: category(a) == category(b)

  @doc false
  # A map's keys as names, values untouched.
  @spec keys(map()) :: map()
  def keys(map) when is_map(map) and not is_struct(map),
    do: Map.new(map, fn {k, v} -> {name(k), v} end)

  def keys(other), do: other

  @doc false
  # The key of `map` that spells `name` — the name itself, or the key of the other spelling —
  # or `:error`: how a design's name finds a host's entry, keyed as the host keyed it (a
  # source in the pool, a variable's value), without an atom made.
  @spec key(map(), term()) :: {:ok, term()} | :error
  def key(map, name) when is_map_key(map, name), do: {:ok, name}

  def key(map, name) when is_binary(name) or is_atom(name) do
    spelled = category(name)

    case Enum.find(Map.keys(map), &((is_atom(&1) and category(&1) == spelled) or &1 == spelled)) do
      nil -> :error
      found -> {:ok, found}
    end
  end

  def key(_map, _name), do: :error

  @doc false
  # `Map.fetch/2` by spelling.
  @spec fetch(map(), term()) :: {:ok, term()} | :error
  def fetch(map, name) do
    case key(map, name) do
      {:ok, found} -> Map.fetch(map, found)
      :error -> :error
    end
  end
end
