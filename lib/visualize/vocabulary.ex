defmodule Visualize.Vocabulary do
  @moduledoc false
  # A closed vocabulary read from a string (spec/14 §9.4, D-195): a table from each member's
  # spelling to the member, built from the vocabulary's own list. A reader looks a document's
  # string up in it and never makes an atom of one — nor asks the node whether an atom exists
  # (`String.to_existing_atom/1`), which would let a document probe the atom table and make a
  # read depend on which modules are loaded. A string the table lacks is the caller's to
  # refuse at its path.
  #
  # Build a table once, in a module attribute, wherever the list is known at compile time:
  #
  #     @anchors Vocabulary.table([:title, :subtitle, :caption])
  #     Vocabulary.fetch(@anchors, "title")   #=> {:ok, :title}
  #     Vocabulary.fetch(@anchors, "footer")  #=> :error

  @typedoc "A vocabulary's members by their spelling."
  @type table :: %{String.t() => atom()}

  @doc false
  @spec table([atom()]) :: table()
  def table(members) when is_list(members), do: Map.new(members, &{Atom.to_string(&1), &1})

  @doc false
  # The member a string spells, from a table or — for a list known only at run time, a few
  # members long — from the list itself.
  @spec fetch(table() | [atom()], term()) :: {:ok, atom()} | :error
  def fetch(table, string) when is_map(table) and is_binary(string), do: Map.fetch(table, string)

  def fetch(members, string) when is_list(members) and is_binary(string) do
    case Enum.find(members, &(Atom.to_string(&1) == string)) do
      nil -> :error
      member -> {:ok, member}
    end
  end

  def fetch(_vocabulary, _other), do: :error

  @doc false
  # The member a string spells, or the string itself — the reader's "stays the string it
  # was" for a value the validator refuses by type.
  @spec read(table() | [atom()], String.t()) :: atom() | String.t()
  def read(vocabulary, string) when is_binary(string) do
    case fetch(vocabulary, string) do
      {:ok, member} -> member
      :error -> string
    end
  end
end
