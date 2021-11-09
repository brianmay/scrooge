use Mix.Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :scrooge, ScroogeWeb.Endpoint,
  http: [port: 4002],
  server: false

# Print only warnings and errors during test
config :logger, level: :warn

config :scrooge,
  mqtt_host: "mqtt.example.org",
  mqtt_port: 8883,
  ca_cert_file: "cacert_dummy.pem",
  mqtt_user_name: "mqtt_username",
  mqtt_password: "mqtt_password",
  oidc: %{
    discovery_document_uri: "",
    client_id: "",
    client_secret: "",
    scope: ""
  }

# Configure your database
config :scrooge, Scrooge.Repo,
  pool: Ecto.Adapters.SQL.Sandbox,
  url: System.get_env("DATABASE_URL_TEST")

config :scrooge, Scrooge.Accounts.Guardian,
  issuer: "scrooge",
  secret_key: "/q7S9SP028A/BbWqkiisc5qZXbBWQFg8+GSTkflTAfRw/K9jCzJKWpSWvWUEoUU4"

config :scrooge, ScroogeWeb.Endpoint,
  secret_key_base: "oOWDT+7p6JENufDeyMQFLqDMsj1bkVfQT4Navmr5qYem9crHED4jAMr0Stf4aRNt"

config :plugoid,
  auth_cookie_store_opts: [
    signing_salt: "/EeCfa85oE1mkAPMo2kPsT5zkCFPveHk"
  ],
  state_cookie_store_opts: [
    signing_salt: "/EeCfa85oE1mkAPMo2kPsT5zkCFPveHk"
  ]
