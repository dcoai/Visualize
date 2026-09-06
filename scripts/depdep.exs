# Depdep bootstrap: restore compiled dependencies from the shared store before
# `mix deps.get`, and push what was missing after a green build.
#
#   elixir scripts/depdep.exs --pull     # before mix deps.get (the order is load-bearing)
#   elixir scripts/depdep.exs --push     # after the build succeeded
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

Mix.install([{:depdep, git: url, tag: "v0.1.0"}])

Depdep.CLI.main(System.argv())
