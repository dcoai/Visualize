defmodule Visualize.Audit.SurfaceTest do
  @moduledoc """
  The drift assertion, inside `mix test` so a developer sees it before CI's
  `mix vis.surface --check` does.
  """
  use ExUnit.Case, async: true

  alias Visualize.Audit

  test "API_SURFACE.md is what spec/ and lib/ render to" do
    result = Audit.run(File.cwd!())
    assert File.read!("API_SURFACE.md") == Audit.render(result)
  end

  test "nothing is declared without a definition, and nothing is defined without a row" do
    # The gate's second half (spec/12 §2, D-89), asserted here so `mix test` reports it
    # before CI's `mix vis.surface --check` does.
    result = Audit.run(File.cwd!())
    assert result.unimplemented == []
    assert result.unspecified == []
  end

  test "the columns mean what spec/12 §2 says they mean" do
    # §2: Version is a content hash of the definition, Locus the source file. The two were
    # described the other way round until #96, so the meanings are held here.
    rendered = Audit.render(Audit.run(File.cwd!()))
    [_, header | _] = String.split(rendered, "| Function | Section | Status | Version | Locus |")
    [row | _] = header |> String.split("\n", trim: true) |> Enum.drop(1)
    [_, _function, _section, _status, version, locus, _] = String.split(row, "|")

    assert String.trim(version) =~ ~r/^`[0-9a-f]{8}`$/
    assert String.trim(locus) =~ ~r/^`lib\/.+\.ex`$/
  end
end
