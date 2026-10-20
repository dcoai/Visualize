defmodule Visualize.Render.Raster do
  @moduledoc false
  # `Visualize.Render.to_png/2` through the resvg command-line tool, run as a port (spec/09
  # §9, D-121). The render happens in another OS process, so it holds no BEAM scheduler and
  # a crash in it cannot take the node down. The SVG goes in on stdin and the PNG comes
  # back on stdout, through a POSIX `sh` wrapper that hands resvg exactly the SVG's bytes
  # and then end-of-file, since a port cannot half-close its stdin: no temp file is written.
  #
  # The binary is the host's: `config :visualize, :resvg`, else `resvg` on the PATH. The
  # suite cannot remove a binary the host has, so availability is an argument (spec/09
  # §9.4): `Visualize.Render` passes `available?/0`, a test passes `false`.

  alias Visualize.IR.Element

  # The oldest resvg whose pictures hold the raster goldens (spec/09 §9.4, D-121).
  @minimum {0, 45, 0}

  @signature <<137, 80, 78, 71, 13, 10, 26, 10>>

  # `$1` the SVG's byte count, `$2` the binary, the rest its flags. `head` passes on exactly
  # the SVG and closes resvg's stdin; resvg's stderr joins its stdout (spec/09 §9.5).
  @wrapper ~S(n="$1"; b="$2"; shift 2; head -c "$n" | exec "$b" "$@" - -c 2>&1)

  # One round of the timeout's kill: the group `$1` leads, else the pid `$1` (spec/09 §9.5).
  @kill ~S(kill -s KILL -- "-$1" 2>/dev/null || kill -s KILL -- "$1" 2>/dev/null)

  # The kill is sent again every `@retry` ms until the port exits; after `@stop_bound` ms the
  # port is closed, and its close awaited for at most `@close_bound` ms (spec/09 §9.5, D-213).
  @retry 10
  @stop_bound 5_000
  @close_bound 1_000

  @font_keys [:font_dirs, :system_fonts, :generic_families]
  # The options `to_png/2` reads; every other option of an IR input reaches the SVG backend.
  @keys [:scale, :background, :font_family, :timeout | @font_keys]

  # The generic keywords and the flag that sets each one's family (spec/09 §9.2).
  @generic_flags [
    serif: "--serif-family",
    sans_serif: "--sans-serif-family",
    monospace: "--monospace-family",
    cursive: "--cursive-family",
    fantasy: "--fantasy-family"
  ]

  @root ~r/<svg\b(?:[^>"']|"[^"]*"|'[^']*')*>/
  @root_family ~r/\sfont-family\s*=|font-family\s*:/
  @missing ~r/^Warning \(in [^)]*\): No match for '(.*)' font-family\.$/

  @typedoc "A warning of a render (spec/09 §9.7)."
  @type warning :: {:missing_family, String.t()} | {:rasterizer, String.t()}

  @doc false
  @spec available?() :: boolean()
  def available?, do: binary() != nil

  @doc false
  # The resvg binary the host names, or the one on the PATH; `nil` when there is none. A
  # configured path is never replaced by the PATH's, so a wrong one fails loudly.
  @spec binary() :: String.t() | nil
  def binary do
    case Application.get_env(:visualize, :resvg) do
      nil ->
        System.find_executable("resvg")

      path when is_binary(path) ->
        path |> Path.expand() |> System.find_executable()

      other ->
        raise ArgumentError,
              "config :visualize, :resvg must be the path to a resvg binary, got: #{inspect(other)}"
    end
  end

  @doc false
  @spec to_png(Element.t() | String.t(), keyword(), boolean()) ::
          {:ok, binary(), [warning()]} | {:error, Visualize.Render.png_error()}
  def to_png(input, opts, available) when is_list(opts) and is_boolean(available) do
    {raster, rest} = Keyword.split(opts, @keys)
    flags = flags!(raster)
    family = font_family!(Keyword.get(raster, :font_family, "sans-serif"))
    timeout = timeout!(Keyword.get(raster, :timeout, 30_000))
    svg = svg!(input, rest)

    cond do
      not available -> {:error, :no_rasterizer}
      String.contains?(svg, "var(--") -> {:error, :css_references}
      true -> rasterize(binary(), with_default(svg, family), flags, timeout)
    end
  end

  @doc false
  @spec to_png!(Element.t() | String.t(), keyword(), boolean()) :: binary()
  def to_png!(input, opts, available) do
    case to_png(input, opts, available) do
      {:ok, png, []} -> png
      {:ok, _png, warnings} -> raise "PNG drawn with warnings: #{inspect(warnings)}"
      {:error, reason} -> raise "Failed to rasterize to PNG: #{inspect(reason)}"
    end
  end

  # The binary vanished between `available?/0` and the call: the same as none.
  defp rasterize(nil, _svg, _flags, _timeout), do: {:error, :no_rasterizer}

  defp rasterize(binary, svg, flags, timeout) do
    with :ok <- check_version(binary) do
      case run(binary, flags, svg, timeout) do
        {:exit, 0, output} -> result(output)
        {:exit, _status, output} -> {:error, {:rasterizer, message(output)}}
        {:timeout, _os_pid} -> {:error, :timeout}
      end
    end
  end

  defp result(output) do
    case :binary.split(output, @signature) do
      [text, png] -> {:ok, @signature <> png, warnings(text)}
      [text] -> {:error, {:rasterizer, message(text)}}
    end
  end

  # resvg ends a failure with an `Error: …` line, after its usage text when an argument was
  # refused: the message is that line, or all the text when there is none.
  defp message(text) do
    text
    |> String.split(["\r\n", "\n"])
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&String.starts_with?(&1, "Error:"))
    |> List.last()
    |> Kernel.||(String.trim(text))
  end

  @doc false
  # Runs `binary` with `args` over the wrapper, `input` on its stdin, and collects its
  # stdout until it exits: `{:exit, status, output}`, or `{:timeout, os_pid}` when it has
  # not exited within `timeout` ms, its processes then killed with `signal` (spec/09 §9.5).
  # `signal` is a seam: a test passes one that loses a kill (D-213).
  @spec run(String.t(), [String.t()], binary(), pos_integer(), (pos_integer() -> :ok)) ::
          {:exit, non_neg_integer(), binary()} | {:timeout, pos_integer()}
  def run(binary, args, input, timeout, signal \\ &signal/1) do
    port =
      Port.open({:spawn_executable, "/bin/sh"}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        :hide,
        args: ["-c", @wrapper, "sh", Integer.to_string(byte_size(input)), binary | args]
      ])

    {:os_pid, os_pid} = Port.info(port, :os_pid)
    timer = :erlang.start_timer(timeout, self(), :raster_timeout)
    true = Port.command(port, input)
    collect(port, os_pid, timer, signal, [])
  end

  defp collect(port, os_pid, timer, signal, acc) do
    receive do
      {^port, {:data, data}} ->
        collect(port, os_pid, timer, signal, [acc | data])

      {^port, {:exit_status, status}} ->
        cancel(timer)
        {:exit, status, IO.iodata_to_binary(acc)}

      {:timeout, ^timer, :raster_timeout} ->
        stop(port, os_pid, signal, now() + @stop_bound)
        {:timeout, os_pid}
    end
  end

  # Kills the render until the port reports its exit, every `@retry` ms, and gives up at
  # `deadline` by closing the port (spec/09 §9.5, D-213). A kill can land on nothing: the
  # pid is reported once `erl_child_setup` has forked it, before it calls `setsid`, so a
  # later round reaches the group the earlier one missed. The killed `sh` closes the port
  # itself, so the port is closed here only when no exit came. The exit is looked for
  # before each round, so a render that already ended is never signaled.
  defp stop(port, os_pid, signal, deadline) do
    cond do
      exited?(port, now()) ->
        :ok

      now() >= deadline ->
        close(port)

      true ->
        :ok = signal.(os_pid)

        if exited?(port, min(now() + @retry, deadline)),
          do: :ok,
          else: stop(port, os_pid, signal, deadline)
    end
  end

  # Whether the port reports its exit by `until` (monotonic ms), its output dropped. The
  # wait is to a time, not a length, so output arriving cannot stretch it.
  defp exited?(port, until) do
    receive do
      {^port, {:data, _}} -> exited?(port, until)
      {^port, {:exit_status, _}} -> true
    after
      max(until - now(), 0) -> false
    end
  end

  # Closes a port whose program did not exit, and waits a bounded time for the close to be
  # confirmed. A port that closed meanwhile ignores the request, and its exit is the answer.
  defp close(port) do
    send(port, {self(), :close})
    closed(port, now() + @close_bound)
  end

  defp closed(port, until) do
    receive do
      {^port, {:data, _}} -> closed(port, until)
      {^port, :closed} -> :ok
      {^port, {:exit_status, _}} -> :ok
    after
      max(until - now(), 0) -> :ok
    end
  end

  @doc false
  # One round of the kill (spec/09 §9.5): `SIGKILL` to the process group `os_pid` leads,
  # and, when no such group exists yet, to `os_pid` itself. The port's `sh` leads its own
  # group once OTP's `setsid` has run, and `head` and resvg are in it: one signal to the
  # group ends all three, where closing the port would leave resvg running to completion.
  # Before `setsid` the pid is the forked child that has not yet `exec`ed, and killing it
  # ends the render before it starts. When neither kill lands, the render has ended or not
  # yet reached its group, and the port's exit or the next round settles which.
  @spec signal(pos_integer()) :: :ok
  def signal(os_pid) do
    {_, _} = System.cmd("/bin/sh", ["-c", @kill, "sh", Integer.to_string(os_pid)])
    :ok
  end

  defp now, do: System.monotonic_time(:millisecond)

  defp cancel(timer) do
    if :erlang.cancel_timer(timer) == false do
      receive do
        {:timeout, ^timer, :raster_timeout} -> :ok
      after
        0 -> :ok
      end
    end

    :ok
  end

  @doc false
  # The warnings of the text resvg printed before the PNG, one per distinct line, in order
  # (spec/09 §9.7). resvg's text is not a stable interface; this is the one place read.
  @spec warnings(String.t()) :: [warning()]
  def warnings(text) do
    text
    |> String.split(["\r\n", "\n"], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.map(fn line ->
      case Regex.run(@missing, line) do
        [_, list] -> {:missing_family, family_list(list)}
        nil -> {:rasterizer, line}
      end
    end)
  end

  # resvg prints a family list with each family name in double quotes and each generic
  # keyword bare, joined by `, `; the warning's list has the quotes removed (spec/09 §9.7).
  defp family_list(printed) do
    printed
    |> members([], "", false)
    |> Enum.map(fn member ->
      case Regex.run(~r/^"(.*)"$/s, member) do
        [_, name] -> name
        nil -> member
      end
    end)
    |> Enum.join(", ")
  end

  defp members("", acc, current, _quoted), do: Enum.reverse([String.trim(current) | acc])

  defp members(<<?", rest::binary>>, acc, current, quoted),
    do: members(rest, acc, current <> "\"", not quoted)

  defp members(<<?,, rest::binary>>, acc, current, false),
    do: members(rest, [String.trim(current) | acc], "", false)

  defp members(<<c::utf8, rest::binary>>, acc, current, quoted),
    do: members(rest, acc, current <> <<c::utf8>>, quoted)

  @doc false
  # Whether `binary`'s version is at least the minimum: read once per binary file, from
  # `resvg --version`, and cached (spec/09 §9.4).
  @spec check_version(String.t()) ::
          :ok | {:error, {:rasterizer_version, String.t(), String.t()}}
  def check_version(binary) do
    {found, version} = version(binary)

    if version != nil and version >= @minimum do
      :ok
    else
      {:error, {:rasterizer_version, found, minimum()}}
    end
  end

  @doc false
  @spec minimum() :: String.t()
  def minimum, do: @minimum |> Tuple.to_list() |> Enum.join(".")

  defp version(binary) do
    %File.Stat{mtime: mtime, size: size} = File.stat!(binary)
    key = {__MODULE__, :version, binary, mtime, size}

    case :persistent_term.get(key, nil) do
      nil ->
        version = read_version(binary)
        :persistent_term.put(key, version)
        version

      version ->
        version
    end
  end

  defp read_version(binary) do
    {output, _status} = System.cmd(binary, ["--version"], stderr_to_stdout: true)
    found = String.trim(output)

    case Regex.run(~r/^(\d+)\.(\d+)\.(\d+)$/, found) do
      [_ | parts] -> {found, parts |> Enum.map(&String.to_integer/1) |> List.to_tuple()}
      nil -> {found, nil}
    end
  end

  # The flags of the options (spec/09 §9.2): every render names a resources directory, which
  # also keeps resvg from warning that stdin has none.
  defp flags!(opts) do
    scale = scale!(Keyword.get(opts, :scale, 1))
    background = background!(Keyword.get(opts, :background))
    dirs = font_dirs!(Keyword.get(opts, :font_dirs, []))
    system = system_fonts!(Keyword.get(opts, :system_fonts, true))
    generics = generics!(Keyword.get(opts, :generic_families, []))

    [
      "--resources-dir",
      System.tmp_dir!(),
      "--zoom",
      :erlang.float_to_binary(scale * 1.0, [:short])
    ] ++
      if(background, do: ["--background", background], else: []) ++
      Enum.flat_map(dirs, &["--use-fonts-dir", &1]) ++
      if(system, do: [], else: ["--skip-system-fonts"]) ++
      Enum.flat_map(generics, fn {key, family} -> [@generic_flags[key], family] end)
  end

  # Writes `family` as the root element's `font-family` when the root has none, so text that
  # names no family inherits one the SVG names (spec/09 §9.7). resvg resolves a family only
  # for text that uses it, so a root default no text reads is never reported.
  defp with_default(svg, family) do
    case Regex.run(@root, svg, return: :index) do
      [{at, len}] ->
        if Regex.match?(@root_family, binary_part(svg, at, len)) do
          svg
        else
          split = at + 4
          attr = ~s( font-family="#{escape(family)}")
          binary_part(svg, 0, split) <> attr <> binary_part(svg, split, byte_size(svg) - split)
        end

      nil ->
        svg
    end
  end

  defp escape(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("\"", "&quot;")
    |> String.replace("<", "&lt;")
  end

  defp font_dirs!(dirs) when is_list(dirs) do
    dirs
    |> Enum.map(fn
      dir when is_binary(dir) ->
        expanded = Path.expand(dir)

        File.dir?(expanded) ||
          raise ArgumentError, ":font_dirs names no directory: #{inspect(dir)}"

        expanded

      dir ->
        raise ArgumentError, ":font_dirs must be a list of strings, got: #{inspect(dir)}"
    end)
    |> Enum.uniq()
  end

  defp font_dirs!(dirs),
    do: raise(ArgumentError, ":font_dirs must be a list of strings, got: #{inspect(dirs)}")

  defp system_fonts!(system) when is_boolean(system), do: system

  defp system_fonts!(system),
    do: raise(ArgumentError, ":system_fonts must be a boolean, got: #{inspect(system)}")

  defp generics!(given) when is_list(given) do
    Enum.map(given, fn
      {key, family} when is_binary(family) ->
        Keyword.has_key?(@generic_flags, key) ||
          raise ArgumentError,
                ":generic_families takes #{inspect(Keyword.keys(@generic_flags))}, got: #{inspect(key)}"

        {key, family}

      other ->
        raise ArgumentError, ":generic_families must map keys to strings, got: #{inspect(other)}"
    end)
  end

  defp generics!(given),
    do: raise(ArgumentError, ":generic_families must be a keyword list, got: #{inspect(given)}")

  defp font_family!(family) when is_binary(family), do: family

  defp font_family!(family),
    do: raise(ArgumentError, ":font_family must be a string, got: #{inspect(family)}")

  defp timeout!(timeout) when is_integer(timeout) and timeout > 0, do: timeout

  defp timeout!(timeout),
    do: raise(ArgumentError, ":timeout must be a positive integer (ms), got: #{inspect(timeout)}")

  # A PNG is a whole document: a root element, or the SVG string one renders to.
  defp svg!(%Element{type: :root} = root, svg_opts),
    do: Visualize.Render.to_svg_string(root, svg_opts)

  defp svg!(svg, []) when is_binary(svg), do: svg

  defp svg!(svg, unknown) when is_binary(svg) do
    raise ArgumentError,
          "an SVG string takes only #{inspect(@keys)}, got #{inspect(Keyword.keys(unknown))}"
  end

  defp scale!(scale) when is_number(scale) and scale > 0, do: scale

  defp scale!(scale),
    do: raise(ArgumentError, ":scale must be a positive number, got: #{inspect(scale)}")

  defp background!(background) when is_nil(background) or is_binary(background), do: background

  defp background!(background),
    do: raise(ArgumentError, ":background must be a color string, got: #{inspect(background)}")
end
