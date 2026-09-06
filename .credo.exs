# `mix credo --strict` is the `quality` stage. Every disabled check carries its reason.
%{
  configs: [
    %{
      name: "default",
      strict: true,
      files: %{
        included: ["lib/", "audit/", "specs/", "scripts/", "test/", "mix.exs"],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/examples/"]
      },
      checks: %{
        disabled: [
          # The formatter already holds the code to 98 columns.
          {Credo.Check.Readability.MaxLineLength, []},
          # Aliases are named in full where the reader would otherwise have to look them up.
          {Credo.Check.Design.AliasUsage, []},
          # Projection, layout and encoder maths is branchy by nature; splitting a formula
          # to satisfy a depth or complexity count moves the reasoning, not the risk.
          {Credo.Check.Refactor.Nesting, []},
          {Credo.Check.Refactor.CyclomaticComplexity, []},
          # `Enum.map |> Enum.join` reads as the two steps it is in rendering paths; the
          # allocation saved by `map_join` is not where any backend spends its time (#17).
          {Credo.Check.Refactor.MapJoin, []},
          # `IR.Path.arc_to/8` and friends mirror the SVG path grammar the spec declares.
          {Credo.Check.Refactor.FunctionArity, []},
          # `SVG.Element.clipPath/1`, `linearGradient/1`, `radialGradient/1` are named after
          # the SVG elements they build; the spec (02 §5) declares them under those names.
          {Credo.Check.Readability.FunctionNames, []}
        ]
      }
    }
  ]
}
