defmodule Visualize.Audit.SpellingTest do
  use ExUnit.Case, async: true

  alias Visualize.Audit.Spelling

  doctest Spelling

  # The British forms spelled apart, so this file's own text holds none the gate would refuse.
  @uk_color "col" <> "our"
  @uk_center "cent" <> "re"
  @uk_gray "gr" <> "ey"
  @uk_normalized "normal" <> "ised"
  @conduct "behavi" <> "our"

  defp check(text), do: Spelling.check(text, "lib/x.ex")

  test "a British form fails at its line, in prose and inside an identifier" do
    assert check("a gray line\nthe #{@uk_color} of it\nre#{@uk_color}_all(x)\n") == [
             "lib/x.ex:2: `#{@uk_color}` is British spelling",
             "lib/x.ex:3: `#{@uk_color}` is British spelling"
           ]

    assert [_] = check("the #{@uk_center}d mark")
    assert [_] = check("a #{@uk_gray} rule")
    assert [_] = check("#{@uk_normalized} values")
    assert [_] = check("its #{@conduct} on a click")
  end

  test "the American forms and the words that only look British pass" do
    assert check("color, center, gray, normalized, behavior, raise, precise, otherwise") == []
    assert check("a contour, parameter and metresis") == []
  end

  test "Elixir's behaviour and quoted third-party names are allowed" do
    assert check("@#{@conduct} Visualize.Feed") == []

    assert check("Visualize.Scale.B#{String.slice(@conduct, 1..-1//1)}.normalize(v)") ==
             []

    assert check("a module that implements this #{@conduct}") == []
    assert check(~s(  "#{@uk_gray}" => "#808080", "light#{@uk_gray}" => "#d3d3d3")) == []
    assert check(~s(<svg aria-label#{"led"}by="t">)) == []
  end

  test "a marked line, the line after a marked comment, and a marked region are allowed" do
    assert check("@old :#{@uk_color}_safe # spelling: allow") == []

    assert check("# spelling: allow — the old name\n@old :#{@uk_color}_safe\n#{@uk_color}\n") ==
             ["lib/x.ex:3: `#{@uk_color}` is British spelling"]

    region = "<!-- spelling: allow -->\n`#{@uk_center}`\n<!-- spelling: end -->\n#{@uk_center}\n"

    assert Spelling.check(region, "spec/x.md") == [
             "spec/x.md:4: `#{@uk_center}` is British spelling"
           ]

    assert Spelling.check("`#{@uk_center}` is read <!-- spelling: allow -->\n", "spec/x.md") == []
  end

  test "the CHANGELOG is read up to its first released entry" do
    changelog = "## [Unreleased]\n#{@uk_color}\n## [0.6.0] — 2026-10-14\n#{@uk_color}\n"

    assert Spelling.check(changelog, "CHANGELOG.md") == [
             "CHANGELOG.md:2: `#{@uk_color}` is British spelling"
           ]
  end

  test "the tree spells American" do
    assert Spelling.run(File.cwd!()) == []
  end
end
