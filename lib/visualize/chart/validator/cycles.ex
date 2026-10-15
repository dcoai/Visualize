defmodule Visualize.Chart.Validator.Cycles do
  @moduledoc false
  # Cycles through style derivation (spec/14 §3.5): `extends`, a list of names, a name.

  alias Visualize.Chart.Validator.Types

  @doc false
  # A style that reaches itself — through `extends`, a name or a list (spec/14 §3.5, §3.6,
  # #658) — is `:cycle` at its own path; a style that merely reaches one that is on a cycle
  # is not at fault and is not reported.
  @spec cycles(map()) :: [{list(), :cycle}]
  def cycles(map) do
    case map[:styles] do
      styles when is_map(styles) and not is_struct(styles) ->
        for {name, _node} <- styles,
            Types.name?(name),
            reaches?(styles, refs(Map.get(styles, name)), name, []),
            do: {[:styles, name], :cycle}

      _other ->
        []
    end
  end

  defp reaches?(styles, names, target, seen) do
    Enum.any?(names, fn
      ^target ->
        true

      name ->
        name not in seen and reaches?(styles, refs(Map.get(styles, name)), target, [name | seen])
    end)
  end

  # The style names an entry refers to: itself as a name, a list's entries, an `extends`.
  defp refs(entries) when is_list(entries), do: Enum.flat_map(entries, &refs/1)
  defp refs(%{extends: parent} = node) when not is_struct(node), do: refs(parent)
  defp refs(name) when is_atom(name), do: if(Types.name?(name), do: [name], else: [])
  defp refs(_entry), do: []
end
