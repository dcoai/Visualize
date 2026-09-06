defmodule Visualize.Audit.CodeScanTest do
  use ExUnit.Case, async: true

  alias Visualize.Audit.CodeScan

  @source """
  defmodule Visualize.Fixture do
    use GenServer

    @doc "documented"
    def documented(a, b \\\\ 1), do: {a, b}

    def undocumented(x) when is_integer(x), do: x
    def undocumented(_), do: nil

    @doc false
    def hidden(_), do: :hidden

    @impl true
    def init(arg), do: {:ok, arg}

    @impl true
    def handle_call(_, _, s, opts \\\\ []), do: {:reply, opts, s}

    defp private(_), do: :private

    defdelegate delegated(a, b \\\\ []), to: Other

    defmacro macro(_), do: :macro

    if Code.ensure_loaded?(Nothing.Here) do
      def guarded_by_if, do: :ok
    end
  end
  """

  defp entries, do: CodeScan.scan_source(@source, "lib/fixture.ex")

  defp visible, do: for(e <- entries(), not e.hidden?, do: "#{e.name}/#{e.arity}")

  test "public definitions, default-argument arities, delegates, macros and if-wrapped defs" do
    assert "documented/1" in visible()
    assert "documented/2" in visible()
    assert "undocumented/1" in visible()
    assert "delegated/1" in visible()
    assert "delegated/2" in visible()
    assert "macro/1" in visible()
    assert "guarded_by_if/0" in visible()
  end

  test "private functions are absent" do
    refute Enum.any?(entries(), &(&1.name == :private))
  end

  test "@doc false hides every arity; @impl hides the callback arity only" do
    hidden = for e <- entries(), e.hidden?, do: "#{e.name}/#{e.arity}"
    assert "hidden/1" in hidden
    assert "init/1" in hidden
    assert "handle_call/4" in hidden
    assert "handle_call/3" in visible()
  end

  test "use GenServer injects a public child_spec/1" do
    assert "child_spec/1" in visible()
  end

  test "multi-clause functions are one entry" do
    assert Enum.count(entries(), &(&1.name == :undocumented)) == 1
  end

  test "the version is stable under reformatting and changes with the body" do
    [a] = for e <- CodeScan.scan_source(@source, "x"), e.name == :hidden, do: e.version

    reindented =
      String.replace(
        @source,
        "  def hidden(_), do: :hidden",
        "\n\n      def hidden(_), do: :hidden"
      )

    [b] = for e <- CodeScan.scan_source(reindented, "x"), e.name == :hidden, do: e.version
    changed = String.replace(@source, "do: :hidden", "do: :changed")
    [c] = for e <- CodeScan.scan_source(changed, "x"), e.name == :hidden, do: e.version
    assert a == b
    assert a != c
  end

  test "the locus is the file given" do
    assert Enum.all?(entries(), &(&1.file == "lib/fixture.ex"))
  end
end
