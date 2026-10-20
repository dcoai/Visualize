defmodule Visualize.Audit.Advisories do
  @moduledoc """
  No dependency carries an advisory (spec/12 §3, #782, D-207).

  Runs Hex's own `mix hex.audit` in the root project and in `examples/`, one OS process
  each, so both `mix.lock` files are held to the security advisories and retirements Hex
  publishes with its registry. A project fails when its audit exits non-zero.

  What a project accepts is the allowlist `audit/advisories_allowlist.exs`. Each entry
  names its project (`:library` or `:examples`), exactly one of `advisory:` (an id, primary
  or alias, as `mix hex.audit` matches it) and `retired:` (`"name"` or `"name@version"`),
  and its reason. A project is handed only its own entries, through `HEX_IGNORE_ADVISORIES`
  and `HEX_IGNORE_RETIREMENTS`, which are always set so the caller's environment allows
  nothing. Once a project's audit is green each of its entries is dropped in turn and the
  audit run again: an entry whose absence leaves it green is stale, and fails too.
  """

  @allowlist "audit/advisories_allowlist.exs"
  @projects [library: ".", examples: "examples"]

  @typedoc "Runs `mix hex.audit` in a directory with the given ignores; returns its exit."
  @type runner :: (dir :: Path.t(), ignores :: ignores(), quiet? :: boolean() ->
                     non_neg_integer())
  @type ignores :: %{advisories: [String.t()], retirements: [String.t()]}

  @doc "Every problem under `root`, one line each; `[]` when there is none."
  @spec run(Path.t()) :: [String.t()]
  def run(root) do
    {entries, _binding} = root |> Path.join(@allowlist) |> Code.eval_file()
    run(root, entries, &hex_audit/3)
  end

  @doc false
  # The check against a given allowlist and runner, for the task's own test.
  @spec run(Path.t(), [map()], runner()) :: [String.t()]
  def run(root, entries, runner) do
    case Enum.flat_map(entries, &malformed/1) do
      [] -> Enum.flat_map(@projects, &project(root, &1, entries, runner))
      problems -> problems
    end
  end

  defp project(root, {name, dir}, entries, runner) do
    own = Enum.filter(entries, &(&1.project == name))
    path = Path.expand(dir, root)

    case runner.(path, ignores(own), false) do
      0 ->
        for entry <- own, runner.(path, ignores(own -- [entry]), true) == 0 do
          "#{@allowlist}: #{label(entry)} for #{name} is stale: " <>
            "#{dir}/mix.lock passes mix hex.audit without it"
        end

      status ->
        [
          "#{name} (#{dir}/mix.lock): mix hex.audit exited #{status}; update the lock, " <>
            "or allow the finding with a reason in #{@allowlist}"
        ]
    end
  end

  defp ignores(entries) do
    %{
      advisories: for(%{advisory: id} <- entries, do: id),
      retirements: for(%{retired: package} <- entries, do: package)
    }
  end

  defp malformed(%{project: project, reason: reason} = entry)
       when is_binary(reason) and reason != "" do
    cond do
      not Keyword.has_key?(@projects, project) ->
        ["#{@allowlist}: unknown project #{inspect(project)} in #{inspect(entry)}"]

      not one_finding?(entry) ->
        ["#{@allowlist}: an entry names exactly one advisory: or retired:; got #{inspect(entry)}"]

      true ->
        []
    end
  end

  defp malformed(entry),
    do: ["#{@allowlist}: an entry needs a project, a finding and a reason; got #{inspect(entry)}"]

  defp one_finding?(%{advisory: id} = entry) when is_binary(id) and id != "",
    do: not Map.has_key?(entry, :retired)

  defp one_finding?(%{retired: package} = entry) when is_binary(package) and package != "",
    do: not Map.has_key?(entry, :advisory)

  defp one_finding?(_entry), do: false

  defp label(%{advisory: id}), do: "advisory #{id}"
  defp label(%{retired: package}), do: "retirement #{package}"

  # `mix hex.audit` in its own process: it reads the project in `dir`, which must have its
  # dependencies fetched. A probe of an entry runs quietly; the audit of record prints.
  defp hex_audit(dir, ignores, quiet?) do
    env = [
      {"HEX_IGNORE_ADVISORIES", Enum.join(ignores.advisories, ",")},
      {"HEX_IGNORE_RETIREMENTS", Enum.join(ignores.retirements, ",")}
    ]

    into = if quiet?, do: "", else: IO.stream(:stdio, :line)

    {_, status} =
      System.cmd("mix", ["hex.audit"], cd: dir, env: env, into: into, stderr_to_stdout: true)

    status
  end
end
