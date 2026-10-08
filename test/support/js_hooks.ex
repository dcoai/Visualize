defmodule Visualize.JsHooks do
  @moduledoc """
  Runs the hook bundle under node against a recording DOM stub (spec/12 §6, #458).

  `run/1` writes one ES module — `test/support/js/dom_stub.js`, then
  `Visualize.Hooks.js_code/0`, then the scenario — to a temporary `.mjs` file and runs
  `node` on it. The stub records every 2D-context call, every property and canvas size
  assignment and every `pushEvent`; the scenario ends with `Stub.done(report)`, which
  prints them as one JSON line, and `run/1` returns it decoded:
  `%{"log" => [entry], "report" => map}`.

  A scenario that throws, or never calls `Stub.done/1`, is `{:error, output}` with
  everything node printed, so a failing assertion shows the JavaScript stack.
  """

  @stub Path.expand("js/dom_stub.js", __DIR__)
  @external_resource @stub
  @marker "VIS-HOOKS-LOG "

  @doc "The `node` executable on the path, or nil."
  @spec node_path() :: String.t() | nil
  def node_path, do: System.find_executable("node")

  @doc "Runs `scenario` after the stub and the bundle; the decoded log, or node's output."
  @spec run(String.t()) :: {:ok, map()} | {:error, String.t()}
  def run(scenario) do
    node = node_path() || raise "the :js tests need node on the path (spec/12 §6)"
    dir = Path.join(System.tmp_dir!(), "vis-hooks-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    file = Path.join(dir, "scenario.mjs")
    File.write!(file, [File.read!(@stub), Visualize.Hooks.js_code(), "\n", scenario, "\n"])
    {output, status} = System.cmd(node, [file], stderr_to_stdout: true)
    File.rm_rf!(dir)
    decode(output, status)
  end

  defp decode(output, 0) do
    case output |> String.split("\n") |> Enum.find(&String.starts_with?(&1, @marker)) do
      nil -> {:error, output}
      line -> {:ok, line |> String.replace_prefix(@marker, "") |> Jason.decode!()}
    end
  end

  defp decode(output, _status), do: {:error, output}

  @doc "The entries of `log` after the mark named `label` and before the next mark."
  @spec after_mark([map()], String.t()) :: [map()]
  def after_mark(log, label) do
    log
    |> Enum.drop_while(&(&1 != %{"on" => "scenario", "kind" => "mark", "name" => label}))
    |> Enum.drop(1)
    |> Enum.take_while(&(&1["kind"] != "mark"))
  end

  @doc "The names of the calls in `entries` made on the context of canvas `on`."
  @spec calls([map()], String.t()) :: [String.t()]
  def calls(entries, on) do
    for %{"on" => ^on, "kind" => "call", "name" => name} <- entries, do: name
  end
end
