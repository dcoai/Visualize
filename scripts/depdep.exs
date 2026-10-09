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
# v0.11.0 (#478) removes a third cause, and restores git sources. A dependency that recorded
# a compile-time value this project's config sets read as `:envoutdated`, because nothing
# had put the project's config into the VM that asked (depdep #161). A git dependency's
# source (extla, here) is now its own object, keyed on the repository and the locked commit,
# and restored before `mix deps.get`, so it is not cloned (depdep #163–#165). Keys are
# unchanged again; the first run after this pin pushes the new source objects.
#
# A restore Mix still refuses is counted as a miss and recompiled, and the summary ends
# `rebuilt N`. If N is not 0, `--explain-rebuilt` (v0.8.0) names which input the manifest
# disagrees on.
#
# extla is an ordinary unit of the store, not excluded the way `examples` is: it is a git
# dependency at a pinned tag (#441), so the commit is its content identity across
# checkouts. #430 asked whether it was restorable at all, because v0.7.0 refused it on
# every run; it was the two causes above, and on v0.10.0 it restores and holds (#452,
# pipeline 4490: `missing 0`, nothing rebuilt).
#
# A `compile` or `test` job served by the GitLab runner's own cache (keyed on mix.lock,
# local to each runner) reports `already present` and never touches the store. Only a job
# that missed that cache measures a restore, so read `rebuilt N` from those.
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

Mix.install([{:depdep, git: url, tag: "v0.11.0"}])

Depdep.CLI.main(System.argv())
