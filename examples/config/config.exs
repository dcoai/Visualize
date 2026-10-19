import Config

config :examples, ExamplesWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [html: ExamplesWeb.ErrorHTML], layout: false],
  pubsub_server: Examples.PubSub,
  live_view: [signing_salt: "visualize_examples"]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

# A time scale's display zone reads the host's time zone database (D-115); the library
# takes no tz dependency, so the host configures one.
config :elixir, :time_zone_database, Tz.TimeZoneDatabase

# The host's generators (spec/14 §3.13): the tenant chat's styles and brand colors,
# computed when a chart is drawn (`Examples.Tenants`, #654).
config :visualize, generators: [Examples.Tenants.Generators]

import_config "#{config_env()}.exs"
