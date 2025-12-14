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

import_config "#{config_env()}.exs"
