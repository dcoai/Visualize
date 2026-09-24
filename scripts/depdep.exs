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
# v0.6.0 (#387) is the first release whose restore of a git dependency actually holds: the
# extract ran over the checkout `mix deps.get` had just made and failed on git's read-only
# objects (`pull failed (:eacces)`), so a git dependency was compiled from source on every
# run while the summary counted it as restored. `surfex` is this project's. Every object
# path is unchanged, so no store refill; the v3 key that does change them is the next
# release. It also tells a restored unit Mix would rebuild from a hit, and says why.
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

Mix.install([{:depdep, git: url, tag: "v0.6.0"}])

Depdep.CLI.main(System.argv())
