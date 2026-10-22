defmodule Visualize.HooksTest do
  @moduledoc "D-48: the generated hook module exports each name exactly once."
  use ExUnit.Case, async: true

  alias Visualize.Hooks

  @hooks ~w(ZoomHook BrushHook CanvasChart CanvasBinaryChart CanvasIncrementalChart ResizeHook TooltipHook CrosshairHook LegendHook BuilderHook KeyboardHook BoardHook MotionHook)

  test "every export name appears once, so a bundler accepts the file" do
    names =
      ~r/^\s*export\s+(?:const|function|let|class)\s+(\w+)/m
      |> Regex.scan(Hooks.js_code())
      |> Enum.map(fn [_, name] -> name end)

    assert names == Enum.uniq(names)
    assert Enum.all?(@hooks, &(&1 in names))
    assert length(Regex.scan(~r/^\s*export\s+default\b/m, Hooks.js_code())) == 1
    refute Hooks.js_code() =~ ~r/^\s*export\s*\{/m
  end

  test "the default export lists every hook" do
    [[_, body]] = Regex.scan(~r/export default \{([^}]*)\}/, Hooks.js_code())
    assert body |> String.split(~r/[\s,]+/, trim: true) |> Enum.sort() == Enum.sort(@hooks)
  end

  describe "no object of the bundle defines a key twice (spec/10 §4.1, #923)" do
    # In an object literal the later of two same-named keys silently replaces the earlier,
    # and no engine says so: BuilderHook's frame-box `dragged` shadowed its library drop's,
    # and every library drop threw. Every object the bundle declares at its top level is
    # read member by member, at the indentation of its first member; a member line that is
    # neither a key, a comment nor a closing bracket fails the test rather than being
    # skipped, so a shape the reading does not know cannot hide a duplicate.
    test "every hook, the bus, the motion loop and the hit index's reader are read" do
      names = Hooks.js_code() |> objects() |> Enum.map(&elem(&1, 0))

      assert Enum.sort(names) ==
               Enum.sort(@hooks ++ ~w(VisualizeSync VisualizeMotion VisualizeItems))
    end

    test "each defines every key once" do
      repeated =
        for {object, members} <- objects(Hooks.js_code()),
            {key, lines} <- Enum.group_by(members, &elem(&1, 0), &elem(&1, 1)),
            length(lines) > 1,
            do: "#{object} defines #{show(key)} at bundle lines #{Enum.join(lines, ", ")}"

      assert repeated == []
    end

    test "the reading finds a key a later part repeats" do
      code = """
      export const SomeHook = {
        // a comment
        mounted() {
          this.go();
        },
        go(e) { return e; },
        size: 1,
      };
      """

      assert [{"SomeHook", members}] = objects(code)
      assert Enum.map(members, &elem(&1, 0)) == [{nil, "mounted"}, {nil, "go"}, {nil, "size"}]

      twice = String.replace(code, "  size: 1,", "  go(name, box) { return box; },")
      assert [{"SomeHook", [_, {key, 6}, {key, 7}]}] = objects(twice)
    end
  end

  # Every object the code declares at its top level, `const Name = {` to the `};` that
  # closes it, as `{name, [{key, line}]}`; a key is `{accessor, name}`, so a getter and a
  # setter of one name are two keys.
  defp objects(code) do
    code
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.chunk_while(
      nil,
      fn {line, n}, open ->
        case {open, Regex.run(~r/^(?:export )?const (\w+) = \{$/, line)} do
          {nil, [_, name]} -> {:cont, {name, []}}
          {nil, nil} -> {:cont, nil}
          {{name, lines}, _} when line == "};" -> {:cont, {name, Enum.reverse(lines)}, nil}
          {{name, lines}, _} -> {:cont, {name, [{line, n} | lines]}}
        end
      end,
      fn
        nil -> {:cont, nil}
        {name, _} -> flunk("#{name} is never closed by a `};` line")
      end
    )
    |> Enum.map(fn {name, lines} -> {name, members(name, lines)} end)
  end

  defp members(name, lines) do
    indent =
      Enum.find_value(lines, fn {line, _} ->
        with [_, indent] <- Regex.run(~r/^( +)\S/, line), do: indent
      end) ||
        flunk("#{name} has no members")

    lines
    |> Enum.filter(fn {line, _} ->
      String.starts_with?(line, indent) and not String.starts_with?(line, indent <> " ")
    end)
    |> Enum.map(fn {line, _} = member -> {String.trim(line), member} end)
    |> Enum.reject(fn {text, _} -> text == "" or text =~ ~r"^(//|/\*|\*|[}\])]+[,;]?$)" end)
    |> Enum.map(fn {text, {_, n}} -> {key(name, text, n), n} end)
  end

  defp key(name, text, n) do
    case Regex.run(~r/^(?:async\s+)?(?:(get|set)\s+)?([A-Za-z_$][\w$]*)\s*(?:\(|:|,$)/, text) do
      [_, "", key] ->
        {nil, key}

      [_, accessor, key] ->
        {accessor, key}

      nil ->
        flunk("#{name}, bundle line #{n}: not a key, a comment or a closing bracket: #{text}")
    end
  end

  defp show({nil, key}), do: "`#{key}`"
  defp show({accessor, key}), do: "`#{accessor} #{key}`"
end
