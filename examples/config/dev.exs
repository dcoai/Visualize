import Config

config :examples, ExamplesWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4080],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "development_secret_key_base_that_is_at_least_64_bytes_long_for_examples",
  watchers: []

config :logger, :console, format: "[$level] $message\n"
config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
