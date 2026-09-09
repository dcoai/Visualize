defmodule Mix.Tasks.DocsGroupsTest do
  @moduledoc """
  Every `groups_for_modules` and `groups_for_extras` pattern in `mix.exs` matches
  something.

  ExDoc drops a module no group matches into the ungrouped default section and says
  nothing; `mix docs --warnings-as-errors` fails on a broken reference, never on an empty
  group. So a mistyped pattern — `~r"Visualize\\\\.Chart"`, whose doubled backslash inside a
  `~r` sigil compiles to a literal backslash and matches no module name (#107) — silently
  unfiles a whole layer of the documentation. This is the check that makes that a gate
  failure instead.

  The matching mirrors `ExDoc.Config.match_module/4` and `match_extra/2`: a regex against
  the module id or the extra's path, a string compared to it, an atom compared to the
  module. Each *entry* is asserted, not each group, so a stale module name inside a group's
  list is caught as well as an empty group.
  """
  use ExUnit.Case, async: true

  # `mix docs` runs in `MIX_ENV=dev`, where `elixirc_paths` is `lib`, `audit` and `specs`.
  # The test build adds `test/support`, whose modules ExDoc never sees: counting them would
  # let a support module keep an emptied group looking full.
  @docs_paths ~w(lib audit specs)

  defp documented_modules do
    {:ok, modules} = :application.get_key(:visualize, :modules)
    Enum.filter(modules, &compiled_from_docs_path?/1)
  end

  defp compiled_from_docs_path?(module) do
    with true <- Code.ensure_loaded?(module),
         source when is_list(source) <- module.module_info(:compile)[:source] do
      relative = Path.relative_to(List.to_string(source), File.cwd!())
      Enum.any?(@docs_paths, &String.starts_with?(relative, &1 <> "/"))
    else
      _ -> false
    end
  end

  defp extra_paths do
    Enum.map(Mix.Project.config()[:docs][:extras], fn
      {path, _options} -> to_string(path)
      path -> to_string(path)
    end)
  end

  defp matches_module?(%Regex{} = pattern, module), do: Regex.match?(pattern, inspect(module))
  defp matches_module?(pattern, module) when is_binary(pattern), do: inspect(module) == pattern
  defp matches_module?(pattern, module) when is_atom(pattern), do: pattern == module

  defp matches_extra?(%Regex{} = pattern, path), do: Regex.match?(pattern, path)
  defp matches_extra?(pattern, path) when is_binary(pattern), do: path == pattern

  test "the module list the docs build would see is not empty" do
    # Everything below is vacuously true over an empty list, so the filter is asserted
    # first rather than trusted.
    assert length(documented_modules()) > 100
  end

  test "every groups_for_modules entry matches a module" do
    modules = documented_modules()

    for {group, patterns} <- Mix.Project.config()[:docs][:groups_for_modules],
        pattern <- List.wrap(patterns) do
      assert Enum.any?(modules, &matches_module?(pattern, &1)),
             """
             The docs group #{inspect(group)} has an entry that matches no module: \
             #{inspect(pattern)}.

             ExDoc would file its modules under the ungrouped default section without a \
             warning. Inside a `~r` sigil a literal dot is `\\.`, not `\\\\.` — the doubled \
             form compiles to a literal backslash and can never match (#107).
             """
    end
  end

  test "every groups_for_extras entry matches an extra" do
    paths = extra_paths()

    for {group, patterns} <- Mix.Project.config()[:docs][:groups_for_extras],
        pattern <- List.wrap(patterns) do
      assert Enum.any?(paths, &matches_extra?(pattern, &1)),
             "The extras group #{inspect(group)} has an entry that matches no extra: " <>
               "#{inspect(pattern)}."
    end
  end

  test "the Declarative chart group matches the layer it names" do
    # The regression #107 records, stated over the surface rather than over the pattern:
    # `Visualize.Chart` and its submodules are the largest part of the public surface, and
    # they were all ungrouped.
    modules = documented_modules()

    {_, patterns} =
      List.keyfind(Mix.Project.config()[:docs][:groups_for_modules], :"Declarative chart", 0)

    chart_modules =
      Enum.filter(modules, fn module ->
        Enum.any?(List.wrap(patterns), &matches_module?(&1, module))
      end)

    assert Visualize.Chart in chart_modules
    assert Visualize.Chart.Build in chart_modules
    assert length(chart_modules) > 20
  end
end
