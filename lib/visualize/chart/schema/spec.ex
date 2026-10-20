defmodule Visualize.Chart.Schema.Spec do
  @moduledoc false
  # The key spec builder the schema's tables are written with (spec/14 §14.2): shared by
  # `Schema.Design`, `Schema.Frame` and `Schema.Mark`, which `Visualize.Chart.Schema` reads at
  # compile time, so none of them may depend on `Visualize.Chart.Schema` itself (D-184).

  @doc false
  def spec(key, type, facet, opts \\ []) do
    %{
      key: key,
      type: type,
      facet: facet,
      default: Keyword.get(opts, :default),
      required: Keyword.get(opts, :required, false),
      merge: Keyword.get(opts, :merge, :override),
      range: Keyword.get(opts, :range)
    }
  end

  @doc false
  # The type a style site takes; `Visualize.Chart.Schema.style_stack/0` documents it.
  def style_stack do
    entry = [{:ref, :style}, {:node, :style}, :generator, :field_ref]
    {:one_of, entry ++ [{:list, {:one_of, entry}}]}
  end

  @doc false
  # The type a named style takes; `Visualize.Chart.Schema.style_entry/0` documents it.
  def style_entry do
    entry = [{:node, :style}, {:ref, :style}]
    {:one_of, entry ++ [{:list, {:one_of, Enum.reverse(entry)}}]}
  end

  @doc false
  # The members of every enumeration inside a type.
  def enum_members({:enum, members}), do: members
  def enum_members({:list, t}), do: enum_members(t)
  def enum_members({:map, t}), do: enum_members(t)
  def enum_members({:one_of, types}), do: Enum.flat_map(types, &enum_members/1)
  def enum_members(_type), do: []
end
