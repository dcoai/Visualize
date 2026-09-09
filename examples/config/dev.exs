import Config

# Where the server listens. `run.sh` sets these from its optional `<ip>:<port>` argument;
# the defaults are what it binds with no argument. A value that will not parse stops the
# boot rather than falling back, because a development server quietly listening somewhere
# other than where it was told is worse than one that refuses to start.
bind_ip =
  System.get_env("VISUALIZE_IP", "127.0.0.1")
  |> to_charlist()
  |> :inet.parse_address()
  |> case do
    {:ok, address} ->
      address

    {:error, _} ->
      raise """
      VISUALIZE_IP is not an IP address: #{inspect(System.get_env("VISUALIZE_IP"))}

      Give an IPv4 or IPv6 literal, for example 127.0.0.1, 0.0.0.0 or ::1.
      """
  end

bind_port =
  System.get_env("VISUALIZE_PORT", "4080")
  |> Integer.parse()
  |> case do
    {port, ""} when port in 1..65_535 ->
      port

    _ ->
      raise """
      VISUALIZE_PORT is not a port number: #{inspect(System.get_env("VISUALIZE_PORT"))}

      Give a number between 1 and 65535.
      """
  end

config :examples, ExamplesWeb.Endpoint,
  http: [ip: bind_ip, port: bind_port],
  check_origin: false,
  code_reloader: true,
  # No reloadable_apps for the library: Phoenix's code reloader compiles with dependency
  # checking off, so a path dependency is never rebuilt however it is listed. Verified —
  # an edit under ../lib/visualize produced no recompilation and no change in the response.
  # An edit to the library therefore needs the server restarting.
  debug_errors: true,
  secret_key_base: "development_secret_key_base_that_is_at_least_64_bytes_long_for_examples",
  watchers: []

config :logger, :console, format: "[$level] $message\n"
config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
