defmodule Visualize.Board.Names do
  @moduledoc false
  # A board's names as strings (spec/15 §2.2, spec/14 §9.4, D-195): its cells, its and its
  # cells' variables, its links, its virtual sources and a drill's variables and datum
  # fields. A board written in Elixir with atom names reads as the board its JSON is, by
  # each name's spelling — `Atom.to_string/1`, which makes no atom. A value is left as it
  # is: a variable's value is the board's to give, and a component's id is the store's.

  alias Visualize.Chart.Names
  alias Visualize.VirtualSource

  @doc false
  @spec named(term()) :: term()
  def named(board) when is_map(board) and not is_struct(board) do
    board
    |> update(:cells, &cells/1)
    |> update(:vars, &Names.keys/1)
    |> update(:links, &links/1)
    |> update(:virtual_sources, &virtual_sources/1)
  end

  def named(other), do: other

  defp cells(cells) when is_map(cells) and not is_struct(cells),
    do: Map.new(cells, fn {name, cell} -> {Names.name(name), cell(cell)} end)

  defp cells(other), do: other

  defp cell(cell) when is_map(cell) and not is_struct(cell) do
    cell
    |> update(:vars, &Names.keys/1)
    |> update(:drill, &drill/1)
    |> update(:virtual_sources, &virtual_sources/1)
  end

  defp cell(other), do: other

  defp drill(drill) when is_map(drill) and not is_struct(drill),
    do: update(drill, :vars, &drill_vars/1)

  defp drill(other), do: other

  defp drill_vars(vars) when is_map(vars) and not is_struct(vars) do
    Map.new(vars, fn
      {name, {:datum, field}} -> {Names.name(name), {:datum, Names.name(field)}}
      {name, value} -> {Names.name(name), value}
    end)
  end

  defp drill_vars(other), do: other

  # A virtual source held as a map is named as `Visualize.VirtualSource.new/1` names one.
  defp virtual_sources(sources) when is_map(sources) and not is_struct(sources),
    do: Map.new(sources, fn {id, source} -> {Names.name(id), VirtualSource.named(source)} end)

  defp virtual_sources(other), do: other

  defp links(links) when is_map(links) and not is_struct(links),
    do: Map.new(links, fn {from, to} -> {Names.name(from), Names.name(to)} end)

  defp links(other), do: other

  defp update(map, key, fun) do
    case map do
      %{^key => value} -> Map.put(map, key, fun.(value))
      %{} -> map
    end
  end
end
