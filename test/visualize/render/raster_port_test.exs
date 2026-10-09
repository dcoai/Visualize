defmodule Visualize.Render.RasterPortTest do
  # The port under `Visualize.Render.to_png/2` (spec/09 §9.4, §9.5; spec/12 §6, D-121): what
  # it holds, what it leaves behind, and how it finds its binary. `async: false`: these tests
  # set the `:resvg` setting and TMPDIR, which are global, so nothing may run beside them.
  use ExUnit.Case, async: false

  alias Visualize.{Chart, Designs, Render}
  alias Visualize.IR.Element
  alias Visualize.Render.Raster

  @fonts [
    font_dirs: ["test/support/fonts"],
    system_fonts: false,
    generic_families: [sans_serif: "DejaVu Sans"]
  ]

  setup do
    setting = Application.fetch_env(:visualize, :resvg)
    tmpdir = System.get_env("TMPDIR")

    on_exit(fn ->
      case setting do
        {:ok, path} -> Application.put_env(:visualize, :resvg, path)
        :error -> Application.delete_env(:visualize, :resvg)
      end

      if tmpdir, do: System.put_env("TMPDIR", tmpdir), else: System.delete_env("TMPDIR")
    end)
  end

  defp swatch do
    Element.root(10, 6, children: [Element.rect(0, 0, 5, 6, %{fill: "#ff0000", stroke: :none})])
  end

  # Whether any process of the group `os_pid` led is left: signal 0 to the group fails when
  # none is (spec/12 §6). A killed process is reaped by its parent asynchronously, so this
  # asks up to `tries` times before answering yes.
  defp group_alive?(os_pid, tries \\ 100) do
    {_, status} =
      System.cmd("/bin/sh", ["-c", ~S(kill -0 -- "-$1" 2>/dev/null), "sh", "#{os_pid}"])

    cond do
      status != 0 ->
        false

      tries == 0 ->
        true

      true ->
        Process.sleep(10)
        group_alive?(os_pid, tries - 1)
    end
  end

  # A stand-in binary: a shell script that prints `output` and exits.
  defp stand_in(dir, output) do
    path = Path.join(dir, "resvg")
    File.write!(path, "#!/bin/sh\necho '#{output}'\n")
    File.chmod!(path, 0o755)
    path
  end

  describe "the timeout (spec/09 §9.5)" do
    test "kills the port's whole process group, not only the port" do
      assert {:timeout, os_pid} = Raster.run("/bin/sh", ["-c", "sleep 60"], "<svg/>", 50)
      refute group_alive?(os_pid)
    end

    @tag :resvg
    test "a render that outlasts it is {:error, :timeout}, and resvg is gone" do
      svg = Chart.render(Designs.apply(:rose), root: true, resolve: :literal)

      assert {:timeout, os_pid} =
               Raster.run(
                 Raster.binary(),
                 ["--resources-dir", System.tmp_dir!(), "--zoom", "10.0"],
                 svg,
                 1
               )

      refute group_alive?(os_pid)

      design = Chart.generate(Designs.apply(:rose), root: true, resolve: :literal)
      assert Render.to_png(design, [scale: 10, timeout: 1] ++ @fonts) == {:error, :timeout}
    end
  end

  describe "the render runs outside the VM (spec/09 §9.5)" do
    @describetag :resvg

    # On a node with one normal scheduler, a process ticking on `receive after 1` keeps
    # ticking while a render is in flight. A render holding the only scheduler would let no
    # tick run until it returned. Asserted as a count of ticks, not a time (D-114).
    test "a 1 ms ticker keeps ticking on a one-scheduler node while renders run" do
      paths = Enum.flat_map(:code.get_path(), &[~c"-pa", &1])

      # Unlinked, so `on_exit` is the peer's one owner: a linked peer starts shutting down
      # when the test process exits, racing the stop below (#495).
      {:ok, peer, _node} =
        :peer.start(%{connection: :standard_io, args: [~c"+S", ~c"1:1" | paths]})

      on_exit(fn -> :peer.stop(peer) end)

      {:ok, _} = :peer.call(peer, :application, :ensure_all_started, [:elixir])
      :ok = :peer.call(peer, :application, :set_env, [:visualize, :resvg, Raster.binary()])
      assert :peer.call(peer, :erlang, :system_info, [:schedulers_online]) == 1

      code = """
      parent = self()
      design = Visualize.Chart.generate(Visualize.Designs.apply(:rose), root: true, resolve: :literal)
      fonts = #{inspect(@fonts)}

      spawn(fn ->
        results = for _ <- 1..3, do: Visualize.Render.to_png(design, [scale: 8] ++ fonts)
        send(parent, {:rendered, results})
      end)

      tick = fn tick, n ->
        receive do
          {:rendered, results} -> {n, results}
        after
          1 -> tick.(tick, n + 1)
        end
      end

      tick.(tick, 0)
      """

      {{ticks, results}, _binding} = :peer.call(peer, Code, :eval_string, [code], 300_000)

      assert [{:ok, _, []}, {:ok, _, []}, {:ok, _, []}] = results
      assert ticks >= 20, "#{ticks} ticks ran while three renders were in flight"
    end
  end

  describe "no temp file (spec/09 §9.5)" do
    @describetag :resvg
    @tag :tmp_dir
    test "a render writes nothing to the temp directory or the working directory", %{
      tmp_dir: tmp_dir
    } do
      empty = Path.join(tmp_dir, "tmp")
      File.mkdir_p!(empty)
      System.put_env("TMPDIR", empty)
      assert System.tmp_dir!() == empty

      cwd = File.ls!()
      assert {:ok, _, []} = Render.to_png(swatch(), scale: 4)
      assert File.ls!(empty) == []
      assert File.ls!() == cwd
    end
  end

  describe "finding the binary (spec/09 §9.4)" do
    test "a configured path naming nothing is no rasteriser, whatever the PATH holds" do
      Application.put_env(:visualize, :resvg, "/no/such/dir/resvg")
      refute Raster.available?()
      assert Render.to_png(swatch()) == {:error, :no_rasterizer}
      assert_raise RuntimeError, ~r/no_rasterizer/, fn -> Render.to_png!(swatch()) end
    end

    test "a setting that is not a string is a programmer error" do
      Application.put_env(:visualize, :resvg, :resvg)
      assert_raise ArgumentError, fn -> Raster.binary() end
    end

    @tag :tmp_dir
    test "a binary below the minimum version is refused", %{tmp_dir: tmp_dir} do
      Application.put_env(:visualize, :resvg, stand_in(tmp_dir, "0.44.9"))
      assert Raster.available?()

      assert Render.to_png(swatch()) == {:error, {:rasterizer_version, "0.44.9", "0.45.0"}}
      assert_raise RuntimeError, ~r/rasterizer_version/, fn -> Render.to_png!(swatch()) end
    end

    @tag :tmp_dir
    test "a binary that prints no version is refused like an old one", %{tmp_dir: tmp_dir} do
      Application.put_env(:visualize, :resvg, stand_in(tmp_dir, "resvg nightly"))

      assert Render.to_png(swatch()) ==
               {:error, {:rasterizer_version, "resvg nightly", "0.45.0"}}
    end
  end
end
