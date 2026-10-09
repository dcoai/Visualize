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

  @doc """
  The JavaScript expression that builds `svg`, markup a backend rendered, as the stub's
  element tree: one `Stub.markup(tag, attributes, children)` per element, in document
  order (#508). A scenario then runs a hook over the chart as rendered rather than over a
  hand-written imitation of it. Text content, comments and declarations are dropped —
  no hook reads them — and a closing tag that does not close the open element raises.
  """
  @spec markup(String.t()) :: String.t()
  def markup(svg) do
    ~r/<!--.*?-->|<[^>]+>|[^<]+/s
    |> Regex.scan(svg)
    |> List.flatten()
    |> Enum.reduce([{:root, %{}, []}], &token/2)
    |> case do
      [{:root, _, [root]}] ->
        expression(root)

      stack ->
        raise ArgumentError, "unbalanced markup, open: #{inspect(Enum.map(stack, &elem(&1, 0)))}"
    end
  end

  defp token("<!" <> _, stack), do: stack
  defp token("<?" <> _, stack), do: stack

  defp token("</" <> rest, [{tag, attrs, children}, {parent, pattrs, siblings} | stack]) do
    closing = rest |> String.trim_trailing(">") |> String.trim()

    closing == tag ||
      raise ArgumentError, "markup closes </#{closing}> while <#{tag}> is open"

    [{parent, pattrs, [{tag, attrs, Enum.reverse(children)} | siblings]} | stack]
  end

  defp token("<" <> rest, [{parent, pattrs, siblings} | stack] = all) do
    [tag | _] = String.split(rest, ~r/[\s\/>]/, parts: 2)

    attrs =
      for [_, name, value] <- Regex.scan(~r/([^\s=\/<>]+)="([^"]*)"/, rest),
          into: %{},
          do: {name, unescape(value)}

    if String.ends_with?(rest, "/>"),
      do: [{parent, pattrs, [{tag, attrs, []} | siblings]} | stack],
      else: [{tag, attrs, []} | all]
  end

  defp token(_text, stack), do: stack

  defp expression({tag, attrs, children}) do
    "Stub.markup(#{Jason.encode!(tag)}, #{Jason.encode!(attrs)}, [" <>
      Enum.map_join(children, ", ", &expression/1) <> "])"
  end

  defp unescape(value) do
    value
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&amp;", "&")
  end

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
