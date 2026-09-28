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
# v0.7.0 (#440) is the release v0.6.0's comment promised: the key's inputs are **Mix's
# own** (schema v3). Children, the `only:` rule and the build options a declaration
# carries — `env:`, `compile:`, `system_env:`, none of which was in the key — come from
# the converge `mix deps` runs, so the hand-written graph and env walk are gone. The
# toolchain fingerprint is complete with it: the ERTS, the architecture and the compiler
# environment are in every key, and a dependency with a native build also keys on the OS
# release and the C compiler. That is what the standing `depdep.rebuilt_after_restore` of
# 1 measured here — one object restored and rebuilt by Mix anyway — was asking for.
#
# **Every object path changed, so the first pipeline on this pin is cold**: a full set of
# misses, a longer compile job, and a `--push` that refills the store. The second is warm.
# The refill is the point as much as the fix: objects pushed by this version carry compile
# times, which is what makes `depdep.saved` and `depdep.compile_carried` mean anything.
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

Mix.install([{:depdep, git: url, tag: "v0.7.0"}])

Depdep.CLI.main(System.argv())
