defmodule Visualize.Audit.Spelling do
  @moduledoc """
  American spelling in everything this library names and writes (spec/12 §3, #642, D-183).

  Fails on a British form — `colour`, `centre`, `grey`, `-ise`, `-our`, `-elled`, `metre`
  and the rest — in `lib/`, `test/`, `specs/`, `spec/`, `guides/`, `README.md`, the
  CHANGELOG's unreleased entries and the examples app, inside identifiers as well as prose,
  so `recolour_all` is caught as surely as "a colour".

  What stays British is an allowlist, not a judgment call:

    * Elixir's own `behaviour` — `@behaviour`, a `Behaviour` module, and prose about a
      module contract ("implements this behaviour");
    * quoted third-party text — CSS's `grey` keywords, d3's `Greys` scheme, ARIA's
      `aria-labelledby`, the `metre` unit alias a host may type, and `metresis`, a project's
      name;
    * the CHANGELOG's released entries, which say what each release was called;
    * a line marked `spelling: allow` — a comment line so marked allows the line after it
      too, an old name a migration reads — and a Markdown region between lines that are
      `<!-- spelling: allow -->` and `<!-- spelling: end -->`.
  """

  @scanned ~w(lib test specs spec guides examples/lib examples/test)
  @files ~w(README.md CHANGELOG.md)
  @extensions ~w(.ex .exs .md .cheatmd .heex .js .css)

  @ise ~w(normal serial real raster categor synchron summar recogn initial organ minim maxim
          parametr parameter material human discret capital local synthes vector general atom
          token quant canonical optim custom special visual stabil standard author priorit
          emphas util final memor character apolog critic legal neutral central)

  @ell ~w(label model travel cancel level signal total fuel channel tunnel counsel dial equal
          jewel duel rival pencil shovel quarrel)

  @our ~w(honour favour behaviour neighbour armour harbour flavour labour rumour vapour humour
          rigour vigour endeavour savour splendour clamour fervour ardour candour parlour valour
          glamour odour)

  @words [
    ~r/colour/i,
    ~r/centre|centring|centred/i,
    ~r/(?<![a-z])grey/i,
    Regex.compile!(Enum.join(@our, "|"), "i"),
    Regex.compile!(
      "(?<![a-z])(?:un|re|de)?(?:" <>
        Enum.join(@ise, "|") <> ")is(?:e|ed|es|er|ers|ing|ation|ations|able)(?![a-z])",
      "i"
    ),
    ~r/(?<![a-z])analys(?:e|ed|ing)(?![a-z])/i,
    Regex.compile!(
      "(?<![a-z])(?:un|re)?(?:" <> Enum.join(@ell, "|") <> ")l(?:ed|ing|er|ers)(?![a-z])",
      "i"
    ),
    ~r/(?<![a-z])(?:milli|centi|kilo|micro|nano)?metres?(?![a-z])/i,
    ~r/(?<![a-z])(?:milli|centi)?litres?(?![a-z])/i,
    ~r/(?<![a-z])(?:fibre|licence|defence|offence|catalogue|analogue|dialogue|judgement|acknowledgement|programme|artefact)s?(?![a-z])/i,
    ~r/(?<![a-z])(?:mis)?spelt(?![a-z])/i,
    ~r/(?<![a-z])(?:whilst|amongst|learnt|ageing|fulfils?)(?![a-z])/i,
    ~r/(?<![a-z])(?:sceptic|manoeuvr)/i
  ]

  # Third-party and Elixir spellings, blanked before a line is read.
  @allowed [
    ~r/@behaviour/,
    ~r/:behaviour\b/,
    ~r/\bBehaviour\b/,
    ~r/aria[-_]labelledby|labelledby/i,
    ~r/"grey"/,
    ~r/\bgreys:|:greys\b|Greys/,
    ~r/\bmetre: "m"/,
    ~r/metresis/i
  ]

  # A piece every British form holds, so a line with none is passed over unscanned.
  @fragments ~w(colour centr grey our ise ising isation isable analys lled lling ller metre litre
              fibre licence defence offence logue judgement acknowledgement programme artefact
              spelt whilst amongst learnt ageing fulfil sceptic manoeuvr)

  # A line about an Elixir behaviour, a module contract, keeps its `behaviour`.
  @elixir_behaviour ~r/\bBehaviour\b|Elixir.s behaviour|Elixir behaviour|"the behaviour"|implement|callback|is a behaviour|a behaviour (every|hosts|whose|plus|rather|with)|(feed|backend|clip|scale|store|Store`|`[A-Za-z.]+`) behaviour|this behaviour|the behaviour( alone|'s callbacks|\s+dispatch| every)|behaviour dispatch|declares the behaviour|behaviour rather than a protocol|behaviours = |behaviour, and its|its behaviour module|module that declares this behaviour|the behaviour is three|behaviour plus messages|### \d+(\.\d+)* The behaviour|## \d+\. The backend behaviour|### \d+(\.\d+)* The backend behaviour|Feeds: the behaviour/

  @doc "Problems across the scanned trees under `root`; `[]` when every word is American."
  @spec run(String.t()) :: [String.t()]
  def run(root) do
    trees =
      Enum.flat_map(@scanned, fn dir ->
        root |> Path.join(dir) |> Path.join("**/*") |> Path.wildcard()
      end)

    (trees ++ Enum.map(@files, &Path.join(root, &1)))
    |> Enum.filter(&(File.regular?(&1) and Path.extname(&1) in @extensions))
    |> Enum.sort()
    |> Enum.flat_map(fn path -> check(File.read!(path), Path.relative_to(path, root)) end)
  end

  @doc """
  The British words of one file's text, as `file:line: word` strings. The CHANGELOG is
  read up to its first released entry.

      iex> Visualize.Audit.Spelling.check("a gray line\\n", "lib/x.ex")
      []
  """
  @spec check(String.t(), String.t()) :: [String.t()]
  def check(text, file) do
    text
    |> unreleased(file)
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map_reduce(:read, fn {line, no}, state -> scan(line, no, state) end)
    |> elem(0)
    |> Enum.concat()
    |> Enum.map(fn {no, word} -> "#{file}:#{no}: `#{word}` is British spelling" end)
  end

  defp unreleased(text, "CHANGELOG.md") do
    case Regex.split(~r/^## \[\d/m, text, parts: 2) do
      [unreleased, _released] -> unreleased
      [all] -> all
    end
  end

  defp unreleased(text, _file), do: text

  # A region is opened and closed by marker lines of their own; a `spelling: allow` anywhere
  # else allows its line, and a comment line saying it allows the line after it too.
  defp scan(line, no, state) do
    trimmed = String.trim(line)

    cond do
      trimmed == "<!-- spelling: allow -->" ->
        {[], :region}

      trimmed == "<!-- spelling: end -->" ->
        {[], :read}

      state == :region ->
        {[], :region}

      state == :next ->
        {[], :read}

      String.contains?(line, "spelling: allow") ->
        {[], if(comment?(trimmed), do: :next, else: :read)}

      true ->
        {words(line, no), :read}
    end
  end

  defp comment?(trimmed), do: String.starts_with?(trimmed, ["#", "//"])

  defp words(line, no) do
    p = patterns()

    if :binary.match(String.downcase(line), p.fragments) != :nomatch and Regex.match?(p.any, line) do
      allowed = if Regex.match?(p.elixir, line), do: [p.behaviour | p.allowed], else: p.allowed

      blank =
        Enum.reduce(
          allowed,
          line,
          &Regex.replace(&1, &2, fn m -> String.duplicate(" ", String.length(m)) end)
        )

      for re <- p.words, [word | _] <- Regex.scan(re, blank), do: {no, word}
    else
      []
    end
  end

  # The patterns compiled once per VM, and one alternation of every British form that
  # passes most lines over without a scan per pattern.
  defp patterns do
    case :persistent_term.get(__MODULE__, nil) do
      nil ->
        any = Enum.map_join(@words, "|", &"(?:#{Regex.source(&1)})")

        patterns = %{
          any: Regex.compile!(any, "i"),
          fragments: :binary.compile_pattern(@fragments),
          words: @words,
          allowed: @allowed,
          elixir: @elixir_behaviour,
          behaviour: ~r/behaviours?/i
        }

        :persistent_term.put(__MODULE__, patterns)
        patterns

      patterns ->
        patterns
    end
  end
end
