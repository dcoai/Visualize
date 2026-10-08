# Depdep bootstrap: restore compiled dependencies from the shared store before
# `mix deps.get`, and push what was missing after a green build.
#
#   elixir scripts/depdep.exs --pull --mix-get --compile-deps   # the pull, mix deps.get inside it,
#                                                              # and a compile of what was missing
#   elixir scripts/depdep.exs --push                           # after the build succeeded
#
# `--exclude examples` in the library jobs: the examples member is pulled and pushed by
# the job that builds it, from examples/ (#342, #343).
#
# v0.9.0 (#446) makes a restore land where **this** build looks. An object carries the
# pusher's build path (`_build/sqlite/test` from metresis, say), and extracting it in place
# put the tree where this project's Mix never reads it, so Mix called the build outdated
# and recompiled it: a hit that was not one (depdep #131, behind #122 and #110). Extraction
# is now staged and moved to this member's own build path. Keys are unchanged (schema v3,
# as v0.7.0 set them in #440), so there is **no refill**: objects already in the store
# become usable.
#
# v0.10.0 (#452) fixes the second cause of the same symptom. A git dependency's checkout
# carries the pusher's `origin`, and Mix requires the lock's URL to equal it as a string,
# so an object pushed as `https://…/extla.git` was outdated to this project, which locks
# `git@…:dco-tek/extla.git` (depdep #144). The restore now adopts this project's spelling.
# Keys are unchanged again: no refill.
#
# A restore Mix still refuses is counted as a miss and recompiled, and the summary ends
# `rebuilt N`. If N is not 0, `--explain-rebuilt` (v0.8.0) names which input the manifest
# disagrees on; #430 is the standing case (extla).
#
# Depdep lives in a private project, so the URL has to carry credentials, and what is
# available differs between a developer's machine and a CI container: a developer has an
# ssh key, a job has CI_JOB_TOKEN and no key. With no DEPDEP_* variables set, depdep says
# so and exits 0, so a pipeline never depends on the store being reachable.
url =
  case System.get_env("CI_JOB_TOKEN") do
    nil -> "git@gitlab.conet.yarina.org:dco-tek/depdep.git"
    token -> "https://gitlab-ci-token:#{token}@gitlab.conet.yarina.org/dco-tek/depdep.git"
  end

Mix.install([{:depdep, git: url, tag: "v0.10.0"}])

Depdep.CLI.main(System.argv())
