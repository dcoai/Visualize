# The dependency findings a project accepts (spec/12 §3, D-207), read by
# `mix vis.advisories`, which runs `mix hex.audit` in the root project and in examples/.
# Each entry is one finding in one project, and why it does not apply or cannot be acted on
# yet:
#
#   %{project: :examples, advisory: "EEF-CVE-2026-105659", reason: "..."}
#   %{project: :library, retired: "name@1.2.3", reason: "..."}
#
# `advisory:` is an id as `mix hex.audit` prints it, primary or alias; `retired:` is a
# package name, optionally pinned to a version. An entry the audit passes without fails the
# task, so the list shrinks as the locks move. Prefer updating the lock to an entry here.
[]
