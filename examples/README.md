# Visualize examples

The gallery, the performance view, the client-side interactions and the chart builder,
as a Phoenix LiveView app over the library one directory up.

    ./run.sh                # http://127.0.0.1:4080

`run.sh` fetches and compiles the dependencies, then runs `mix phx.server`. Its one optional
argument says where to listen: `./run.sh 4020` (a port), `./run.sh 0.0.0.0` (an address) or
`./run.sh 0.0.0.0:4020` (both); an IPv6 literal goes in brackets, `./run.sh [::1]:4020`. It
sets `VISUALIZE_IP` and `VISUALIZE_PORT`, which `config/dev.exs` reads, so a bare
`mix phx.server` listens on the same default. An address other than loopback exposes an
unauthenticated development server to whatever can route to it, and `run.sh` says so when it
starts.

## Restart, don't just recompile, after a supervision-tree change

The application's supervision tree (`Examples.Application`) is built when the app
starts. A running server that takes new code by recompilation keeps its old tree: a
child added since — `Examples.TaskSupervisor`, which every performance run renders its
frames under (#323) — is simply not there, and each run would have died with
`GenServer.call(Examples.TaskSupervisor, …) ** (EXIT) no process`. The pages now say so
instead (*the task supervisor is not running — restart the server*, #340). When the
tree changes, stop the server and start it again.

## Tests

    mix test

Every route is fetched under test (`test/examples_web/routes_test.exs`), so a page that
cannot render fails the suite; CI runs it (`examples:test`).
