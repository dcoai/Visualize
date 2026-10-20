defmodule Visualize.Theme.Names do
  @moduledoc false
  # A theme's names as a document reads them (spec/08 §7.1, spec/14 §9.4, D-195): its own
  # name and its counterparts are a built-in theme's atom or the string of the host's, and a
  # color it adds is the string of its name, the library's own names staying atoms — so a
  # theme built in Elixir and the theme its document reads are one value. `Atom.to_string/1`
  # makes no atom.

  alias Visualize.Chart.Migration.Named
  alias Visualize.Theme

  @library_names Map.new(Theme.library_color_names(), &{&1, true})

  @doc false
  # The fields given to `Visualize.Theme.new/1` or `merge/2` with their theme names read.
  @spec fields(map()) :: map()
  def fields(fields) do
    Enum.reduce([:name, :dark, :light], fields, fn key, fields ->
      case fields do
        %{^key => name} -> %{fields | key => theme_name(name)}
        %{} -> fields
      end
    end)
  end

  @doc false
  # The colors a theme adds, keyed by their names as a document reads them, each value a
  # color whose names are read the same way.
  @spec colors(term()) :: term()
  def colors(colors) when is_map(colors) or is_list(colors) do
    Map.new(colors, fn {name, value} -> {own_name(name), Named.value(:color, value)} end)
  end

  def colors(other), do: other

  defp theme_name(name) when is_atom(name) and name not in [nil, true, false],
    do: if(name in Theme.builtins(), do: name, else: Atom.to_string(name))

  defp theme_name(name), do: name

  defp own_name(name) when is_atom(name) and name not in [nil, true, false],
    do: if(Map.has_key?(@library_names, name), do: name, else: Atom.to_string(name))

  defp own_name(name), do: name
end
