# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
use Mix.Config

config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

config :scrooge,
  ecto_repos: [Scrooge.Repo],
  mqtt_host: System.get_env("MQTT_HOST"),
  mqtt_port: String.to_integer(System.get_env("MQTT_PORT") || "8883"),
  ca_cert_file: System.get_env("MQTT_CA_CERT_FILE"),
  mqtt_user_name: System.get_env("MQTT_USER_NAME"),
  mqtt_password: System.get_env("MQTT_PASSWORD"),
  build_date: System.get_env("BUILD_DATE"),
  vcs_ref: System.get_env("VCS_REF"),
  timezone: "Australia/Melbourne"

config :scrooge, Scrooge.Repo,
  url: System.get_env("DATABASE_URL"),
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

port = String.to_integer(System.get_env("PORT") || "4000")

# Configures the endpoint
config :scrooge, ScroogeWeb.Endpoint,
  http: [:inet6, port: port],
  url: [host: "localhost", port: port],
  secret_key_base: System.get_env("SECRET_KEY_BASE"),
  render_errors: [view: ScroogeWeb.ErrorView, accepts: ~w(html json)],
  pubsub: [name: Scrooge.PubSub, adapter: Phoenix.PubSub.PG2],
  live_view: [
    signing_salt: System.get_env("SIGNING_SALT")
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :scrooge, Scrooge.Accounts.Guardian,
  issuer: "scrooge",
  secret_key: System.get_env("GUARDIAN_SECRET")

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
