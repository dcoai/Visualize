# Visualize examples

The gallery, the performance view, the client-side interactions and the chart builder,
as a Phoenix LiveView app over the library one directory up.

    mix deps.get
    mix phx.server          # http://localhost:4000

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
