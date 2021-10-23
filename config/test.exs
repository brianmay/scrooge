use Mix.Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :scrooge, ScroogeWeb.Endpoint,
  http: [port: 4002],
  server: false

# Print only warnings and errors during test
config :logger, level: :warn

# Configure your database
config :scrooge, Scrooge.Repo,
  pool: Ecto.Adapters.SQL.Sandbox,
  url: System.get_env("DATABASE_URL_TEST")

config :scrooge, Scrooge.Accounts.Guardian,
  issuer: "scrooge",
  secret_key: "/q7S9SP028A/BbWqkiisc5qZXbBWQFg8+GSTkflTAfRw/K9jCzJKWpSWvWUEoUU4"

config :scrooge, ScroogeWeb.Endpoint,
  secret_key_base: "oOWDT+7p6JENufDeyMQFLqDMsj1bkVfQT4Navmr5qYem9crHED4jAMr0Stf4aRNt"

config :scrooge, :openid_connect_providers, client: nil
