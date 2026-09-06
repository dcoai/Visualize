# House style shared with the sibling libraries (extc, extla): 98 columns, and the
# tooling directories formatted alongside `lib/` so they cannot drift.
[
  inputs: ["{mix,.formatter}.exs", "{audit,config,lib,scripts,specs,test}/**/*.{ex,exs}"],
  line_length: 98
]
