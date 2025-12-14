import Config

config :examples, ExamplesWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json"

config :logger, level: :info
